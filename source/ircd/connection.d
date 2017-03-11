module ircd.connection;

import std.stdio;

import vibe.d;

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

			switch(message.command)
			{
				case "NICK":
					//TODO: Check availablity and validity etc.
					nick = message.parameters[0];
					writeln("nick: " ~ nick);
					break;
				case "USER":
					user = message.parameters[0];
					realname = message.parameters[3];

					writeln("user: " ~ user);
					writeln("mode: " ~ message.parameters[1]);
					writeln("unused: " ~ message.parameters[2]);
					writeln("realname: " ~ realname);

					send(Message("localhost", "001", [nick, "Welcome to the Internet Relay Network " ~ nick ~ "!" ~ user ~ "@hostname"], true));
					send(Message("localhost", "002", [nick, "Your host is ircd, running version 0.01"], true));
					send(Message("localhost", "003", [nick, "This server was created 2017-03-11"], true));
					send(Message("localhost", "004", [nick, "ircd", "0.01", "w", "snt"]));
					break;
				case "PING":
					send(Message(null, "PONG", [message.parameters[0]]));
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

