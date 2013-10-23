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
        projs=${install_package_proj[$i]}
        i=$(expr $i + 1)

        proj=$(echo $projs|awk -F'|' '{print $1}')
        sproj=$(echo $projs|awk -F'|' '{print $2}')
        if [ -z "$sproj" ];then
            sproj="$proj"
            proj=""
        fi
        # args for install_package:
        # (project, repo, packages, sproject, testreq_packages, extra_repos)
        cat >>$BUILDHOME/run <<EOF
$TARGETBIN/install_package "$proj" "$OBS_REPO" "$pack" "$sproj" "" ""
EOF
    done

    cat >>$BUILDHOME/run <<EOF
su - build -c "cd $itest_env_path; runtest -v $test_suite 2>&1"
EOF
}

usage() {
    echo "Usage: itest_env_path [options]"
    echo "    itest_env_path: path contain test cases"
    echo "    -m KVM_MEMSZ: memory size of KVM session, in MBytes"
    echo "    -p project,package[,dependsproject]: package to install in vm,"
    echo "        dependsproject can be given to install dependent packages"
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

set -- $(getopt hs:p:t:m: "$@")
while [ $# -gt 0 ]
do
    case "$1" in
    (-h) usage; exit 0;;
    (-p)
        nargs=$(echo $2|awk -F',' '{print NF}')
        if [ $nargs -lt 2 ] || [ $nargs -gt 3 ]; then
            echo "Bad package name and project name to install:$2"
            exit 1
        fi
        proj=$(echo $2|awk -F',' '{print $1}')
        pack=$(echo $2|awk -F',' '{print $2}')
        depends_proj=$(echo $2|awk -F',' '{print $3}')
        add_pack "$proj|$depends_proj" $pack
        shift
        ;;
    (-t)
        test_suite="$(echo $2|tr , ' ')"
        shift
        ;;
    (-s) NAME_SUFFIX=$2; shift;;
    (-m)
         KVM_MEMSZ=$2
         check_kvm_args
         shift
         ;;
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

date
prepare_kvm $label additional_init
launch_kvm
copy_back_from_kvm testspace/logs
