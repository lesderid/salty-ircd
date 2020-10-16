module ircd.numerics;

struct SimpleNumeric
{
    string number;
    string[] params;
}

private alias N = SimpleNumeric;

enum : SimpleNumeric
{
    //Command responses
    RPL_WELCOME                    = N("001", []),
    RPL_YOURHOST                   = N("002", []),
    RPL_CREATED                    = N("003", []),
    RPL_MYINFO                     = N("004", []),
    RPL_STATSCOMMANDS              = N("212", []),
    RPL_ENDOFSTATS                 = N("219", ["End of STATS report"]),
    RPL_UMODEIS                    = N("221", []),
    RPL_STATSUPTIME                = N("242", []),
    RPL_LUSERCLIENT                = N("251", []),
    RPL_LUSEROP                    = N("252", ["operator(s) online"]),
    RPL_LUSERUNKNOWN               = N("253", ["unknown connection(s)"]),
    RPL_LUSERCHANNELS              = N("254", ["channels formed"]),
    RPL_LUSERME                    = N("255", []),
    RPL_AWAY                       = N("301", []),
    RPL_ISON                       = N("303", []),
    RPL_UNAWAY                     = N("305", ["You are no longer marked as being away"]),
    RPL_NOWAWAY                    = N("306", ["You have been marked as being away"]),
    RPL_WHOISUSER                  = N("311", []),
    RPL_WHOISSERVER                = N("312", []),
    RPL_WHOISOPERATOR              = N("313", ["is an IRC operator"]),
    RPL_ENDOFWHO                   = N("315", ["End of WHO list"]),
    RPL_WHOISIDLE                  = N("317", ["seconds idle"]),
    RPL_ENDOFWHOIS                 = N("318", ["End of WHOIS list"]),
    RPL_WHOISCHANNELS              = N("319", []),
    RPL_LIST                       = N("322", []),
    RPL_LISTEND                    = N("323", ["End of LIST"]),
    RPL_CHANNELMODEIS              = N("324", []),
    RPL_NOTOPIC                    = N("331", ["No topic is set"]),
    RPL_TOPIC                      = N("332", []),
    RPL_INVITING                   = N("341", []),
    RPL_INVITELIST                 = N("346", []),
    RPL_ENDOFINVITELIST            = N("347", ["End of channel invite list"]),
    RPL_EXCEPTLIST                 = N("348", []),
    RPL_ENDOFEXCEPTLIST            = N("349", ["End of channel exception list"]),
    RPL_VERSION                    = N("351", []),
    RPL_WHOREPLY                   = N("352", []),
    RPL_NAMREPLY                   = N("353", []),
    RPL_ENDOFNAMES                 = N("366", ["End of NAMES list"]),
    RPL_BANLIST                    = N("367", []),
    RPL_ENDOFBANLIST               = N("368", ["End of channel ban list"]),
    RPL_MOTD                       = N("372", []),
    RPL_MOTDSTART                  = N("375", []),
    RPL_ENDOFMOTD                  = N("376", ["End of MOTD command"]),
    RPL_TIME                       = N("391", []),

    //Error replies
    ERR_NOSUCHNICK                 = N("401", ["No such nick/channel"]),
    ERR_NOSUCHCHANNEL              = N("403", ["No such channel"]),
    ERR_CANNOTSENDTOCHAN           = N("404", ["Cannot send to channel"]),
    ERR_NORECIPIENT_PRIVMSG        = N("411", ["No recipient given (PRIVMSG)"]),
    ERR_NORECIPIENT_NOTICE         = N("411", ["No recipient given (NOTICE)"]),
    ERR_NOTEXTTOSEND               = N("412", ["No text to send"]),
    ERR_UNKNOWNCOMMAND             = N("421", ["Unknown command"]),
    ERR_NOMOTD                     = N("422", ["MOTD File is missing"]),
    ERR_NONICKNAMEGIVEN            = N("431", ["No nickname given"]),
    ERR_ERRONEUSNICKNAME           = N("432", ["Erroneous nickname"]),
    ERR_NICKNAMEINUSE              = N("433", ["Nickname is already in use"]),
    ERR_USERNOTINCHANNEL           = N("441", ["They aren't on that channel"]),
    ERR_NOTONCHANNEL               = N("442", ["You're not on that channel"]),
    ERR_USERONCHANNEL              = N("443", ["is already on channel"]),
    ERR_NOTREGISTERED              = N("451", ["You have not registered"]),
    ERR_NEEDMOREPARAMS             = N("461", ["Not enough parameters"]),
    ERR_ALREADYREGISTRED /* sic */ = N("462", ["Unauthorized command (already registered)"]),
    ERR_PASSWDMISMATCH             = N("464", ["Password incorrect"]),
    ERR_CHANNELISFULL              = N("471", ["Cannot join channel (+l)"]),
    ERR_UNKNOWNMODE                = N("472", []),
    ERR_INVITEONLYCHAN             = N("473", ["Cannot join channel (+i)"]),
    ERR_BANNEDFROMCHAN             = N("474", ["Cannot join channel (+b)"]),
    ERR_BADCHANNELKEY              = N("475", ["Cannot join channel (+k)"]),
    ERR_NOPRIVILEGES               = N("481", ["Permission Denied- You're not an IRC operator"]),
    ERR_CHANOPRIVSNEEDED           = N("482", ["You're not channel operator"]),
    ERR_UMODEUNKNOWNFLAG           = N("501", ["Unknown MODE flag"]),
    ERR_USERSDONTMATCH             = N("502", ["Cannot change mode for other users"]),
    ERR_USERSDONTMATCH_ALT         = N("502", ["Cannot view mode of other users"]), //non-standard message (NotStrict-only)
}

