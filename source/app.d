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

void handleConnection(TCPConnection connection)
{
	writeln("connection opened");
	while(connection.connected)
	{
		auto message = Message.fromString((cast(string)connection.readLine()).chomp);
		writeln("C> " ~ message.toString);
	}
	writeln("connection closed");
}


