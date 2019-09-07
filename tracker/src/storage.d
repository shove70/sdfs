module sdfs.tracker.storage;

import core.sync.rwmutex;
import std.exception : enforce;
import std.datetime;
import std.conv : to;
import std.algorithm.searching : count;
import std.json;
import std.parallelism;

import appbase.utils;

import sdfs.tracker.leveldb;

package class Storager
{
    ushort  group;
    ubyte   name;
    string  host;
    ushort  port;
    DateTime lastOnlineTime;

    this(const ushort group, const ubyte name, const string host, const ushort port, const DateTime lastOnlineTime)
    {
        enforce(name == 1 || name == 2, "The storager's name must be equal to 1 or 2 only.");

        this.group = group;
        this.name = name;
        this.host = host;
        this.port = port;
        this.lastOnlineTime = lastOnlineTime;
    }
}

class Storage
{
    __gshared private int interval = 600;
    __gshared private Storager[string] storagers;
    __gshared private string cached_all;
    __gshared private DateTime cached_all_tick;
    __gshared private string cached_all_key      = "__cached_all__";
    __gshared private string cached_all_tick_key = "__cached_all_tick__";

    __gshared private string[] cached_onlines;
    __gshared private DateTime cached_onlines_tick;

    __gshared private ReadWriteMutex _mutex;

    shared static this()
    {
        _mutex = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    static void load()
    {
        cached_all = LevelDB.get(cached_all_key, string.init);
        if (cached_all == string.init)
        {
            return;
        }
        cached_all_tick = dateTimeFromString(LevelDB.get(cached_all_tick_key, string.init), DateTime.init);

        JSONValue json;
        try
        {
            json = parseJSON(uncompressString(cached_all));
        }
        catch (Exception e)
        {
            return ;
        }

        try
        {
            json = json["data"];
            if (json.type != JSONType.array)
            {
                return;
            }
        }
        catch (Exception e)
        {
            return;
        }

        if (json.array.length == 0)
        {
            return;
        }

        foreach (JSONValue j; json.array)
        {
            ushort group = cast(ushort)j["group"].integer;
            ubyte name   = cast(ubyte)j["name"].integer;
            string host = j["host"].str;
            ushort port = cast(ushort)j["port"].integer;
            DateTime lastOnlineTime = dateTimeFromString(j["lastOnlineTime"].str, DateTime.init);

            string key = group.to!string ~ "." ~ name.to!string;
            Storager storager = new Storager(group, name, host, port, lastOnlineTime);
            storagers[key] = storager;
        }
    }

    static short register(const ushort group, const ubyte name, const string host, const ushort port, ref string allStoragers, ref string errorInfo)
    {
        allStoragers = string.init;
        errorInfo = string.init;

        string key = group.to!string ~ "." ~ name.to!string;
        DateTime now = appbase.utils.now;
        Storager storager;
        int state;

        synchronized (Storage.classinfo)
        {
            if (key !in storagers)
            {
                if (name != 1 && name != 2)
                {
                    errorInfo = "The storager's name must be equal to 1 or 2 only.";
                    return -1;
                }

                if (storagers.values.count!("a.group == b")(group) >= 2)
                {
                    errorInfo = "The same group can only run two more storagers.";
                    return -2;
                }

                storager = new Storager(group, name, host, port, now);
                storagers[key] = storager;
                state = 1;
            }
            else
            {
                storager = storagers[key];
                state = ((storager.host != host) || (storager.port != port) || (now - storager.lastOnlineTime >= interval.seconds)) ? 2 : 0;
                storager.host = host;
                storager.port = port;
                storager.lastOnlineTime = now;
            }
        }

        if ((state > 0) || (now - cached_all_tick >= interval.seconds))
        {
            synchronized (_mutex.writer)
            {
                if ((state > 0) || (now - cached_all_tick >= interval.seconds))
                {
                    JSONValue data;
                    data["data"] = [ null ];
                    data["data"].array.length = 0;

                    foreach (s; storagers)
                    {
                        JSONValue j = ["group": "", "name": "", "host": "", "port": "", "lastOnlineTime": "", "online": ""];
                        j["group"].integer      = s.group;
                        j["name"].integer       = s.name;
                        j["host"].str           = s.host;
                        j["port"].integer       = s.port;
                        j["lastOnlineTime"].str = dateTimeToString(s.lastOnlineTime);
                        j["online"].integer = (now - s.lastOnlineTime >= interval.seconds) ? 0 : 1;
                        data["data"].array ~= j;
                    }

                    cached_all = compressString(data.toString());
                    cached_all_tick = now;
                    LevelDB.put(cached_all_key, cached_all);
                    LevelDB.put(cached_all_tick_key, dateTimeToString(cached_all_tick));
                }
            }
        }

        allStoragers = cached_all;
        return 0;
    }

    static string get()
    {
        DateTime now = appbase.utils.now;

        if (now - cached_onlines_tick >= interval.seconds)
        {
            synchronized (_mutex.writer)
            {
                if (now - cached_onlines_tick >= interval.seconds)
                {
                    cached_onlines.length = 0;

                    foreach (storager; storagers)
                    {
                        if (now - storager.lastOnlineTime >= interval.seconds)
                            continue;

                        JSONValue data;
                        data["data"] = [ null ];
                        data["data"].array.length = 0;

                        JSONValue j = ["group": "", "name": "", "host": "", "port": ""];
                        j["group"].integer  = storager.group;
                        j["name"].integer   = storager.name;
                        j["host"].str       = storager.host;
                        j["port"].integer   = storager.port;
                        data["data"].array ~= j;

                        cached_onlines ~= compressString(data.toString());
                    }

                    cached_onlines_tick = now;
                }
            }
        }

        if (cached_onlines.length == 0)
            return string.init;

        return cached_onlines[rnd.next!size_t(0, cached_onlines.length - 1)];
    }

    static void reportFileChanged(const ushort group, const byte operation, const string keyHash)
    {
        if (operation == 1)
        {
            LevelDB.put(keyHash, group);
        }
        else if (operation == 2)
        {
            LevelDB.remove(keyHash);
        }
    }

    static string findFileUrl(const string keyHash)
    {
        ushort group = LevelDB.get(keyHash, cast(ushort) 0);
        if (group == 0)
        {
            return string.init;
        }

        return group.to!string ~ "/" ~ keyHash;
    }
}
