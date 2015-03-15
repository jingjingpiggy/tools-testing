#!/bin/sh -xeu
. $(dirname $0)/kvm-worker.sh

#for debug
#JENKINS_HOME=/var/lib/jenkins
#WORKSPACE=$JENKINS_HOME/workspace
#BUILD_NUMBER=0
#EXECUTOR_NUMBER=0


BACKUP_DIR=/var/tmp/repo_store_backup

backup_repo_store() {
    echo "mkdir -p $BACKUP_DIR"
    echo "rm -rf $BACKUP_DIR/*"
    echo "cp -rf $repo_store/* $BACKUP_DIR"
}

revert_repo_store() {
    echo "rm -rf $repo_store/*"
    echo "cp -rf $BACKUP_DIR/* $repo_store"
}

generate_html_head() {
echo "<html>"
echo "<head>"
echo "<title>"
if [ ${upgrade_repo+defined} ]; then
echo "    $(echo $package_name | tr [:lower:] [:upper:]) Upgrade Test Report"
else
echo "    $(echo $package_name | tr [:lower:] [:upper:]) Install Test Report"
fi
echo "</title>"
echo "<style>"
echo ".diff { color: blue }"
echo "table { border-collapse:collapse;margin-bottom: 1em }"
echo "th { background-color: #F3F3F3 }"
echo "td, th { border: 1px solid grey;padding: 3px}"
echo "table.right th { text-align: right }"
echo "</style>"
echo "</head>"
echo "<body>"
if [ ${upgrade_repo+defined} ]; then
echo "<h1>$(echo $package_name | tr [:lower:] [:upper:]) Upgrade Test Report</h1>"
else
echo "<h1>$(echo $package_name | tr [:lower:] [:upper:]) Install Test Report</h1>"
fi
echo "<h2>from:$(echo $install_repo)</h2>"
if [ ${upgrade_repo+defined} ]; then
echo "<h2>to:$(echo $upgrade_repo)</h2>"
fi
echo "<h1>Dependencies</h1>"
echo "<table class=\"right\">"
}

generate_html_table() {
if [ ${upgrade_repo+defined} ]; then
echo "<tr><th>Version diff</th><td>Before</td><td>After</td><td>Install</td></tr>"
else
echo "<tr><th>Package</th><td>Version</td></tr>"
fi
}

generate_html_tail() {
echo "</table>"
echo "</body>"
echo "</html>"
}

check_version() {
    local pkgmgr=$1
    local pkgname=$2
    local log=$3
    if [ $pkgmgr = 'dpkg' ]; then
        echo "echo \"$pkgname \$(dpkg -s $pkgname 2>/dev/null | (grep ^Version || echo Version N/A )|awk '{print \$2}')\" >> $log"
    else
        echo "echo \"$pkgname \$(rpm -q --qf \"%{version}-%{release}\\n\" $pkgname |grep -v \"not install\" || echo N/A)\" >> $log"
    fi
}

uninstall() {
    local pkgmgr=$1
    local pkgname=$2
    local log=$3
    if [ $pkgmgr = 'dpkg' ]; then
        echo "dpkg -P --force-depends $pkgname >> $log || true"
    else
        echo "rpm -e --nodeps $pkgname >> $log || true"
    fi
}

additional_init() {
    BUILDHOME=$1
    LOGS=/home/build/logs

    ###### pass proxy settings into KVM
    setenv_to_run http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY

    ##### enable proxy on fedora/centos ####
    cat >> $BUILDHOME/run <<EOF
sed -i '/^proxy=_none_/d' $TARGETBIN/install_package
EOF

    ########### first install ################
    cat >>$BUILDHOME/run <<EOF
$(backup_repo_store)
EOF
    cat >>$BUILDHOME/run <<EOF
mkdir $LOGS
EOF
    cat >>$BUILDHOME/run <<EOF
$TARGETBIN/install_package "" "" "${package_name}" "" "" "${install_repo_parameter}" "" "" > $LOGS/install.log
EOF

    if [ ${PKGLIST+defined} ]; then
        for pkg in $PKGLIST
        do
            cat >>$BUILDHOME/run <<EOF
$(check_version $package_manager $pkg $LOGS/install.info)
EOF
        done
    fi
    cat >>$BUILDHOME/run <<EOF
cp $LOGS/install.info $LOGS/summary.info
EOF

    ########### upgrade install ##############
    if [ ${upgrade_repo+defined} ]; then
        cat >>$BUILDHOME/run <<EOF
$(revert_repo_store)
EOF
        cat >>$BUILDHOME/run <<EOF
$TARGETBIN/install_package "" "" "$package_name" "" "" "${upgrade_repo_parameter}" "noupdate" "" > $LOGS/upgrade.log
EOF

        if [ ${PKGLIST+defined} ]; then
            for pkg in $PKGLIST
            do
                cat >>$BUILDHOME/run <<EOF
$(check_version $package_manager $pkg $LOGS/upgrade.info)
$(uninstall $package_manager $pkg $LOGS/uninstall.log)
EOF
            done
        fi
        cat >>$BUILDHOME/run <<EOF
join $LOGS/install.info $LOGS/upgrade.info > $LOGS/compare.info
EOF

        ############ reinstall ###############
        cat >>$BUILDHOME/run <<EOF
$(revert_repo_store)
EOF
        cat >>$BUILDHOME/run <<EOF
$TARGETBIN/install_package "" "" "$package_name" "" "" "${upgrade_repo_parameter}" "" "" > $LOGS/reinstall.log
EOF

        if [ ${PKGLIST+defined} ]; then
            for pkg in $PKGLIST
            do
                cat >>$BUILDHOME/run <<EOF
$(check_version $package_manager $pkg $LOGS/reinstall.info)
EOF
            done
        fi
        cat >>$BUILDHOME/run <<EOF
join $LOGS/compare.info $LOGS/reinstall.info > $LOGS/summary.info
EOF
    fi

    ############### generate report.html ################
    html=$LOGS/report.html

    cat >>$BUILDHOME/run <<EOF
cat >>$html <<HTML
$(generate_html_head)
$(generate_html_table)
\$(awk '{if(NF==2){print "<tr><th>",\$1,"</th><td>",\$2,abc,"</td></tr>"}else{if(\$2!=\$3)cls1="class=diff";else cls1="";if(\$3!=\$4)cls2="class=diff";else cls2="";print "<tr><th>",\$1,"</th><td>",\$2,"</td><td",cls1,">",\$3,"</td><td",cls2,">",\$4,"</td></tr>"}}' $LOGS/summary.info)
$(generate_html_tail)
HTML
EOF

}

usage() {
    echo "Usage: -i/--install-from repository [-u/--upgrade-to repository] package_name"
    echo "    package_name: name of package which you want to test"
    echo "    -i|--install-from repository from which you want to install"
    echo "    -u|--upgrade-to   repository from which you want to upgrade"
    echo ""
    echo "You should set env-variable PKGLIST to get the version check!"
}

############
# Main
############

eval set -- $(getopt -o i:u:h --long install-from:,upgrade-to:,help -- "$@")
while [ $# -gt 0 ]
do
    case "$1" in
    (-h|--help) usage; exit 0;;
    (-i|--install-from)
        install_repo=$2
        shift
        ;;
    (-u|--upgrade-to)
        upgrade_repo=$2
        shift
        ;;
    (--) shift; break;;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*)  break;;
    esac
    shift
done

package_name=$1

if [ -z "$package_name" ]; then
    echo "Argument package name is required"
    exit 1
fi

if [ -z "$install_repo" ]; then
    echo "Repository is not specified, please give it by -i"
    exit 1
fi

distro=$(echo $label|cut -d'_' -f 1|tr [:upper:] [:lower:])

if [ $distro = "ubuntu" -o $distro = "debian" ] ; then
    repo_store="/etc/apt"
    package_manager="dpkg"
    install_repo_parameter="deb $install_repo/$OBS_REPO /"
    if [ ${upgrade_repo+defined} ]; then
        upgrade_repo_parameter="deb $upgrade_repo/$OBS_REPO /"
    fi
elif [ $distro = "opensuse" ] ; then
    repo_store="/etc/zypp/repos.d"
    package_manager="rpm"
    install_repo_parameter="$install_repo/$OBS_REPO"
    if [ ${upgrade_repo+defined} ]; then
        upgrade_repo_parameter="$upgrade_repo/$OBS_REPO"
    fi
else
    repo_store="/etc/yum.repos.d"
    package_manager="rpm"
    install_repo_parameter="$install_repo/$OBS_REPO"
    if [ ${upgrade_repo+defined} ]; then
        upgrade_repo_parameter="$upgrade_repo/$OBS_REPO"
    fi
fi


date
prepare_kvm $label additional_init
launch_kvm
copy_back_from_kvm logs
