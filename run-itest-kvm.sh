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

    i=0
    while [ $i -lt $install_package_cnt ]; do
        pack=${install_package_name[$i]}
        proj=${install_package_proj[$i]}
        i=$(expr $i + 1)
        cat >>$BUILDHOME/run <<EOF
$TARGETBIN/install_package "" "$OBS_REPO" "" "$proj" "$pack" ""
EOF
    done

    cat >>$BUILDHOME/run <<EOF
su - build -c "cd $itest_env_path; runtest -v $test_suite 2>&1"
EOF
}

usage() {
    echo "Usage: itest_env_path [options]"
    echo "    itest_env_path: path contain test cases"
    echo "    -p project,package: package to install in vm"
    echo "    -t test_suite: test to run, comma separated"
    echo "    -s NAME_SUFFIX"
}

install_package_proj=
install_package_name=
install_package_cnt=0
add_pack() {
    proj=$1
    pack=$2

    # overwrite project if package exists
    i=0
    while [ $i -lt $install_package_cnt ]; do
        packi=${install_package_name[$i]}
        if [ $packi = $pack ]; then
            install_package_proj[$i]=$proj
            return
        fi
        i=$(expr $i + 1)
    done

    # append new pair if package doesn't exist
    install_package_proj[$install_package_cnt]=$proj
    install_package_name[$install_package_cnt]=$pack
    install_package_cnt=$(expr $install_package_cnt + 1)
}

############
# Main
############

NAME_SUFFIX=""
test_suite=

set -- $(getopt hs:p:t: "$@")
while [ $# -gt 0 ]
do
    case "$1" in
    (-h) usage; exit 0;;
    (-p)
        if [ 2 -ne $(echo $2|awk -F',' '{print NF}') ]; then
            echo "Bad package name and project name to install:$2"
            exit 1
        fi
        proj=$(echo $2|awk -F',' '{print $1}')
        pack=$(echo $2|awk -F',' '{print $2}')
        add_pack $proj $pack
        shift
        ;;
    (-t)
        test_suite="$(echo $2|tr , ' ')"
        shift
        ;;
    (-s) NAME_SUFFIX=$2; shift;;
    (--) shift; break;;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*)  break;;
    esac
    shift
done
itest_env_path=$1
if [ -z "$itest_env_path" ]; then
    echo "Argument itest_env_path is required"
    exit 1
fi

if [ $install_package_cnt -lt 1 ]; then
    echo "Can't find test case and target package, please give it by -p"
    exit 1
fi

OBS_REPO=`echo $label|cut -f1 -d-`
OBS_ARCH=`echo $label|cut -f2 -d-`
date

prepare_kvm $label additional_init
launch_kvm
copy_back_from_kvm testspace/logs
