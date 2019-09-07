module sdfs.tracker.business;

import std.conv : to;

import buffer;
import appbase.utils;
import appbase.configuration;

import sdfs.tracker.storage;

alias as = appbase.utils.utility.as;

package class Business
{
    mixin(LoadBufferFile!"sdfs.buffer");

    RegisterResponse register(ushort group, ubyte name, string host, ushort port)
    {
        RegisterResponse res = new RegisterResponse();
        scope(failure)
        {
            logger.write("System Failure.");
            res.result = -1;
            res.description = "There is an unpredicted exception to the sdfs.tracker. Please contact the system manager to check the server application log.";

            return res;
        }

        if (!BusinessUility.checkName(name))
        {
            string msg = "Name error: " ~ name.to!string;
            logger.write(msg);
            res.result = -2;
            res.description = msg;

            return res;
        }

        string allStoragers;
        string errorInfo;
        short result = Storage.register(group, name, host, port, allStoragers, errorInfo);
        if (result < 0)
        {
            res.result = result;
            res.description = errorInfo;

            return res;
        }

        res.result = 0;
        res.allStoragers = allStoragers;
        return res;
    }

    ReportFileChangedResponse reportFileChanged(ushort group, ubyte name, byte operation, string keyHash)
    {
        ReportFileChangedResponse res = new ReportFileChangedResponse();
        scope(failure)
        {
            logger.write("System Failure.");
            res.result = -1;
            res.description = "There is an unpredicted exception to the sdfs.tracker. Please contact the system manager to check the server application log.";

            return res;
        }

        if (!BusinessUility.checkName(name))
        {
            string msg = "Name error: " ~ name.to!string;
            logger.write(msg);
            res.result = -2;
            res.description = msg;

            return res;
        }

        if (!BusinessUility.checkFileChangedOperation(operation))
        {
            string msg = "Operation error: " ~ operation.to!string;
            logger.write(msg);
            res.result = -3;
            res.description = msg;

            return res;
        }

        Storage.reportFileChanged(group, operation, keyHash);

        res.result = 0;
        return res;
    }

    PreuploadResponse preupload(string keyHash)
    {
        PreuploadResponse res = new PreuploadResponse();
        scope(failure)
        {
            logger.write("System Failure.");
            res.result = -1;
            res.description = "There is an unpredicted exception to the sdfs.tracker. Please contact the system manager to check the server application log.";

            return res;
        }

        string url = Storage.findFileUrl(keyHash);

        if (url != string.init)
        {
            res.result = 0;
            res.url = url;
            return res;
        }

        res.result = 0;
        res.storager = Storage.get();
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
