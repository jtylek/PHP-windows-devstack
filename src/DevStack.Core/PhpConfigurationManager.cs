using System.Text.Json;

namespace DevStack.Core;

public sealed record PhpExtensionState(string Name, bool Enabled, bool Available);

public sealed record OpcacheSettings(
    bool Enabled = true,
    int MemoryConsumptionMb = 256,
    int MaxAcceleratedFiles = 20000,
    int RevalidateFrequencySeconds = 2);

public sealed class PhpConfigurationManager
{
    private static readonly string[] KnownExtensions =
    [
        "ctype", "curl", "fileinfo", "gd", "intl", "mbstring", "mysqli", "openssl", "pdo_mysql", "sodium", "xml", "zip"
    ];

    // PHP 8.5 ships these extensions in the core binary instead of as DLLs
    // under ext. They are always available and must not be emitted as
    // extension= directives in php.ini.
    private static readonly HashSet<string> BuiltInExtensions = ["ctype", "pdo", "tokenizer", "xml"];

    private readonly StackPaths paths;
    private readonly JsonSerializerOptions jsonOptions = new() { WriteIndented = true };

    public PhpConfigurationManager(StackPaths paths)
    {
        this.paths = paths;
    }

    public IReadOnlyList<PhpExtensionState> GetExtensionStates()
    {
        var saved = LoadSettings();
        return KnownExtensions
            .Select(name => new PhpExtensionState(name, saved.Extensions.TryGetValue(name, out var enabled) ? enabled : true, IsAvailable(name)))
            .ToArray();
    }

    public void SaveExtensionStates(IEnumerable<PhpExtensionState> states)
    {
        var settings = LoadSettings();
        foreach (var state in states)
        {
            if (!KnownExtensions.Contains(state.Name, StringComparer.Ordinal))
            {
                throw new ArgumentException($"Unknown PHP extension: {state.Name}", nameof(states));
            }
            if (!IsAvailable(state.Name) && state.Enabled)
            {
                throw new InvalidOperationException($"PHP extension '{state.Name}' is not available in this runtime.");
            }
            settings.Extensions[state.Name] = state.Enabled;
        }
        SaveSettings(settings);
    }

    public OpcacheSettings GetOpcacheSettings() => LoadSettings().Opcache;

    public void SaveOpcacheSettings(OpcacheSettings settings)
    {
        if (settings.MemoryConsumptionMb < 8 || settings.MemoryConsumptionMb > 4096)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "OPcache memory must be between 8 and 4096 MB.");
        }
        if (settings.MaxAcceleratedFiles < 100 || settings.MaxAcceleratedFiles > 1000000)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "OPcache file capacity must be between 100 and 1,000,000.");
        }
        if (settings.RevalidateFrequencySeconds < 0 || settings.RevalidateFrequencySeconds > 3600)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "OPcache revalidation must be between 0 and 3600 seconds.");
        }

        var saved = LoadSettings();
        saved.Opcache = settings;
        SaveSettings(saved);
    }

    public string RenderExtensions() => string.Join(Environment.NewLine,
        GetExtensionStates()
            .Where(state => state.Enabled && state.Available && !BuiltInExtensions.Contains(state.Name))
            .Select(state => $"extension={state.Name}"));

    public string RenderOpcache()
    {
        var settings = GetOpcacheSettings();
        if (!settings.Enabled)
        {
            return "; OPcache disabled";
        }

        return string.Join(Environment.NewLine,
        [
            "zend_extension=opcache",
            "opcache.enable=1",
            "opcache.enable_cli=0",
            $"opcache.memory_consumption={settings.MemoryConsumptionMb}",
            "opcache.interned_strings_buffer=32",
            $"opcache.max_accelerated_files={settings.MaxAcceleratedFiles}",
            $"opcache.revalidate_freq={settings.RevalidateFrequencySeconds}"
        ]);
    }

    private bool IsAvailable(string name) => BuiltInExtensions.Contains(name) || File.Exists(Path.Combine(paths.PhpRoot, "ext", $"php_{name}.dll"));

    private PhpSettings LoadSettings()
    {
        var path = GetSettingsPath();
        if (!File.Exists(path)) return new PhpSettings();
        try
        {
            return JsonSerializer.Deserialize<PhpSettings>(File.ReadAllText(path), jsonOptions) ?? new PhpSettings();
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException($"The PHP settings file is invalid: {path}", exception);
        }
    }

    private void SaveSettings(PhpSettings settings)
    {
        var path = GetSettingsPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(settings, jsonOptions));
    }

    private string GetSettingsPath() => Path.Combine(paths.DataRoot, "config", "php-settings.json");

    private sealed class PhpSettings
    {
        public Dictionary<string, bool> Extensions { get; set; } = new(StringComparer.Ordinal);
        public OpcacheSettings Opcache { get; set; } = new();
    }
}
