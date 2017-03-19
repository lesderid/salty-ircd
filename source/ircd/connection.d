module ircd.connection;

import std.stdio;
import std.string;
import std.algorithm;
import std.range;
import std.conv;
import std.socket;

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

	@property auto channels() { return _server.channels.filter!(c => c.members.canFind(this)); }

	@property string mask() { return nick ~ "!" ~ user ~ "@" ~ hostname; }
	@property bool registered() { return nick !is null && user !is null; }
	@property bool isOperator() { return modes.canFind('o') || modes.canFind('O'); }
	@property string servername() { return _server.name; } //TODO: Support server linking

	bool connected;

	this(TCPConnection connection, Server server)
	{
		_connection = connection;
		_server = server;

		connected = _connection.connected;
	}

	override int opCmp(Object o)
	{
		Connection other;
		if((other = cast(Connection)other) !is null)
		{
			return cmp(nick, other.nick);
		}
		return 0;
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

			writeln("C> " ~ message.toString);

			//TODO: If RFC-strictness is off, ignore case
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
					if(!registered) sendErrNotRegistered();
					else onJoin(message);
					break;
				case "PART":
					if(!registered) sendErrNotRegistered();
					else onPart(message);
					break;
				case "PRIVMSG":
					if(!registered) sendErrNotRegistered();
					else onPrivMsg(message);
					break;
				case "WHO":
					if(!registered) sendErrNotRegistered();
					else onWho(message);
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

		if(!_server.isNickAvailable(newNick))
		{
			send(Message(_server.name, "433", [nick, newNick, "Nickname already in use"]));
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

		if(!wasRegistered)
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

		//TODO: Maybe do something with the unused parameter?
		user = message.parameters[0];
		modes = modeMaskToModes(message.parameters[1]);
		realname = message.parameters[3];
		hostname = getHost();

		if(registered)
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
		else if(!channels.canFind!(c => c.name == channel))
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
			if(!_server.channels.canFind!(c => c.name == target))
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
			if(!_server.connections.canFind!(c => c.nick == target))
			{
				sendErrNoSuchNick(target);
			}
			else
			{
				_server.privmsgToUser(this, target, text);
			}
		}
		else
		{
			//is this the right reply?
			sendErrNoSuchNick(target);
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

			if(_server.isValidChannelName(mask) && _server.channels.canFind!(c => c.name == mask))
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

	void sendErrNotRegistered()
	{
		send(Message(_server.name, "451", ["(You)", "You have not registered"], true));
	}

	void sendErrNeedMoreParams(string command)
	{
		send(Message(_server.name, "461", [nick, command, "Not enough parameters"], true));
	}

	void sendWhoReply(string channel, Connection user, uint hopCount)
	{
		auto flags = user.modes.canFind('a') ? "G" : "H";
		if(user.isOperator)	flags ~= "*";
		//TODO: Add channel prefix

		send(Message(_server.name, "352", [nick, channel, user.user, user.hostname, user.servername, user.nick, flags, hopCount.to!string ~ " " ~ user.realname], true));
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

