#!/bin/sh -xeu
. $(dirname $0)/kvm-worker.sh

#for debug
#JENKINS_HOME=/var/lib/jenkins
#WORKSPACE=$JENKINS_HOME/workspace
#BUILD_NUMBER=0
#EXECUTOR_NUMBER=0
#TARGETBIN=/usr/bin
#cd $WORKSPACE/tmp
#cd /tmp
#label=openSUSE_12.1-i586-debug

additional_init() {
    # this function will be called when kvm images are ready
    # to do some additional initial work
    BUILDHOME=$1

    # copy ks file into kvm image
    cp $KS_FILE $BUILDHOME/image.ks

    # add to run script that will be auto-started in Virtual machine
    cat > $BUILDHOME/create_images << EOF
#!/bin/bash -xu
cd /home/build
mkdir -p reports/ # this dir name is an interface for copy_back_from_kvm

start_time=\$(date +%s)
timeout 7200 sudo mic cr auto image.ks --logfile=reports/mic.log >reports/console.log 2>&1
exitcode=\$?
cost=\$(expr \$(date +%s) - \${start_time} + 1) #plus 1 to avoid expr exit 1 when result is 0

echo ========= mic.log
cat reports/mic.log
echo ========= console.log
cat reports/console.log

exit \$exitcode
EOF
    chmod +x $BUILDHOME/create_images
    cat $BUILDHOME/create_images

    # install packages
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

    # create sudoers files and call create images
    cat >> $BUILDHOME/run << EOF
cat >> /etc/sudoers.d/mic <<EOFINNER
ALL     ALL=(ALL) NOPASSWD: \$(which mic)
ALL     ALL=(ALL) NOPASSWD: \$(which echo)

Defaults env_keep += "http_proxy"
Defaults env_keep += "no_proxy"
Defaults env_keep += "https_proxy"
Defaults env_keep += "HTTP_PROXY"
Defaults env_keep += "HTTPS_PROXY"
EOFINNER
EOF
    if [ "${http_proxy+defined}" ] && [ -n "$http_proxy" ]; then
        echo "export http_proxy=\"$http_proxy\"" >> $BUILDHOME/run
    fi
    if [ "${https_proxy+defined}" ] && [ -n "$https_proxy" ]; then
        echo "export https_proxy=\"$https_proxy\"" >> $BUILDHOME/run
    fi
    if [ "${no_proxy+defined}" ] && [ -n "$no_proxy" ]; then
        echo "export no_proxy=\"$no_proxy\"" >> $BUILDHOME/run
    fi
    cat >> $BUILDHOME/run << EOF
su - build -c "/home/build/create_images 2>&1"
EOF
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

usage() {
    echo "Usage: $0 <KS_FILE> [options]"
    echo "    KS_FILE: create image according to this KS file"
    echo "    -p project,package[,dependsproject]: package to install in vm,"
    echo "        dependsproject can be given to install dependent packages"
}
########
# Main
########
set -- $(getopt hs:p: "$@")
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
        add_pack "${proj}|${depends_proj}" $pack
        shift
        ;;
    (-s) NAME_SUFFIX=$2; shift;;
    (--) shift; break;;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*)  break;;
    esac
    shift
done

if [ $# -lt 1 ]; then
    echo "KS_FILE is required" >&2
    exit 1
fi
KS_FILE=$(pwd)/$1
shift
if [ ! -f "$KS_FILE" ]; then
    echo "No such file: $KS_FILE" >&2
    exit 1
fi

if [ $install_package_cnt -lt 1 ]; then
    echo "Can't find any packages to install, please give it by -p"
    exit 1
fi

prepare_kvm $label additional_init
launch_kvm
copy_back_from_kvm
