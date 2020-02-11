#!/usr/bin/fish

set packageVersion (git describe)

echo "module ircd.packageVersion; enum packageVersion = \"$packageVersion\";" > source/ircd/packageVersion.d
