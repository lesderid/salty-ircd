module ircd.channel;

import std.algorithm;
import std.string;
import std.typecons : Nullable;

import ircd.connection;
import ircd.server;
import ircd.message;
import ircd.helpers;
import ircd.numerics;

//TODO: Make this a struct?
class Channel
{
    string name;
    string topic = "";

    Connection[] members;
    char[] modes;
    char[][Connection] memberModes;
    string[][char] maskLists;

    string key;
    Nullable!uint memberLimit;
    Connection[] inviteHolders;

    private Server _server;

    this(string name, Server server)
    {
        this.name = name;
        this._server = server;
        this.maskLists = ['b': [], 'e': [], 'I': []];
    }

    void join(Connection connection)
    {
        members ~= connection;

        if (members.length == 1)
        {
            memberModes[connection] ~= 'o';
        }
        else
        {
            memberModes[connection] = [];
        }

        if (inviteHolders.canFind(connection))
        {
            inviteHolders = inviteHolders.remove!(c => c == connection);
        }
    }

    void part(Connection connection, string partMessage)
    {
        foreach (member; members)
        {
            if (partMessage !is null)
            {
                member.send(Message(connection.prefix, "PART", [
                            name, partMessage
                        ], true));
            }
            else
            {
                member.send(Message(connection.prefix, "PART", [name]));
            }
        }

        members = members.remove!(m => m == connection);
        memberModes.remove(connection);
    }

    void invite(Connection connection)
    {
        inviteHolders ~= connection;
    }

    void sendNames(Connection connection, bool sendRplEndOfNames = true)
    {
        string channelType;

        if (modes.canFind('s'))
        {
            channelType = "@";
        }
        else if (modes.canFind('p'))
        {
            channelType = "*";
        }
        else
        {
            channelType = "=";
        }

        auto onChannel = members.canFind(connection);

        connection.sendNumeric!RPL_NAMREPLY(channelType, name,
                members.filter!(m => onChannel || !m.modes.canFind('i'))
                .map!(m => prefixedNick(m))
                .join(' '));

        if (sendRplEndOfNames)
        {
            connection.sendNumeric!RPL_ENDOFNAMES(name);
        }
    }

    void sendPrivMsg(Connection sender, string text)
    {
        foreach (member; members.filter!(m => m.nick != sender.nick))
        {
            member.send(Message(sender.prefix, "PRIVMSG", [name, text], true));
        }
    }

    void sendNotice(Connection sender, string text)
    {
        foreach (member; members.filter!(m => m.nick != sender.nick))
        {
            member.send(Message(sender.prefix, "NOTICE", [name, text], true));
        }
    }

    void sendTopic(Connection connection)
    {
        if (topic.empty)
            connection.sendNumeric!RPL_NOTOPIC(name);
        else
            connection.sendNumeric!RPL_TOPIC(name, topic);
    }

    void setTopic(Connection connection, string newTopic)
    {
        topic = newTopic;

        foreach (member; members)
        {
            member.send(Message(connection.prefix, "TOPIC", [name, newTopic], true));
        }
    }

    void kick(Connection kicker, Connection user, string comment)
    {
        foreach (member; members)
        {
            member.send(Message(kicker.prefix, "KICK", [
                        name, user.nick, comment
                    ], true));
        }

        members = members.remove!(m => m == user);
        memberModes.remove(user);
    }

    void sendModes(Connection user)
    {
        auto specialModes = "";
        string[] specialModeParameters;

        if (members.canFind(user) && key !is null)
        {
            specialModes ~= "k";
            specialModeParameters ~= key;
        }

        if (members.canFind(user) && !memberLimit.isNull)
        {
            import std.conv : to;

            specialModes ~= "l";
            specialModeParameters ~= memberLimit.to!string;
        }

        user.sendNumeric!RPL_CHANNELMODEIS([name,
                "+" ~ modes.idup ~ specialModes] ~ specialModeParameters);
    }

    bool setMemberMode(Connection target, char mode)
    {
        if (memberModes[target].canFind(mode))
        {
            return false;
        }
        memberModes[target] ~= mode;

        return true;
    }

    bool unsetMemberMode(Connection target, char mode)
    {
        if (!memberModes[target].canFind(mode))
        {
            return false;
        }

        //NOTE: byCodeUnit is necessary due to auto-decoding (https://wiki.dlang.org/Language_issues#Unicode_and_ranges)
        import std.utf : byCodeUnit;
        import std.range : array;

        memberModes[target] = memberModes[target].byCodeUnit.remove!(m => m == mode).array;

        return true;
    }

    bool setMode(char mode)
    {
        if (modes.canFind(mode))
        {
            return false;
        }

        modes ~= mode;

        //NOTE: The RFCs don't specify that the invite list should be cleared on +i
        version (BasicFixes)
        {
            if (mode == 'i')
            {
                inviteHolders = [];
            }
        }

        return true;
    }

    bool unsetMode(char mode)
    {
        if (!modes.canFind(mode))
        {
            return false;
        }

        //NOTE: byCodeUnit is necessary due to auto-decoding (https://wiki.dlang.org/Language_issues#Unicode_and_ranges)
        import std.utf : byCodeUnit;
        import std.range : array;

        modes = modes.byCodeUnit.remove!(m => m == mode).array;

        return true;
    }

    bool addMaskListEntry(string mask, char mode)
    {
        if (maskLists[mode].canFind!(m => m.toIRCLower == mask.toIRCLower))
        {
            return false;
        }

        maskLists[mode] ~= mask;

        return true;
    }

    bool removeMaskListEntry(string mask, char mode)
    {
        if (!maskLists[mode].canFind!(m => m.toIRCLower == mask.toIRCLower))
        {
            return false;
        }

        maskLists[mode] = maskLists[mode].remove!(m => m.toIRCLower == mask.toIRCLower);

        return true;
    }

    void sendBanList(Connection connection)
    {
        foreach (entry; maskLists['b'])
        {
            connection.sendNumeric!RPL_BANLIST(name, entry);
        }

        connection.sendNumeric!RPL_ENDOFBANLIST(name);
    }

    void sendExceptList(Connection connection)
    {
        foreach (entry; maskLists['e'])
        {
            connection.sendNumeric!RPL_EXCEPTLIST(name, entry);
        }

        connection.sendNumeric!RPL_ENDOFEXCEPTLIST(name);
    }

    void sendInviteList(Connection connection)
    {
        foreach (entry; maskLists['I'])
        {
            connection.sendNumeric!RPL_INVITELIST(name, entry);
        }

        connection.sendNumeric!RPL_ENDOFINVITELIST(name);
    }

    bool setKey(string key)
    {
        this.key = key;

        return true;
    }

    bool unsetKey(string key)
    {
        if (this.key != key)
        {
            return false;
        }

        this.key = null;

        return true;
    }

    void setMemberLimit(uint memberLimit)
    {
        this.memberLimit = memberLimit;
    }

    bool unsetMemberLimit()
    {
        if (memberLimit.isNull)
        {
            return false;
        }

        memberLimit.nullify();

        return true;
    }

    string nickPrefix(Connection member)
    {
        if (!members.canFind(member))
            return null;

        if (memberModes[member].canFind('o'))
        {
            return "@";
        }
        else if (memberModes[member].canFind('v'))
        {
            return "+";
        }

        return "";
    }

    string prefixedNick(Connection member)
    {
        return nickPrefix(member) ~ member.nick;
    }

    bool visibleTo(Connection connection)
    {
        return members.canFind(connection) || !modes.canFind('s') && !modes.canFind('p');
    }

    bool canReceiveMessagesFromUser(Connection connection)
    {
        if (modes.canFind('n') && !members.canFind(connection))
        {
            return false;
        }
        else if (modes.canFind('m') && nickPrefix(connection).empty)
        {
            return false;
        }
        else if (maskLists['b'].any!(m => connection.matchesMask(m))
                && !maskLists['e'].any!(m => connection.matchesMask(m))
                && nickPrefix(connection).length == 0)
        {
            return false;
        }

        return true;
    }

    bool hasMember(Connection connection)
    {
        return members.canFind(connection);
    }
}
