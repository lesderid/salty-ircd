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

	string key; //TODO: Fully implement key
	//TODO: Implement member limit (+l)

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

	void part(Connection connection, string partMessage)
	{
		foreach(member; members)
		{
			if(partMessage !is null)
			{
				member.send(Message(connection.mask, "PART", [name, partMessage], true));
			}
			else
			{
				member.send(Message(connection.mask, "PART", [name]));
			}
		}

		members = members.remove!(m => m == connection);
		memberModes.remove(connection);
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

	void kick(Connection kicker, Connection user, string comment)
	{
		foreach(member; members)
		{
			member.send(Message(kicker.mask, "KICK", [name, user.nick, comment], true));
		}

		members = members.remove!(m => m == user);
		memberModes.remove(user);
	}

	void sendModes(Connection user)
	{
		if(members.canFind(user) && key !is null)
		{
			user.send(Message(_server.name, "324", [user.nick, name, "+" ~ modes.idup ~ "k", key]));
		}
		else
		{
			user.send(Message(_server.name, "324", [user.nick, name, "+" ~ modes.idup]));
		}
	}

	bool setMemberMode(Connection setter, Connection target, char mode)
	{
		if(memberModes[target].canFind(mode))
		{
			return false;
		}
		memberModes[target] ~= mode;

		return true;
	}

	bool unsetMemberMode(Connection setter, Connection target, char mode)
	{
		if(!memberModes[target].canFind(mode))
		{
			return false;
		}

		//NOTE: byCodeUnit is necessary due to auto-decoding (https://wiki.dlang.org/Language_issues#Unicode_and_ranges)
		import std.utf : byCodeUnit;
		import std.range : array;
		memberModes[target] = memberModes[target].byCodeUnit.remove!(m => m == mode).array;

		return true;
	}

	bool setMode(Connection setter, char mode)
	{
		if(modes.canFind(mode))
		{
			return false;
		}

		modes ~= mode;

		return true;
	}

	bool unsetMode(Connection setter, char mode)
	{
		if(!modes.canFind(mode))
		{
			return false;
		}

		//NOTE: byCodeUnit is necessary due to auto-decoding (https://wiki.dlang.org/Language_issues#Unicode_and_ranges)
		import std.utf : byCodeUnit;
		import std.range : array;
		modes = modes.byCodeUnit.remove!(m => m == mode).array;

		return true;
	}

	string prefixedNick(Connection member)
	{
		if(memberModes[member].canFind('o'))
		{
			return '@' ~ member.nick;
		}
		else if(memberModes[member].canFind('v'))
		{
			return '+' ~ member.nick;
		}

		return member.nick;
	}

	bool visibleTo(Connection connection)
	{
		return members.canFind(connection) || !modes.canFind('s') && !modes.canFind('p');
	}
}
