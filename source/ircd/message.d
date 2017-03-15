module ircd.message;

import std.string;
import std.functional;
import std.array;
import std.algorithm;
import std.conv;

//TODO: Make this a class
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

		//stop early when no space character can be found (message without parameters)
		if(!line.canFind(' '))
		{
			return Message(prefix, line, [], false);
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

		if(parameters.length == 0)
		{
			return message ~ command;
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

