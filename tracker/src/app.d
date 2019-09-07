module sdfs.tracker.app;

import std.stdio : writeln;
import std.conv : to;
import std.exception : collectException;

import async;
import buffer;
import buffer.rpc.server;
import crypto.rsa;
import appbase.utils;
import appbase.listener;

import sdfs.tracker.configuration;
import sdfs.tracker.business;
import sdfs.tracker.leveldb;
import sdfs.tracker.storage;

__gshared Server!(Business) business;

void main()
{
    Config.initConfiguration();

    if (!LevelDB.open())
    {
        writeln("Open leveldb error.");

        return;
    }

    Storage.load();

    Message.settings(config.sys.protocol.magic.as!ushort);

    business = new Server!(Business)();

    startServer(config.server.port.as!ushort, config.sys.workThreads.as!int, config.sys.protocol.magic.as!ushort,
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
            logger.write("spiders.tracker send to " ~ remoteAddress ~ " Error. Original size: " ~ data.length.to!string ~ ", sent: " ~ sent_size.to!string);
        }
    }());
}
