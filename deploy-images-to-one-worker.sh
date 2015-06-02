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
