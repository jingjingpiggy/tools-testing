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
deploy-one-hda-to-all-workers.sh $IMG
