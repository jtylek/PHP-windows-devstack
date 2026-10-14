using System.Net;
using System.Net.Sockets;
using System.Text;

namespace DevStack.Core;

public sealed class SmtpCaptureService : IAsyncDisposable
{
    private readonly string storageRoot;
    private readonly int port;
    private TcpListener? listener;
    private CancellationTokenSource? cancellation;

    public SmtpCaptureService(string storageRoot, int port = 25)
    {
        this.storageRoot = storageRoot;
        this.port = port;
    }

    public event EventHandler<string>? MessageCaptured;

    public bool IsRunning => listener is not null;

    public void Start()
    {
        if (IsRunning)
        {
            return;
        }

        Directory.CreateDirectory(storageRoot);
        cancellation = new CancellationTokenSource();
        listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        _ = AcceptConnectionsAsync(listener, cancellation.Token);
    }

    public async Task StopAsync()
    {
        var currentListener = listener;
        var currentCancellation = cancellation;
        listener = null;
        cancellation = null;
        currentCancellation?.Cancel();
        currentListener?.Stop();
        currentCancellation?.Dispose();
        await Task.CompletedTask;
    }

    public IReadOnlyList<SmtpCapturedMessage> GetMessages()
    {
        Directory.CreateDirectory(storageRoot);
        return Directory.EnumerateFiles(storageRoot, "*.eml", SearchOption.TopDirectoryOnly)
            .Select(path => SmtpCapturedMessage.FromFile(path))
            .OrderByDescending(message => message.ReceivedAt)
            .ToArray();
    }

    public string ReadMessage(SmtpCapturedMessage message) => File.ReadAllText(message.Path, Encoding.UTF8);

    public void DeleteMessage(SmtpCapturedMessage message)
    {
        if (File.Exists(message.Path))
        {
            File.Delete(message.Path);
        }
    }

    public void DeleteAllMessages()
    {
        foreach (var path in Directory.EnumerateFiles(storageRoot, "*.eml", SearchOption.TopDirectoryOnly))
        {
            File.Delete(path);
        }
    }

    private async Task AcceptConnectionsAsync(TcpListener currentListener, CancellationToken token)
    {
        try
        {
            while (!token.IsCancellationRequested)
            {
                var client = await currentListener.AcceptTcpClientAsync(token);
                _ = HandleClientAsync(client, token);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
        catch (ObjectDisposedException) when (token.IsCancellationRequested)
        {
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken serviceToken)
    {
        using (client)
        await using var stream = client.GetStream();
        using var reader = new StreamReader(stream, Encoding.ASCII, false, 1024, leaveOpen: true);
        await using var writer = new StreamWriter(stream, new UTF8Encoding(false), 1024, leaveOpen: true) { NewLine = "\r\n", AutoFlush = true };

        await writer.WriteLineAsync("220 DevStack SMTP capture ready");
        string? mailFrom = null;
        var recipients = new List<string>();

        try
        {
            while (!serviceToken.IsCancellationRequested)
            {
                var line = await reader.ReadLineAsync(serviceToken);
                if (line is null)
                {
                    break;
                }

                var command = line.Trim();
                var verb = command.Split(' ', 2)[0].ToUpperInvariant();
                switch (verb)
                {
                    case "EHLO":
                    case "HELO":
                        await writer.WriteLineAsync("250-DevStack");
                        await writer.WriteLineAsync("250 SIZE 52428800");
                        break;
                    case "MAIL":
                        mailFrom = ExtractAddress(command);
                        recipients.Clear();
                        await writer.WriteLineAsync("250 2.1.0 Sender OK");
                        break;
                    case "RCPT":
                        if (mailFrom is null)
                        {
                            await writer.WriteLineAsync("503 5.5.1 Send MAIL FROM first");
                            break;
                        }
                        recipients.Add(ExtractAddress(command));
                        await writer.WriteLineAsync("250 2.1.5 Recipient OK");
                        break;
                    case "DATA":
                        if (mailFrom is null || recipients.Count == 0)
                        {
                            await writer.WriteLineAsync("503 5.5.1 Send MAIL FROM and RCPT TO first");
                            break;
                        }
                        await writer.WriteLineAsync("354 End data with <CR><LF>.<CR><LF>");
                        var message = await ReadDataAsync(reader, serviceToken);
                        var path = SaveMessage(mailFrom, recipients, message);
                        MessageCaptured?.Invoke(this, path);
                        await writer.WriteLineAsync("250 2.0.0 Message captured");
                        mailFrom = null;
                        recipients.Clear();
                        break;
                    case "RSET":
                        mailFrom = null;
                        recipients.Clear();
                        await writer.WriteLineAsync("250 2.0.0 Reset");
                        break;
                    case "NOOP":
                        await writer.WriteLineAsync("250 2.0.0 OK");
                        break;
                    case "QUIT":
                        await writer.WriteLineAsync("221 2.0.0 Bye");
                        return;
                    default:
                        await writer.WriteLineAsync("502 5.5.2 Command not supported");
                        break;
                }
            }
        }
        catch (IOException)
        {
        }
        catch (OperationCanceledException) when (serviceToken.IsCancellationRequested)
        {
        }
    }

    private static async Task<string> ReadDataAsync(StreamReader reader, CancellationToken token)
    {
        var builder = new StringBuilder();
        while (true)
        {
            var line = await reader.ReadLineAsync(token);
            if (line is null || line == ".")
            {
                break;
            }
            builder.AppendLine(line.StartsWith("..", StringComparison.Ordinal) ? line[1..] : line);
        }
        return builder.ToString();
    }

    private string SaveMessage(string from, IReadOnlyCollection<string> recipients, string content)
    {
        var timestamp = DateTimeOffset.Now;
        var path = Path.Combine(storageRoot, $"{timestamp:yyyyMMdd-HHmmssfff}-{Guid.NewGuid():N}.eml");
        var headers = $"X-DevStack-Received: {timestamp:O}\r\nX-DevStack-Envelope-From: {from}\r\nX-DevStack-Envelope-To: {string.Join(", ", recipients)}\r\n\r\n";
        File.WriteAllText(path, headers + content, new UTF8Encoding(false));
        return path;
    }

    private static string ExtractAddress(string command)
    {
        var start = command.IndexOf('<');
        var end = command.IndexOf('>', start + 1);
        if (start >= 0 && end > start)
        {
            return command[(start + 1)..end];
        }
        var separator = command.IndexOf(':');
        return separator >= 0 ? command[(separator + 1)..].Trim() : command;
    }

    public async ValueTask DisposeAsync() => await StopAsync();
}

public sealed record SmtpCapturedMessage(string Path, DateTime ReceivedAt, long Size)
{
    public string FileName => System.IO.Path.GetFileName(Path);
    public string DisplayName => $"{ReceivedAt:yyyy-MM-dd HH:mm:ss}  {FileName}";

    public static SmtpCapturedMessage FromFile(string path) =>
        new(path, File.GetCreationTime(path), new FileInfo(path).Length);
}
