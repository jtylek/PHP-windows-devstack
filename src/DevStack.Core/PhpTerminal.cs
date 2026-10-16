using System.Diagnostics;
using System.Text;

namespace DevStack.Core;

public static class PhpTerminal
{
    public static ProcessStartInfo CreateStartInfo(StackPaths paths, StackOptions options)
    {
        var executable = Path.Combine(paths.PhpRoot, "php.exe");
        if (!File.Exists(executable))
            throw new FileNotFoundException("The bundled PHP runtime is missing. Complete runtime setup first.", executable);

        // Do not regenerate Apache's configuration or restart any running service.
        new ConfigurationGenerator(paths, options).GeneratePhpConfiguration();
        var ini = Path.Combine(paths.GeneratedConfigRoot, "php.ini");
        var scanDirectory = Path.Combine(paths.DataRoot, "config", "php-cli.d");
        Directory.CreateDirectory(scanDirectory);

        // Explicit -c remains effective after changing directory; PHPRC also covers
        // child tools (such as Composer) that invoke php.exe directly.
        static string Quote(string value) => "'" + value.Replace("'", "''", StringComparison.Ordinal) + "'";
        var command = $"function global:php {{ & {Quote(executable)} -c {Quote(ini)} @args }}; " +
            "Write-Host 'PHPDevStack PowerShell - bundled PHP and configuration'; " +
            "Write-Host 'Run php --ini to check configuration; cd to your project to run its commands.'; php --ini";
        var start = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "powershell.exe"),
            WorkingDirectory = paths.PhpRoot,
            UseShellExecute = false,
            CreateNoWindow = false
        };
        start.ArgumentList.Add("-NoLogo");
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NoExit");
        start.ArgumentList.Add("-EncodedCommand");
        start.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(command)));
        start.Environment["PHPRC"] = ini;
        start.Environment["PHP_INI_SCAN_DIR"] = scanDirectory;
        start.Environment["PATH"] = string.Join(Path.PathSeparator, paths.PhpRoot,
            Path.Combine(paths.ApacheRoot, "bin"), Environment.GetEnvironmentVariable("PATH") ?? "");
        return start;
    }
}
