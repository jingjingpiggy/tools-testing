#!/bin/sh

# This copies one HDA to all workers,
# striping off -mgmt suffix
# 1st arg: file with -mgmt suffix

. /etc/jenkins-worker/workers.env

SRC=$1
IMG=`echo $SRC | sed 's/-mgmt//g'`
DEBUG_IMG=`echo $SRC | sed 's/-mgmt/-debug/g'`
echo src=$SRC img=$IMG debugimg=$DEBUG_IMG
cd $JENKINS_HOME
deploy-one-file-to-all-workers.sh $SRC $JENKINS_HOME/$IMG $JENKINS_HOME/$DEBUG_IMG
