module sdfs.storager.synchronizer;

import core.sync.rwmutex;
import std.typecons;

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
        if (_queueTracker.empty)
        {
            return;
        }

        synchronized (_mutexTracker.writer)
        {
            while (!_queueTracker.empty)
            {
                SynchronizeMethod method = _queueTracker.front;

                ReportFileChangedResponse res;
                try
                {
                    res = Client.callEx!ReportFileChangedResponse(
                        trackerSocket,
                        config.sys.protocol.magic.as!ushort, CryptType.NONE, string.init, Nullable!RSAKeyInfo(),
                        "reportFileChanged",
                        config.storager.group.as!ushort,
                        config.storager.name.as!ubyte,
                        method.operation,
                        method.keyHash);
                }
                catch (Exception e)
                {
                }

                _queueTracker.pop;
            }
        }
    }

    static void pushToPartner(SynchronizeMethod method)
    {
        // synchronized (_mutexPartner.writer)
        // {
        //     _queuePartner.push(method);
        // }
    }

    static void synchronizeToPartner()
    {
        if (_queuePartner.empty)
        {
            return;
        }

        synchronized (_mutexPartner.writer)
        {
            while (!_queuePartner.empty)
            {
                SynchronizeMethod method = _queuePartner.front;

                SyncFileChangedResponse res;
                try
                {
                    res = Client.callEx!SyncFileChangedResponse(
                        partnerSocket,
                        config.sys.protocol.magic.as!ushort, CryptType.NONE, string.init, Nullable!RSAKeyInfo(),
                        "syncFileChanged",
                        config.storager.group.as!ushort,
                        config.storager.name.as!ubyte,
                        method.operation,
                        method.keyHash,
                        method.operation == 1 ? compressString(FileStorager.read(method.keyHash)) : string.init);
                }
                catch (Exception e)
                {
                }

                _queuePartner.pop;
            }
        }
    }

private:

    __gshared ReadWriteMutex _mutexTracker;
    __gshared ReadWriteMutex _mutexPartner;

    __gshared Queue!SynchronizeMethod _queueTracker;
    __gshared Queue!SynchronizeMethod _queuePartner;
}
