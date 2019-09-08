module sdfs.storager.filestorager;

import std.path;
import std.file;

import appbase.utils;

import sdfs.storager.configuration;
import sdfs.storager.synchronizer;

class FileStorager
{
    static bool exists(const string keyHash, ref string fileRealname)
    {
        string filename = buildStorageFilename(keyHash);

        fileRealname = filename ~ "$$";
        if (fileRealname.exists)
        {
            return true;
        }

        fileRealname = filename ~ "$_";
        if (fileRealname.exists)
        {
            return true;
        }

        fileRealname = filename ~ "_$";
        if (fileRealname.exists)
        {
            return true;
        }

        fileRealname = filename ~ "__";
        if (fileRealname.exists)
        {
            return true;
        }

        fileRealname = string.init;
        return false;
    }

    static void save(const string keyHash, const scope ubyte[] content, const bool isSyncMode)
    {
        string fileRealname;
        if (exists(keyHash, fileRealname))
        {
            return;
        }

        string path = buildStoragePath(keyHash);
        if (!path.exists)
        {
            path.mkdirRecurse();
        }

        path = buildPath(path, keyHash ~ (isSyncMode ? "$$" : "__"));

        try
        {
            write(path, content);
        }
        catch (Exception e)
        {
        }

        if (!isSyncMode)
        {
            SynchronizeMethod method = new SynchronizeMethod(1, keyHash);
            Synchronizer.pushToTracker(method);
            Synchronizer.pushToPartner(method);
        }
    }

    static ubyte[] read(const string keyHash)
    {
        string fileRealname;
        if (!exists(keyHash, fileRealname))
        {
            return null;
        }

        try
        {
            return cast(ubyte[])std.file.read(fileRealname);
        }
        catch (Exception e)
        {
            return null;
        }
    }

    static void remove(const string keyHash, const bool isSyncMode)
    {
        string fileRealname;
        if (!exists(keyHash, fileRealname))
        {
            return;
        }

        try
        {
            std.file.remove(fileRealname);
        }
        catch (Exception e)
        {
        }

        if (!isSyncMode)
        {
            SynchronizeMethod method = new SynchronizeMethod(2, keyHash);
            Synchronizer.pushToTracker(method);
            Synchronizer.pushToPartner(method);
        }
    }

    static string generateKeyHash(const scope ubyte[] content)
    {
        return RIPEMD160(content);
    }

    static string buildUrl(const string keyHash)
    {
        return config.storager.group.value ~ "/" ~ keyHash;
    }

    static string buildStoragePath(const string keyHash)
    {
        return buildPath(config.storager.data.path.value, keyHash[0..3], keyHash[3..6], keyHash[6..9]);
    }

    static string buildStorageFilename(const string keyHash)
    {
        return buildPath(buildStoragePath(keyHash), keyHash);
    }
}
