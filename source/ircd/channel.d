module ircd.channel;

import std.algorithm;
import std.string;

import ircd.connection;
import ircd.server;
import ircd.message;

class Channel
{
	private string _name;

	Connection[] members;
	Connection owner;

	private Server _server;

	this(string name, Connection owner, Server server)
	{
		this._name = name;
		this.owner = owner;
		this.members = [owner];
		this._server = server;
	}

	@property
	string name()
	{
		return _name;
	}

	void sendNames(Connection connection)
	{
		enum channelType = "="; //TODO: Support secret and private channels

		connection.send(Message(_server.name, "353", [connection.nick, channelType, name, members.map!(m => m.nick).join(' ')], true));
		connection.send(Message(_server.name, "366", [connection.nick, name, "End of NAMES list"], true));
	}
}
