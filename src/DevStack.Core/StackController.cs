namespace DevStack.Core;

public sealed class StackController : IDisposable
{
    private readonly StackPaths paths;
    private readonly StackOptions options;
    private readonly ManagedProcess apache;
    private readonly ManagedProcess mariaDb;

    public StackController(StackPaths paths, StackOptions options)
    {
        this.paths = paths;
        this.options = options;
        apache = new ManagedProcess("Apache", Path.Combine(paths.ApacheRoot, "bin", "httpd.exe"));
        mariaDb = new ManagedProcess("MariaDB", Path.Combine(paths.MariaDbRoot, "bin", "mariadbd.exe"));
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

        ConfigureRuntimePath();

        mariaDb.Start(
            Path.Combine(paths.MariaDbRoot, "bin", "mariadbd.exe"),
            $"--defaults-file=\"{Path.Combine(paths.GeneratedConfigRoot, "mariadb.ini")}\" --console",
            paths.MariaDbRoot);

        StartApache();

        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    public void StartApacheOnly()
    {
        if (IsApacheRunning)
        {
            return;
        }
        if (!PortProbe.IsAvailable(options.HttpPort))
        {
            throw new InvalidOperationException($"Port {options.HttpPort} is already in use.");
        }

        new ConfigurationGenerator(paths, options).Generate();
        ConfigureRuntimePath();
        OutputReceived?.Invoke(this, "Starting Apache...");
        StartApache();
        OutputReceived?.Invoke(this, "Apache started.");
        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    public void StartMariaDbOnly()
    {
        if (IsMariaDbRunning)
        {
            return;
        }
        if (!PortProbe.IsAvailable(options.MariaDbPort))
        {
            throw new InvalidOperationException($"Port {options.MariaDbPort} is already in use.");
        }

        new ConfigurationGenerator(paths, options).Generate();
        OutputReceived?.Invoke(this, "Starting MariaDB...");
        mariaDb.Start(
            Path.Combine(paths.MariaDbRoot, "bin", "mariadbd.exe"),
            $"--defaults-file=\"{Path.Combine(paths.GeneratedConfigRoot, "mariadb.ini")}\" --console",
            paths.MariaDbRoot);
        OutputReceived?.Invoke(this, "MariaDB started.");
        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    public async Task StopAllAsync()
    {
        await StopApacheAsync();
        await StopMariaDbAsync();
    }

    public async Task StopApacheAsync()
    {
        OutputReceived?.Invoke(this, "Stopping Apache...");
        await apache.StopAsync(TimeSpan.FromSeconds(5));
        OutputReceived?.Invoke(this, "Apache stopped.");
        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    public async Task StopMariaDbAsync()
    {
        OutputReceived?.Invoke(this, "Stopping MariaDB...");
        await mariaDb.StopAsync(TimeSpan.FromSeconds(10));
        OutputReceived?.Invoke(this, "MariaDB stopped.");
        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    public async Task RestartApacheAsync()
    {
        if (!IsApacheRunning)
        {
            return;
        }

        await apache.StopAsync(TimeSpan.FromSeconds(5));
        new ConfigurationGenerator(paths, options).Generate();
        ConfigureRuntimePath();
        StartApache();
        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    private void ConfigureRuntimePath()
    {
        // PHP's Apache module loads php8ts.dll and extension dependencies from
        // the PHP directory. Child processes inherit this process-local PATH.
        var currentPath = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        var runtimePath = string.Join(
            Path.PathSeparator,
            paths.PhpRoot,
            Path.Combine(paths.ApacheRoot, "bin"),
            currentPath);
        Environment.SetEnvironmentVariable("PATH", runtimePath, EnvironmentVariableTarget.Process);
    }

    private void StartApache() => apache.Start(
        Path.Combine(paths.ApacheRoot, "bin", "httpd.exe"),
        $"-f \"{Path.Combine(paths.GeneratedConfigRoot, "httpd.conf")}\"",
        paths.ApacheRoot);

    private void ForwardOutput(object? sender, string message) =>
        OutputReceived?.Invoke(this, message);

    public void Dispose()
    {
        apache.Dispose();
        mariaDb.Dispose();
    }
}
