#!/bin/sh -xeu
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

. $(dirname $0)/kvm-worker.sh

TBNAME=$(target_project_basename "$GERRIT_PROJECT")

safeosc ls | grep home:tester:$TBNAME-.*$GERRIT_CHANGE_NUMBER\\.[0-9]\\+\$ | while read prj ; do
    echo "Deleting $prj"
    safeosc rdelete -r -m "Cleaned up because change $GERRIT_CHANGE_NUMBER has been merged or abandoned" $prj
done
