namespace DevStack.Core;

public sealed record StackPaths(string Root)
{
    public string RuntimeRoot => Path.Combine(Root, "runtime");
    public string ApacheRoot => Path.Combine(RuntimeRoot, "apache");
    public string PhpRoot => Path.Combine(RuntimeRoot, "php");
    public string MariaDbRoot => Path.Combine(RuntimeRoot, "mariadb");
    public string TemplateRoot => Path.Combine(RuntimeRoot, "templates");
    public string GeneratedConfigRoot => Path.Combine(RuntimeRoot, "config", "generated");
    public string DataRoot => Path.Combine(Root, "data");
    public string MariaDbDataRoot => Path.Combine(DataRoot, "mariadb");
    public string LogRoot => Path.Combine(Root, "logs");
    public string SessionRoot => Path.Combine(DataRoot, "sessions");
    public string WebRoot => Path.Combine(Root, "www");

    public static StackPaths FromApplicationDirectory() =>
        new(Path.GetFullPath(AppContext.BaseDirectory));

    public void EnsureMutableDirectories()
    {
        Directory.CreateDirectory(GeneratedConfigRoot);
        Directory.CreateDirectory(MariaDbDataRoot);
        Directory.CreateDirectory(LogRoot);
        Directory.CreateDirectory(SessionRoot);
        Directory.CreateDirectory(WebRoot);
    }
}
