module sdfs.access.configuration;

import std.path : buildPath;

import appbase.utils;
public import appbase.configuration;

class Config
{
    static void initConfiguration()
    {
        config.load(buildPath(getExePath(), "sdfs.access.conf"));
    }
}
