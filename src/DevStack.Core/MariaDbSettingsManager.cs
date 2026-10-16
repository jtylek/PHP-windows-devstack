using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace DevStack.Core;

public sealed record MariaDbSettings(int? BufferPoolSizeMb = null);

public sealed class MariaDbSettingsManager(StackPaths paths)
{
    private string SettingsPath => Path.Combine(paths.DataRoot, "config", "mariadb-settings.json");

    public MariaDbSettings Load()
    {
        if (!File.Exists(SettingsPath)) return new();
        try
        {
            var settings = JsonSerializer.Deserialize<MariaDbSettings>(File.ReadAllText(SettingsPath))
                ?? throw new InvalidOperationException("MariaDB settings must be a JSON object.");
            Validate(settings);
            return settings;
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException($"Invalid MariaDB settings: {SettingsPath}", exception);
        }
    }

    public void Save(MariaDbSettings settings)
    {
        Validate(settings);
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        var temporary = SettingsPath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, SettingsPath, overwrite: true);
    }

    public static void Validate(MariaDbSettings settings)
    {
        if (settings.BufferPoolSizeMb is int value && (value < 128 || value > 65536 || value % 64 != 0))
            throw new ArgumentOutOfRangeException(nameof(settings), "Buffer pool must be 128–65536 MB in multiples of 64, or blank for automatic sizing.");
    }

    // Follow the requested examples (1/16 RAM), not the conflicting 1/8 wording.
    // Use installed physical RAM so hardware-reserved memory does not turn 16G into 960M.
    public static int CalculateAutomaticSizeMb(ulong physicalMemoryBytes)
    {
        if (physicalMemoryBytes == 0) return 256; // conservative discovery-failure fallback
        var rounded = physicalMemoryBytes / (1024UL * 1024 * 16 * 64) * 64;
        return (int)Math.Clamp(rounded, 128UL, 2048UL);
    }

    public static ulong GetPhysicalMemoryBytes()
    {
        if (OperatingSystem.IsWindows() && GetPhysicallyInstalledSystemMemory(out var kilobytes))
            return kilobytes * 1024;
        return 0;
    }

    public string RenderBufferPoolSize(ulong? physicalMemoryBytes = null)
    {
        var megabytes = Load().BufferPoolSizeMb ?? CalculateAutomaticSizeMb(physicalMemoryBytes ?? GetPhysicalMemoryBytes());
        return megabytes % 1024 == 0
            ? (megabytes / 1024).ToString(CultureInfo.InvariantCulture) + "G"
            : megabytes.ToString(CultureInfo.InvariantCulture) + "M";
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetPhysicallyInstalledSystemMemory(out ulong totalMemoryInKilobytes);
}
