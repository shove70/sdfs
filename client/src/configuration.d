module sdfs.client.configuration;

import std.path : buildPath;

import appbase.utils;
public import appbase.configuration;

class Config
{
    static void initConfiguration()
    {
        config.load(buildPath(getExePath(), "sdfs.client.conf"));

        config.sys.protocol.magic.default_value!ushort = 0;
    }
}
