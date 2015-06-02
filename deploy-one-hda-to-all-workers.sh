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
