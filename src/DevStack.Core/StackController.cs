namespace DevStack.Core;

public sealed class StackController : IDisposable
{
    private readonly StackPaths paths;
    private readonly StackOptions options;
    private readonly ManagedProcess apache = new("Apache");
    private readonly ManagedProcess mariaDb = new("MariaDB");

    public StackController(StackPaths paths, StackOptions options)
    {
        this.paths = paths;
        this.options = options;
        apache.OutputReceived += ForwardOutput;
        mariaDb.OutputReceived += ForwardOutput;
        apache.Exited += (_, _) => StatusChanged?.Invoke(this, EventArgs.Empty);
        mariaDb.Exited += (_, _) => StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    public event EventHandler<string>? OutputReceived;
    public event EventHandler? StatusChanged;

    public bool IsApacheRunning => apache.IsRunning;
    public bool IsMariaDbRunning => mariaDb.IsRunning;

    public void StartAll()
    {
        if (!IsMariaDbRunning && !PortProbe.IsAvailable(options.MariaDbPort))
        {
            throw new InvalidOperationException($"Port {options.MariaDbPort} is already in use.");
        }

        if (!IsApacheRunning && !PortProbe.IsAvailable(options.HttpPort))
        {
            throw new InvalidOperationException($"Port {options.HttpPort} is already in use.");
        }

        new ConfigurationGenerator(paths, options).Generate();

        // PHP's Apache module loads php8ts.dll and extension dependencies from
        // the PHP directory. Child processes inherit this process-local PATH.
        var currentPath = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        var runtimePath = string.Join(
            Path.PathSeparator,
            paths.PhpRoot,
            Path.Combine(paths.ApacheRoot, "bin"),
            currentPath);
        Environment.SetEnvironmentVariable("PATH", runtimePath, EnvironmentVariableTarget.Process);

        mariaDb.Start(
            Path.Combine(paths.MariaDbRoot, "bin", "mariadbd.exe"),
            $"--defaults-file=\"{Path.Combine(paths.GeneratedConfigRoot, "mariadb.ini")}\" --console",
            paths.MariaDbRoot);

        apache.Start(
            Path.Combine(paths.ApacheRoot, "bin", "httpd.exe"),
            $"-f \"{Path.Combine(paths.GeneratedConfigRoot, "httpd.conf")}\"",
            paths.ApacheRoot);

        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    public async Task StopAllAsync()
    {
        await apache.StopAsync(TimeSpan.FromSeconds(5));
        await mariaDb.StopAsync(TimeSpan.FromSeconds(10));
        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    private void ForwardOutput(object? sender, string message) =>
        OutputReceived?.Invoke(this, message);

    public void Dispose()
    {
        apache.Dispose();
        mariaDb.Dispose();
    }
}
