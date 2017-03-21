module ircd.channel;

import std.algorithm;
import std.string;

import ircd.connection;
import ircd.server;
import ircd.message;

class Channel
{
	string name;

	Connection[] members;
	Connection owner;

	string topic = "";

	char[] modes;

	private Server _server;

	this(string name, Connection owner, Server server)
	{
		this.name = name;
		this.owner = owner;
		this.members = [owner];
		this._server = server;
	}

	void sendNames(Connection connection)
	{
		enum channelType = "="; //TODO: Support secret and private channels

		connection.send(Message(_server.name, "353", [connection.nick, channelType, name, members.map!(m => m.nick).join(' ')], true));
		connection.send(Message(_server.name, "366", [connection.nick, name, "End of NAMES list"], true));
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
}
