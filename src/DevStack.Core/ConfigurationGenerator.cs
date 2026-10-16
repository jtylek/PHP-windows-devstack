namespace DevStack.Core;

public sealed class ConfigurationGenerator(StackPaths paths, StackOptions options)
{
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
            ["PHP_RUNTIME_SETTINGS"] = phpConfiguration.RenderRuntimeSettings(),
            ["OPCACHE_SETTINGS"] = phpConfiguration.RenderOpcache(),
            ["HTTP_PORT"] = options.HttpPort.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["MARIADB_PORT"] = options.MariaDbPort.ToString(System.Globalization.CultureInfo.InvariantCulture)
        };

        var contents = File.ReadAllText(templatePath);
        foreach (var value in values)
        {
            contents = contents.Replace($"{{{{{value.Key}}}}}", value.Value, StringComparison.Ordinal);
        }

        if (contents.Contains("{{", StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"Unresolved token in {templateName}.");
        }

        File.WriteAllText(Path.Combine(paths.GeneratedConfigRoot, outputName), contents);
    }

    private static string Normalize(string path) => path.Replace('\\', '/');
}
