using System.Net.Http;
using System.Net.Sockets;

namespace DevStack.Core;

public sealed class MailpitService : IDisposable
{
    public const int SmtpPort = 25;
    public const int WebPort = 8025;
    public const string InboxUrl = "http://127.0.0.1:8025/";
    private readonly StackPaths paths;
    private readonly ManagedProcess process;
    private readonly SemaphoreSlim lifecycle = new(1, 1);
    private string lastOutput = string.Empty;

    public MailpitService(StackPaths paths)
    {
        this.paths = paths;
        process = new ManagedProcess("Mailpit", Path.Combine(paths.MailpitRoot, "mailpit.exe"));
        process.OutputReceived += (_, line) =>
        {
            lastOutput = line;
            OutputReceived?.Invoke(this, line);
        };
        process.Exited += (_, _) => StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    public event EventHandler<string>? OutputReceived;
    public event EventHandler? StatusChanged;
    public bool IsRunning => process.IsRunning;

    public async Task StartAsync()
    {
        await lifecycle.WaitAsync();
        try
        {
            if (IsRunning) return;
            foreach (var port in new[] { SmtpPort, WebPort })
                if (!PortProbe.IsAvailable(port))
                    throw new InvalidOperationException($"Mailpit cannot start: port {port} is already in use.");

            Directory.CreateDirectory(paths.SmtpRoot);
            lastOutput = string.Empty;
            process.Start(Path.Combine(paths.MailpitRoot, "mailpit.exe"),
                $"--smtp 127.0.0.1:{SmtpPort} --listen 127.0.0.1:{WebPort} " +
                $"--database \"{Path.Combine(paths.SmtpRoot, "mailpit.db")}\" " +
                "--max 0 --disable-version-check --smtp-disable-rdns",
                paths.MailpitRoot, start =>
                {
                    // Machine/user Mailpit settings must not enable delivery or
                    // expose this local capture instance on other interfaces.
                    foreach (var key in start.Environment.Keys.Where(key => key.StartsWith("MP_", StringComparison.OrdinalIgnoreCase)).ToArray())
                        start.Environment.Remove(key);
                });

            try
            {
                using var client = new HttpClient(new HttpClientHandler { UseProxy = false }) { Timeout = TimeSpan.FromSeconds(1) };
                var deadline = DateTime.UtcNow.AddSeconds(15);
                while (DateTime.UtcNow < deadline)
                {
                    if (!IsRunning)
                        throw new InvalidOperationException($"Mailpit exited during startup. {lastOutput}");
                    try
                    {
                        using var smtp = new TcpClient();
                        await smtp.ConnectAsync("127.0.0.1", SmtpPort).WaitAsync(TimeSpan.FromSeconds(1));
                        using var response = await client.GetAsync(InboxUrl);
                        if (response.IsSuccessStatusCode) return;
                    }
                    catch (Exception exception) when (exception is SocketException or HttpRequestException or TaskCanceledException or TimeoutException) { }
                    await Task.Delay(100);
                }
                throw new TimeoutException($"Mailpit did not become ready on ports {SmtpPort} and {WebPort}. {lastOutput}");
            }
            catch
            {
                await process.StopAsync(TimeSpan.Zero);
                throw;
            }
        }
        finally
        {
            lifecycle.Release();
            StatusChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public async Task StopAsync()
    {
        await lifecycle.WaitAsync();
        try { await process.StopAsync(TimeSpan.Zero); }
        finally
        {
            lifecycle.Release();
            StatusChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public void Dispose()
    {
        process.Dispose();
        lifecycle.Dispose();
    }
}
