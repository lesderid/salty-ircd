import vibe.d;

import std.stdio;
import std.functional;
import std.array;
import std.algorithm;
import std.conv;

shared static this()
{
	listenTCP(6667, toDelegate(&handleConnection), "127.0.0.1");
}

struct Message
{
	string prefix;
	string command;
	string[] parameters;
	bool prefixedParameter;

	static Message fromString(string line)
	{
		string prefix = null;
		if(line.startsWith(':'))
		{
			line = line[1 .. $];
			prefix = line[0 .. line.indexOf(' ')];
			line = line[prefix.length + 1 .. $];
		}

		auto command = line[0 .. line.indexOf(' ')];
		line = line[command.length + 1 .. $];
		string[] params = [];
		bool prefixedParam;
		while(true)
		{
			if(line.startsWith(':'))
			{
				params ~= line[1 .. $];
				prefixedParam = true;
				break;
			}
			else if(line.canFind(' '))
			{
				auto param = line[0 .. line.indexOf(' ')];
				line = line[param.length + 1 .. $];
				params ~= param;
			}
			else
			{
				params ~= line;
				break;
			}
		}

		return Message(prefix, command, params, prefixedParam);
	}

	string toString()
	{
		auto message = "";
		if(prefix != null)
		{
			message = ":" ~ prefix ~ " ";
		}

		message ~= command ~ " ";
		if(parameters.length > 1)
		{
			message ~= parameters[0 .. $-1].join(' ') ~ " ";
		}
		if(parameters[$-1].canFind(' ') || prefixedParameter)
		{
			message ~= ":";
		}
		message ~= parameters[$-1];

		return message;
	}
}

void send(TCPConnection connection, Message message)
{
	string messageString = message.toString;
	writeln("S> " ~ messageString);
	connection.write(messageString ~ "\r\n");
}

void handleConnection(TCPConnection connection)
{
	string nick;
	string user;
	string realname;
	while(connection.connected)
	{
		auto message = Message.fromString((cast(string)connection.readLine()).chomp);
		writeln("C> " ~ message.toString);

		switch(message.command)
		{
			case "NICK":
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

				connection.send(Message("localhost", "001", [nick, "Welcome to the Internet Relay Network " ~ nick ~ "!" ~ user ~ "@hostname"], true));
				connection.send(Message("localhost", "002", [nick, "Your host is ircd, running version 0.01"], true));
				connection.send(Message("localhost", "003", [nick, "This server was created 2017-03-11"], true));
				connection.send(Message("localhost", "004", [nick, "ircd", "0.01", "w", "snt"]));
				break;
			case "PING":
				connection.send(Message(null, "PONG", [message.parameters[0]]));
				break;
			default:
				writeln("unknown command '", message.command, "'");
				break;
		}
	}
}


