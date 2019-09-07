module sdfs.storager.configuration;

import std.path : buildPath;

import appbase.utils;
public import appbase.configuration;

class Config
{
    static void initConfiguration()
    {
        config.load(buildPath(getExePath(), "sdfs.storager.conf"));

        config.sys.protocol.magic.default_value!ushort = 0;
        config.sys.workThreads.default_value!int       = 0;
    }
}
