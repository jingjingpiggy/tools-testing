#!/bin/sh

# This is used to send set of images and misc. files to empty worker,
# for example after adding a new worker.
# 1st arg: address of new worker

. /etc/jenkins-worker/workers.env

W=$1
cd $JENKINS_HOME
$RSYNC kvm-seed-hdb.tar *-fake $W:$JENKINS_HOME/
IMAGES=`ls kvm-seed-hda-*-mgmt`
for SRC in $IMAGES; do
  IMG=`echo $SRC | sed 's/-mgmt//g'`
  echo src=$SRC dest=$IMG
  $RSYNC $SRC $W:$JENKINS_HOME/$IMG
done
