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

#for debug
#JENKINS_HOME=/var/lib/jenkins
#WORKSPACE=$JENKINS_HOME/workspace
#BUILD_NUMBER=0
#EXECUTOR_NUMBER=0
#TARGETBIN=/usr/bin
#cd $WORKSPACE/predeployment
#label=openSUSE_12.3-x86_64-debug

. $(dirname $0)/kvm-worker.sh

additional_init() {
    # this function will be called when kvm images are ready
    # to do some additional initial work
    BUILDHOME=$1
    distro=$(echo $label|cut -d'_' -f 1|tr [:upper:] [:lower:])
    # pass proxy settings into KVM
    setenv_to_run http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY
    # install packages
    i=0
    while [ $i -lt $install_package_cnt ]; do
        pack=${install_package_name[$i]}
        projs=${install_package_proj[$i]}
        extra_repo=${install_package_extra_r[$i]}
        i=$(expr $i + 1)

        proj=$(echo $projs|awk -F'|' '{print $1}')
        sproj=$(echo $projs|awk -F'|' '{print $2}')
        if [ -z "$sproj" ];then
            sproj="$proj"
            proj=""
        fi

        if [ -n "$extra_repo" ]; then
            if [ "$distro" = "ubuntu" ]; then
                extra_repo="deb $extra_repo/$OBS_REPO /"
            else
                extra_repo="$extra_repo/$OBS_REPO"
            fi
        fi
        # args for install_package:
        # (project, repo, packages, sproject, testreq_packages, extra_repos)
        cat >>$BUILDHOME/run <<EOF
DOWNLOAD_HOST=\`grep "DOWNLOAD_HOST" /home/build/tools-tester.d/servers*.conf | cut -d':' -f 2-\`
$TARGETBIN/install_package "$proj" "$OBS_REPO" "$pack" "$sproj" "" "$extra_repo" "" "\$DOWNLOAD_HOST"
EOF
    done

    cat >>$BUILDHOME/run <<EOF
/home/build/create_image
EOF
    if [ "${COPY_TO_VM_DIR+defined}" ] && [ -d "${COPY_TO_VM_DIR}" ]; then
        cp -r $COPY_TO_VM_DIR/* $BUILDHOME
    fi

    # create image
    set +x # avoid password print to console
    cat > $BUILDHOME/create_image << EOF
#!/bin/sh
export PATH=/sbin:/usr/sbin:\$PATH
cd /home/build
mkdir -p reports/ # this dir name is an interface for copy_back_from_kvm

date
sed -i 's!^tmpdir\s*=.*!tmpdir=/home/build/tmp/mic!'  /etc/mic/mic.conf
sed -i 's!^cachedir\s*=.*!cachedir=/home/build/tmp/mic/cache!' /etc/mic/mic.conf
sed -i 's!^rootdir\s*=.*!rootdir=/home/build/tmp/mic-bootstrap!' /etc/mic/mic.conf
python -m pre_deployment_test.create_and_diff -O reports/result.txt "$IMG_BASE_URL"
exitcode=\$?
date

ls
[ -f mic.log ] && cp mic.log reports/
ls img.diff* >/dev/null 2>&1 && cp img.diff* reports/
ls *.ks >/dev/null 2>&1 && cp *.ks reports/
EOF

    if [ "${COPY_IMG_PATTERN+defined}" ]; then
    cat >> $BUILDHOME/create_image << EOF
[ -d mic-output ] && ls mic-output | grep -E "$COPY_IMG_PATTERN" && cp -avr mic-output/* reports
EOF
    fi

    cat >> $BUILDHOME/create_image << EOF
ls reports/

exit \$exitcode
EOF
    set -x
    chmod +x $BUILDHOME/create_image
}

install_package_proj=
install_package_name=
install_package_extra_r=
install_package_cnt=0
add_pack() {
    proj=$1
    pack=$2
    extra_repo=$3

    # overwrite project if package exists
    i=0
    while [ $i -lt $install_package_cnt ]; do
        packi=${install_package_name[$i]}
        if [ $packi = $pack ]; then
            install_package_proj[$i]=$proj
            install_package_extra_r[$i]=$extra_repo
            return
        fi
        i=$(expr $i + 1)
    done

    # append new pair if package doesn't exist
    install_package_proj[$install_package_cnt]=$proj
    install_package_name[$install_package_cnt]=$pack
    install_package_extra_r[$install_package_cnt]=$extra_repo
    install_package_cnt=$(expr $install_package_cnt + 1)
}

usage() {
    echo "Usage: $0 <imgBaseURL> [options]"
    echo "    imgBaseURL: an URL under which we can find KS file and image file"
    echo "    -m KVM_MEMSZ: memory size of KVM session, in MBytes"
    echo "    -p project,package[,dependsproject]: package to install in vm,"
    echo "        dependsproject can be given to install dependent packages"
    echo "    -d copyToVMDir: if it's given, all files in this dir will be"
    echo "        copied into VM build home dir"
    echo "    -E pattern: extended regexp to match image name. If the pattern"
    echo "        matched, image will be copied out from VM instance into "
    echo "        Jenkins job's workspace. The format is the same as grep -E."
}

store_repo(){
    proj=$1
    depends_proj=$2
    extra_repo=$3

    download_host=`grep "DOWNLOAD_HOST" /etc/tools-tester.d/servers*.conf | cut -d':' -f 2-`
    if echo "$proj" | grep "Tools:/Devel" ;then
        repo_str="$download_host/$proj"
    elif echo "$proj" | grep "Tools" ;then
        repo_str="$download_host/$proj"
    elif echo $proj | grep "Tools-mic-" ;then
        repo_str="$download_host/home:/tester:/$proj/"
    else
        repo_str=''
    fi
    if [ -n "$depends_proj" ];then
        if echo "$depends_proj" | grep "Tools:/Devel" ;then
            if [ -z "$repo_str" ];then
                repo_str="$download_host/$depends_proj"
            else
                repo_str="$repo_str;$download_host/$depends_proj"
            fi
        fi
    fi
    if [ -n "$extra_repo" ];then
        if [ -z "$repo_str" ];then
          repo_str="$extra_repo"
        else
          repo_str="$repo_str;$extra_repo"
        fi
    fi
    echo $repo_str >> mic.repo
}

########
# Main
########
set +x
set -- $(getopt hs:p:m:d:E: "$@")
while [ $# -gt 0 ]
do
    case "$1" in
    (-h) usage; exit 0;;
    (-p)
        nargs=$(echo $2|awk -F',' '{print NF}')
        if [ $nargs -lt 2 ] || [ $nargs -gt 4 ]; then
            echo "Bad package name and project name to install:$2"
            exit 1
        fi
        proj=$(echo $2|awk -F',' '{print $1}')
        pack=$(echo $2|awk -F',' '{print $2}')
        depends_proj=$(echo $2|awk -F',' '{print $3}')
        extra_repo=$(echo $2|awk -F',' '{print $4}')
        if echo $pack | grep "mic" ;then
            store_repo "${proj}" "${depends_proj}" "$extra_repo"
        fi
        add_pack "${proj}|${depends_proj}" "$pack" "$extra_repo"
        shift
        ;;
    (-s) NAME_SUFFIX=$2; shift;;
    (-m)
         KVM_MEMSZ=$2
         check_kvm_args
         shift
         ;;
    (-d)
        COPY_TO_VM_DIR=$2; shift;;
    (-E) COPY_IMG_PATTERN="$2"; shift;;
    (--) shift; break;;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*)  break;;
    esac
    shift
done

if [ $# -lt 1 ]; then
    echo "imgDirURL is required" >&2
    exit 1
fi
IMG_BASE_URL="$1"
set -x
shift

if [ $install_package_cnt -lt 1 ]; then
    echo "Can't find any packages to install, please give it by -p"
    exit 1
fi

prepare_kvm $label additional_init
launch_kvm
copy_back_from_kvm
