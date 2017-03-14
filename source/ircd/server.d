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
import ircd.channel;

class Server
{
	Connection[] connections;

	enum creationDate = packageTimestampISO.until('T').text; //TODO: Also show time when RFC-strictness is off
	enum versionString = "salty-ircd-" ~ packageVersion;

	string name;

	Channel[] channels;

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
				connection.send(Message(null, "PING", [name], true));
			}
			sleep(30.seconds);
		}
	}

	private void acceptConnection(TCPConnection tcpConnection)
	{
		auto connection = new Connection(tcpConnection, this);
		connections ~= connection;
		connection.handle();
		connections = connections.filter!(c => c != connection).array;
	}

	static bool isValidChannelName(string name)
	{
		return (name.startsWith('#') || name.startsWith('&')) && name.length <= 200;
	}

	void join(Connection connection, string channelName)
	{
		auto channelRange = channels.find!(c => c.name == channelName);
		Channel channel;
		if(channelRange.empty)
		{
			channel = new Channel(channelName, connection, this);
			channels ~= channel;
		}
		else
		{
			channel = channelRange[0];
			channel.members ~= connection;
		}

		foreach(member; channel.members)
		{
			member.send(Message(connection.mask, "JOIN", [channelName]));
		}

		channel.sendNames(connection);
	}

	void part(Connection connection, string channelName, string partMessage)
	{
		auto channel = connection.channels.array.find!(c => c.name == channelName)[0];

		foreach(member; channel.members)
		{
			if(partMessage !is null)
			{
				member.send(Message(connection.mask, "PART", [channelName, partMessage], true));
			}
			else
			{
				member.send(Message(connection.mask, "PART", [channelName]));
			}
		}

		channel.members = channel.members.remove!(m => m == connection);

		if(channel.members.length == 0)
		{
			channels = channels.remove!(c => c == channel);
		}
	}

	void quit(Connection connection, string quitMessage)
	{
		Connection[] peers;
		foreach(channel; connection.channels)
		{
			peers ~= channel.members;
			channel.members = channel.members.remove!(m => m == connection);
			if(channel.members.length == 0)
			{
				channels = channels.remove!(c => c == channel);
			}
		}
		peers = peers.sort().uniq.filter!(c => c != connection).array;

		foreach(peer; peers)
		{
			if(quitMessage !is null)
			{
				peer.send(Message(connection.mask, "QUIT", [quitMessage], true));
			}
			else
			{
				peer.send(Message(connection.mask, "QUIT"));
			}
		}
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
