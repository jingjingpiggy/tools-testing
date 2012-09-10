#!/bin/sh

set -eu

if [ $# -lt 2 ]; then
  echo "2 args needed: BUILDROOT_SEED BUILDROOT"
  exit 1
fi

BUILDROOT_SEED=$1
BUILDROOT=$2
BUILDROOT_UNPACK_TMP="buildroot-tmp-$BUILD_ID"

trap "rm -rf $BUILDROOT_UNPACK_TMP; exit" INT TERM EXIT

# Unpack buildroot.tar
mkdir $BUILDROOT_UNPACK_TMP
cd $BUILDROOT_UNPACK_TMP
sudo tar -xf $BUILDROOT_SEED
sudo mv -f buildroot "$BUILDROOT"
cd ..

#####################################################################
if [ -x /usr/bin/apt-get -a -d /etc/apt/sources.list.d/ ] ; then
echo Ubuntu
   sudo chroot "$BUILDROOT" apt-get update
   NUMUPD=`sudo chroot "$BUILDROOT" apt-get -s upgrade | grep "Inst " | wc -l`
   echo NUMUPD=$NUMUPD
   if [ $NUMUPD -gt 0 ] ; then
     echo $NUMUPD updates available, will apply in "$BUILDROOT"
     sudo chroot "$BUILDROOT" apt-get -y upgrade
     exit 0
   fi
elif [ -x /usr/bin/zypper -a -d /etc/zypp/repos.d ] ; then
echo Opensuse
   NUMUPD=`sudo chroot "$BUILDROOT" zypper --non-interactive lu | wc -l`
   echo NUMUPD=$NUMUPD
   if [ $NUMUPD -gt 3 ] ; then
     echo $NUMUPD updates available, will apply in "$BUILDROOT"
     sudo chroot "$BUILDROOT" zypper --non-interactive up
     exit 0
   fi
elif [ \( -x /bin/yum -o -x /usr/bin/yum \) -a -d /etc/yum.repos.d ] ; then
   NUMUPD=`sudo chroot "$BUILDROOT" yum check-update | grep updates | wc -l`
   echo NUMUPD=$NUMUPD
   if [ $NUMUPD -gt 0 ] ; then
     echo $NUMUPD updates available, will apply in "$BUILDROOT"
     sudo chroot "$BUILDROOT" yum -y update
     exit 0
   fi
fi
echo "No updates available, delete $BUILDROOT"
sudo rm -rf "$BUILDROOT"
