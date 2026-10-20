using System.Text.RegularExpressions;

namespace DevStack.Core;

public sealed class ConfigurationGenerator(StackPaths paths, StackOptions options)
{
    private const string ManagedCaSettingComment = "; PHPDevStack managed CA default; change this in php.ini.template to override.";
    private static readonly Regex CaDirective = new(@"^[ 	]*(?<name>curl\.cainfo|openssl\.cafile)[ 	]*=[ 	]*(?<value>.*?)[ 	]*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);
    private static readonly Regex CaDirectiveLine = new(@"^[ 	]*(?:curl\.cainfo|openssl\.cafile)[ 	]*=.*(?:\r?\n|$)", RegexOptions.Multiline | RegexOptions.IgnoreCase);
    private readonly PhpConfigurationManager phpConfiguration = new(paths);

    public void GeneratePhpConfiguration()
    {
        paths.EnsureMutableDirectories();
        Render("php.ini.template", "php.ini");
    }

    public void Generate()
    {
        paths.EnsureMutableDirectories();

        Render("httpd.conf.template", "httpd.conf");
        Render("php.ini.template", "php.ini");
        Render("mariadb.ini.template", "mariadb.ini");
    }

    private void Render(string templateName, string outputName)
    {
        var templatePath = Path.Combine(paths.TemplateRoot, templateName);
        if (!File.Exists(templatePath))
        {
            throw new FileNotFoundException($"Configuration template is missing: {templatePath}");
        }

        var contents = File.ReadAllText(templatePath);
        var runtimeSettings = phpConfiguration.RenderRuntimeSettings();
        if (templateName.Equals("php.ini.template", StringComparison.OrdinalIgnoreCase))
        {
            var outputPath = Path.Combine(paths.GeneratedConfigRoot, outputName);
            var existingOutput = File.Exists(outputPath) ? File.ReadAllText(outputPath) : string.Empty;
            var caSettings = ReadCustomCaSettings(contents, paths.CaBundlePath);
            foreach (var setting in ReadCustomCaSettings(existingOutput, paths.CaBundlePath))
            {
                caSettings.TryAdd(setting.Key, setting.Value);
            }

            contents = CaDirectiveLine.Replace(contents, string.Empty);
            runtimeSettings = string.Join(Environment.NewLine,
                runtimeSettings,
                RenderCaSettings(caSettings, paths.CaBundlePath));
        }

        var values = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["APACHE_ROOT"] = Normalize(paths.ApacheRoot),
            ["PHPMYADMIN_ROOT"] = Normalize(paths.PhpMyAdminRoot),
            ["PHP_ROOT"] = Normalize(paths.PhpRoot),
            ["MARIADB_ROOT"] = Normalize(paths.MariaDbRoot),
            ["MARIADB_DATA_ROOT"] = Normalize(paths.MariaDbDataRoot),
            ["CONFIG_ROOT"] = Normalize(paths.GeneratedConfigRoot),
            ["WWW_ROOT"] = Normalize(paths.WebRoot),
            ["LOG_ROOT"] = Normalize(paths.LogRoot),
            ["SESSION_ROOT"] = Normalize(paths.SessionRoot),
            ["PHP_EXTENSIONS"] = phpConfiguration.RenderExtensions(),
            ["PHP_RUNTIME_SETTINGS"] = runtimeSettings,
            ["OPCACHE_SETTINGS"] = phpConfiguration.RenderOpcache(),
            ["HTTP_PORT"] = options.HttpPort.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["MARIADB_PORT"] = options.MariaDbPort.ToString(System.Globalization.CultureInfo.InvariantCulture)
        };

        foreach (var value in values)
        {
            contents = contents.Replace($"{{{{{value.Key}}}}}", value.Value, StringComparison.Ordinal);
        }

        if (contents.Contains("{{INNODB_BUFFER_POOL_SIZE}}", StringComparison.Ordinal))
            contents = contents.Replace("{{INNODB_BUFFER_POOL_SIZE}}",
                new MariaDbSettingsManager(paths).RenderBufferPoolSize(), StringComparison.Ordinal);

        if (contents.Contains("{{", StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"Unresolved token in {templateName}.");
        }

        File.WriteAllText(Path.Combine(paths.GeneratedConfigRoot, outputName), contents);
    }

    private static Dictionary<string, string> ReadCustomCaSettings(string iniContents, string managedBundlePath)
    {
        var settings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match match in CaDirective.Matches(iniContents))
        {
            var value = match.Groups["value"].Value.Trim();
            var unquoted = value.Trim().Trim('"', '\'').Replace('\\', '/');
            var normalizedManagedPath = Normalize(managedBundlePath);
            var isManagedBundle = unquoted.Equals(normalizedManagedPath, StringComparison.OrdinalIgnoreCase) ||
                unquoted.EndsWith("/runtime/certificates/cacert.pem", StringComparison.OrdinalIgnoreCase);
            if (!isManagedBundle)
            {
                settings[match.Groups["name"].Value] = value;
            }
        }
        return settings;
    }

    private static string RenderCaSettings(IReadOnlyDictionary<string, string> overrides, string caBundlePath)
    {
        var bundlePath = Normalize(caBundlePath);
        var quotedBundlePath = "\"" + bundlePath + "\"";
        var curl = overrides.TryGetValue("curl.cainfo", out var curlOverride)
            ? curlOverride
            : quotedBundlePath;
        var openssl = overrides.TryGetValue("openssl.cafile", out var sslOverride)
            ? sslOverride
            : quotedBundlePath;
        return string.Join(Environment.NewLine,
        [
            ManagedCaSettingComment,
            $"curl.cainfo={curl}",
            ManagedCaSettingComment,
            $"openssl.cafile={openssl}"
        ]);
    }

    private static string Normalize(string path) => path.Replace('\\', '/');
}
