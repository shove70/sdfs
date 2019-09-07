module sdfs.tracker.leveldb;

import std.string;
import std.conv;
import std.traits;
import std.file;

import deimos.leveldb.leveldb;

import sdfs.tracker.configuration;

__gshared private leveldb_t db;
__gshared private leveldb_options_t opt;
__gshared private leveldb_writeoptions_t writeOpt;
__gshared private leveldb_readoptions_t  readOpt;

class LevelDB
{
    static bool open()
    {
        if (!exists(config.business.data.path.value))
        {
            mkdirRecurse(config.business.data.path.value);
        }

        opt = leveldb_options_create();
        if (opt is null)
        {
            return false;
        }

        leveldb_options_set_create_if_missing(opt, true);
        //leveldb_options_set_write_buffer_size(opt, 4096);

        writeOpt = leveldb_writeoptions_create();
        if (writeOpt is null)
        {
            leveldb_options_destroy(opt);
            opt = null;

            return false;
        }

        readOpt = leveldb_readoptions_create();
        if (readOpt is null)
        {
            leveldb_options_destroy(opt);
            opt = null;
            leveldb_writeoptions_destroy(writeOpt);
            writeOpt = null;

            return false;
        }

        char* errptr = null;
        scope(failure) if (errptr) leveldb_free(errptr);

        db = leveldb_open(opt, toStringz(config.business.data.path.value), &errptr);
        return !errptr;
    }

    static void close()
    {
        leveldb_options_destroy(opt);
        opt = null;
        leveldb_writeoptions_destroy(writeOpt);
        writeOpt = null;
        leveldb_readoptions_destroy(readOpt);
        readOpt = null;

        leveldb_close(db);
        db = null;
    }

    static bool put(K, V)(const K key, const V val)
    {
        char* errptr = null;
        scope(failure) if (errptr) leveldb_free(errptr);

        static if (isSomeString!V || isArray!V)
            leveldb_put(db, writeOpt, key.ptr, key.length, val.ptr, val.length, &errptr);
        else
            leveldb_put(db, writeOpt, key.ptr, key.length, cast(char*) &val, val.sizeof, &errptr);

        return !errptr;
    }

    static bool remove(T)(const T key)
    {
        char* errptr = null;
        scope(failure) if (errptr) leveldb_free(errptr);

        leveldb_delete(db, writeOpt, key.ptr, key.length, &errptr);
        return !errptr;
    }

    static bool get_object(T, V)(const T key, out V value)
    if (!is(V == interface))
    {
        char* errptr = null;
        scope(failure) if (errptr) leveldb_free(errptr);

        size_t vallen;
        auto valptr = leveldb_get(db, readOpt, key.ptr, key.length, &vallen, &errptr);
        scope(exit) if (valptr !is null) leveldb_free(valptr);
    
        if (errptr || (valptr is null))
        {
            return false;
        }

        static if (isSomeString!V || isArray!V)
        {
            value = cast(V)(cast(char[])(valptr)[0..vallen]).dup;
        }
        else static if (is(V == class))
        {
            if (typeid(V).sizeof > vallen)
            {
                return false;
            }

            value = *(cast(V*)valptr).dup;
        }
        else
        {
            if (V.sizeof > vallen)
            {
                return false;
            }

            value = *(cast(V*)valptr);
        }

        return true;
    }

    static T get(T)(const string key, const T defaultValue)
    {
        T v;
        if (!get_object(key, v))
        {
            v = defaultValue;
        }

        return v;
    }
}
