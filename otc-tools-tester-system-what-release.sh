#! /bin/sh

#
# Show Release-Version on different distros
#

REL="Unknown"
VER="Unknown"

if [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    REL=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    REL=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/redhat-release ]; then
    REL=`cat /etc/redhat-release | cut -d' ' -f 1`
    VER=`cat /etc/redhat-release | cut -d' ' -f 3`
elif [ -f /etc/SuSE-release ]; then
    REL=`cat /etc/SuSE-release | head -1 | cut -d' ' -f 1`
    VER=`cat /etc/SuSE-release | head -1 | cut -d' ' -f 2`
fi

echo "$REL-$VER"
