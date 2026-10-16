using System.Diagnostics;

namespace DevStack.Core;

public sealed class ManagedProcess(string name) : IDisposable
{
    private readonly List<Process> processes = [];
    private string? executablePath;

    public event EventHandler<string>? OutputReceived;
    public event EventHandler? Exited;

    public ManagedProcess(string name, string executablePath) : this(name)
    {
        this.executablePath = Path.GetFullPath(executablePath);
        Refresh();
    }

    public bool IsRunning
    {
        get
        {
            Refresh();
            return processes.Count > 0;
        }
    }

    public void Refresh()
    {
        RemoveExitedProcesses();
        if (executablePath is null)
        {
            return;
        }

        var processName = Path.GetFileNameWithoutExtension(executablePath);
        foreach (var candidate in Process.GetProcessesByName(processName))
        {
            try
            {
                var candidatePath = candidate.MainModule?.FileName;
                if (candidatePath is not null &&
                    string.Equals(Path.GetFullPath(candidatePath), executablePath, StringComparison.OrdinalIgnoreCase))
                {
                    Track(candidate);
                }
                else
                {
                    candidate.Dispose();
                }
            }
            catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException)
            {
                candidate.Dispose();
            }
        }
    }

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

        executablePath = Path.GetFullPath(executable);
        var process = new Process
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
        if (!process.Start())
        {
            process.Dispose();
            throw new InvalidOperationException($"Windows did not start {name}.");
        }

        Track(process);
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
    }

    public async Task StopAsync(TimeSpan timeout)
    {
        Refresh();
        if (processes.Count == 0)
        {
            return;
        }

        var stopping = processes.ToArray();
        foreach (var process in stopping)
        {
            try { process.CloseMainWindow(); }
            catch (InvalidOperationException) { }
        }

        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            Refresh();
            if (processes.Count == 0)
            {
                return;
            }
            await Task.Delay(100);
        }

        // Apache can have several httpd.exe workers. Stop every process whose
        // executable was verified to be this installation's bundled binary.
        Refresh();
        foreach (var process in processes.ToArray())
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: false);
                }
            }
            catch (InvalidOperationException) { }
            catch (System.ComponentModel.Win32Exception) { }
        }

        foreach (var process in processes.ToArray())
        {
            try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5)); }
            catch (TimeoutException) { }
            catch (InvalidOperationException) { }
        }
        Refresh();
        if (processes.Count > 0)
        {
            throw new InvalidOperationException($"Could not stop {name} process(es): {string.Join(", ", processes.Select(process => process.Id))}.");
        }
    }

    private void Track(Process process)
    {
        if (processes.Any(existing => existing.Id == process.Id))
        {
            process.Dispose();
            return;
        }

        processes.Add(process);
        process.EnableRaisingEvents = true;
        process.Exited += (_, _) => Exited?.Invoke(this, EventArgs.Empty);
    }

    private void RemoveExitedProcesses()
    {
        foreach (var process in processes.ToArray())
        {
            try
            {
                if (!process.HasExited) continue;
            }
            catch (InvalidOperationException) { }
            processes.Remove(process);
            process.Dispose();
        }
    }

    private void Forward(string? message)
    {
        if (!string.IsNullOrWhiteSpace(message))
        {
            OutputReceived?.Invoke(this, $"[{name}] {message}");
        }
    }

    public void Dispose()
    {
        foreach (var process in processes)
        {
            process.Dispose();
        }
        processes.Clear();
    }
}
