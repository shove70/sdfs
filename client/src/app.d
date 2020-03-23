module sdfs.client.app;

import std.stdio : writeln, writefln;
import std.path;
import std.file;

import buffer.rpc.client;
import appbase.utils;

import sdfs.client.configuration;

extern (C) short sdfs_upload(const string trackerHost, const ushort trackerPort, const ushort messageMagic,
    const scope void[] content, ref string url, ref string errorInfo);

void main(string[] args)
{
    if (args.length < 2)
    {
        writeln("Usage: sdfs.client filename.");

        return;
    }

    if (!args[1].exists)
    {
        writefln("File %s not exists.", args[1]);

        return;
    }

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

    string url, errorInfo;
    immutable short result = sdfs_upload(
        config.server.host.tracker.value,
        config.server.port.tracker.as!ushort,
        config.sys.protocol.magic.as!ushort,
        read(args[1]),
        url, errorInfo);

    writeln(result);
    writeln(url);
    writeln(errorInfo);
}
