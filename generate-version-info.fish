#!/usr/bin/fish

set gitVersion (git describe)
set buildDate (date --iso-8601=seconds)

echo -e "/* This file is generated on build! */\n\nmodule ircd.versionInfo;\n\nenum gitVersion = \"$gitVersion\";\nenum buildDate = \"$buildDate\";" > source/ircd/versionInfo.d
