module ircd.server;

import std.stdio;
import std.algorithm;
import std.range;
import std.conv;
import std.socket;
import core.time;
import std.datetime;

import vibe.core.core;

import ircd.packageVersion;

import ircd.message;
import ircd.connection;
import ircd.channel;
import ircd.helpers;

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

	static bool isValidNick(string name)
	{
		//TODO: Use the real rules
		return !name.startsWith('#') && !name.startsWith('&') && name.length <= 9;
	}

	bool isNickAvailable(string nick)
	{
		return !connections.canFind!(c => c.nick == nick);
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

		if(!channel.topic.empty)
		{
			channel.sendTopic(connection);
		}
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
				peer.send(Message(connection.mask, "QUIT", [connection.nick], true));
			}
		}
	}

	void whoChannel(Connection origin, string channelName, bool operatorsOnly)
	{
		//TODO: Check what RFCs say about secret/private channels

		auto channel = channels.find!(c => c.name == channelName)[0];
		foreach(c; channel.members.filter!(c => !operatorsOnly || c.isOperator)
								  .filter!(c => c.visibleTo(origin)))
		{
			//TODO: Support hop count
			origin.sendWhoReply(channelName, c, 0);
		}
	}

	void whoGlobal(Connection origin, string mask, bool operatorsOnly)
	{
		foreach(c; connections.filter!(c => c.visibleTo(origin))
							  .filter!(c => !operatorsOnly || c.isOperator)
							  .filter!(c => [c.hostname, c.servername, c.realname, c.nick].any!(n => wildcardMatch(n, mask))))
		{
			//TODO: Don't leak secret/private channels if RFC-strictness is off (the RFCs don't seem to say anything about it?)
			auto channelName = c.channels.empty ? "*" : c.channels.array[0].name;
			//TODO: Support hop count
			origin.sendWhoReply(channelName, c, 0);
		}
	}

	void privmsgToChannel(Connection sender, string target, string text)
	{
		auto channel = channels.find!(c => c.name == target)[0];
		channel.sendPrivMsg(sender, text);
	}

	void privmsgToUser(Connection sender, string target, string text)
	{
		auto user = connections.find!(c => c.nick == target)[0];
		user.send(Message(sender.mask, "PRIVMSG", [target, text], true));
	}

	void noticeToChannel(Connection sender, string target, string text)
	{
		auto channel = channels.find!(c => c.name == target)[0];
		channel.sendNotice(sender, text);
	}

	void noticeToUser(Connection sender, string target, string text)
	{
		auto user = connections.find!(c => c.nick == target)[0];
		user.send(Message(sender.mask, "NOTICE", [target, text], true));
	}

	void sendChannelTopic(Connection origin, string channelName)
	{
		auto channel = channels.find!(c => c.name == channelName)[0];
		channel.sendTopic(origin);
	}

	void setChannelTopic(Connection origin, string channelName, string newTopic)
	{
		auto channel = channels.find!(c => c.name == channelName)[0];
		channel.setTopic(origin, newTopic);
	}

	void sendChannelNames(Connection connection, string channelName)
	{
		auto channel = channels.find!(c => c.name == channelName)[0];
		channel.sendNames(connection);
	}

	void sendGlobalNames(Connection connection)
	{
		foreach(channel; channels.filter!(c => c.visibleTo(connection)))
		{
			channel.sendNames(connection, false);
		}

		auto otherUsers = connections.filter!(c => !c.modes.canFind('i') && c.channels.filter!(ch => !ch.modes.canFind('s') && !ch.modes.canFind('p')).empty);
		if(!otherUsers.empty)
		{
			connection.send(Message(name, "353", [connection.nick, "=", "*", otherUsers.map!(m => m.nick).join(' ')], true));
		}

		connection.sendRplEndOfNames("*");
	}

	void sendFullList(Connection connection)
	{
		foreach(channel; channels.filter!(c => c.visibleTo(connection)))
		{
			connection.sendRplList(channel.name, channel.members.filter!(m => m.visibleTo(connection)).array.length, channel.topic);
		}
		connection.sendRplListEnd();
	}

	void sendPartialList(Connection connection, string[] channelNames)
	{
		foreach(channel; channels.filter!(c => channelNames.canFind(c.name) && c.visibleTo(connection)))
		{
			connection.sendRplList(channel.name, channel.members.filter!(m => m.visibleTo(connection)).array.length, channel.topic);
		}
		connection.sendRplListEnd();
	}

	void sendVersion(Connection connection)
	{
		connection.send(Message(name, "351", [connection.nick, versionString ~ ".", name, ""], true));
	}

	void sendTime(Connection connection)
	{
		auto timeString = Clock.currTime.toISOExtString;
		connection.send(Message(name, "391", [connection.nick, name, timeString], true));
	}

	void invite(Connection inviter, string target, string channelName)
	{
		auto user = connections.find!(c => c.nick = target)[0];
		user.send(Message(inviter.mask, "INVITE", [user.nick, channelName]));
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
