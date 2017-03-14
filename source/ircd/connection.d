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

class Connection
{
	private TCPConnection _connection;
	private Server _server;

	//TODO: Make into auto-properties (via template)
	string nick;
	string user;
	string realname;
	string hostname = "HOSTNAME";

	@property string mask() { return nick ~ "!" ~ user ~ "@" ~ hostname; }

	@property auto channels() { return _server.channels.filter!(c => c.members.canFind(this)); }

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

	void send(Message message)
	{
		string messageString = message.toString;
		writeln("S> " ~ messageString ~ " (" ~ nick.to!string ~ ")");
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
					onJoin(message);
					break;
				case "PART":
					onPart(message);
					break;
				default:
					writeln("unknown command '", message.command, "'");
					send(Message(_server.name, "421", [nick, "Unknown command"]));
					break;
			}
		}

		onDisconnect();
	}

	void onNick(Message message)
	{
		auto newNick = message.parameters[0];
		if(nick !is null)
		{
			sendToPeers(Message(nick, "NICK", [newNick]));
			send(Message(nick, "NICK", [newNick]));
		}

		//TODO: Check availablity and validity etc.
		nick = newNick;
	}

	void onUser(Message message)
	{
		//TODO: Parse user mode
		user = message.parameters[0];
		writeln("mode: " ~ message.parameters[1]);
		writeln("unused: " ~ message.parameters[2]);
		realname = message.parameters[3];
		hostname = getHost();

		send(Message(_server.name, "001", [nick, "Welcome to the Internet Relay Network " ~ mask], true));
		send(Message(_server.name, "002", [nick, "Your host is " ~ _server.name ~ ", running version " ~ _server.versionString], true));
		send(Message(_server.name, "003", [nick, "This server was created " ~ _server.creationDate], true));
		send(Message(_server.name, "004", [nick, _server.name, _server.versionString, "w", "snt"]));
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
		auto channel = message.parameters[0];
		if(!Server.isValidChannelName(channel))
		{
			send(Message(_server.name, "403", [nick, channel, "No such channel"], true));
		}
		else
		{
			_server.join(this, channel);
		}
	}

	void onPart(Message message)
	{
		//TODO: Support channel lists
		//TODO: Check if user is member of channel(s)
		auto channel = message.parameters[0];
		if(!Server.isValidChannelName(channel))
		{
			send(Message(_server.name, "403", [nick, channel, "No such channel"], true));
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
}

