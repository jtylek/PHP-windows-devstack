using System.Text;
using DevStack.Core;

// No real runtime or services needed: exercise paths with spaces and apostrophes,
// missing runtimes, regenerated ini, and preservation of process/global state.
var root = Path.Combine(Path.GetTempPath(), "DevStack terminal's checks " + Guid.NewGuid().ToString("N"));
var paths = new StackPaths(root);
var originalPath = Environment.GetEnvironmentVariable("PATH");
var originalIni = Environment.GetEnvironmentVariable("PHPRC");
try
{
    try
    {
        PhpTerminal.CreateStartInfo(paths, new StackOptions());
        throw new Exception("Missing runtime should fail before starting PowerShell.");
    }
    catch (FileNotFoundException) { }

    Directory.CreateDirectory(paths.PhpRoot);
    Directory.CreateDirectory(paths.TemplateRoot);
    Directory.CreateDirectory(paths.GeneratedConfigRoot);
    File.WriteAllText(Path.Combine(paths.PhpRoot, "php.exe"), "test placeholder");
    File.WriteAllText(Path.Combine(paths.TemplateRoot, "php.ini.template"), "extension_dir=\"{{PHP_ROOT}}/ext\"");
    var apacheConfig = Path.Combine(paths.GeneratedConfigRoot, "httpd.conf");
    File.WriteAllText(apacheConfig, "preserve running Apache config");
    var start = PhpTerminal.CreateStartInfo(paths, new StackOptions());
    void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    var ini = Path.Combine(paths.GeneratedConfigRoot, "php.ini");
    Check(start.WorkingDirectory == paths.PhpRoot, "Wrong starting directory.");
    Check(!start.UseShellExecute && !start.CreateNoWindow, "Terminal must have its own visible console.");
    Check(start.Environment["PHPRC"] == ini && File.Exists(ini), "Missing generated ini selection.");
    Check(start.Environment["PATH"]!.StartsWith(paths.PhpRoot + Path.PathSeparator), "Bundled PHP must be first in PATH.");
    Check(Directory.Exists(start.Environment["PHP_INI_SCAN_DIR"]), "CLI scan directory must exist.");
    Check(start.ArgumentList.Contains("-NoProfile") && start.ArgumentList.Contains("-NoExit"), "Wrong PowerShell flags.");
    var command = Encoding.Unicode.GetString(Convert.FromBase64String(start.ArgumentList.Last()));
    Check(command.Contains("terminal''s") && command.Contains(" -c '") && command.Contains("@args"), "Unsafe quoting or missing ini/argument forwarding.");
    Check(File.ReadAllText(apacheConfig) == "preserve running Apache config", "Terminal changed Apache configuration.");
    Check(Environment.GetEnvironmentVariable("PATH") == originalPath && Environment.GetEnvironmentVariable("PHPRC") == originalIni,
        "Terminal configuration must not mutate the parent environment.");
    Console.WriteLine("PHP terminal configuration checks passed.");
}
finally
{
    if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
}
