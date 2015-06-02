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

# This is used after HDA seed updater script produces set of
# updated images named kvm-seed-hda-REPO-ARCH-mgmt.new
# No arguments are needed, all such files are deployed in all workers

. /etc/jenkins-worker/workers.env

cd $JENKINS_HOME
IMAGES=`ls kvm-seed-hda-*-mgmt.new`
for IMG in $IMAGES; do
  echo img=$IMG
  deploy-one-new-hda-to-all-workers.sh $IMG
done
