using System.Net;
using System.Net.Http;
using System.Net.Mail;
using System.Net.Sockets;
using System.Text.Json;
using DevStack.Core;

if (args.Length != 1) throw new ArgumentException("Pass an installed runtime/mailpit directory.");
var paths = new StackPaths(Path.Combine(Path.GetTempPath(), "DevStack Mailpit's checks " + Guid.NewGuid().ToString("N")));
using var service = new MailpitService(paths);
var oldRelay = Environment.GetEnvironmentVariable("MP_SMTP_RELAY_CONFIG");
var oldBind = Environment.GetEnvironmentVariable("MP_UI_BIND_ADDR");
void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
using var http = new HttpClient(new HttpClientHandler { UseProxy = false });
async Task<int> MessageCount()
{
    using var json = JsonDocument.Parse(await http.GetStringAsync(MailpitService.InboxUrl + "api/v1/messages"));
    return json.RootElement.GetProperty("total").GetInt32();
}
// A stopped Mailpit can keep its ports and files for a moment on a busy CI runner.
async Task WaitForPortsFree()
{
    for (var i = 0; i < 50 && !(PortProbe.IsAvailable(MailpitService.SmtpPort) && PortProbe.IsAvailable(MailpitService.WebPort)); i++)
        await Task.Delay(200);
}
async Task DeleteWithRetry(string path)
{
    for (var i = 0; i < 20 && Directory.Exists(path); i++)
    {
        try { Directory.Delete(path, recursive: true); }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException) { await Task.Delay(500); }
    }
    if (Directory.Exists(path)) Console.WriteLine($"Warning: could not remove temporary folder {path}.");
}
try
{
    try { await service.StartAsync(); throw new Exception("Missing Mailpit binary was accepted."); }
    catch (FileNotFoundException) { }
    Directory.CreateDirectory(paths.MailpitRoot);
    File.Copy(Path.Combine(Path.GetFullPath(args[0]), "mailpit.exe"), Path.Combine(paths.MailpitRoot, "mailpit.exe"));
    Directory.CreateDirectory(paths.SmtpRoot);
    var legacy = Path.Combine(paths.SmtpRoot, "legacy.eml");
    File.WriteAllText(legacy, "Subject: Legacy capture\r\n\r\nPreserve me.");

    foreach (var port in new[] { MailpitService.SmtpPort, MailpitService.WebPort })
    {
        using var occupied = new TcpListener(IPAddress.Loopback, port);
        occupied.Start();
        try { await service.StartAsync(); throw new Exception($"Occupied port {port} was accepted."); }
        catch (InvalidOperationException exception) when (exception.Message.Contains($"port {port}")) { }
        Check(!service.IsRunning, "Port conflict left Mailpit running.");
    }
    Environment.SetEnvironmentVariable("MP_SMTP_RELAY_CONFIG", Path.Combine(paths.Root, "nonexistent-relay.yml"));
    Environment.SetEnvironmentVariable("MP_UI_BIND_ADDR", "0.0.0.0:18025");
    await WaitForPortsFree();
    await service.StartAsync();
    Check(service.IsRunning, "Mailpit did not start.");
    await service.StartAsync(); // idempotent, no second process/bind
    using (var smtp = new SmtpClient("127.0.0.1", MailpitService.SmtpPort))
    using (var message = new MailMessage("sender@example.test", "recipient@example.test", "DevStack capture check", "<b>Hello Mailpit</b>") { IsBodyHtml = true })
        await smtp.SendMailAsync(message);
    Check(await MessageCount() == 1, "SMTP message did not reach the inbox API.");
    Check(File.Exists(Path.Combine(paths.SmtpRoot, "mailpit.db")), "Persistent database is missing.");

    await service.StopAsync();
    Check(!service.IsRunning && PortProbe.IsAvailable(MailpitService.SmtpPort) && PortProbe.IsAvailable(MailpitService.WebPort),
        "Stop did not release both ports.");
    await WaitForPortsFree();
    await service.StartAsync();
    Check(await MessageCount() == 1, "Captured message was lost after restart.");
    Check(File.ReadAllText(legacy).Contains("Preserve me."), "Legacy capture was changed.");
    using (var otherInstall = new MailpitService(new StackPaths(Path.Combine(paths.Root, "other-install"))))
        Check(!otherInstall.IsRunning, "Another installation's Mailpit was adopted.");
    using (var reconnected = new MailpitService(paths))
    {
        Check(reconnected.IsRunning, "Could not reconnect to this installation's Mailpit.");
        await reconnected.StopAsync();
    }
    Check(!service.IsRunning, "Stopped process is still reported as running.");
    // Repeated discovery during exit exercises short-lived process races on CI.
    for (var attempt = 0; attempt < 5; attempt++)
    {
        await WaitForPortsFree();
        await service.StartAsync();
        using var reconnected = new MailpitService(paths);
        Check(reconnected.IsRunning, "Reconnect lost the running process.");
        await reconnected.StopAsync();
        Check(!service.IsRunning, "Exited process was retained after reconnect/stop.");
    }
    Check(Environment.GetEnvironmentVariable("MP_SMTP_RELAY_CONFIG")!.EndsWith("nonexistent-relay.yml"),
        "Starting Mailpit mutated the parent environment.");
    Console.WriteLine("Mailpit capture, persistence, port conflicts, environment isolation and process detection passed.");
}
finally
{
    try { await service.StopAsync(); } catch (Exception exception) { Console.WriteLine($"Warning: stopping Mailpit failed during cleanup: {exception.Message}"); }
    Environment.SetEnvironmentVariable("MP_SMTP_RELAY_CONFIG", oldRelay);
    Environment.SetEnvironmentVariable("MP_UI_BIND_ADDR", oldBind);
    await DeleteWithRetry(paths.Root);
}
