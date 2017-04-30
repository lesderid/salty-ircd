module ircd.connection;

import std.stdio;
import std.string;
import std.algorithm;
import std.range;
import std.conv;
import std.socket;
import std.utf;
import std.datetime;

import vibe.core.core;
import vibe.stream.operations;

import ircd.message;
import ircd.server;
import ircd.channel;
import ircd.helpers;

class Connection
{
	private TCPConnection _connection;
	private Server _server;

	//TODO: Make into auto-properties (via template)
	string nick;
	string user;
	string realname;
	string hostname;
	char[] modes;

	SysTime lastMessageTime;

	string awayMessage;

	bool connected;

	@property auto channels() { return _server.channels.filter!(c => c.members.canFind(this)); }

	@property string mask() { return nick ~ "!" ~ user ~ "@" ~ hostname; }
	@property bool registered() { return nick !is null && user !is null; }
	@property bool isOperator() { return modes.canFind('o') || modes.canFind('O'); }
	@property string servername() { return _server.name; } //TODO: Support server linking

	this(TCPConnection connection, Server server)
	{
		_connection = connection;
		_server = server;

		connected = _connection.connected;
	}

	override int opCmp(Object o)
	{
		Connection other;
		if((other = cast(Connection)o) !is null)
		{
			return cmp(nick, other.nick);
		}
		return 0;
	}

	override bool opEquals(Object o)
	{
		Connection other;
		if((other = cast(Connection)o) !is null)
		{
			return nick == other.nick;
		}
		return false;
	}

	override ulong toHash()
	{
		return typeid(nick).getHash(&nick);
	}

	bool visibleTo(Connection other)
	{
		return !modes.canFind('i') || channels.any!(c => c.members.canFind(other));
	}

	void send(Message message)
	{
		string messageString = message.toString;
		writeln("S> " ~ messageString);
		_connection.write(messageString ~ "\r\n");
	}

	void closeConnection()
	{
		_connection.close();
	}

	//sends the message to all clients who have a channel in common with this client
	void sendToPeers(Message message)
	{
		if(channels.empty)
		{
			return;
		}

		foreach(connection; channels.map!(c => c.members).fold!((a, b) => a ~ b).sort().uniq.filter!(c => c != this))
		{
			connection.send(message);
		}
	}

	void onDisconnect()
	{
		writeln("client disconnected");
	}

	void handle()
	{
		while(connected)
		{
			Message message = void;
			try
			{
				message = Message.fromString((cast(string)_connection.readLine()).chomp);
			}
			catch(Throwable)
			{
				//TODO: The actual Throwable could be useful?
				connected = _connection.connected;
				continue;
			}

			//TODO: If RFC-strictness is off, ignore command case

			//NOTE: The RFCs don't specify what 'being idle' means
			//		We assume that it's sending any message that isn't a PING/PONG.
			if(message.command != "PING" && message.command != "PONG")
			{
				lastMessageTime = Clock.currTime;
			}

			writeln("C> " ~ message.toString);

			if(!registered && !["NICK", "USER", "PING", "PONG", "QUIT"].canFind(message.command))
			{
				sendErrNotRegistered();
				continue;
			}

			switch(message.command)
			{
				case "NICK":
					onNick(message);
					break;
				case "USER":
					onUser(message);
					break;
				case "PING":
					//TODO: Connection timeout when we don't get a PONG
					send(Message(_server.name, "PONG", [_server.name, message.parameters[0]], true));
					break;
				case "PONG":
					//TODO: Handle pong
					break;
				case "QUIT":
					onQuit(message);
					break;
				case "JOIN":
					onJoin(message);
					break;
				case "PART":
					onPart(message);
					break;
				case "PRIVMSG":
					onPrivMsg(message);
					break;
				case "NOTICE":
					onNotice(message);
					break;
				case "WHO":
					onWho(message);
					break;
				case "AWAY":
					onAway(message);
					break;
				case "TOPIC":
					onTopic(message);
					break;
				case "NAMES":
					onNames(message);
					break;
				case "LIST":
					onList(message);
					break;
				case "INVITE":
					onInvite(message);
					break;
				case "VERSION":
					onVersion(message);
					break;
				case "TIME":
					onTime(message);
					break;
				case "MOTD":
					onMotd(message);
					break;
				case "LUSERS":
					onLusers(message);
					break;
				case "ISON":
					onIson(message);
					break;
				case "WHOIS":
					onWhois(message);
					break;
				case "KILL":
					onKill(message);
					break;
				case "KICK":
					onKick(message);
					break;
				default:
					writeln("unknown command '", message.command, "'");
					send(Message(_server.name, "421", [nick, message.command, "Unknown command"]));
					break;
			}
		}

		onDisconnect();
	}

	void onNick(Message message)
	{
		if(message.parameters.length == 0)
		{
			sendErrNoNickGiven();
			return;
		}

		auto newNick = message.parameters[0];

		if(!_server.isNickAvailable(newNick) && newNick.toIRCLower != nick.toIRCLower)
		{
			send(Message(_server.name, "433", [nick, newNick, "Nickname already in use"]));
			return;
		}

		if(!_server.isValidNick(newNick))
		{
			send(Message(_server.name, "432", [nick, newNick, "Erroneous nickname"]));
			return;
		}

		if(nick !is null)
		{
			sendToPeers(Message(nick, "NICK", [newNick]));
			send(Message(nick, "NICK", [newNick]));
		}

		auto wasRegistered = registered;

		//TODO: Check validity etc.
		nick = newNick;

		if(!wasRegistered && registered)
		{
			sendWelcome();
		}
	}

	void onUser(Message message)
	{
		if(message.parameters.length < 4)
		{
			sendErrNeedMoreParams(message.command);
			return;
		}

		if(user !is null)
		{
			send(Message(_server.name, "462", [nick, "Unauthorized command (already registered)"], true));
			return;
		}

		auto wasRegistered = registered;

		//TODO: Maybe do something with the unused parameter?
		user = message.parameters[0];
		modes = modeMaskToModes(message.parameters[1]);
		realname = message.parameters[3];
		hostname = getHost();

		if(!wasRegistered && registered)
		{
			sendWelcome();
		}
	}

	void onQuit(Message message)
	{
		connected = false;
		send(Message(_server.name, "ERROR", ["Bye!"]));

		if(message.parameters.length > 0)
		{
			_server.quit(this, message.parameters[0]);
		}
		else
		{
			_server.quit(this, null);
		}
	}

	void onJoin(Message message)
	{
		if(message.parameters.length == 0)
		{
			sendErrNeedMoreParams(message.command);
			return;
		}

		auto channel = message.parameters[0];
		if(!Server.isValidChannelName(channel))
		{
			sendErrNoSuchChannel(channel);
		}
		else
		{
			_server.join(this, channel);
		}
	}

	void onPart(Message message)
	{
		if(message.parameters.length == 0)
		{
			sendErrNeedMoreParams(message.command);
			return;
		}

		//TODO: Support channel lists
		//TODO: Check if user is member of channel(s)
		auto channel = message.parameters[0];
		if(!Server.isValidChannelName(channel))
		{
			sendErrNoSuchChannel(channel);
		}
		else if(!_server.canFindChannelByName(channel))
		{
			send(Message(_server.name, "442", [nick, channel, "You're not on that channel"], true));
		}
		else
		{
			if(message.parameters.length > 1)
			{
				_server.part(this, channel, message.parameters[1]);
			}
			else
			{
				_server.part(this, channel, null);
			}
		}
	}

	void onPrivMsg(Message message)
	{
		//TODO: Support special message targets
		auto target = message.parameters[0];
		auto text = message.parameters[1];

		if(message.parameters.length == 0)
		{
			send(Message(_server.name, "411", [nick, "No recipient given (PRIVMSG)"], true));
			return;
		}
		if(message.parameters.length == 1)
		{
			send(Message(_server.name, "412", [nick, "No text to send"], true));
			return;
		}

		if(Server.isValidChannelName(target))
		{
			if(!_server.canFindChannelByName(target))
			{
				sendErrNoSuchNick(target);
			}
			else
			{
				_server.privmsgToChannel(this, target, text);
			}
		}
		else if(Server.isValidNick(target))
		{
			if(!_server.canFindConnectionByNick(target))
			{
				sendErrNoSuchNick(target);
			}
			else
			{
				_server.privmsgToUser(this, target, text);

				auto targetUser = _server.findConnectionByNick(target)[0];
				if(targetUser.modes.canFind('a'))
				{
					sendRplAway(target, targetUser.awayMessage);
				}
			}
		}
		else
		{
			//is this the right reply?
			sendErrNoSuchNick(target);
		}
	}

	void onNotice(Message message)
	{
		//TODO: Support special message targets
		auto target = message.parameters[0];
		auto text = message.parameters[1];

		//TODO: Figure out what we are allowed to send exactly

		if(message.parameters.length < 2)
		{
			return;
		}

		if(Server.isValidChannelName(target) && _server.canFindChannelByName(target))
		{
			_server.noticeToChannel(this, target, text);
		}
		else if(Server.isValidNick(target) && _server.canFindConnectionByNick(target))
		{
			_server.noticeToUser(this, target, text);
		}
	}

	void onWho(Message message)
	{
		if(message.parameters.length == 0)
		{
			_server.whoGlobal(this, "*", false);
		}
		else
		{
			auto mask = message.parameters[0];
			auto operatorsOnly = message.parameters.length > 1 && message.parameters[1] == "o";

			if(_server.isValidChannelName(mask) && _server.canFindChannelByName(mask))
			{
				_server.whoChannel(this, mask, operatorsOnly);
			}
			else
			{
				_server.whoGlobal(this, mask == "0" ? "*" : mask, operatorsOnly);
			}
		}

		auto name = message.parameters.length == 0 ? "*" : message.parameters[0];
		send(Message(_server.name, "315", [nick, name, "End of WHO list"], true));
	}

	void onAway(Message message)
	{
		if(message.parameters.length == 0)
		{
			//NOTE: byCodeUnit is necessary due to auto-decoding (https://wiki.dlang.org/Language_issues#Unicode_and_ranges)
			modes = modes.byCodeUnit.remove!(a => a == 'a').array;
			awayMessage = null;
			send(Message(_server.name, "305", [nick, "You are no longer marked as being away"], true));
		}
		else
		{
			modes ~= 'a';
			awayMessage = message.parameters[0];
			send(Message(_server.name, "306", [nick, "You have been marked as being away"], true));
		}
	}

	void onTopic(Message message)
	{
		if(message.parameters.length == 0)
		{
			sendErrNeedMoreParams(message.command);
			return;
		}

		auto channelName = message.parameters[0];
		if(message.parameters.length == 1)
		{
			if(!_server.channels.canFind!(c => c.name.toIRCLower == channelName.toIRCLower && (!(c.modes.canFind('s') || c.modes.canFind('p')) || c.members.canFind(this))))
			{
				//NOTE: The RFCs don't allow ERR_NOSUCHCHANNEL as a response to TOPIC
				//TODO: If RFC-strictness is off, do send ERR_NOSUCHCHANNEL
				send(Message(_server.name, "331", [nick, channelName, "No topic is set"], true));
			}
			else
			{
				_server.sendChannelTopic(this, channelName);
			}
		}
		else
		{
			auto newTopic = message.parameters[1];
			if(!channels.canFind!(c => c.name.toIRCLower == channelName.toIRCLower))
			{
				sendErrNotOnChannel(channelName);
			}
			//TODO: Allow operators to set flags
			else if(channels.find!(c => c.name.toIRCLower == channelName.toIRCLower).map!(c => c.modes.canFind('t') /* && this user isn't an operator */).array[0])
			{
				sendErrChanopPrivsNeeded(channelName);
			}
			else
			{
				_server.setChannelTopic(this, channelName, newTopic);
			}
		}
	}

	void onNames(Message message)
	{
		if(message.parameters.length > 1)
		{
			notImplemented("forwarding NAMES to another server");
			return;
		}

		if(message.parameters.length == 0)
		{
			_server.sendGlobalNames(this);
		}
		else
		{
			foreach(channelName; message.parameters[0].split(','))
			{
				if(_server.channels.canFind!(c => c.name.toIRCLower == channelName.toIRCLower && c.visibleTo(this)))
				{
					_server.sendChannelNames(this, channelName);
				}
				else
				{
					sendRplEndOfNames(channelName);
				}
			}
		}
	}

	void onList(Message message)
	{
		if(message.parameters.length > 1)
		{
			notImplemented("forwarding LIST to another server");
			return;
		}

		if(message.parameters.length == 0)
		{
			_server.sendFullList(this);
		}
		else
		{
			auto channelNames = message.parameters[0].split(',');
			_server.sendPartialList(this, channelNames);
		}
	}

	void onInvite(Message message)
	{
		if(message.parameters.length < 2)
		{
			sendErrNeedMoreParams(message.command);
			return;
		}

		auto targetNick = message.parameters[0];
		auto targetUserRange = _server.findConnectionByNick(targetNick);
		if(targetUserRange.empty)
		{
			sendErrNoSuchNick(targetNick);
			return;
		}
		auto targetUser = targetUserRange[0];

		auto channelName = message.parameters[1];
		auto channelRange = _server.findChannelByName(channelName);
		if(channelRange.empty)
		{
			_server.invite(this, targetUser.nick, channelName);

			sendRplInviting(channelName, targetUser.nick);

			if(targetUser.modes.canFind('a'))
			{
				sendRplAway(targetUser.nick, targetUser.awayMessage);
			}
		}
		else
		{
			auto channel = channelRange[0];
			if(!channel.members.canFind(this))
			{
				sendErrNotOnChannel(channel.name);
			}
			else if(channel.members.canFind(targetUser))
			{
				send(Message(_server.name, "443", [nick, targetUser.nick, channel.name, "is already on channel"], true));
			}
			else if(channel.modes.canFind('i') /* TODO: and this connection isn't a chanop */)
			{
				sendErrChanopPrivsNeeded(channel.name);
			}
			else
			{
				_server.invite(this, targetUser.nick, channel.name);

				sendRplInviting(channel.name, targetUser.nick);

				if(targetUser.modes.canFind('a'))
				{
					sendRplAway(targetUser.nick, targetUser.awayMessage);
				}
			}
		}
	}

	void onVersion(Message message)
	{
		if(message.parameters.length > 0)
		{
			notImplemented("querying the version of another server");
			return;
		}
		_server.sendVersion(this);
	}

	void onTime(Message message)
	{
		if(message.parameters.length > 0)
		{
			notImplemented("querying the time of another server");
			return;
		}
		_server.sendTime(this);
	}

	void onMotd(Message message)
	{
		if(message.parameters.length > 0)
		{
			notImplemented("querying the motd of another server");
			return;
		}
		else if(_server.motd is null)
		{
			send(Message(_server.name, "422", [nick, "MOTD File is missing"], true));
			return;
		}
		_server.sendMotd(this);
	}

	void onLusers(Message message)
	{
		if(message.parameters.length == 1)
		{
			notImplemented("querying the size of a part of the network");
			return;
		}
		else if(message.parameters.length > 1)
		{
			notImplemented("forwarding LUSERS to another server");
			return;
		}
		_server.sendLusers(this);
	}

	void onIson(Message message)
	{
		if(message.parameters.length < 1)
		{
			sendErrNeedMoreParams(message.command);
			return;
		}

		//NOTE: The RFCs are ambiguous about the parameter(s).
		//		It specifies one allowed parameter type, a space-separated list of nicknames (i.e. prefixed with ':').
		//		However, the nicknames in the example are sent as separate parameters, not as a single string prefixed with ':'.
		//		For this implementation, we assume the example is wrong, like most clients seem to assume as well.
		//		(Other server implementations usually seem to support both interpretations.)
		_server.ison(this, message.parameters[0].split);
	}

	void onWhois(Message message)
	{
		if(message.parameters.length < 1)
		{
			sendErrNoNickGiven();
			return;
		}
		else if(message.parameters.length > 1)
		{
			notImplemented("forwarding WHOIS to another server");
			return;
		}

		auto mask = message.parameters[0];
		//TODO: Support user masks
		if(!_server.canFindConnectionByNick(mask) || !_server.findConnectionByNick(mask)[0].visibleTo(this))
		{
			sendErrNoSuchNick(mask);
		}
		else
		{
			_server.whois(this, mask);
		}

		send(Message(_server.name, "318", [nick, mask, "End of WHOIS list"], true));
	}

	void onKill(Message message)
	{
		if(!isOperator)
		{
			sendErrNoPrivileges();
			return;
		}

		if(message.parameters.length < 2)
		{
			sendErrNeedMoreParams(message.command);
			return;
		}

		auto nick = message.parameters[0];
		if(!_server.canFindConnectionByNick(nick))
		{
			sendErrNoSuchNick(nick);
			return;
		}

		auto comment = message.parameters[1];

		_server.kill(this, nick, comment);
	}

	void onKick(Message message)
	{
		if(message.parameters.length < 2)
		{
			sendErrNeedMoreParams(message.command);
			return;
		}

		auto channelList = message.parameters[0].split(',');
		auto userList = message.parameters[1].split(',');
		auto comment = message.parameters.length > 2 ? message.parameters[2] : nick;

		if(channelList.length != 1 && channelList.length != userList.length)
		{
			//TODO: Figure out what the right error is here
			sendErrNeedMoreParams(message.command);
			return;
		}

		foreach(i, nick; userList)
		{
			auto channelName = channelList[0];
			if(channelList.length != 1)
			{
				channelName = channelList[i];
			}

			if(!_server.canFindChannelByName(channelName))
			{
				sendErrNoSuchChannel(channelName);
			}
			else
			{
				auto channel = _server.findChannelByName(channelName)[0];
				if(!channel.members.canFind(this))
				{
					sendErrNotOnChannel(channelName);
				}
				else if(!channel.memberModes[this].canFind('o'))
				{
					sendErrChanopPrivsNeeded(channelName);
				}
				else if(!channel.members.canFind!(m => m.nick.toIRCLower == nick.toIRCLower))
				{
					sendErrUserNotInChannel(nick, channelName);
				}
				else
				{
					_server.kick(this, channelName, nick, comment);
				}
			}
		}
	}

	void sendWhoReply(string channel, Connection user, uint hopCount)
	{
		auto flags = user.modes.canFind('a') ? "G" : "H";
		if(user.isOperator) flags ~= "*";
		//TODO: Add channel prefix

		send(Message(_server.name, "352", [nick, channel, user.user, user.hostname, user.servername, user.nick, flags, hopCount.to!string ~ " " ~ user.realname], true));
	}

	void sendRplAway(string target, string message)
	{
		send(Message(_server.name, "301", [nick, target, message], true));
	}

	void sendRplList(string channelName, ulong visibleCount, string topic)
	{
		send(Message(_server.name, "322", [nick, channelName, visibleCount.to!string, topic], true));
	}

	void sendRplListEnd()
	{
		send(Message(_server.name, "323", [nick, "End of LIST"], true));
	}

	void sendRplInviting(string channelName, string name)
	{
		//TODO: If RFC-strictness is off, send parameters in reverse order
		send(Message(_server.name, "341", [nick, channelName, name]));
	}

	void sendRplEndOfNames(string channelName)
	{
		send(Message(_server.name, "366", [nick, channelName, "End of NAMES list"], true));
	}

	void sendErrNoSuchNick(string name)
	{
		send(Message(_server.name, "401", [nick, name, "No such nick/channel"], true));
	}

	void sendErrNoSuchChannel(string name)
	{
		send(Message(_server.name, "403", [nick, name, "No such channel"], true));
	}

	void sendErrNoNickGiven()
	{
		send(Message(_server.name, "431", [nick, "No nickname given"], true));
	}

	void sendErrUserNotInChannel(string otherNick, string channel)
	{
		send(Message(_server.name, "441", [nick, otherNick, channel, "They aren't on that channel"], true));
	}

	void sendErrNotOnChannel(string channel)
	{
		send(Message(_server.name, "442", [nick, channel, "You're not on that channel"], true));
	}

	void sendErrNotRegistered()
	{
		send(Message(_server.name, "451", ["(You)", "You have not registered"], true));
	}

	void sendErrNeedMoreParams(string command)
	{
		send(Message(_server.name, "461", [nick, command, "Not enough parameters"], true));
	}

	void sendErrNoPrivileges()
	{
		send(Message(_server.name, "481", [nick, "Permission Denied- You're not an IRC operator"], true));
	}

	void sendErrChanopPrivsNeeded(string channel)
	{
		send(Message(_server.name, "482", [nick, channel, "You're not channel operator"], true));
	}

	void notImplemented(string description)
	{
		send(Message(_server.name, "ERROR", ["Not implemented yet (" ~ description ~ ")"], true));
	}

	void sendWelcome()
	{
		send(Message(_server.name, "001", [nick, "Welcome to the Internet Relay Network " ~ mask], true));
		send(Message(_server.name, "002", [nick, "Your host is " ~ _server.name ~ ", running version " ~ _server.versionString], true));
		send(Message(_server.name, "003", [nick, "This server was created " ~ _server.creationDate], true));
		send(Message(_server.name, "004", [nick, _server.name, _server.versionString, "w", "snt"]));
	}

	string getHost()
	{
		auto address = parseAddress(_connection.peerAddress);
		auto hostname = address.toHostNameString;
		if(hostname is null)
		{
			hostname = address.toAddrString;
		}
		return hostname;
	}

	char[] modeMaskToModes(string maskString)
	{
		import std.conv : to;
		import std.exception : ifThrown;

		auto mask = maskString.to!ubyte.ifThrown(0);

		char[] modes;

		if(mask & 0b100)
		{
			modes ~= 'w';
		}
		if(mask & 0b1000)
		{
			modes ~= 'i';
		}

		return modes;
	}
}

