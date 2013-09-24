#!/bin/sh

# This is used to send set of images and misc. files to empty worker,
# for example after adding a new worker.
# 1st arg: address of new worker

. /etc/jenkins-worker/workers.env

W=$1
cd $JENKINS_HOME
$RSYNC kvm-seed-hdb.tar *-fake $W:$JENKINS_HOME/
IMAGES=`ls kvm-seed-hda-*-debug`
for DEBIMG in $IMAGES; do
  IMG=`echo $DEBIMG | sed 's/-debug//g'`
  echo deb=$DEBIMG img=$IMG
  $RSYNC -S $DEBIMG $W:$JENKINS_HOME/$IMG
done
