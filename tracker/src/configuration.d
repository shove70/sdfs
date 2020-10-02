module sdfs.tracker.configuration;

import std.path : buildPath;

import appbase.utils;
public import appbase.configuration;

class Config
{
    static void initConfiguration()
    {
        config.load(buildPath(getExePath(), "sdfs.tracker.conf"));

        config.sys.protocol.magic.default_value!ushort = 0;
        config.sys.businessThreads.default_value!int   = 64;
    }
}
