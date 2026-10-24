using System.Text.Json;

namespace DevStack.Core;

public sealed record PhpExtensionState(string Name, bool Enabled, bool Available);

public sealed record OpcacheSettings(
    bool Enabled = true,
    int MemoryConsumptionMb = 256,
    int InternedStringsBufferMb = 32,
    int MaxAcceleratedFiles = 20000,
    int RevalidateFrequencySeconds = 2,
    bool ValidateTimestamps = true,
    int RealpathCacheSizeKb = 4096,
    int RealpathCacheTtlSeconds = 600,
    int ZendAssertions = -1,
    bool DisplayErrors = false,
    int MemoryLimitMb = 256,
    bool ExposePhp = false);

public sealed class PhpConfigurationManager
{
    private static readonly string[] KnownExtensions =
    [
        "ctype", "curl", "fileinfo", "gd", "intl", "mbstring", "mysqli", "openssl", "pdo_mysql", "pdo_sqlite", "sodium", "sqlite3", "xml", "zip"
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
        if (settings.InternedStringsBufferMb < 1 || settings.InternedStringsBufferMb > 4096)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "OPcache interned strings buffer must be between 1 and 4096 MB.");
        }
        if (settings.MaxAcceleratedFiles < 100 || settings.MaxAcceleratedFiles > 1000000)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "OPcache file capacity must be between 100 and 1,000,000.");
        }
        if (settings.RevalidateFrequencySeconds < 0 || settings.RevalidateFrequencySeconds > 3600)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "OPcache revalidation must be between 0 and 3600 seconds.");
        }
        if (settings.RealpathCacheSizeKb < 256 || settings.RealpathCacheSizeKb > 1048576)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "Realpath cache size must be between 256 and 1,048,576 KB.");
        }
        if (settings.RealpathCacheTtlSeconds < 0 || settings.RealpathCacheTtlSeconds > 86400)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "Realpath cache TTL must be between 0 and 86400 seconds.");
        }
        if (settings.ZendAssertions is not (-1 or 0 or 1))
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "zend.assertions must be -1, 0, or 1.");
        }
        if (settings.MemoryLimitMb < 8 || settings.MemoryLimitMb > 16384)
        {
            throw new ArgumentOutOfRangeException(nameof(settings), "PHP memory limit must be between 8 and 16,384 MB.");
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
            "opcache.enable=1",
            "opcache.enable_cli=1",
            $"opcache.memory_consumption={settings.MemoryConsumptionMb}",
            $"opcache.interned_strings_buffer={settings.InternedStringsBufferMb}",
            $"opcache.max_accelerated_files={settings.MaxAcceleratedFiles}",
            $"opcache.revalidate_freq={settings.RevalidateFrequencySeconds}",
            $"opcache.validate_timestamps={(settings.ValidateTimestamps ? 1 : 0)}"
        ]);
    }

    public string RenderRuntimeSettings()
    {
        var settings = GetOpcacheSettings();
        return string.Join(Environment.NewLine,
        [
            $"realpath_cache_ttl={settings.RealpathCacheTtlSeconds}",
            $"realpath_cache_size={settings.RealpathCacheSizeKb}K",
            $"zend.assertions={settings.ZendAssertions}",
            $"display_errors={(settings.DisplayErrors ? "On" : "Off")}",
            $"display_startup_errors={(settings.DisplayErrors ? "On" : "Off")}",
            $"memory_limit={settings.MemoryLimitMb}M",
            $"expose_php={(settings.ExposePhp ? "On" : "Off")}"
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
