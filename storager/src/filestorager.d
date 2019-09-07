module sdfs.storager.filestorager;

import std.path;
import std.file;

import appbase.utils;

import sdfs.storager.configuration;
import sdfs.storager.synchronizer;

class FileStorager
{
package:

    static bool exists(const string keyHash)
    {
        string path = buildStorageFilename(keyHash);

        return path.exists;
    }

    static void save(const string keyHash, const scope ubyte[] content)
    {
        string path = buildStoragePath(keyHash);
        if (!path.exists)
        {
            path.mkdirRecurse();
        }

        path = buildPath(path, keyHash);
        if (path.exists)
        {
            return;
        }

        try
        {
            write(path, content);
        }
        catch (Exception e)
        {
        }

        SynchronizeMethod method = new SynchronizeMethod(1, keyHash);
        Synchronizer.pushToTracker(method);
        Synchronizer.pushToPartner(method);
    }

    static ubyte[] read(const string keyHash)
    {
        string path = buildStorageFilename(keyHash);
        if (!path.exists)
        {
            return null;
        }

        return cast(ubyte[])std.file.read(path);
    }

    static void remove(const string keyHash)
    {
        string path = buildStorageFilename(keyHash);
        if (!path.exists)
        {
            return;
        }

        try
        {
            std.file.remove(path);
        }
        catch (Exception e)
        {
        }

        SynchronizeMethod method = new SynchronizeMethod(2, keyHash);
        Synchronizer.pushToTracker(method);
        Synchronizer.pushToPartner(method);
    }

    static string generateKeyHash(const scope ubyte[] content)
    {
        return RIPEMD160(content);
    }

    static string buildUrl(const string keyHash)
    {
        return config.storager.group.value ~ "/" ~ keyHash;
    }

private:

    static string buildStoragePath(const string keyHash)
    {
        return buildPath(config.storager.data.path.value, keyHash[0..3], keyHash[3..6], keyHash[6..9]);
    }

    static string buildStorageFilename(const string keyHash)
    {
        return buildPath(buildStoragePath(keyHash), keyHash);
    }
}
