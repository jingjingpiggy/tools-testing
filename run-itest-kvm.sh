#!/bin/sh -xeu
. $(dirname $0)/kvm-worker.sh

#for debug
#JENKINS_HOME=/var/lib/jenkins
#WORKSPACE=$JENKINS_HOME/workspace
#BUILD_NUMBER=0
#EXECUTOR_NUMBER=0
#cd $WORKSPACE/run-itest
#label=openSUSE_12.1-i586-debug


additional_init() {
    BUILDHOME=$1

    cat >>$BUILDHOME/run <<EOF
$TARGETBIN/install_package "" "$OBS_REPO" "" "itest" "itest-core" ""
$TARGETBIN/install_package "" "$OBS_REPO" "" "Tools:/Devel" "gbs" ""
$TARGETBIN/install_package "" "$OBS_REPO" "" "itest:/Devel" "itest-cases-gbs" ""

su - build -c "cd /srv/itest/cases/gbs; runtest -v 2>&1"
EOF
}

usage() {
  echo "Usage: [ -s NAME_SUFFIX]"
  exit 0
}

############
# Main
############

NAME_SUFFIX=""
set -- $(getopt hs: "$@")
while [ $# -gt 0 ]
do
    case "$1" in
    (-h) usage;;
    (-s) NAME_SUFFIX=$2; shift;;
    (--) shift; break;;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*)  break;;
    esac
    shift
done

OBS_REPO=`echo $label|cut -f1 -d-`
OBS_ARCH=`echo $label|cut -f2 -d-`
date

prepare_kvm $label additional_init
launch_kvm
copy_back_from_kvm testspace/logs
