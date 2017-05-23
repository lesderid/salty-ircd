module ircd.channel;

import std.algorithm;
import std.string;
import std.typecons : Nullable;

import ircd.connection;
import ircd.server;
import ircd.message;
import ircd.helpers;

class Channel
{
	string name;
	string topic = "";

	Connection[] members;
	char[] modes;
	char[][Connection] memberModes;
	string[][char] maskLists;

	string key;
	Nullable!uint userLimit;

	private Server _server;

	this(string name, Server server)
	{
		this.name = name;
		this._server = server;
		this.maskLists = ['b' : [], 'e' : [], 'I' : []];
	}

	void join(Connection connection)
	{
		members ~= connection;

		if(members.length == 1)
		{
			memberModes[connection] ~= 'o';
		}
		else
		{
			memberModes[connection] = [];
		}
	}

	void part(Connection connection, string partMessage)
	{
		foreach(member; members)
		{
			if(partMessage !is null)
			{
				member.send(Message(connection.prefix, "PART", [name, partMessage], true));
			}
			else
			{
				member.send(Message(connection.prefix, "PART", [name]));
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
			member.send(Message(sender.prefix, "PRIVMSG", [name, text], true));
		}
	}

	void sendNotice(Connection sender, string text)
	{
		foreach(member; members.filter!(m => m.nick != sender.nick))
		{
			member.send(Message(sender.prefix, "NOTICE", [name, text], true));
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
			member.send(Message(connection.prefix, "TOPIC", [name, newTopic], true));
		}
	}

	void kick(Connection kicker, Connection user, string comment)
	{
		foreach(member; members)
		{
			member.send(Message(kicker.prefix, "KICK", [name, user.nick, comment], true));
		}

		members = members.remove!(m => m == user);
		memberModes.remove(user);
	}

	void sendModes(Connection user)
	{
		auto specialModes = "";
		string[] specialModeParameters;

		if(members.canFind(user) && key !is null)
		{
			specialModes ~= "k";
			specialModeParameters ~= key;
		}

		if(members.canFind(user) && !userLimit.isNull)
		{
			import std.conv : to;

			specialModes ~= "l";
			specialModeParameters ~= userLimit.to!string;
		}

		user.send(Message(_server.name, "324", [user.nick, name, "+" ~ modes.idup ~ specialModes] ~ specialModeParameters));
	}

	bool setMemberMode(Connection target, char mode)
	{
		if(memberModes[target].canFind(mode))
		{
			return false;
		}
		memberModes[target] ~= mode;

		return true;
	}

	bool unsetMemberMode(Connection target, char mode)
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

	bool setMode(char mode)
	{
		if(modes.canFind(mode))
		{
			return false;
		}

		modes ~= mode;

		return true;
	}

	bool unsetMode(char mode)
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

	bool addMaskListEntry(string mask, char mode)
	{
		if(maskLists[mode].canFind!(m => m.toIRCLower == mask.toIRCLower))
		{
			return false;
		}

		maskLists[mode] ~= mask;

		return true;
	}

	bool removeMaskListEntry(string mask, char mode)
	{
		if(!maskLists[mode].canFind!(m => m.toIRCLower == mask.toIRCLower))
		{
			return false;
		}

		maskLists[mode] = maskLists[mode].remove!(m => m.toIRCLower == mask.toIRCLower);

		return true;
	}

	void sendBanList(Connection connection)
	{
		foreach(entry; maskLists['b'])
		{
			connection.send(Message(_server.name, "367", [connection.nick, name, entry], false));
		}

		connection.send(Message(_server.name, "368", [connection.nick, name, "End of channel ban list"], true));
	}

	void sendExceptList(Connection connection)
	{
		foreach(entry; maskLists['e'])
		{
			connection.send(Message(_server.name, "348", [connection.nick, name, entry], false));
		}

		connection.send(Message(_server.name, "349", [connection.nick, name, "End of channel exception list"], true));
	}

	void sendInviteList(Connection connection)
	{
		foreach(entry; maskLists['I'])
		{
			connection.send(Message(_server.name, "346", [connection.nick, name, entry], false));
		}

		connection.send(Message(_server.name, "347", [connection.nick, name, "End of channel invite list"], true));
	}

	bool setKey(string key)
	{
		this.key = key;

		return true;
	}

	bool unsetKey(string key)
	{
		if(this.key != key)
		{
			return false;
		}

		this.key = null;

		return true;
	}

	void setUserLimit(uint userLimit)
	{
		this.userLimit = userLimit;
	}

	bool unsetUserLimit()
	{
		if(userLimit.isNull)
		{
			return false;
		}

		userLimit.nullify();

		return true;
	}

	string nickPrefix(Connection member)
	{
		if(memberModes[member].canFind('o'))
		{
			return "@";
		}
		else if(memberModes[member].canFind('v'))
		{
			return "+";
		}

		return "";
	}

	string prefixedNick(Connection member) { return nickPrefix(member) ~ member.nick; }

	bool visibleTo(Connection connection)
	{
		return members.canFind(connection) || !modes.canFind('s') && !modes.canFind('p');
	}

	bool canReceiveMessagesFromUser(Connection connection)
	{
		if(modes.canFind('n') && !members.canFind(connection))
		{
			return false;
		}
		else if(modes.canFind('m') && nickPrefix(connection).empty)
		{
			return false;
		}
		else if(maskLists['b'].any!(m => connection.matchesMask(m)) && !maskLists['e'].any!(m => connection.matchesMask(m)))
		{
			return false;
		}

		return true;
	}
}
