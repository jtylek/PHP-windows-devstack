namespace DevStack.Core;

public sealed class StackOptions
{
    public StackOptions(int httpPort = 80, int mariaDbPort = 3306)
    {
        HttpPort = httpPort;
        MariaDbPort = mariaDbPort;
    }

    public int HttpPort { get; set; }
    public int MariaDbPort { get; set; }
}
