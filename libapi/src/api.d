module sdfs.client.api;

import core.thread;

import std.json;
import std.string;
import std.typecons;

import buffer;
import buffer.rpc.client;
import crypto.rsa;

import appbase.utils;

mixin(LoadBufferFile!"sdfs.buffer");

__gshared string g_trackerHost;
__gshared ushort g_trackerPort;
__gshared ushort g_messageMagic;

extern (C) void init(const string trackerHost, const ushort trackerPort, const ushort messageMagic, size_t poolMax = 16)
{
    g_trackerHost  = trackerHost;
    g_trackerPort  = trackerPort;
    g_messageMagic = messageMagic;
}

extern (C) short sdfs_upload(const string trackerHost, const ushort trackerPort, const ushort messageMagic,
    const scope void[] content, ref string url, ref string errorInfo)
{
    url = string.init;
    errorInfo = string.init;

    string keyHash = RIPEMD160(content);

    int trys = 0;
    label_preupload:

    PreuploadResponse res1;
    try
    {
        res1 = Client.callEx!PreuploadResponse(trackerHost, trackerPort, messageMagic, CryptType.NONE, string.init, Nullable!RSAKeyInfo(),
            "preupload", keyHash);
    }
    catch (Exception e)
    {
        if (++trys < 3)
        {
            Thread.sleep(200.msecs);
            goto label_preupload;
        }

        errorInfo = "Call sdfs api has error: " ~ e.msg;
        return -1;
    }

    if (res1 is null)
    {
        if (++trys < 3)
        {
            Thread.sleep(200.msecs);
            goto label_preupload;
        }

        errorInfo = "Call sdfs api has error: preupload fail.";
        return -2;
    }

    if (res1.result < 0)
    {
        if (++trys < 3)
        {
            Thread.sleep(200.msecs);
            goto label_preupload;
        }

        errorInfo = "Call sdfs api has error: " ~ res1.description;
        return res1.result;
    }

    if (res1.url != string.init)
    {
        url = res1.url;
        return 0;
    }

    if (res1.storager == string.init)
    {
        errorInfo = "Call sdfs api has error: No storager available yet.";
        return -3;
    }

    JSONValue json;
    try
    {
        json = parseJSON(uncompressString(res1.storager));
    }
    catch (Exception e)
    {
        errorInfo = "Call sdfs api has error: " ~ e.msg;

        return -4;
    }

    try
    {
        json = json["data"];
        if (json.type != JSONType.array)
        {
            errorInfo = "Call sdfs api has error: Json data must have a array key \"data\".";
            return -5;
        }
    }
    catch (Exception e)
    {
        errorInfo = "Call sdfs api has error: Json data error: " ~ e.msg;
        return -6;
    }

    if (json.array.length == 0)
    {
        errorInfo = "Call sdfs api has error: Json data is empty.";
        return -7;
    }

    JSONValue j = json.array[0];
    ushort group = cast(ushort)j["group"].integer;
    string host = j["host"].str;
    ushort port = cast(ushort)j["port"].integer;

    trys = 0;
    label_upload:

    UploadResponse res2;
    try
    {
        res2 = Client.callEx!UploadResponse(host, port, messageMagic, CryptType.NONE, string.init, Nullable!RSAKeyInfo(),
            "upload", compressString(content));
    }
    catch (Exception e)
    {
        if (++trys < 3)
        {
            Thread.sleep(200.msecs);
            goto label_upload;
        }

        errorInfo = "Call sdfs api has error: " ~ e.msg;
        return -11;
    }

    if (res2 is null)
    {
        if (++trys < 3)
        {
            Thread.sleep(200.msecs);
            goto label_upload;
        }

        errorInfo = "Call sdfs api has error: upload fail.";
        return -12;
    }

    if (res2.result < 0)
    {
        if (++trys < 3)
        {
            Thread.sleep(200.msecs);
            goto label_upload;
        }

        errorInfo = "Call sdfs api has error: " ~ res2.description;
        return res2.result;
    }

    url = res2.url;
    return 0;
}
