module ircd.app;

import std.stdio;
import std.algorithm;
import core.time;

import vibe.d;

import ircd.message;
import ircd.connection;

shared static this()
{
	Connection[] connections = [];

	listenTCP(6667, delegate(TCPConnection connection)
	{
		auto c = new Connection(connection);
		connections ~= c;
		c.handle();
		connections = connections.filter!(a => a != c).array;
	},"127.0.0.1");
}

