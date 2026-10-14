namespace DevStack.Core;

public sealed record StackOptions(
    int HttpPort = 8080,
    int MariaDbPort = 3307);
