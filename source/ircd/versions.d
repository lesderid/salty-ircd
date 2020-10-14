module ircd.versions;

/++
    Supported versions:

    * SupportTLS: compile with TLS support
    * BasicFixes: enable basic/sanity RFC fixes
    * MaxNickLengthConfigurable: makes max nick length configurable
    * Modern: enable all versions

    (* NotStrict: enabled when any versions are enabled that disable RFC-strictness, i.e. any of the above)
+/

//TODO: Implement 'SupportTLS'
//TODO: Implement 'MaxNickLengthConfigurable'

version (Modern)
{
    version = SupportTLS;
    version = BasicFixes;
    version = MaxNickLengthConfigurable;
}

version (SupportTLS) version = NotStrict;
version (BasicFixes) version = NotStrict;
version (MaxNickLengthConfigurable) version = NotStrict;

version (NotStrict)
{
    version (SupportTLS) {}
    else
    {
        static assert(false, "TLS support must be enabled if any non-strict versions are enabled.");
    }
}
