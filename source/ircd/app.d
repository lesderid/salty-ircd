module ircd.app;

import ircd.server;

shared static this()
{
	auto server = new Server();
	server.listen();
}

