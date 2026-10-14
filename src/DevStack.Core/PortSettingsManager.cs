using System.Text.Json;

namespace DevStack.Core;

public sealed class PortSettingsManager
{
    private readonly StackPaths paths;
    private readonly JsonSerializerOptions jsonOptions = new() { WriteIndented = true };

    public PortSettingsManager(StackPaths paths) => this.paths = paths;

    public StackOptions Load()
    {
        var path = GetSettingsPath();
        if (!File.Exists(path))
        {
            return new StackOptions();
        }

        try
        {
            var settings = JsonSerializer.Deserialize<PortSettings>(File.ReadAllText(path), jsonOptions);
            return settings is null ? new StackOptions() : new StackOptions(settings.HttpPort, settings.MariaDbPort);
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException($"The port settings file is invalid: {path}", exception);
        }
    }

    public void Save(StackOptions current, int httpPort, int mariaDbPort)
    {
        ValidatePort(httpPort, "Apache");
        ValidatePort(mariaDbPort, "MariaDB");
        if (httpPort == mariaDbPort)
        {
            throw new InvalidOperationException("Apache and MariaDB must use different ports.");
        }

        if (httpPort != current.HttpPort && !PortProbe.IsAvailable(httpPort))
        {
            throw new InvalidOperationException($"Port {httpPort} is already in use and cannot be assigned to Apache.");
        }
        if (mariaDbPort != current.MariaDbPort && !PortProbe.IsAvailable(mariaDbPort))
        {
            throw new InvalidOperationException($"Port {mariaDbPort} is already in use and cannot be assigned to MariaDB.");
        }

        var path = GetSettingsPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(new PortSettings(httpPort, mariaDbPort), jsonOptions));
    }

    public void UpdatePhpMyAdminPort(int mariaDbPort)
    {
        var path = Path.Combine(paths.PhpMyAdminRoot, "config.inc.php");
        if (!File.Exists(path))
        {
            return;
        }

        var lines = File.ReadAllLines(path);
        const string prefix = "$cfg['Servers'][$i]['port']";
        for (var index = 0; index < lines.Length; index++)
        {
            if (lines[index].TrimStart().StartsWith(prefix, StringComparison.Ordinal))
            {
                lines[index] = $"$cfg['Servers'][$i]['port'] = {mariaDbPort};";
            }
        }
        File.WriteAllLines(path, lines);
    }

    private string GetSettingsPath() => Path.Combine(paths.DataRoot, "config", "ports.json");

    private static void ValidatePort(int port, string service)
    {
        if (port is < 1 or > 65535)
        {
            throw new ArgumentOutOfRangeException(nameof(port), $"{service} port must be between 1 and 65535.");
        }
    }

    private sealed record PortSettings(int HttpPort, int MariaDbPort);
}
