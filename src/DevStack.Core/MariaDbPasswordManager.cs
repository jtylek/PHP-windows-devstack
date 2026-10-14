using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Runtime.Versioning;

namespace DevStack.Core;

[SupportedOSPlatform("windows")]
public sealed class MariaDbPasswordManager
{
    private readonly StackPaths paths;
    private readonly StackOptions options;

    public MariaDbPasswordManager(StackPaths paths, StackOptions options)
    {
        this.paths = paths;
        this.options = options;
    }

    public void ChangeRootPassword(string newPassword)
    {
        ValidatePassword(newPassword);
        var passwordPath = Path.Combine(paths.DataRoot, "secrets", "mariadb-root-password.dpapi");
        if (!File.Exists(passwordPath))
        {
            throw new InvalidOperationException("The stored MariaDB root password was not found.");
        }

        var currentPassword = ReadProtectedPassword(passwordPath);
        var optionPath = Path.Combine(Path.GetDirectoryName(passwordPath)!, $"mariadb-client-{Guid.NewGuid():N}.cnf");
        try
        {
            File.WriteAllText(optionPath, string.Empty, new UTF8Encoding(false));
            RestrictToCurrentUser(optionPath);
            File.WriteAllText(optionPath, $"[client]{Environment.NewLine}password={currentPassword}{Environment.NewLine}", new UTF8Encoding(false));
            ExecutePasswordChange(optionPath, newPassword);
            WriteProtectedPassword(passwordPath, newPassword);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(Encoding.UTF8.GetBytes(currentPassword));
            TryDelete(optionPath);
        }
    }

    private void ExecutePasswordChange(string optionPath, string newPassword)
    {
        var clientPath = Path.Combine(paths.MariaDbRoot, "bin", "mariadb.exe");
        if (!File.Exists(clientPath))
        {
            throw new InvalidOperationException("The MariaDB client executable was not found.");
        }

        var startInfo = new ProcessStartInfo(clientPath)
        {
            Arguments = $"--defaults-extra-file=\"{optionPath}\" --protocol=tcp --host=127.0.0.1 --port={options.MariaDbPort} --user=root --batch --skip-column-names",
            WorkingDirectory = paths.MariaDbRoot,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException("Could not start the MariaDB client.");
        }

        var escapedPassword = newPassword.Replace("\\", "\\\\").Replace("'", "''");
        process.StandardInput.WriteLine($"SET PASSWORD = PASSWORD('{escapedPassword}');");
        process.StandardInput.Close();
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        process.WaitForExit();
        _ = outputTask.Result;
        var error = errorTask.Result;
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(error)
                ? "MariaDB rejected the root password change."
                : $"MariaDB rejected the root password change: {error.Trim()}");
        }
    }

    private static void ValidatePassword(string password)
    {
        if (string.IsNullOrWhiteSpace(password) || password.Length < 8)
        {
            throw new ArgumentException("The root password must contain at least 8 characters.", nameof(password));
        }
        if (password.Contains('\r') || password.Contains('\n'))
        {
            throw new ArgumentException("The root password cannot contain line breaks.", nameof(password));
        }
    }

    private static string ReadProtectedPassword(string passwordPath)
    {
        var protectedBytes = File.ReadAllBytes(passwordPath);
        try
        {
            var passwordBytes = ProtectedData.Unprotect(protectedBytes, null, DataProtectionScope.CurrentUser);
            try
            {
                return Encoding.UTF8.GetString(passwordBytes);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(passwordBytes);
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(protectedBytes);
        }
    }

    private static void WriteProtectedPassword(string passwordPath, string password)
    {
        var passwordBytes = Encoding.UTF8.GetBytes(password);
        try
        {
            var protectedBytes = ProtectedData.Protect(passwordBytes, null, DataProtectionScope.CurrentUser);
            var temporaryPath = $"{passwordPath}.{Guid.NewGuid():N}.tmp";
            try
            {
                File.WriteAllBytes(temporaryPath, protectedBytes);
                File.Move(temporaryPath, passwordPath, true);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(protectedBytes);
                TryDelete(temporaryPath);
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(passwordBytes);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch
        {
            // Cleanup must not hide the result of the database operation.
        }
    }

    private static void RestrictToCurrentUser(string path)
    {
        var user = WindowsIdentity.GetCurrent().User
            ?? throw new InvalidOperationException("The current Windows user could not be determined.");
        var security = new FileSecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(
            user,
            FileSystemRights.Read | FileSystemRights.Write | FileSystemRights.Delete,
            AccessControlType.Allow));
        new FileInfo(path).SetAccessControl(security);
    }
}
