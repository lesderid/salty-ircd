module ircd.app;

import std.algorithm;
import std.traits;
import std.string;

import sdlang;

import ircd.server;

static T tagValueOrNull(T)(Tag tag, string childName)
{
    if (childName !in tag.tags)
    {
        return null;
    }
    else
    {
        return tagValue!T(tag, childName);
    }
}

static T tagValue(T)(Tag tag, string childName)
{
    static if (isArray!T && !isSomeString!T)
    {
        template U(T : T[])
        {
            alias U = T;
        }

        T array = [];

        foreach (value; tag.tags[childName][0].values)
        {
            array ~= value.get!(U!T);
        }

        return array;
    }
    else static if (isIntegral!T && !is(T == int))
    {
        return cast(T) tagValue!int(tag, childName);
    }
    else
    {
        return tag.tags[childName][0].values[0].get!T;
    }
}

shared static this()
{
    auto server = new Server();

    auto config = parseFile("config.sdl");

    auto pass = config.tagValue!string("pass");
    server.setPass(pass.empty ? null : pass);

    foreach (listenBlock; config.tags.filter!(t => t.getFullName.toString == "listen"))
    {
        assert(listenBlock.tagValue!string("type") == "plaintext");

        auto addresses = listenBlock.tagValue!(string[])("address");
        auto port = listenBlock.tagValue!ushort("port");

        foreach (address; addresses)
        {
            server.listen(port, address);
        }
    }
}
