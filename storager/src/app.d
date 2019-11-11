module sdfs.storager.app;

import core.thread : Thread;
import std.conv : to;
import std.exception : collectException, enforce;
import std.datetime;
import std.stdio : writeln;
import std.typecons;
import std.json;

import async;
import buffer;
import buffer.rpc.server;
import buffer.rpc.client;
import crypto.rsa;
import appbase.utils;
import appbase.listener;

import sdfs.storager.configuration;
import sdfs.storager.business;
import sdfs.storager.socket;
import sdfs.storager.synchronizer;

__gshared Server!(Business) business;

void main()
{
    version (Posix)
    {
        import core.sys.posix.signal;
        sigset_t mask1;
        sigemptyset(&mask1);
        sigaddset(&mask1, SIGPIPE);
        sigaddset(&mask1, SIGILL);
        sigprocmask(SIG_BLOCK, &mask1, null);
    }

    Config.initConfiguration();

    string errorInfo;
    if (!connectToTracker(errorInfo))
    {
        writeln("Connect to tracker fail: " ~ errorInfo);
        return;
    }

    Message.settings(config.sys.protocol.magic.as!ushort);

    immutable result = register(errorInfo);
    if (result < 0)
    {
        writeln("Register to tracker fail: " ~ errorInfo);
        return;
    }

    business = new Server!(Business)();

    new Thread({ registerTask(); }).start();
    new Thread({ synchronizeToTrackerTask(); }).start();

    startServer(config.storager.port.as!ushort, config.sys.workThreads.as!int, config.sys.protocol.magic.as!ushort,
        &onRequest, &onSendCompleted);
}

private void onRequest(TcpClient client, const scope ubyte[] data)
{
    ubyte[] ret_data = business.Handler(data, client.remoteAddress.toAddrString());

    client.send(ret_data);
}

void onSendCompleted(const int fd, string remoteAddress, const scope ubyte[] data, const size_t sent_size) nothrow @trusted
{
    collectException({
        if (sent_size != data.length)
        {
            logger.write("sdfs.storager send to " ~ remoteAddress ~ " Error. Original size: " ~ data.length.to!string ~ ", sent: " ~ sent_size.to!string);
        }
    }());
}


private:

__gshared int interval = 60;

short register(ref string errorInfo)
{
    int trys = 0;
    label_register:

    RegisterResponse res;
    try
    {
        res = Client.callEx!RegisterResponse(
            config.server.host.tracker.value, config.server.port.tracker.as!ushort,
            config.sys.protocol.magic.as!ushort, CryptType.NONE, string.init, Nullable!RSAKeyInfo(),
            "register",
            config.storager.group.as!ushort,
            config.storager.name.as!ubyte,
            config.storager.host.value,
            config.storager.port.as!ushort);
    }
    catch (Exception e)
    {
        if (++trys < 3)
        {
            Thread.sleep(200.msecs);
            goto label_register;
        }

        errorInfo = e.msg;
        return -1;
    }

    if (res is null)
    {
        if (++trys < 3)
        {
            Thread.sleep(200.msecs);
            goto label_register;
        }

        errorInfo = "sfds.storager register task fail.";
        return -2;
    }

    if (res.result < 0)
    {
        errorInfo = res.description;
        return res.result;
    }

    enforce(res.allStoragers != string.init);

    if (partnerHost == string.init)
    {
        JSONValue json = parseJSON(uncompressString(res.allStoragers))["data"];
        foreach (JSONValue j; json.array)
        {
            ushort group = cast(ushort)j["group"].integer;
            ubyte name = cast(ubyte)j["name"].integer;

            if ((group == config.storager.group.as!ushort) && (name != config.storager.name.as!ubyte))
            {
                if (cast(byte)j["online"].integer == 1)
                {
                    partnerHost = j["host"].str;
                    partnerPort = cast(ushort)j["port"].integer;
                }

                break;
            }
        }

        if (partnerHost != string.init)
        {
            new Thread({ synchronizeToPartnerTask(); }).start();
        }
    }

    return 0;
}

void registerTask()
{
    while (true)
    {
        scope(failure)
        {
            logger.write("System Failure in registerTask().");
            continue;
        }

        Thread.sleep(interval.seconds);

        string errorInfo;
        immutable result = register(errorInfo);

        if (result < 0)
        {
            logger.write(errorInfo);
            continue;
        }
    }
}

void synchronizeToTrackerTask()
{
    while (true)
    {
        Thread.sleep(50.msecs);

        scope(failure)
        {
            logger.write("System Failure in synchronizeToTrackerTask().");
            Thread.sleep(10.seconds);

            continue;
        }

        string errorInfo = string.init;
        if (!trackerSocket.isAlive && !connectToTracker(errorInfo))
        {
            logger.write("Connect to tracker fail: " ~ errorInfo);
            Thread.sleep(10.seconds);

            continue;
        }

        Synchronizer.synchronizeToTracker();
    }
}

void synchronizeToPartnerTask()
{
    enforce(partnerHost != string.init);

    while (true)
    {
        Thread.sleep(50.msecs);

        scope(failure)
        {
            logger.write("System Failure in synchronizeToPartnerTask().");
            Thread.sleep(10.seconds);

            continue;
        }

        string errorInfo = string.init;
        if (((partnerSocket is null) || !partnerSocket.isAlive) && !connectToPartner(errorInfo))
        {
            logger.write("Connect to partner fail: " ~ errorInfo);
            Thread.sleep(10.seconds);

            continue;
        }

        Synchronizer.synchronizeToPartner();
    }
}
