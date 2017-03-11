module ircd.server;

import std.stdio;
import std.algorithm;
import std.range;
import std.conv;
import std.socket;
import core.time;

import vibe.core.core;

import ircd.packageVersion;

import ircd.message;
import ircd.connection;

class Server
{
	Connection[] connections;

	enum creationDate = packageTimestampISO.until('T').text; //TODO: Also show time when RFC-strictness is off
	enum versionString = "salty-ircd-" ~ packageVersion;

	string name;

	this()
	{
		name = Socket.hostName;

		runTask(&pingLoop);
	}

	private void pingLoop()
	{
		while(true)
		{
			foreach(connection; connections)
			{
				connection.send(Message(null, "PING", [connection.nick]));
			}
			sleep(10.seconds);
		}
	}

	private void acceptConnection(TCPConnection tcpConnection)
	{
		auto connection = new Connection(tcpConnection, this);
		connections ~= connection;
		connection.handle();
		connections = connections.filter!(c => c != connection).array;
	}

	void listen(ushort port = 6667)
	{
		listenTCP(port, &acceptConnection);
	}

	void listen(ushort port, string address)
	{
		listenTCP(port, &acceptConnection, address);
	}
}
