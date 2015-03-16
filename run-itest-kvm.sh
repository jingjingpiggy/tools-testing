#!/bin/sh -xeu
. $(dirname $0)/kvm-worker.sh

#for debug
#JENKINS_HOME=/var/lib/jenkins
#WORKSPACE=$JENKINS_HOME/workspace
#BUILD_NUMBER=0
#EXECUTOR_NUMBER=0
#cd $WORKSPACE/run-itest
#label=openSUSE_12.1-i586-debug

make_export_proxy_script() {
    ###### pass proxy settings into '$BUIDHOME/proxy_prepare'
    ###### mainly to use the it when running itest as user 'build'
    echo "#!/bin/bash" > $BUILDHOME/proxy_prepare
    if [ "${http_proxy+defined}" ]; then
        echo "export http_proxy=\"$http_proxy\"" >> $BUILDHOME/proxy_prepare
    fi
    if [ "${https_proxy+defined}" ]; then
        echo "export https_proxy=\"$https_proxy\"" >> $BUILDHOME/proxy_prepare
    fi
    if [ "${no_proxy+defined}" ]; then
        echo "export no_proxy=\"$no_proxy\"" >> $BUILDHOME/proxy_prepare
    fi
    if [ "${HTTP_PROXY+defined}" ]; then
        echo "export HTTP_PROXY=\"$HTTP_PROXY\"" >> $BUILDHOME/proxy_prepare
    fi
    if [ "${HTTPS_PROXY+defined}" ]; then
        echo "export HTTPS_PROXY=\"$HTTPS_PROXY\"" >> $BUILDHOME/proxy_prepare
    fi
    if [ "${NO_PROXY+defined}" ]; then
        echo "export NO_PROXY=\"$NO_PROXY\"" >> $BUILDHOME/proxy_prepare
    fi
    chmod +x $BUILDHOME/proxy_prepare
}

set_proxy(){
    make_export_proxy_script
    cat >>$BUILDHOME/run << EOF
##### enable proxy on fedora/centos ####
sed -i '/^proxy=_none_/d' $TARGETBIN/install_package
#### export proxy through script proxy_prepare ####
test -e /home/build/proxy_prepare && cat /home/build/proxy_prepare
test -e /home/build/proxy_prepare && . /home/build/proxy_prepare
EOF
}

additional_init() {
    BUILDHOME=$1
    distro=$(echo $label|cut -d'_' -f 1|tr [:upper:] [:lower:])
    set_proxy

    i=0
    while [ $i -lt $install_package_cnt ]; do
        pack=${install_package_name[$i]}
        projs=${install_package_proj[$i]}
        extra_repo=${install_package_extra_r[$i]}
        if [ -n "$extra_repo" ]; then
            if [ "$distro" = "ubuntu" -o "$distro" = "debian" ]; then
                extra_repo="deb $extra_repo/$OBS_REPO /"
            else
                extra_repo="$extra_repo/$OBS_REPO"
            fi
        fi
        i=$(expr $i + 1)

        proj=$(echo $projs|awk -F'|' '{print $1}')
        sproj=$(echo $projs|awk -F'|' '{print $2}')
        # args for install_package:
        # (project, repo, packages, sproject, testreq_packages, extra_repos)
        cat >>$BUILDHOME/run <<EOF
DOWNLOAD_HOST=\`grep "DOWNLOAD_HOST" /home/build/tools-tester.d/servers*.conf | cut -d':' -f 2-\`
$TARGETBIN/install_package "$proj" "$OBS_REPO" "$pack" "$sproj" "" "$extra_repo" "" "\$DOWNLOAD_HOST"
EOF
    done

    if [ "${tz_user_passwd+defined}" ]; then
        #It's hack to insert user and passwd in this way, only use this method
        #in the intermediate period to test liveusb/livecd related ks, and will
        #abandon it once new itest templates are applied. And the passwd used
        #here should be encoded passwd.
        cat >>$BUILDHOME/run << EOF
sed -i 's!https\:\/\/download.tz.jf.intel.com!https\:\/\/$tz_user_passwd\@download.tz.jf.intel.com!g' $itest_env_path/fixtures/ks_files/*.ks
EOF
    fi
    cat >>$BUILDHOME/run <<EOF
if [ -e /etc/mic/mic.conf ]; then
    sed -i 's!^tmpdir\s*=.*!tmpdir=/home/build/tmp/mic!'  /etc/mic/mic.conf
    sed -i 's!^cachedir\s*=.*!cachedir=/home/build/tmp/mic/cache!' /etc/mic/mic.conf
    sed -i 's!^rootdir\s*=.*!rootdir=/home/build/tmp/mic-bootstrap!' /etc/mic/mic.conf
fi
su - build -c "test -e /home/build/proxy_prepare && . /home/build/proxy_prepare; mkdir -p /home/build/reports; cd $itest_env_path; runtest -vv --with-xunit --xunit-file=/home/build/reports/xunit.xml $test_suite 2>&1"
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
install_package_extra_r=
install_package_cnt=0
add_pack() {
    proj=$1
    pack=$2
    extra_r=$3

    # overwrite project if package exists
    i=0
    while [ $i -lt $install_package_cnt ]; do
        packi=${install_package_name[$i]}
        if [ $packi = $pack ]; then
            install_package_proj[$i]=$proj
            install_package_extra_r[$i]=$extra_r
            return
        fi
        i=$(expr $i + 1)
    done

    # append new pair if package doesn't exist
    install_package_proj[$install_package_cnt]=$proj
    install_package_name[$install_package_cnt]=$pack
    install_package_extra_r[$install_package_cnt]=$extra_r
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
        if [ $nargs -lt 2 ] || [ $nargs -gt 4 ]; then
            echo "Bad package name and project name to install:$2"
            exit 1
        fi
        proj=$(echo $2|awk -F',' '{print $1}')
        pack=$(echo $2|awk -F',' '{print $2}')
        depends_proj=$(echo $2|awk -F',' '{print $3}')
        extra_repo=$(echo $2|awk -F',' '{print $4}')
        add_pack "$proj|$depends_proj" $pack "$extra_repo"
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
copy_back_from_kvm
