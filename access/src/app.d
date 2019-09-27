module sdfs.access.app;

import core.time;
import std.path : buildPath, stripExtension, baseName;
import std.range;
import std.file : exists, read, DirEntry;
import std.string : endsWith, startsWith, chompPrefix, rightJustify, capitalize;
import std.stdio : writeln, writefln;
import std.datetime;
import std.digest.md : hexDigest, MD5;
import std.conv : to;
import std.array : split, Appender;
import std.format : format;
import std.algorithm.searching : canFind;
import std.typecons : Nullable;

import lighttp;
import cachetools;
import appbase.utils;

import sdfs.access.configuration;

__gshared auto g_cache = new Cache2Q!(string, FileInfo);

void main()
{
	Config.initConfiguration();

    if (config.business.cache.size.as!uint > 0)
    {
        g_cache.size = config.business.cache.size.as!uint;
    }

    auto server = new Server();
    server.host("0.0.0.0", config.server.port.as!ushort);
    server.host("::", config.server.port.as!ushort);
    server.router.add(new StaticRouter());
    writefln("sdfs.access start listening to 0.0.0.0:%d...", config.server.port.as!ushort);
    server.run();
}

class StaticRouter
{
    @Get(`^(\d+)[\/]([A-F0-9]{40})([\.].+)*`)
	get(ServerRequest req, ServerResponse res, string path, string filename, string ext)
    {
        if (path != config.storager.data.route.value)
        {
            res.status = StatusCodes.notFound;
            return;
        }

        const string name = buildPath(config.storager.data.path.value, filename[0..3], filename[3..6], filename[6..9], filename);

        string realname = name ~ "$$";
        if (realname.exists)
        {
            setResponse(req, res, realname, filename);
            return;
        }

        realname = name ~ "$_";
        if (realname.exists)
        {
            setResponse(req, res, realname, filename);
            return;
        }

        realname = name ~ "_$";
        if (realname.exists)
        {
            setResponse(req, res, realname, filename);
            return;
        }

        realname = name ~ "__";
        if (realname.exists)
        {
            setResponse(req, res, realname, filename);
            return;
        }

        res.status = StatusCodes.notFound;
    }

    void setResponse(ServerRequest req, ServerResponse res, const string filename, const string key)
    {
        auto fi = g_cache.get(key);

        if (fi.isNull)
        {
            try
            {
                fi = makeFileInfo(filename);
            }
            catch (Exception e)
            {
                res.status = StatusCodes.internalServerError;
                return;
            }

            if (fi.isNull)
            {
                res.status = StatusCodes.notFound;
                return;
            }

            try
            {
                fi.get.data = cast(char[]) read(filename);
            }
            catch (Exception e)
            {
                writeln("access internalServerError: " ~ e.msg);
                logger.write("access internalServerError: " ~ e.msg);
                res.status = StatusCodes.internalServerError;
                return;
            }

            g_cache.put(key, fi.get);
        }

        immutable lastModified = toRFC822DateTimeString(fi.get.timeModified.toUTC());
        immutable etag = "\"" ~ hexDigest!(std.digest.md.MD5)(filename ~ ":" ~ lastModified ~ ":" ~ to!string(fi.get.data.length)).idup ~ "\"";
        res.headers["Last-Modified"] = lastModified;
        res.headers["Etag"] = etag;

        immutable expireTime = Clock.currTime(UTC()) + 1.days;
        res.headers["Expires"] = toRFC822DateTimeString(expireTime);
        res.headers["Cache-Control"] = "max-age=86400";

        if ((req.headers.get("If-Modified-Since", string.init) == lastModified) ||
            (req.headers.get("If-None-Match", string.init) == etag))
        {
            res.status = StatusCodes.notModified;
            return;
        }

        res.headers["Accept-Ranges"] = "bytes";
        ulong rangeStart = 0;
        ulong rangeEnd = 0;

        string rangeheader = req.headers.get("Range", string.init);
        if (rangeheader != string.init)
        {
            // https://tools.ietf.org/html/rfc7233
            // Range can be in form "-\d", "\d-" or "\d-\d"
            auto range = rangeheader.chompPrefix("bytes=");
            if (range.canFind(','))
            {
                res.status = StatusCodes.notImplemented;
                return;
            }
            auto s = range.split("-");

            if (s.length != 2)
            {
                res.status = StatusCodes.badRequest;
                return;
            }

            try
            {
                if (s[0].length)
                {
                    rangeStart = s[0].to!ulong;
                    rangeEnd = s[1].length ? s[1].to!ulong : fi.get.data.length;
                }
                else if (s[1].length)
                {
                    rangeEnd = fi.get.data.length;
                    auto len = s[1].to!ulong;

                    if (len >= rangeEnd)
                    {
                        rangeStart = 0;
                    }
                    else
                    {
                        rangeStart = rangeEnd - len;
                    }
                }
                else
                {
                    res.status = StatusCodes.badRequest;
                    return;
                }
            }
            catch (Exception e)
            {
                res.status = StatusCodes.badRequest;
                return;
            }

            if (rangeEnd > fi.get.data.length)
            {
                rangeEnd = fi.get.data.length;
            }

            if (rangeStart > rangeEnd)
            {
                rangeStart = rangeEnd;
            }

            if (rangeEnd)
            {
                rangeEnd--; // End is inclusive, so one less than length
            }
            // potential integer overflow with rangeEnd - rangeStart == size_t.max is intended. This only happens with empty files, the + 1 will then put it back to 0

            res.headers["Content-Length"] = to!string(rangeEnd - rangeStart + 1);
            res.headers["Content-Range"] = "bytes %s-%s/%s".format(rangeStart < rangeEnd ? rangeStart : rangeEnd, rangeEnd, fi.get.data.length);
            res.status = StatusCodes.partialContent;
        }
        else
        {
            rangeEnd = fi.get.data.length - 1;
            res.headers["Content-Length"] = fi.get.data.length.to!string;
        }

        res.headers["Content-Type"] = "text/plain;charset=utf-8";
        res.headers["Access-Control-Allow-Origin"] = "*";
        res.headers["Access-Control-Allow-Headers"] = "Content-Type,api_key,Authorization,X-Requested-With,Accept,Origin,Last-Modified";
        res.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS";

        res.body_ = fi.get.data[rangeStart .. rangeEnd + 1];
    }

    Nullable!FileInfo makeFileInfo(const string filename)
    {
        auto entry = DirEntry(filename);
        if (entry.isDir || entry.isSymlink)
        {
            return Nullable!FileInfo();
        }

        FileInfo fi;
        fi.timeModified = entry.timeLastModified;
        version(Windows)
        {
            fi.timeCreated = entry.timeCreated;
        }
        else
        {
            fi.timeCreated = entry.timeLastModified;
        }

        return Nullable!FileInfo(fi);
    }

    /// convert time to RFC822 format string
    string toRFC822DateTimeString(SysTime systime)
    {
        Appender!string ret;
        
        DateTime dt = cast(DateTime)systime;
        Date date = dt.date;
        
        ret.put(to!string(date.dayOfWeek).capitalize);
        ret.put(", ");
        ret.put(rightJustify(to!string(date.day), 2, '0'));
        ret.put(" ");
        ret.put(to!string(date.month).capitalize);
        ret.put(" ");
        ret.put(to!string(date.year));
        ret.put(" ");
        
        TimeOfDay time = cast(TimeOfDay)systime;
        int tz_offset = cast(int)systime.utcOffset.total!"minutes";
        
        ret.put(rightJustify(to!string(time.hour), 2, '0'));
        ret.put(":");
        ret.put(rightJustify(to!string(time.minute), 2, '0'));
        ret.put(":");
        ret.put(rightJustify(to!string(time.second), 2, '0'));
        
        if (tz_offset == 0)
        {
            ret.put(" GMT");
        }
        else
        {
            ret.put(" " ~ (tz_offset >= 0 ? "+" : "-"));
            
            if (tz_offset < 0) tz_offset = -tz_offset;
            ret.put(rightJustify(to!string(tz_offset / 60), 2, '0'));
            ret.put(rightJustify(to!string(tz_offset % 60), 2, '0'));
        }
        
        return ret.data;
    }
}

struct FileInfo
{
    SysTime timeModified;
    SysTime timeCreated;
    char[] data;
}
