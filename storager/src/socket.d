module sdfs.storager.socket;

import std.socket;

import sdfs.storager.configuration;

__gshared Socket trackerSocket;
__gshared Socket partnerSocket;

__gshared string partnerHost;
__gshared ushort partnerPort;

bool connectToTracker(ref string errorInfo)
{
    errorInfo = string.init;

    trackerSocket = new TcpSocket();
    trackerSocket.blocking = true;
    try
    {
        trackerSocket.connect(new InternetAddress(config.server.host.tracker.value, config.server.port.tracker.as!ushort));
    }
    catch (Exception e)
    {
        errorInfo = e.msg;

        return false;
    }

    try
    {
        trackerSocket.setKeepAlive(600, 10);
    }
    catch (Exception e)
    {
    }

    return trackerSocket.isAlive;
}

bool connectToPartner(ref string errorInfo)
{
    errorInfo = string.init;

    partnerSocket = new TcpSocket();
    partnerSocket.blocking = true;
    try
    {
        partnerSocket.connect(new InternetAddress(partnerHost, partnerPort));
    }
    catch (Exception e)
    {
        errorInfo = e.msg;

        return false;
    }

    try
    {
        partnerSocket.setKeepAlive(600, 10);
    }
    catch (Exception e)
    {
    }

    return partnerSocket.isAlive;
}
