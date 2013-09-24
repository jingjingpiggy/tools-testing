#!/bin/sh

# This copies one file to all workers,
# is called mainly from other scripts.
# 1st arg: source file
# 2nd arg: dest file (should have full path)
#
# List of workers is specified in /etc/jenkins-worker/workers.env
# Example contents:
# JENKINS_HOME=/var/lib/jenkins
# WORKERS="w1.b.c.d w2.b.c.d ..."

. /etc/jenkins-worker/workers.env

SFILE=$1
DFILE=$2
cd $JENKINS_HOME
for W in $WORKERS ; do
  $RSYNC -S $SFILE $W:$DFILE
done
