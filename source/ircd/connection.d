module ircd.connection;

import std.stdio;
import std.string;
import std.algorithm;
import std.range;
import std.conv;
import std.socket;
import std.utf;
import std.datetime;

import vibe.core.core;
import vibe.core.net;
import vibe.core.stream : IOMode;
import vibe.stream.operations : readLine;

import ircd.versionInfo;

import ircd.message;
import ircd.server;
import ircd.channel;
import ircd.helpers;
import ircd.numerics;

//TODO: Make this a struct?
class Connection
{
    private TCPConnection _connection;
    private Server _server;

    string nick;
    string user;
    string realname;
    string hostname;
    char[] modes;

    SysTime lastMessageTime;

    string awayMessage;

    bool connected;

    string pass = null;

    @property auto channels()
    {
        return _server.channels.filter!(c => c.members.canFind(this));
    }

    @property string prefix()
    {
        return nick ~ "!" ~ user ~ "@" ~ hostname;
    }

    @property bool registrationAttempted()
    {
        return nick !is null && user !is null;
    }

    @property bool registered()
    {
        return registrationAttempted && (!_server.hasPass || _server.isPassCorrect(pass));
    }

    @property bool isOperator()
    {
        return modes.canFind('o') || modes.canFind('O');
    }

    @property string servername()
    {
        return _server.name;
    }

    //TODO: Support server linking
    //TODO: Maybe 'replace' string's opEquals (or make a new string class/struct) to compare with toIRCLower
    //TODO: Read errata

    this(TCPConnection connection, Server server)
    {
        _connection = connection;
        _server = server;

        connected = _connection.connected;
    }

    override int opCmp(Object o)
    {
        Connection other;
        if ((other = cast(Connection) o) !is null)
        {
            return cmp(nick, other.nick);
        }
        return 0;
    }

    override bool opEquals(Object o)
    {
        Connection other;
        if ((other = cast(Connection) o) !is null)
        {
            return nick == other.nick;
        }
        return false;
    }

    override ulong toHash()
    {
        return typeid(nick).getHash(&nick);
    }

    bool visibleTo(Connection other)
    {
        return !modes.canFind('i') || channels.any!(c => c.members.canFind(other));
    }

    bool matchesMask(string mask)
    {
        return wildcardMatch(prefix.toIRCLower, mask.toIRCLower);
    }

    void send(Message message)
    {
        string messageString = message.toString;
        writeln("S> " ~ messageString);

        auto messageBytes = cast(const(ubyte)[]) (messageString ~ "\r\n");
        auto bytesSent = _connection.write(messageBytes, IOMode.once);

        if (bytesSent < 0)
        {
            writeln("client disconnected (write error)");
            closeConnection();
        }
    }

    void sendNumeric(alias numeric)(string[] params...)
    {
        auto message = Message(_server.name, numeric.number, [nick] ~ params ~ numeric.params);
        send(message);
    }

    void closeConnection()
    {
        connected = false;
        _connection.close();
    }

    //sends the message to all clients who have a channel in common with this client
    void sendToPeers(Message message)
    {
        if (channels.empty)
        {
            return;
        }

        foreach (connection; channels.map!(c => c.members)
                .fold!((a, b) => a ~ b)
                .sort().uniq.filter!(c => c != this))
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
        while (connected)
        {
            Message message = void;
            try
            {
                message = Message.fromString((cast(string) _connection.readLine()).chomp);
            }
            catch (Throwable)
            {
                //TODO: The actual Throwable could be useful?
                connected = _connection.connected;
                continue;
            }

            //NOTE: The RFCs don't specify whether commands are case-sensitive
            version (BasicFixes)
            {
                message.command = message.command
                    .map!toUpper
                    .to!string;
            }

            //NOTE: The RFCs don't specify what 'being idle' means
            //      We assume that it's sending any message that isn't a PING/PONG.
            if (message.command != "PING" && message.command != "PONG")
            {
                lastMessageTime = Clock.currTime;
            }

            writeln("C> " ~ message.toString);

            if (!registered && !["NICK", "USER", "PASS", "PING", "PONG",
                    "QUIT"].canFind(message.command))
            {
                //NOTE: This actually does not work if NICK hasn't been sent
                //      The first parameter for numerics is the client's nick.
                //      This makes it technically impossible to correctly implement the RFCs.
                sendNumeric!ERR_NOTREGISTERED();
                continue;
            }

            switch (message.command)
            {
                case "NICK":
                    onNick(message);
                    break;
                case "USER":
                    onUser(message);
                    break;
                case "PASS":
                    onPass(message);
                    break;
                case "PING":
                    //TODO: Connection timeout when we don't get a PONG
                    send(Message(_server.name, "PONG", [
                                _server.name, message.parameters[0]
                            ], true));
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
                case "PRIVMSG":
                    onPrivMsg(message);
                    break;
                case "NOTICE":
                    onNotice(message);
                    break;
                case "WHO":
                    onWho(message);
                    break;
                case "AWAY":
                    onAway(message);
                    break;
                case "TOPIC":
                    onTopic(message);
                    break;
                case "NAMES":
                    onNames(message);
                    break;
                case "LIST":
                    onList(message);
                    break;
                case "INVITE":
                    onInvite(message);
                    break;
                case "VERSION":
                    onVersion(message);
                    break;
                case "TIME":
                    onTime(message);
                    break;
                case "MOTD":
                    onMotd(message);
                    break;
                case "LUSERS":
                    onLusers(message);
                    break;
                case "ISON":
                    onIson(message);
                    break;
                case "WHOIS":
                    onWhois(message);
                    break;
                case "KILL":
                    onKill(message);
                    break;
                case "KICK":
                    onKick(message);
                    break;
                case "MODE":
                    onMode(message);
                    break;
                case "STATS":
                    onStats(message);
                    break;
                default:
                    writeln("unknown command '", message.command, "'");
                    sendNumeric!ERR_UNKNOWNCOMMAND();
                    continue;
            }

            _server.updateCommandStatistics(message);
        }

        closeConnection();
    }

    void onNick(Message message)
    {
        if (message.parameters.length == 0)
        {
            sendNumeric!ERR_NONICKNAMEGIVEN();
            return;
        }

        auto newNick = message.parameters[0];

        if (!_server.isNickAvailable(newNick) && newNick.toIRCLower != nick.toIRCLower)
        {
            sendNumeric!ERR_NICKNAMEINUSE(newNick);
            return;
        }

        if (!_server.isValidNick(newNick))
        {
            sendNumeric!ERR_ERRONEUSNICKNAME(newNick);
            return;
        }

        if (nick !is null)
        {
            sendToPeers(Message(nick, "NICK", [newNick]));
            send(Message(nick, "NICK", [newNick]));
        }

        auto wasRegistered = registered;

        nick = newNick;

        if (!wasRegistered && registered)
        {
            sendWelcome();
        }
        else if (!wasRegistered && registrationAttempted)
        {
            onIncorrectPassword();
        }
    }

    void onUser(Message message)
    {
        if (message.parameters.length < 4)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        if (user !is null)
        {
            sendNumeric!ERR_ALREADYREGISTRED();
            return;
        }

        auto wasRegistered = registered;

        //TODO: Maybe do something with the unused parameter?
        user = message.parameters[0];
        modes = modeMaskToModes(message.parameters[1]);
        realname = message.parameters[3];
        hostname = getHost();

        if (!wasRegistered && registered)
        {
            sendWelcome();
        }
        else if (registrationAttempted)
        {
            onIncorrectPassword();
        }
    }

    void onPass(Message message)
    {
        if (message.parameters.length < 1)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        if (registered)
        {
            sendNumeric!ERR_ALREADYREGISTRED();
            return;
        }

        pass = message.parameters[0];
    }

    void onQuit(Message message)
    {
        connected = false;
        send(Message(_server.name, "ERROR", ["Bye!"]));

        if (message.parameters.length > 0)
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
        if (message.parameters.length == 0)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        if (message.parameters[0] == "0")
        {
            foreach (channel; channels)
            {
                channel.part(this, null);
            }
            return;
        }

        auto channelList = message.parameters[0].split(',');
        auto channelKeys = message.parameters.length > 1 ? message.parameters[1].split(',') : null;
        foreach (i, channelName; channelList)
        {
            if (!Server.isValidChannelName(channelName))
            {
                sendNumeric!ERR_NOSUCHCHANNEL(channelName);
            }
            else
            {
                auto channelRange = _server.findChannelByName(channelName);
                if (channelRange.empty)
                {
                    _server.join(this, channelName);
                }
                else
                {
                    auto channel = channelRange[0];

                    if (channel.hasMember(this))
                    {
                        return;
                    }

                    if (!channel.memberLimit.isNull
                            && channel.members.length >= channel.memberLimit.get)
                    {
                        sendNumeric!ERR_CHANNELISFULL(channelName);
                    }
                    else if (channel.modes.canFind('i')
                            && !(channel.maskLists['I'].any!(m => matchesMask(m))
                                || channel.inviteHolders.canFind(this)))
                    {
                        sendNumeric!ERR_INVITEONLYCHAN(channelName);
                    }
                    else if (channel.maskLists['b'].any!(m => matchesMask(m))
                            && !channel.maskLists['e'].any!(m => matchesMask(m))
                            && !channel.inviteHolders.canFind(this))
                    {
                        sendNumeric!ERR_BANNEDFROMCHAN(channelName);
                    }
                    else if (channel.key !is null && (channelKeys.length < i + 1
                            || channelKeys[i] != channel.key))
                    {
                        sendNumeric!ERR_BADCHANNELKEY(channelName);
                    }
                    else
                    {
                        _server.join(this, channelName);
                    }
                }
            }
        }
    }

    void onPart(Message message)
    {
        if (message.parameters.length == 0)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        auto channelList = message.parameters[0].split(',');
        foreach (channel; channelList)
        {
            if (!Server.isValidChannelName(channel))
            {
                sendNumeric!ERR_NOSUCHCHANNEL(channel);
            }
            else if (!_server.canFindChannelByName(channel)
                    || !channels.canFind!(c => c.name.toIRCLower == channel.toIRCLower))
            {
                sendNumeric!ERR_NOTONCHANNEL(channel);
            }
            else
            {
                if (message.parameters.length > 1)
                    _server.part(this, channel, message.parameters[1]);
                else
                    _server.part(this, channel, null);
            }
        }
    }

    void onPrivMsg(Message message)
    {
        //TODO: Support special message targets
        auto target = message.parameters[0];
        auto text = message.parameters[1];

        if (message.parameters.length == 0)
        {
            sendNumeric!ERR_NORECIPIENT_PRIVMSG();
            return;
        }
        if (message.parameters.length == 1)
        {
            sendNumeric!ERR_NOTEXTTOSEND();
            return;
        }

        if (Server.isValidChannelName(target))
        {
            auto channelRange = _server.findChannelByName(target);
            if (channelRange.empty)
            {
                sendNumeric!ERR_NOSUCHNICK(target);
            }
            else if (!channelRange[0].canReceiveMessagesFromUser(this))
            {
                sendNumeric!ERR_CANNOTSENDTOCHAN(target);
            }
            else
            {
                _server.privmsgToChannel(this, target, text);
            }
        }
        else if (Server.isValidNick(target))
        {
            if (!_server.canFindConnectionByNick(target))
            {
                sendNumeric!ERR_NOSUCHNICK(target);
            }
            else
            {
                _server.privmsgToUser(this, target, text);

                auto targetUser = _server.findConnectionByNick(target)[0];
                if (targetUser.modes.canFind('a'))
                {
                    sendNumeric!RPL_AWAY(target, targetUser.awayMessage);
                }
            }
        }
        else
        {
            //is this the right reply?
            sendNumeric!ERR_NOSUCHNICK(target);
        }
    }

    void onNotice(Message message)
    {
        //TODO: Support special message targets
        if (message.parameters.length == 0)
        {
            sendNumeric!ERR_NORECIPIENT_NOTICE();
            return;
        }
        auto target = message.parameters[0];

        if (message.parameters.length == 1)
        {
            sendNumeric!ERR_NOTEXTTOSEND();
            return;
        }
        auto text = message.parameters[1];

        //TODO: Fix replies
        if (Server.isValidChannelName(target) && _server.canFindChannelByName(target))
        {
            _server.noticeToChannel(this, target, text);
        }
        else if (Server.isValidNick(target) && _server.canFindConnectionByNick(target))
        {
            _server.noticeToUser(this, target, text);
        }
    }

    void onWho(Message message)
    {
        if (message.parameters.length == 0)
        {
            _server.whoGlobal(this, "*", false);
        }
        else
        {
            auto mask = message.parameters[0];
            auto operatorsOnly = message.parameters.length > 1 && message.parameters[1] == "o";

            if (_server.isValidChannelName(mask) && _server.canFindChannelByName(mask))
            {
                _server.whoChannel(this, mask, operatorsOnly);
            }
            else
            {
                _server.whoGlobal(this, mask == "0" ? "*" : mask, operatorsOnly);
            }
        }

        auto name = message.parameters.length == 0 ? "*" : message.parameters[0];
        sendNumeric!RPL_ENDOFWHO(name);
    }

    void onAway(Message message)
    {
        if (message.parameters.length == 0)
        {
            removeMode('a');
            awayMessage = null;
            sendNumeric!RPL_UNAWAY();
        }
        else
        {
            modes ~= 'a';
            awayMessage = message.parameters[0];
            sendNumeric!RPL_NOWAWAY();
        }
    }

    void onTopic(Message message)
    {
        if (message.parameters.length == 0)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        auto channelName = message.parameters[0];
        if (message.parameters.length == 1)
        {
            if (!_server.channels.canFind!(c => c.name.toIRCLower == channelName.toIRCLower
                    && (!(c.modes.canFind('s') || c.modes.canFind('p')) || c.members.canFind(this))))
            {
                //NOTE: The RFCs don't allow ERR_NOSUCHCHANNEL as a response to TOPIC
                version (BasicFixes)
                    sendNumeric!ERR_NOSUCHCHANNEL(channelName);
                else
                    sendNumeric!RPL_NOTOPIC(channelName);
            }
            else
            {
                _server.sendChannelTopic(this, channelName);
            }
        }
        else
        {
            auto newTopic = message.parameters[1];
            if (!channels.canFind!(c => c.name.toIRCLower == channelName.toIRCLower))
            {
                sendNumeric!ERR_NOTONCHANNEL(channelName);
            }
            else if (channels.find!(c => c.name.toIRCLower == channelName.toIRCLower)
                    .map!(c => c.modes.canFind('t') && !c.memberModes[this].canFind('o'))
                    .array[0])
            {
                sendNumeric!ERR_CHANOPRIVSNEEDED(channelName);
            }
            else
            {
                _server.setChannelTopic(this, channelName, newTopic);
            }
        }
    }

    void onNames(Message message)
    {
        if (message.parameters.length > 1)
        {
            notImplemented("forwarding NAMES to another server");
            return;
        }

        if (message.parameters.length == 0)
        {
            _server.sendGlobalNames(this);
        }
        else
        {
            foreach (channelName; message.parameters[0].split(','))
            {
                if (_server.channels.canFind!(c => c.name.toIRCLower == channelName.toIRCLower
                        && c.visibleTo(this)))
                {
                    _server.sendChannelNames(this, channelName);
                }
                else
                {
                    sendNumeric!RPL_ENDOFNAMES(channelName);
                }
            }
        }
    }

    void onList(Message message)
    {
        if (message.parameters.length > 1)
        {
            notImplemented("forwarding LIST to another server");
            return;
        }

        if (message.parameters.length == 0)
        {
            _server.sendFullList(this);
        }
        else
        {
            auto channelNames = message.parameters[0].split(',');
            _server.sendPartialList(this, channelNames);
        }
    }

    void onInvite(Message message)
    {
        if (message.parameters.length < 2)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        auto targetNick = message.parameters[0];
        auto targetUserRange = _server.findConnectionByNick(targetNick);
        if (targetUserRange.empty)
        {
            sendNumeric!ERR_NOSUCHNICK(targetNick);
            return;
        }
        auto targetUser = targetUserRange[0];

        auto channelName = message.parameters[1];
        auto channelRange = _server.findChannelByName(channelName);
        if (channelRange.empty)
        {
            _server.invite(this, targetUser.nick, channelName);

            sendNumeric!RPL_INVITING(targetUser.nick, channelName);

            if (targetUser.modes.canFind('a'))
            {
                sendNumeric!RPL_AWAY(targetUser.nick, targetUser.awayMessage);
            }
        }
        else
        {
            auto channel = channelRange[0];
            if (!channel.members.canFind(this))
            {
                sendNumeric!ERR_NOTONCHANNEL(channel.name);
            }
            else if (channel.members.canFind(targetUser))
            {
                sendNumeric!ERR_USERONCHANNEL(targetUser.nick, channel.name);
            }
            else if (channel.modes.canFind('i') && !channel.memberModes[this].canFind('o'))
            {
                sendNumeric!ERR_CHANOPRIVSNEEDED(channel.name);
            }
            else
            {
                _server.invite(this, targetUser.nick, channel.name);

                sendNumeric!RPL_INVITING(targetUser.nick, channel.name);

                if (targetUser.modes.canFind('a'))
                {
                    sendNumeric!RPL_AWAY(targetUser.nick, targetUser.awayMessage);
                }
            }
        }
    }

    void onVersion(Message message)
    {
        if (message.parameters.length > 0)
        {
            notImplemented("querying the version of another server");
            return;
        }
        _server.sendVersion(this);
    }

    void onTime(Message message)
    {
        if (message.parameters.length > 0)
        {
            notImplemented("querying the time of another server");
            return;
        }
        _server.sendTime(this);
    }

    void onMotd(Message message)
    {
        if (message.parameters.length > 0)
        {
            notImplemented("querying the motd of another server");
            return;
        }
        else if (_server.motd is null)
        {
            sendNumeric!ERR_NOMOTD();
            return;
        }
        _server.sendMotd(this);
    }

    void onLusers(Message message)
    {
        if (message.parameters.length == 1)
        {
            notImplemented("querying the size of a part of the network");
            return;
        }
        else if (message.parameters.length > 1)
        {
            notImplemented("forwarding LUSERS to another server");
            return;
        }
        _server.sendLusers(this);
    }

    void onIson(Message message)
    {
        if (message.parameters.length < 1)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        //NOTE: The RFCs are ambiguous about the parameter(s).
        //      It specifies one allowed parameter type, a space-separated list of nicknames (i.e. prefixed with ':').
        //      However, the nicknames in the example are sent as separate parameters, not as a single string prefixed with ':'.
        //      For this implementation, we assume the example is wrong, like most clients seem to assume as well.
        //      (Other server implementations usually seem to support both interpretations.)
        _server.ison(this, message.parameters[0].split);
    }

    void onWhois(Message message)
    {
        if (message.parameters.length < 1)
        {
            sendNumeric!ERR_NONICKNAMEGIVEN();
            return;
        }
        else if (message.parameters.length > 1)
        {
            notImplemented("forwarding WHOIS to another server");
            return;
        }

        auto mask = message.parameters[0];
        //TODO: Support user masks
        if (!_server.canFindConnectionByNick(mask)
                || !_server.findConnectionByNick(mask)[0].visibleTo(this))
        {
            sendNumeric!ERR_NOSUCHNICK(mask);
        }
        else
        {
            _server.whois(this, mask);
        }

        sendNumeric!RPL_ENDOFWHOIS(mask);
    }

    void onKill(Message message)
    {
        if (!isOperator)
        {
            sendNumeric!ERR_NOPRIVILEGES();
            return;
        }

        if (message.parameters.length < 2)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        auto nick = message.parameters[0];
        if (!_server.canFindConnectionByNick(nick))
        {
            sendNumeric!ERR_NOSUCHNICK(nick);
            return;
        }

        auto comment = message.parameters[1];

        _server.kill(this, nick, comment);
    }

    void onKick(Message message)
    {
        if (message.parameters.length < 2)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        auto channelList = message.parameters[0].split(',');
        auto userList = message.parameters[1].split(',');
        auto comment = message.parameters.length > 2 ? message.parameters[2] : nick;

        if (channelList.length != 1 && channelList.length != userList.length)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        foreach (i, nick; userList)
        {
            auto channelName = channelList[0];
            if (channelList.length != 1)
            {
                channelName = channelList[i];
            }

            if (!_server.canFindChannelByName(channelName))
            {
                sendNumeric!ERR_NOSUCHCHANNEL(channelName);
            }
            else
            {
                auto channel = _server.findChannelByName(channelName)[0];
                if (!channel.members.canFind(this))
                {
                    sendNumeric!ERR_NOTONCHANNEL(channelName);
                }
                else if (!channel.memberModes[this].canFind('o'))
                {
                    sendNumeric!ERR_CHANOPRIVSNEEDED(channelName);
                }
                else if (!channel.members.canFind!(m => m.nick.toIRCLower == nick.toIRCLower))
                {
                    sendNumeric!ERR_USERNOTINCHANNEL(nick, channelName);
                }
                else
                {
                    _server.kick(this, channelName, nick, comment);
                }
            }
        }
    }

    void onMode(Message message)
    {
        if (message.parameters.empty)
        {
            sendNumeric!ERR_NEEDMOREPARAMS(message.command);
            return;
        }

        auto target = message.parameters[0];
        if (Server.isValidNick(target))
        {
            onUserMode(message);
        }
        else if (Server.isValidChannelName(target))
        {
            onChannelMode(message);
        }
        else
        {
            //NOTE: The RFCs don't allow ERR_NOSUCHNICK as a reponse to MODE
            version (BasicFixes)
            {
                sendNumeric!ERR_NOSUCHNICK(target);
            }
        }
    }

    void onUserMode(Message message)
    {
        auto target = message.parameters[0];

        if (target.toIRCLower != nick.toIRCLower)
        {
            //NOTE: The RFCs don't specify a different message for viewing other users' modes
            version (BasicFixes)
            {
                if (message.parameters.length > 1)
                    sendNumeric!ERR_USERSDONTMATCH();
                else
                    sendNumeric!ERR_USERSDONTMATCH_ALT();
            }
            else
            {
                sendNumeric!ERR_USERSDONTMATCH();
            }
            return;
        }

        if (message.parameters.length == 1)
        {
            sendNumeric!RPL_UMODEIS("+" ~ modes.idup);
        }
        else
        {
            foreach (modeString; message.parameters[1 .. $])
            {
                auto add = modeString[0] == '+';
                if (!add && modeString[0] != '-')
                {
                    //NOTE: The RFCs don't specify what should happen on malformed mode operations
                    version (BasicFixes)
                    {
                        sendMalformedMessageError(message.command,
                                "Invalid mode operation: " ~ modeString[0]);
                    }
                    continue;
                }

                if (modeString.length == 1)
                    continue;

                auto changedModes = modeString[1 .. $];
                foreach (mode; changedModes)
                {
                    switch (mode)
                    {
                        case 'i':
                        case 'w':
                        case 's':
                            if (add)
                                modes ~= mode;
                            else
                                removeMode(mode);
                            break;
                        case 'o':
                        case 'O':
                            if (!add)
                                removeMode(mode);
                            break;
                        case 'r':
                            if (add)
                                modes ~= 'r';
                            break;
                        case 'a':
                            //ignore
                            break;
                        default:
                            sendNumeric!ERR_UMODEUNKNOWNFLAG();
                            break;
                    }
                }
            }
        }
    }

    void onChannelMode(Message message)
    {
        auto channelRange = _server.findChannelByName(message.parameters[0]);
        if (channelRange.empty)
        {
            //NOTE: The RFCs don't allow ERR_NOSUCHCHANNEL as a response to MODE
            version (BasicFixes)
            {
                sendNumeric!ERR_NOSUCHCHANNEL(message.parameters[0]);
            }
            return;
        }
        auto channel = channelRange[0];

        //NOTE: The RFCs are inconsistent on channel mode query syntax for mask list modes
        //      ('MODE #chan +b', but 'MODE #chan e' and 'MODE #chan I')
        version (BasicFixes)
            enum listQueryModes = ["+b", "+e", "+I", "e", "I"];
        else
            enum listQueryModes = ["+b", "e", "I"];

        if (message.parameters.length == 1)
        {
            channel.sendModes(this);
        }
        else if (message.parameters.length == 2 && listQueryModes.canFind(message.parameters[1]))
        {
            auto listChar = message.parameters[1][$ - 1];
            final switch (listChar)
            {
                case 'b':
                    channel.sendBanList(this);
                    break;
                case 'e':
                    channel.sendExceptList(this);
                    break;
                case 'I':
                    channel.sendInviteList(this);
                    break;
            }
        }
        else
        {
            if (!channel.memberModes[this].canFind('o'))
            {
                sendNumeric!ERR_CHANOPRIVSNEEDED(channel.name);
                return;
            }

            for (auto i = 1; i < message.parameters.length; i++)
            {
                auto modeString = message.parameters[i];
                auto add = modeString[0] == '+';
                if (!add && modeString[0] != '-')
                {
                    //NOTE: The RFCs don't specify what should happen on malformed mode operations
                    version (BasicFixes)
                    {
                        sendMalformedMessageError(message.command,
                                "Invalid mode operation: " ~ modeString[0]);
                    }
                    return;
                }

                if (modeString.length == 1)
                    continue;

                char[] processedModes;
                string[] processedParameters;

                auto changedModes = modeString[1 .. $];
                Lforeach: foreach (mode; changedModes)
                {
                    switch (mode)
                    {
                        //TODO: If RFC-strictness is on, limit mode changes with parameter to 3 per command

                        case 'o':
                        case 'v':
                            if (i + 1 == message.parameters.length)
                            {
                                break Lforeach;
                            }
                            auto memberNick = message.parameters[++i];

                            auto memberRange = _server.findConnectionByNick(memberNick);
                            if (memberRange.empty)
                            {
                                sendNumeric!ERR_NOSUCHNICK(memberNick);
                                break Lforeach;
                            }

                            auto member = memberRange[0];
                            if (!channel.members.canFind(member))
                            {
                                sendNumeric!ERR_USERNOTINCHANNEL(memberNick, channel.name);
                                break Lforeach;
                            }

                            bool success;
                            if (add)
                                success = channel.setMemberMode(member, mode);
                            else
                                success = channel.unsetMemberMode(member, mode);
                            if (success)
                            {
                                processedModes ~= mode;
                                processedParameters ~= memberNick;
                            }
                            break;
                        case 'b':
                        case 'e':
                        case 'I':
                            if (i + 1 == message.parameters.length)
                            {
                                break Lforeach;
                            }
                            auto mask = message.parameters[++i];
                            if (!Server.isValidUserMask(mask))
                            {
                                //NOTE: The RFCs don't specify whether nicks are valid masks
                                //NOTE: The RFCs don't allow an error reply on an invalid user mask
                                version (BasicFixes)
                                {
                                    if (Server.isValidNick(mask))
                                    {
                                        mask ~= "!*@*";
                                    }
                                    else
                                    {
                                        sendMalformedMessageError(message.command,
                                                "Invalid user mask: " ~ mask);
                                        break Lforeach;
                                    }
                                }
                                else
                                {
                                    break Lforeach;
                                }
                            }

                            bool success;
                            if (add)
                                success = channel.addMaskListEntry(mask, mode);
                            else
                                success = channel.removeMaskListEntry(mask, mode);
                            if (success)
                            {
                                processedModes ~= mode;
                                processedParameters ~= mask;
                            }
                            break;
                        case 'k':
                            if (i + 1 == message.parameters.length)
                            {
                                break Lforeach;
                            }
                            auto key = message.parameters[++i];

                            bool success;
                            if (add)
                                success = channel.setKey(key);
                            else
                                success = channel.unsetKey(key);
                            if (success)
                            {
                                processedModes ~= mode;
                                processedParameters ~= key;
                            }
                            break;
                        case 'l':
                            if (add)
                            {
                                if (i + 1 == message.parameters.length)
                                    break Lforeach;

                                auto limitString = message.parameters[++i];
                                uint limit = 0;
                                try
                                    limit = limitString.to!uint;
                                catch (Throwable)
                                    break Lforeach;

                                channel.setMemberLimit(limit);

                                processedModes ~= mode;
                                processedParameters ~= limitString;
                            }
                            else
                            {
                                if (channel.unsetMemberLimit())
                                {
                                    processedModes ~= mode;
                                }
                            }
                            break;
                        case 'i':
                        case 'm':
                        case 'n':
                        case 'p':
                        case 's':
                        case 't':
                            bool success;
                            if (add)
                                success = channel.setMode(mode);
                            else
                                success = channel.unsetMode(mode);

                            if (success)
                                processedModes ~= mode;
                            break;
                        default:
                            sendNumeric!ERR_UNKNOWNMODE([mode],
                                    "is unknown mode char to me for " ~ channel.name);
                            break;
                    }
                }

                if (!processedModes.empty)
                {
                    foreach (member; channel.members)
                    {
                        member.send(Message(prefix, "MODE", [
                                    channel.name, (add ? '+' : '-') ~ processedModes.idup
                                ] ~ processedParameters, false));
                    }
                }
            }
        }
    }

    void onStats(Message message)
    {
        if (message.parameters.length > 1)
        {
            notImplemented("forwarding STATS to another other server");
            return;
        }

        char statsLetter = message.parameters.length > 0 ? message.parameters[0][0] : '*';

        switch (statsLetter)
        {
            case 'l':
                notImplemented("STATS server link information");
                break;
            case 'm':
                _server.sendCommandUsage(this);
                break;
            case 'o':
                notImplemented("O-lines and O-line querying");
                break;
            case 'u':
                _server.sendUptime(this);
                break;
            default:
                break;
        }

        sendNumeric!RPL_ENDOFSTATS([statsLetter].idup);
    }

    void sendWhoReply(string channel, Connection user, string nickPrefix, uint hopCount)
    {
        auto flags = user.modes.canFind('a') ? "G" : "H";
        if (user.isOperator)
            flags ~= "*";
        flags ~= nickPrefix;

        sendNumeric!RPL_WHOREPLY(channel, user.user, user.hostname, user.servername,
                user.nick, flags, hopCount.to!string ~ " " ~ user.realname);
    }

    void notImplemented(string description)
    {
        send(Message(_server.name, "ERROR", [
                    "Not implemented yet (" ~ description ~ ")"
                ], true));
    }

    void sendMalformedMessageError(string command, string description)
    {
        send(Message(_server.name, "ERROR", [
                    command, "Malformed message: " ~ description
                ], true));
    }

    void sendWelcome()
    {
        //NOTE: According to the RFCs these aren't ':'-prefixed strings but separate parameters

        enum availableUserModes = "aiwroOs";
        enum availableChannelModes = "OovaimnqpsrtklbeI";

        sendNumeric!RPL_WELCOME("Welcome", "to", "the", "Internet", "Relay", "Network", prefix);
        sendNumeric!RPL_YOURHOST("Your", "host", "is", _server.name ~ ",",
                "running", "version", _server.versionString);
        sendNumeric!RPL_CREATED("This", "server", "was", "created", buildDate);
        sendNumeric!RPL_MYINFO(_server.name, _server.versionString,
                availableUserModes, availableChannelModes);
    }

    void onIncorrectPassword()
    {
        //NOTE: The RFCs don't allow ERR_PASSWDMISMATCH as a response to NICK/USER
        version (BasicFixes)
            sendNumeric!ERR_PASSWDMISMATCH();

        //NOTE: The RFCs don't actually specify what should happen here
        closeConnection();
    }

    string getHost()
    {
        auto address = parseAddress(_connection.remoteAddress.toAddressString);
        auto hostname = address.toHostNameString;
        if (hostname is null)
        {
            hostname = address.toAddrString;

            //TODO: Enclose IPv6 addresses in square brackets?
        }
        return hostname;
    }

    char[] modeMaskToModes(string maskString)
    {
        import std.conv : to;
        import std.exception : ifThrown;

        auto mask = maskString.to!ubyte.ifThrown(0);

        char[] modes;

        if (mask & 0b100)
            modes ~= 'w';

        if (mask & 0b1000)
            modes ~= 'i';

        return modes;
    }

    void removeMode(char mode)
    {
        //NOTE: byCodeUnit is necessary due to auto-decoding (https://wiki.dlang.org/Language_issues#Unicode_and_ranges)
        modes = modes.byCodeUnit.remove!(a => a == mode).array;
    }
}
