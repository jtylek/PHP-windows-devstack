using System.Net;
using System.Net.Sockets;

namespace DevStack.Core;

public static class PortProbe
{
    public static bool IsAvailable(int port)
    {
        try
        {
            using var listener = new TcpListener(IPAddress.Loopback, port);
            listener.Start();
            listener.Stop();
            return true;
        }
        catch (SocketException)
        {
            return false;
        }
    }
}
