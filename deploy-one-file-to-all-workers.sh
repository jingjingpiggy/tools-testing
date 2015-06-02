#!/bin/sh
#
# Copyright (c) 2013, 2014, 2015 Intel, Inc.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; version 2 of the License
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.

# This copies one file to all workers,
# is called mainly from other scripts.
# 1st arg: source file
# 2nd arg: dest file (should have full path)
#
# List of workers is specified in /etc/jenkins-worker/workers.env
# Example contents:
# JENKINS_HOME=/var/lib/jenkins
# WORKERS="w1.b.c.d w2.b.c.d ..."
# DEBUG_WORKERS="w3.b.c.d"

. /etc/jenkins-worker/workers.env

SFILE=$1
DFILE=$2
DEBUG_DFILE=$3
cd $JENKINS_HOME
for W in $WORKERS ; do
  $RSYNC $SFILE $W:$DFILE
done
for W in $DEBUG_WORKERS ; do
  $RSYNC $SFILE $W:$DEBUG_DFILE
done
