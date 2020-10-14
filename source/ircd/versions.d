module ircd.versions;

/++
    Supported versions:

    * NotStrict: enabled when any versions are enabled that disable RFC-strictness (i.e. any of the following)
    * SupportTLS: compile with TLS support, enabled when NotStrict is on
    * BasicFixes: enable basic/sanity RFC fixes
    * MaxNickLengthConfigurable: makes max nick length configurable
    * Modern: enable all versions
+/

version (SupportTLS) version = NotStrict;
version (BasicFixes) version = NotStrict;
version (MaxNickLengthConfigurable) version = NotStrict;

version (NotStrict)
{
    version = SupportTLS;
}

version (Modern)
{
    version = NotStrict;

    version = SupportTLS;
    version = BasicFixes;
    version = MaxNickLengthConfigurable;
}
