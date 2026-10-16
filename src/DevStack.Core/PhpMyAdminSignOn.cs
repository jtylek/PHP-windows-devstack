using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Runtime.Versioning;

namespace DevStack.Core;

[SupportedOSPlatform("windows")]
public sealed class PhpMyAdminSignOn(StackPaths paths, StackOptions options)
{
    private const int TokenLifetimeSeconds = 60;

    public void Launch()
    {
        var password = ReadRootPassword();
        try
        {
            var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
            var tokenRoot = Path.Combine(paths.DataRoot, "secrets", "phpmyadmin-signon");
            Directory.CreateDirectory(tokenRoot);
            RestrictToCurrentUser(tokenRoot);
            RemoveExpiredTokens(tokenRoot);
            var record = JsonSerializer.Serialize(new TokenRecord(DateTimeOffset.UtcNow.AddSeconds(TokenLifetimeSeconds).ToUnixTimeSeconds(), "root", password));
            var recordPath = Path.Combine(tokenRoot, Convert.ToHexString(SHA256.HashData(Encoding.ASCII.GetBytes(token))).ToLowerInvariant() + ".json");
            File.WriteAllText(recordPath, record, new UTF8Encoding(false));

            var handoff = Path.Combine(Path.GetTempPath(), $"phpdevstack-pma-{Guid.NewGuid():N}.html");
            File.WriteAllText(handoff, "<!doctype html><form id=\"signon\" method=\"post\" action=\"http://127.0.0.1:" +
                options.HttpPort.ToString(System.Globalization.CultureInfo.InvariantCulture) +
                "/_devstack/phpmyadmin-signon.php\"><input type=\"hidden\" name=\"token\" value=\"" + token +
                "\"></form><script>document.getElementById('signon').submit()</script>", new UTF8Encoding(false));
            Process.Start(new ProcessStartInfo(handoff) { UseShellExecute = true });
        }
        finally
        {
            // The password exists only in the managed string required to create the
            // single-use record. The record is restricted to the current user and
            // removed by the local PHP endpoint on its first use or expiry cleanup.
            password = string.Empty;
        }
    }

    private string ReadRootPassword()
    {
        var path = Path.Combine(paths.DataRoot, "secrets", "mariadb-root-password.dpapi");
        if (!File.Exists(path)) throw new InvalidOperationException("The stored MariaDB root password was not found.");
        var protectedBytes = File.ReadAllBytes(path);
        try
        {
            var bytes = ProtectedData.Unprotect(protectedBytes, null, DataProtectionScope.CurrentUser);
            try { return Encoding.UTF8.GetString(bytes); }
            finally { CryptographicOperations.ZeroMemory(bytes); }
        }
        finally { CryptographicOperations.ZeroMemory(protectedBytes); }
    }

    private static void RemoveExpiredTokens(string root)
    {
        foreach (var file in Directory.EnumerateFiles(root, "*.json"))
            if (File.GetLastWriteTimeUtc(file) < DateTime.UtcNow.AddMinutes(-5)) File.Delete(file);
    }

    private static void RestrictToCurrentUser(string path)
    {
        var user = WindowsIdentity.GetCurrent().User ?? throw new InvalidOperationException("The current Windows user could not be determined.");
        var security = new DirectorySecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, AccessControlType.Allow));
        new DirectoryInfo(path).SetAccessControl(security);
    }

    private sealed record TokenRecord(long expires, string user, string password);
}
