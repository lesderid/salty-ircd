module ircd.channel;

import std.algorithm;
import std.string;

import ircd.connection;
import ircd.server;
import ircd.message;

class Channel
{
	string name;
	string topic = "";

	Connection[] members;
	char[] modes;
	char[][Connection] memberModes;

	private Server _server;

	this(string name, Server server)
	{
		this.name = name;
		this.members = [];
		this._server = server;
	}

	void join(Connection connection)
	{
		members ~= connection;
		memberModes[connection] = null;

		if(members.length == 1)
		{
			memberModes[connection] ~= 'o';
		}
	}

	void sendNames(Connection connection, bool sendRplEndOfNames = true)
	{
		string channelType;

		if(modes.canFind('s'))
		{
			channelType = "@";
		}
		else if(modes.canFind('p'))
		{
			channelType = "*";
		}
		else
		{
			channelType = "=";
		}

		auto onChannel = members.canFind(connection);

		connection.send(Message(_server.name, "353", [connection.nick, channelType, name, members.filter!(m => onChannel || !m.modes.canFind('i')).map!(m => prefixedNick(m)).join(' ')], true));

		if(sendRplEndOfNames)
		{
			connection.sendRplEndOfNames(name);
		}
	}

	string prefixedNick(Connection member)
	{
		if(memberModes[member].canFind('o'))
		{
			return '@' ~ member.nick;
		}

		return member.nick;
	}

	void sendPrivMsg(Connection sender, string text)
	{
		foreach(member; members.filter!(m => m.nick != sender.nick))
		{
			member.send(Message(sender.mask, "PRIVMSG", [name, text], true));
		}
	}

	void sendNotice(Connection sender, string text)
	{
		foreach(member; members.filter!(m => m.nick != sender.nick))
		{
			member.send(Message(sender.mask, "NOTICE", [name, text], true));
		}
	}

	void sendTopic(Connection connection)
	{
		if(topic.empty)
		{
			connection.send(Message(_server.name, "331", [connection.nick, name, "No topic is set"]));
		}
		else
		{
			connection.send(Message(_server.name, "332", [connection.nick, name, topic], true));
		}
	}

	void setTopic(Connection connection, string newTopic)
	{
		topic = newTopic;

		foreach(member; members)
		{
			member.send(Message(connection.mask, "TOPIC", [name, newTopic], true));
		}
	}

	bool visibleTo(Connection connection)
	{
		return members.canFind(connection) || !modes.canFind('s') && !modes.canFind('p');
	}
}
