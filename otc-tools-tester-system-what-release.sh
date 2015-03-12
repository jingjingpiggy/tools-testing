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
elif [ -f /etc/centos-release ]; then
    REL=`cat /etc/centos-release | cut -d' ' -f 1`
    # Centos 6 does not have /etc/os-release
    # centos-release has different number of fields in 6 vs 7
    if [ -f /etc/os-release ]; then
      # this covers CentOS_7
      VER=`grep VERSION_ID /etc/os-release | tr -d '[:punct:][:alpha:]'`
    else
      # this covers CentOS_6, have to strip off 6.x part after dot
      VER=`cat /etc/centos-release | cut -d' ' -f 3 | cut -d'.' -f 1`
    fi
elif [ -f /etc/debian_version ]; then
    REL=Debian
    VER=`grep VERSION_ID /etc/os-release | tr -d '[:punct:][:alpha:]'`
elif [ -f /etc/redhat-release ]; then
    REL=`cat /etc/redhat-release | cut -d' ' -f 1`
    VER=`grep VERSION_ID /etc/os-release | tr -d '[:punct:][:alpha:]'`
elif [ -f /etc/SuSE-release ]; then
    REL=`cat /etc/SuSE-release | head -1 | cut -d' ' -f 1`
    VER=`cat /etc/SuSE-release | head -1 | cut -d' ' -f 2`
elif [ -f /etc/arch-release ]; then
    REL="Arch"
    VER="0"
fi

echo "$REL-$VER"
