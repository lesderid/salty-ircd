module ircd.connection;

import std.stdio;
import std.string;

import vibe.core.core;
import vibe.stream.operations;

import ircd.packageVersion;

import ircd.message;

class Connection
{
	private TCPConnection _connection;

	//TODO: Make into auto-properties (via template)
	string nick;
	string user;
	string realname;

	bool connected;

	this(TCPConnection connection)
	{
		_connection = connection;
	}

	void send(Message message)
	{
		string messageString = message.toString;
		writeln("S> " ~ messageString);
		_connection.write(messageString ~ "\r\n");
	}

	void handle()
	{
		connected = true;
		while(connected)
		{
			auto message = Message.fromString((cast(string)_connection.readLine()).chomp);
			writeln("C> " ~ message.toString);

			//TODO: If RFC-strictness is off, ignore case
			switch(message.command)
			{
				case "NICK":
					//TODO: Check availablity and validity etc.
					nick = message.parameters[0];
					break;
				case "USER":
					user = message.parameters[0];
					realname = message.parameters[3];

					writeln("mode: " ~ message.parameters[1]);
					writeln("unused: " ~ message.parameters[2]);

					send(Message("localhost", "001", [nick, "Welcome to the Internet Relay Network " ~ nick ~ "!" ~ user ~ "@hostname"], true));
					send(Message("localhost", "002", [nick, "Your host is localhost, running version salty-ircd-" ~ packageVersion], true));
					send(Message("localhost", "003", [nick, "This server was created " ~ packageTimestampISO], true));
					send(Message("localhost", "004", [nick, "localhost", "salty-ircd-" ~ packageVersion, "w", "snt"]));
					break;
				case "PING":
					send(Message(null, "PONG", [message.parameters[0]], true));
					break;
				case "PONG":
					//TODO: Handle pong
					break;
				case "QUIT":
					send(Message(null, "ERROR", ["Bye!"]));
					connected = false;
					break;
				default:
					writeln("unknown command '", message.command, "'");
					break;
			}
		}
	}

}

