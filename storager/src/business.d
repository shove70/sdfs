module sdfs.storager.business;

import std.conv : to;
import std.string;
import std.path : buildPath;

import buffer;
import appbase.utils;
import appbase.configuration;

import sdfs.storager.filestorager;

alias as = appbase.utils.utility.as;

mixin(LoadBufferFile!"sdfs.buffer");

package class Business
{
    UploadResponse upload(string content)
    {
        UploadResponse res = new UploadResponse();
        scope(failure)
        {
            logger.write("System Failure.");
            res.result = -1;
            res.description = "There is an unpredicted exception to the sdfs.storager. Please contact the system manager to check the server application log.";

            return res;
        }

        ubyte[] buf = uncompressUbytes(content);

        string keyHash = FileStorager.generateKeyHash(buf);
        FileStorager.save(keyHash, buf, false);

        res.result = 0;
        res.url = FileStorager.buildUrl(keyHash);
        return res;
    }

    RemoveResponse remove(string keyHash)
    {
        RemoveResponse res = new RemoveResponse();
        scope(failure)
        {
            logger.write("System Failure.");
            res.result = -1;
            res.description = "There is an unpredicted exception to the sdfs.storager. Please contact the system manager to check the server application log.";

            return res;
        }

        string fileRealname;
        if (!FileStorager.exists(keyHash, fileRealname))
        {
            res.result = -1;
            res.description = "File is not exists in the specified storager.";

            return res;
        }

        FileStorager.remove(keyHash, false);

        res.result = 0;
        return res;
    }

    SyncFileChangedResponse syncFileChanged(ushort group, ubyte name, byte operation, string keyHash, string content)
    {
        SyncFileChangedResponse res = new SyncFileChangedResponse();
        scope(failure)
        {
            logger.write("System Failure.");
            res.result = -1;
            res.description = "There is an unpredicted exception to the sdfs.storager. Please contact the system manager to check the server application log.";

            return res;
        }

        if (group != config.storager.group.as!ushort)
        {
            string msg = "Group error: " ~ group.to!string;
            logger.write(msg);
            res.result = -2;
            res.description = msg;

            return res;
        }

        if (!BusinessUility.checkName(name))
        {
            string msg = "Name error: " ~ name.to!string;
            logger.write(msg);
            res.result = -3;
            res.description = msg;

            return res;
        }

        if (!BusinessUility.checkFileChangedOperation(operation))
        {
            string msg = "Operation error: " ~ operation.to!string;
            logger.write(msg);
            res.result = -4;
            res.description = msg;

            return res;
        }

        if (operation == 1)
        {
            ubyte[] buf = uncompressUbytes(content);
            FileStorager.save(keyHash, buf, true);
        }
        else if (operation == 2)
        {
            FileStorager.remove(keyHash, true);
        }

        res.result = 0;
        return res;
    }
}

private class BusinessUility
{
    static bool checkName(const ubyte name)
    {
        return (name == 1) || (name == 2);
    }

    static bool checkFileChangedOperation(const byte operation)
    {
        return (operation >= 1) || (operation <= 2);
    }
}
