#!/bin/sh

if [ -x /usr/bin/apt-get -a -d /etc/apt/sources.list.d/ ] ; then
    echo Ubuntu
    apt-get update
    NUMUPD=`apt-get -s upgrade | grep "Inst " | wc -l`
    if [ $NUMUPD -gt 0 ] ; then
        echo "$NUMUPD updates available, will apply."
        apt-get -y upgrade
    fi
elif [ -x /usr/bin/zypper -a -d /etc/zypp/repos.d ] ; then
    echo Opensuse
    NUMUPD=`zypper --non-interactive lu | wc -l`
    if [ $NUMUPD -gt 3 ] ; then
        echo "$NUMUPD updates available, will apply."
        zypper --non-interactive up
    fi
elif [ \( -x /bin/yum -o -x /usr/bin/yum \) -a -d /etc/yum.repos.d ] ; then
    echo Fedora
    NUMUPD=`yum check-update | grep updates | wc -l`
    if [ $NUMUPD -gt 0 ] ; then
        echo "$NUMUPD updates available, will apply."
        yum -y update
    fi
fi
