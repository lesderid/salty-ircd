module ircd.helpers;

import std.range : array, empty, front, popFront, save;
import std.algorithm : map;

//Based on std.path.globMatch (https://github.com/dlang/phobos/blob/v2.073.2/std/path.d#L3164)
//License: Boost License 1.0 (http://www.boost.org/LICENSE_1_0.txt)
//Copyright (c) Lars T. Kyllingstad, Walter Bright
@safe pure bool wildcardMatch(string input, string pattern)
{
    foreach (ref pi; 0 .. pattern.length)
    {
        const pc = pattern[pi];
        switch (pc)
        {
            case '*':
                if (pi + 1 == pattern.length)
                {
                    return true;
                }
                for (; !input.empty; input.popFront())
                {
                    auto p = input.save;
                    if (wildcardMatch(p, pattern[pi + 1 .. pattern.length]))
                    {
                        return true;
                    }
                }
                return false;
            case '?':
                if (input.empty)
                {
                    return false;
                }
                input.popFront();
                break;
            default:
                if (input.empty || pc != input.front)
                {
                    return false;
                }
                input.popFront();
                break;
        }
    }
    return input.empty;
}

@safe pure dchar toIRCLower(dchar input)
{
    import std.uni : toLower;

    switch (input)
    {
        case '[':
            return '{';
        case ']':
            return '}';
        case '\\':
            return '|';
        default:
            return input.toLower;
    }
}

@safe pure string toIRCLower(string input)
{
    import std.utf : byChar;

    return input.map!toIRCLower.byChar.array.idup;
}
