module sdfs.storager.synchronizer;

import core.sync.rwmutex;
import std.typecons;
import std.exception : enforce;
import std.file;

import buffer;
import buffer.rpc.client;
import crypto.rsa;
import appbase.utils;
import appbase.utils.container.queue;

import sdfs.storager.configuration;
import sdfs.storager.socket;
import sdfs.storager.business;
import sdfs.storager.filestorager;

class SynchronizeMethod
{
    byte operation;
    string keyHash;

    this(const byte operation, const string keyHash)
    {
        this.operation = operation;
        this.keyHash = keyHash;
    }
}

class Synchronizer
{
    shared static this()
    {
        _mutexTracker = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        _mutexPartner = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        _mutexFileSyncState = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    }

    static void pushToTracker(SynchronizeMethod method)
    {
        synchronized (_mutexTracker.writer)
        {
            _queueTracker.push(method);
        }
    }

    static void synchronizeToTracker()
    {
        while (!_queueTracker.empty)
        {
            byte operation;
            string keyHash;

            synchronized (_mutexTracker.writer)
            {
                if (_queueTracker.empty)
                {
                    return;
                }

                SynchronizeMethod method = _queueTracker.front;
                operation = method.operation;
                keyHash = method.keyHash;
                _queueTracker.pop;
            }

            ReportFileChangedResponse res;
            try
            {
                res = Client.callEx!ReportFileChangedResponse(
                    trackerSocket,
                    config.sys.protocol.magic.as!ushort, CryptType.NONE, string.init, Nullable!RSAKeyInfo(),
                    "reportFileChanged",
                    config.storager.group.as!ushort,
                    config.storager.name.as!ubyte,
                    operation,
                    keyHash);
            }
            catch (Exception) { }

            if (operation == 1)
            {
                setFileSynchronizedState(keyHash, 1);
            }
        }
    }

    static void pushToPartner(SynchronizeMethod method)
    {
        if (partnerHost == string.init)
        {
            return;
        }

        synchronized (_mutexPartner.writer)
        {
            _queuePartner.push(method);
        }
    }

    static void synchronizeToPartner()
    {
        while (!_queuePartner.empty)
        {
            byte operation;
            string keyHash;

            synchronized (_mutexPartner.writer)
            {
                if (_queuePartner.empty)
                {
                    return;
                }

                SynchronizeMethod method = _queuePartner.front;
                operation = method.operation;
                keyHash = method.keyHash;
                _queuePartner.pop;
            }

            SyncFileChangedResponse res;
            try
            {
                res = Client.callEx!SyncFileChangedResponse(
                    partnerSocket,
                    config.sys.protocol.magic.as!ushort, CryptType.NONE, string.init, Nullable!RSAKeyInfo(),
                    "syncFileChanged",
                    config.storager.group.as!ushort,
                    config.storager.name.as!ubyte,
                    operation,
                    keyHash,
                    operation == 1 ? cast(string) FileStorager.read(keyHash) : string.init);
            }
            catch (Exception) { }

            if (operation == 1)
            {
                setFileSynchronizedState(keyHash, 2);
            }
        }
    }

private:

    __gshared ReadWriteMutex _mutexTracker;
    __gshared ReadWriteMutex _mutexPartner;

    __gshared Queue!SynchronizeMethod _queueTracker;
    __gshared Queue!SynchronizeMethod _queuePartner;

    __gshared ReadWriteMutex _mutexFileSyncState;
    __gshared byte[string] _lockedFiles;

    static void setFileSynchronizedState(const string keyHash, const byte syncTarget)
    {
        enforce(syncTarget == 1 || syncTarget == 2);

        string fileRealname;
        if (!FileStorager.exists(keyHash, fileRealname))
        {
            return;
        }

        string lastTwo = fileRealname[$ - 2 .. $];

        if (lastTwo[syncTarget - 1] == '$')
        {
            return;
        }

        lockFile(keyHash);

        char[] newname = cast(char[]) fileRealname.dup;
        newname[$ - (3 - syncTarget)] = '$';

        try
        {
            rename(fileRealname, cast(string) newname);
        }
        catch (Exception) { }

        unlockFile(keyHash);
    }

    static void lockFile(const string keyHash)
    {
        while (true)
        {
            if (keyHash in _lockedFiles)
            {
                continue;
            }

            synchronized (_mutexFileSyncState.writer)
            {
                if (keyHash in _lockedFiles)
                {
                    continue;
                }

                _lockedFiles[keyHash] = 1;
                return;
            }
        }
    }

    static void unlockFile(const string keyHash)
    {
        if (keyHash in _lockedFiles)
        {
            synchronized (_mutexFileSyncState.writer)
            {
                if (keyHash in _lockedFiles)
                {
                    _lockedFiles.remove(keyHash);
                }
            }
        }
    }
}
