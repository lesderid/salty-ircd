module ircd.server;

import std.stdio;
import std.algorithm;
import std.range;
import std.conv;
import std.socket;
import core.time;
import std.datetime;
import std.string;

import vibe.core.core;
import vibe.core.net;

import ircd.versionInfo;

import ircd.message;
import ircd.connection;
import ircd.channel;
import ircd.helpers;
import ircd.numerics;

//TODO: Make this a struct?
class Server
{
    Connection[] connections;

    enum versionString = "salty-ircd-" ~ gitVersion;

    string name;
    enum string info = "A salty-ircd server"; //TODO: Make server info configurable

    string motd;

    Channel[] channels;

    private uint[string] _commandUsage;
    private ulong[string] _commandBytes;

    private string _pass = null;

    private SysTime _startTime;

    this()
    {
        name = Socket.hostName;

        readMotd();

        _startTime = Clock.currTime;

        runTask(&pingLoop);
    }

    private void readMotd()
    {
        import std.file : exists, readText;

        if (exists("motd"))
        {
            motd = readText("motd");
        }
    }

    private void pingLoop()
    {
        while (true)
        {
            foreach (connection; connections)
            {
                connection.send(Message(null, "PING", [name], true));
            }
            sleep(30.seconds);
        }
    }

    private void acceptConnection(TCPConnection tcpConnection)
    {
        auto connection = new Connection(tcpConnection, this);
        connections ~= connection;
        connection.handle();
        connections = connections.filter!(c => c != connection).array;
    }

    static bool isValidChannelName(string name)
    {
        return (name.startsWith('#') || name.startsWith('&')) && name.length <= 200;
    }

    static bool isValidNick(string name)
    {
        import std.ascii : digits, letters;

        if (name.length > 9)
        {
            return false;
        }
        foreach (i, c; name)
        {
            auto allowed = letters ~ "[]\\`_^{|}";
            if (i > 0)
            {
                allowed ~= digits ~ "-";
            }

            if (!allowed.canFind(c))
            {
                return false;
            }
        }
        return true;
    }

    static bool isValidUserMask(string mask)
    {
        import std.regex : ctRegex, matchFirst;

        auto validMaskRegex = ctRegex!r"^([^!]+)!([^@]+)@(.+)$";
        return !mask.matchFirst(validMaskRegex).empty;
    }

    Connection[] findConnectionByNick(string nick)
    {
        return connections.find!(c => c.nick.toIRCLower == nick.toIRCLower);
    }

    bool canFindConnectionByNick(string nick)
    {
        return !findConnectionByNick(nick).empty;
    }

    bool isNickAvailable(string nick)
    {
        return !canFindConnectionByNick(nick);
    }

    Channel[] findChannelByName(string name)
    {
        return channels.find!(c => c.name.toIRCLower == name.toIRCLower);
    }

    bool canFindChannelByName(string name)
    {
        return !findChannelByName(name).empty;
    }

    void join(Connection connection, string channelName)
    {
        auto channelRange = findChannelByName(channelName);
        Channel channel;
        if (channelRange.empty)
        {
            channel = new Channel(channelName, this);
            channels ~= channel;
        }
        else
        {
            channel = channelRange[0];
        }
        channel.join(connection);

        foreach (member; channel.members)
        {
            member.send(Message(connection.prefix, "JOIN", [channelName]));
        }

        channel.sendNames(connection);

        if (!channel.topic.empty)
        {
            channel.sendTopic(connection);
        }
    }

    void part(Connection connection, string channelName, string partMessage)
    {
        auto channel = connection.channels.array.find!(
                c => c.name.toIRCLower == channelName.toIRCLower)[0];

        channel.part(connection, partMessage);

        if (channel.members.empty)
        {
            channels = channels.remove!(c => c == channel);
        }
    }

    void quit(Connection connection, string quitMessage)
    {
        Connection[] peers;
        foreach (channel; connection.channels)
        {
            peers ~= channel.members;
            channel.members = channel.members.remove!(m => m == connection);
            if (channel.members.empty)
            {
                channels = channels.remove!(c => c == channel);
            }
        }
        peers = peers.sort().uniq.filter!(c => c != connection).array;

        foreach (peer; peers)
        {
            if (quitMessage !is null)
            {
                peer.send(Message(connection.prefix, "QUIT", [quitMessage], true));
            }
            else
            {
                peer.send(Message(connection.prefix, "QUIT", [connection.nick], true));
            }
        }
    }

    void whoChannel(Connection origin, string channelName, bool operatorsOnly)
    {
        //TODO: Check what RFCs say about secret/private channels

        auto channel = findChannelByName(channelName)[0];
        foreach (c; channel.members
                .filter!(c => !operatorsOnly || c.isOperator)
                .filter!(c => c.visibleTo(origin)))
        {
            //TODO: Support hop count
            origin.sendWhoReply(channelName, c, channel.nickPrefix(c), 0);
        }
    }

    void whoGlobal(Connection origin, string mask, bool operatorsOnly)
    {
        foreach (c; connections.filter!(c => c.visibleTo(origin))
                .filter!(c => !operatorsOnly || c.isOperator)
                .filter!(c => [c.hostname, c.servername, c.realname,
                        c.nick].any!(n => wildcardMatch(n, mask))))
        {
            //TODO: Don't leak secret/private channels if RFC-strictness is off (the RFCs don't seem to say anything about it?)
            auto channelName = c.channels.empty ? "*" : c.channels.array[0].name;
            auto nickPrefix = c.channels.empty ? "" : c.channels.array[0].nickPrefix(c);
            //TODO: Support hop count
            origin.sendWhoReply(channelName, c, nickPrefix, 0);
        }
    }

    void privmsgToChannel(Connection sender, string target, string text)
    {
        auto channel = findChannelByName(target)[0];
        channel.sendPrivMsg(sender, text);
    }

    void privmsgToUser(Connection sender, string target, string text)
    {
        auto user = findConnectionByNick(target)[0];
        user.send(Message(sender.prefix, "PRIVMSG", [target, text], true));
    }

    void noticeToChannel(Connection sender, string target, string text)
    {
        auto channel = findChannelByName(target)[0];
        channel.sendNotice(sender, text);
    }

    void noticeToUser(Connection sender, string target, string text)
    {
        auto user = findConnectionByNick(target)[0];
        user.send(Message(sender.prefix, "NOTICE", [target, text], true));
    }

    void sendChannelTopic(Connection origin, string channelName)
    {
        auto channel = findChannelByName(channelName)[0];
        channel.sendTopic(origin);
    }

    void setChannelTopic(Connection origin, string channelName, string newTopic)
    {
        auto channel = findChannelByName(channelName)[0];
        channel.setTopic(origin, newTopic);
    }

    void sendChannelNames(Connection connection, string channelName)
    {
        auto channel = findChannelByName(channelName)[0];
        channel.sendNames(connection);
    }

    void sendGlobalNames(Connection connection)
    {
        foreach (channel; channels.filter!(c => c.visibleTo(connection)))
        {
            channel.sendNames(connection, false);
        }

        auto otherUsers = connections.filter!(c => !c.modes.canFind('i')
                && c.channels.filter!(ch => !ch.modes.canFind('s')
                    && !ch.modes.canFind('p')).empty);
        if (!otherUsers.empty)
        {
            connection.sendNumeric!RPL_NAMREPLY("=", "*", otherUsers.map!(m => m.nick).join(' '));
        }

        connection.sendNumeric!RPL_ENDOFNAMES("*");
    }

    void sendFullList(Connection connection)
    {
        foreach (channel; channels.filter!(c => c.visibleTo(connection)))
        {
            connection.sendNumeric!RPL_LIST(channel.name, channel.members
                    .filter!(m => m.visibleTo(connection))
                    .array
                    .length
                    .to!string, channel.topic);
        }
        connection.sendNumeric!RPL_LISTEND();
    }

    void sendPartialList(Connection connection, string[] channelNames)
    {
        foreach (channel; channels.filter!(c => channelNames.canFind(c.name)
                && c.visibleTo(connection)))
        {
            connection.sendNumeric!RPL_LIST(channel.name, channel.members
                    .filter!(m => m.visibleTo(connection))
                    .array
                    .length
                    .to!string, channel.topic);
        }
        connection.sendNumeric!RPL_LISTEND();
    }

    void sendVersion(Connection connection)
    {
        //TODO: Include enabled versions in comments?
        connection.sendNumeric!RPL_VERSION(versionString ~ ".", name, ":");
    }

    void sendTime(Connection connection)
    {
        auto timeString = Clock.currTime.toISOExtString;
        connection.sendNumeric!RPL_TIME(name, timeString);
    }

    void invite(Connection inviter, string target, string channelName)
    {
        auto user = findConnectionByNick(target)[0];
        auto channel = findChannelByName(channelName)[0];

        channel.invite(user);

        user.send(Message(inviter.prefix, "INVITE", [user.nick, channelName]));
    }

    void sendMotd(Connection connection)
    {
        connection.sendNumeric!RPL_MOTDSTART("- " ~ name ~ " Message of the day - ");
        foreach (line; motd.splitLines)
        {
            //TODO: Implement line wrapping
            connection.sendNumeric!RPL_MOTD("- " ~ line);
        }
        connection.sendNumeric!RPL_ENDOFMOTD();
    }

    void sendLusers(Connection connection)
    {
        //TODO: If RFC-strictness is off, use '1 server' instead of '1 servers' if the network (or the part of the network of the query) has only one server

        //TODO: Support services and multiple servers
        connection.sendNumeric!RPL_LUSERCLIENT(
                "There are " ~ connections.filter!(c => c.registered)
                .count
                .to!string ~ " users and 0 services on 1 servers");

        if (connections.any!(c => c.isOperator))
        {
            connection.sendNumeric!RPL_LUSEROP(connections.count!(c => c.isOperator)
                    .to!string);
        }

        if (connections.any!(c => !c.registered))
        {
            connection.sendNumeric!RPL_LUSERUNKNOWN(connections.count!(c => !c.registered)
                    .to!string);
        }

        if (channels.length > 0)
        {
            connection.sendNumeric!RPL_LUSERCHANNELS(channels.length.to!string);
        }

        connection.sendNumeric!RPL_LUSERME(
                "I have " ~ connections.length.to!string ~ " clients and 1 servers");
    }

    void ison(Connection connection, string[] nicks)
    {
        auto reply = nicks.filter!(n => canFindConnectionByNick(n)).join(' ');
        connection.sendNumeric!RPL_ISON(reply);
    }

    void whois(Connection connection, string mask)
    {
        auto user = findConnectionByNick(mask)[0];

        connection.sendNumeric!RPL_WHOISUSER(user.nick, user.user,
                user.hostname, "*", user.realname);

        //TODO: Send information about the user's actual server (which is not necessarily this one)
        connection.sendNumeric!RPL_WHOISSERVER(user.nick, name, info);

        if (user.isOperator)
        {
            connection.sendNumeric!RPL_WHOISOPERATOR(user.nick);
        }

        auto idleSeconds = (Clock.currTime - user.lastMessageTime).total!"seconds";
        connection.sendNumeric!RPL_WHOISIDLE(user.nick, idleSeconds.to!string);

        auto userChannels = user.channels.map!(c => c.nickPrefix(user) ~ c.name).join(' ');
        connection.sendNumeric!RPL_WHOISCHANNELS(user.nick, userChannels);
    }

    void kill(Connection killer, string nick, string comment)
    {
        auto user = findConnectionByNick(nick)[0];

        user.send(Message(killer.prefix, "KILL", [nick, comment], true));

        quit(user, "Killed by " ~ killer.nick ~ " (" ~ comment ~ ")");

        user.send(Message(null, "ERROR",
                ["Closing Link: Killed by " ~ killer.nick ~ " (" ~ comment ~ ")"], true));
        user.closeConnection();
    }

    void kick(Connection kicker, string channelName, string nick, string comment)
    {
        auto channel = findChannelByName(channelName)[0];
        auto user = findConnectionByNick(nick)[0];

        channel.kick(kicker, user, comment);
    }

    void updateCommandStatistics(Message message)
    {
        auto command = message.command.toUpper;
        if (command !in _commandUsage)
        {
            _commandUsage[command] = 0;
            _commandBytes[command] = 0;
        }
        _commandUsage[command]++;
        _commandBytes[command] += message.bytes;
    }

    void sendCommandUsage(Connection connection)
    {
        foreach (command, count; _commandUsage)
        {
            //TODO: Implement remote count
            connection.sendNumeric!RPL_STATSCOMMANDS(command,
                    count.to!string, _commandBytes[command].to!string, "0");
        }
    }

    void sendUptime(Connection connection)
    {
        import std.format : format;

        auto uptime = (Clock.currTime - _startTime).split!("days", "hours", "minutes", "seconds");

        auto uptimeString = format!"Server Up %d days %d:%02d:%02d"(uptime.days,
                uptime.hours, uptime.minutes, uptime.seconds);
        connection.sendNumeric!RPL_STATSUPTIME(uptimeString);
    }

    void setPass(string pass)
    {
        _pass = pass;
    }

    bool isPassCorrect(string pass)
    {
        return pass == _pass;
    }

    bool hasPass()
    {
        return _pass != null;
    }

    void listen(ushort port = 6667)
    {
        listenTCP(port, &acceptConnection);
    }

    void listen(ushort port, string address)
    {
        listenTCP(port, &acceptConnection, address);
    }
}
