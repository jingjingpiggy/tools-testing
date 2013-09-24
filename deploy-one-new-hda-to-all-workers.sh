#!/bin/sh

# This copies one new HDA to all workers,
# rotating it to working image name first,
# and rotating previous working image to .prev
# 1st arg: file with .new suffix

. /etc/jenkins-worker/workers.env

NEWIMG=$1
IMG=`echo $NEWIMG | sed 's/\.new//g'`
cd $JENKINS_HOME
mv -f $IMG $IMG.prev
mv $NEWIMG $IMG
chmod 444 $IMG
deploy-one-hda-to-all-workers.sh $IMG
