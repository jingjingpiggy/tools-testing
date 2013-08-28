#!/bin/sh -xeu
. $(dirname $0)/kvm-worker.sh

TBNAME=$(target_project_basename "$GERRIT_PROJECT")

safeosc ls | grep home:tester:$TBNAME-.*$GERRIT_CHANGE_NUMBER\\.[0-9]\\+\$ | while read prj ; do
    echo "Deleting $prj"
    safeosc rdelete -r -m "Cleaned up because change $GERRIT_CHANGE_NUMBER has been merged or abandoned" $prj
done
