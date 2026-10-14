using System.Diagnostics;

namespace DevStack.Core;

public sealed class ManagedProcess(string name) : IDisposable
{
    private Process? process;

    public event EventHandler<string>? OutputReceived;
    public event EventHandler? Exited;

    public bool IsRunning => process is { HasExited: false };

    public void Start(string executable, string arguments, string workingDirectory)
    {
        if (IsRunning)
        {
            return;
        }

        if (!File.Exists(executable))
        {
            throw new FileNotFoundException($"{name} executable is missing: {executable}");
        }

        process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = executable,
                Arguments = arguments,
                WorkingDirectory = workingDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            },
            EnableRaisingEvents = true
        };

        process.OutputDataReceived += (_, eventArgs) => Forward(eventArgs.Data);
        process.ErrorDataReceived += (_, eventArgs) => Forward(eventArgs.Data);
        process.Exited += (_, _) => Exited?.Invoke(this, EventArgs.Empty);

        if (!process.Start())
        {
            throw new InvalidOperationException($"Windows did not start {name}.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
    }

    public async Task StopAsync(TimeSpan timeout)
    {
        if (!IsRunning || process is null)
        {
            return;
        }

        process.CloseMainWindow();
        using var timeoutSource = new CancellationTokenSource(timeout);
        try
        {
            await process.WaitForExitAsync(timeoutSource.Token);
        }
        catch (OperationCanceledException)
        {
            process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync();
        }
    }

    private void Forward(string? message)
    {
        if (!string.IsNullOrWhiteSpace(message))
        {
            OutputReceived?.Invoke(this, $"[{name}] {message}");
        }
    }

    public void Dispose() => process?.Dispose();
}
