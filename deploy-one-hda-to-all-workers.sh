#!/bin/sh

# This copies one HDA to all workers,
# striping off -debug suffix
# 1st arg: file with -debug suffix

. /etc/jenkins-worker/workers.env

DEBIMG=$1
IMG=`echo $DEBIMG | sed 's/-debug//g'`
echo deb=$DEBIMG img=$IMG
cd $JENKINS_HOME
deploy-one-file-to-all-workers.sh $DEBIMG $JENKINS_HOME/$IMG
