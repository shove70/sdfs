module sdfs.access.app;

import core.time;
import std.path : buildPath, stripExtension, baseName;
import std.range;
import std.file : exists, read, DirEntry;
import std.string : endsWith, startsWith, chompPrefix, rightJustify, capitalize;
import std.stdio : writeln, writefln, File;
import std.datetime;
import std.digest.md : hexDigest, MD5;
import std.conv : to;
import std.array : split, Appender;
import std.format : format;
import std.algorithm.searching : canFind;

import lighttp;
import appbase.utils;

import sdfs.access.configuration;

void main()
{
	Config.initConfiguration();

    auto server = new Server();
    server.host("0.0.0.0", config.server.port.as!ushort);
    server.host("::", config.server.port.as!ushort);
    server.router.add(new StaticRouter(config.storager.data.path.value));
    writefln("sdfs.access start listening to 0.0.0.0:%d...", config.server.port.as!ushort);
    server.run();
}

class StaticRouter
{
    private immutable string path;

    this(const string path)
    {
        if (!path.endsWith("/"))
            this.path = (path ~ "/");
        else
            this.path = path;
    }

    @Get(`(.*)`)
	get(ServerRequest req, ServerResponse res, string filename)
    {
        if (!filename.startsWith(config.storager.data.route.value))
        {
            res.status = StatusCodes.notFound;
            return;
        }

        string name = stripExtension(chompPrefix(filename, config.storager.data.route.value));

        if (name.length < 40)
        {
            res.status = StatusCodes.notFound;
            return;
        }

        name = buildPath(path, name[0..3], name[3..6], name[6..9], name);

        string name2 = name ~ "$$";
        if (name2.exists)
        {
            setResponse(req, res, name2);
            return;
        }

        name2 = name ~ "$_";
        if (name2.exists)
        {
            setResponse(req, res, name2);
            return;
        }

        name2 = name ~ "_$";
        if (name2.exists)
        {
            setResponse(req, res, name2);
            return;
        }

        name2 = name ~ "__";
        if (name2.exists)
        {
            setResponse(req, res, name2);
            return;
        }

        res.status = StatusCodes.notFound;
    }

    void setResponse(ServerRequest req, ServerResponse res, const string filename)
    {
        FileInfo fi;
        try
        {
            fi = makeFileInfo(filename);
        }
        catch (Exception e)
        {
            res.status = StatusCodes.internalServerError;
            return;
        }

        if (fi.isDirectory)
        {
            res.status = StatusCodes.notFound;
            return;
        }

        immutable lastModified = toRFC822DateTimeString(fi.timeModified.toUTC());
        immutable etag = "\"" ~ hexDigest!(std.digest.md.MD5)(filename ~ ":" ~ lastModified ~ ":" ~ to!string(fi.size)).idup ~ "\"";
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
                    rangeEnd = s[1].length ? s[1].to!ulong : fi.size;
                }
                else if (s[1].length)
                {
                    rangeEnd = fi.size;
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

            if (rangeEnd > fi.size)
            {
                rangeEnd = fi.size;
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
            res.headers["Content-Range"] = "bytes %s-%s/%s".format(rangeStart < rangeEnd ? rangeStart : rangeEnd, rangeEnd, fi.size);
            res.status = StatusCodes.partialContent;
        }
        else
        {
            rangeEnd = fi.size - 1;
            res.headers["Content-Length"] = fi.size.to!string;
        }

        res.headers["Content-Type"] = "text/plain;charset=utf-8";
        res.headers["Access-Control-Allow-Origin"] = "*";
        res.headers["Access-Control-Allow-Headers"] = "Content-Type,api_key,Authorization,X-Requested-With,Accept,Origin,Last-Modified";
        res.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS";

        File f;
        try
        {
            f = File(filename, "r");
            f.seek(rangeStart);
            res.body_ = f.rawRead(new void[rangeEnd.to!uint - rangeStart.to!uint + 1]);
        }
        catch (Exception e)
        {
            writeln("access internalServerError: " ~ e.msg);
            logger.write("access internalServerError: " ~ e.msg);
            res.status = StatusCodes.internalServerError;
        }
        finally
        {
            f.close();
        }
    }

    FileInfo makeFileInfo(const string filename)
    {
        FileInfo fi;
        fi.name = baseName(filename);
        auto entry = DirEntry(filename);
        fi.size = entry.size;
        fi.timeModified = entry.timeLastModified;
        version(Windows)
        {
            fi.timeCreated = entry.timeCreated;
        }
        else
        {
            fi.timeCreated = entry.timeLastModified;
        }
        fi.isSymlink = entry.isSymlink;
        fi.isDirectory = entry.isDir;

        return fi;
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
    string name;
    ulong size;
    SysTime timeModified;
    SysTime timeCreated;
    bool isSymlink;
    bool isDirectory;
}
