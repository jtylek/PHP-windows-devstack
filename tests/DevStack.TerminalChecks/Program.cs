using System.Text;
using DevStack.Core;

if (args.Length == 2 && args[0] == "--render")
{
    var installedPaths = new StackPaths(Path.GetFullPath(args[1]));
    new ConfigurationGenerator(installedPaths, new PortSettingsManager(installedPaths).Load()).Generate();
    return;
}

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

    // Verify the real templates render tuning into the server section, retain
    // selected ports, and never modify user database/project contents.
    var templates = Path.Combine(Directory.GetCurrentDirectory(), "runtime", "templates");
    foreach (var file in Directory.GetFiles(templates, "*.template"))
        File.Copy(file, Path.Combine(paths.TemplateRoot, Path.GetFileName(file)), overwrite: true);
    paths.EnsureMutableDirectories();
    var databaseSentinel = Path.Combine(paths.MariaDbDataRoot, "preserve-test.txt");
    var projectSentinel = Path.Combine(paths.WebRoot, "preserve-test.txt");
    File.WriteAllText(databaseSentinel, "database sentinel");
    File.WriteAllText(projectSentinel, "project sentinel");
    var mariaDbSettings = new MariaDbSettingsManager(paths);
    const ulong gib = 1024UL * 1024 * 1024;
    foreach (var (ram, expected) in new (ulong, int)[] { (2, 128), (4, 256), (8, 512), (16, 1024), (32, 2048), (64, 2048) })
        Check(MariaDbSettingsManager.CalculateAutomaticSizeMb(ram * gib) == expected, $"Wrong automatic size for {ram} GiB.");
    Check(MariaDbSettingsManager.CalculateAutomaticSizeMb(0) == 256, "Wrong RAM detection fallback.");
    Check(mariaDbSettings.RenderBufferPoolSize(16 * gib) == "1G", "Fresh 16 GiB machine must select 1G.");
    Check(mariaDbSettings.RenderBufferPoolSize(8 * gib) == "512M", "Fresh 8 GiB machine must select 512M.");
    mariaDbSettings.Save(new MariaDbSettings(512));
    Check(new MariaDbSettingsManager(paths).RenderBufferPoolSize(32 * gib) == "512M", "Saved override ignored.");
    mariaDbSettings.Save(new MariaDbSettings());
    Check(mariaDbSettings.RenderBufferPoolSize(32 * gib) == "2G", "Clearing override must restore automatic sizing.");
    foreach (var invalid in new[] { 0, -1, 127, 513, 65537 })
    {
        try { mariaDbSettings.Save(new MariaDbSettings(invalid)); throw new Exception("Invalid override accepted."); }
        catch (ArgumentOutOfRangeException) { }
    }
    mariaDbSettings.Save(new MariaDbSettings(1024));
    new ConfigurationGenerator(paths, new StackOptions(8088, 3311)).Generate();
    var databaseIni = File.ReadAllText(Path.Combine(paths.GeneratedConfigRoot, "mariadb.ini"));
    var serverSection = databaseIni.Split("[client]", StringSplitOptions.None)[0];
    foreach (var setting in new[] { "innodb_buffer_pool_size=1G", "innodb_flush_log_at_trx_commit=2",
        "innodb_log_file_size=256M", "innodb_io_capacity=1000", "innodb_io_capacity_max=4000",
        "table_definition_cache=1000", "tmp_table_size=64M", "max_heap_table_size=64M",
        "key_buffer_size=16M", "slow_query_log=1", "log_output=FILE", "long_query_time=1", "port=3311" })
        Check(serverSection.Split('\n').Any(line => line.Trim() == setting), "Missing server setting: " + setting);
    Check(serverSection.Contains(paths.LogRoot.Replace('\\', '/') + "/mariadb-slow.log"), "Wrong slow log path.");
    Check(!databaseIni.Contains("{{"), "Unresolved database template token.");
    Check(File.ReadAllText(databaseSentinel) == "database sentinel" && File.ReadAllText(projectSentinel) == "project sentinel",
        "Config generation modified user data.");
    Console.WriteLine("MariaDB development template checks passed.");
}
finally
{
    if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
}
