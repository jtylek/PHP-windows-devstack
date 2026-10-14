namespace DevStack.Core;

public sealed class StackOptions
{
    public StackOptions(int httpPort = 8080, int mariaDbPort = 3307)
    {
        HttpPort = httpPort;
        MariaDbPort = mariaDbPort;
    }

    public int HttpPort { get; set; }
    public int MariaDbPort { get; set; }
}
