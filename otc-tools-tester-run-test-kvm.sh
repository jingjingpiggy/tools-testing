#!/bin/sh -xeu

UMOUNT="sudo umount -l"

Cleanup () {
 test "${SRC_TMPCOPY+defined}" && rm -fr $SRC_TMPCOPY
 test "${BUILDMOUNT+defined}" && mountpoint -q $BUILDMOUNT && $UMOUNT $BUILDMOUNT
 if test "${KVM_ROOT+defined}" ; then
     mountpoint -q $KVM_ROOT && $UMOUNT $KVM_ROOT
     rm -fr $KVM_ROOT
 fi
 date
}

OBS_REPO=`echo $label|cut -f1 -d-`
OBS_ARCH=`echo $label|cut -f2 -d-`
role=$OBS_REPO

if [ "$role" != "Builder" ]; then
    trap Cleanup INT TERM EXIT ABRT
fi

if [ $# -lt 2 ]; then
  echo "Usage: PACKAGE SOURCE_PROJECT [ -s NAME_SUFFIX] [-u GIT_URL]"
  exit 1
fi

NAME_SUFFIX=""
GIT_URL=""
set -- $(getopt s:u: "$@")
while [ $# -gt 0 ]
do
    case "$1" in
    (-u) GIT_URL=$2; shift;;
    (-s) NAME_SUFFIX=$2; shift;;
    (--) shift; break;;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*)  break;;
    esac
    shift
done

PACKAGE=$1
MAIN_PROJECT=$2

date
SOURCE_PROJECT=''
SUFFIX="$BUILD_NUMBER"
if test "${GERRIT_CHANGE_NUMBER+defined}" ; then
    if [ -n "$GERRIT_CHANGE_NUMBER" -a -n "$GERRIT_PATCHSET_NUMBER" ] ; then
        SUFFIX="$GERRIT_CHANGE_NUMBER.$GERRIT_PATCHSET_NUMBER"
    fi
fi

if [ -n "${GERRIT_REFNAME+defined}" ] ; then
    EVENT="ref updated"
    BRANCH_PREFIX=`echo $GERRIT_REFNAME|cut -f1 -d-`
    REF_TO_FETCH=$GERRIT_REFNAME
elif [ -n "${GERRIT_REFSPEC+defined}" ] ; then
    EVENT="patchset created"
    BRANCH_PREFIX=`echo $GERRIT_BRANCH|cut -f1 -d-`
    REF_TO_FETCH=$GERRIT_REFSPEC
else
    echo 'GERRIT_REFNAME and GERRIT_REFSPEC are undefined.'
    exit 1
fi

if [ "$BRANCH_PREFIX" != "devel" -a "$BRANCH_PREFIX" != "master" \
                                 -a "$BRANCH_PREFIX" != "release" ] ; then
    echo 'Ref $BRANCH_PREFIX is not supported.'
    exit 1
fi

# Get source tree and reset it to proper REF
if [ ! -d "$GERRIT_PROJECT/.git" ] ; then
    [ -d "$GERRIT_PROJECT" ] && rm -rf $GERRIT_PROJECT
    git clone ssh://Gerrit/$GERRIT_PROJECT
fi
cd $GERRIT_PROJECT
git clean -xdf
git fetch origin $REF_TO_FETCH
git reset --hard FETCH_HEAD
git submodule update --init

if [ "$EVENT" = 'ref updated' ] ; then # ref updated - upload to base
    TARGET_PROJECT_NAME=""
    # branch -> target repo mapping
    [ "$GERRIT_REFNAME" = "master" ] && TARGET_PROJECT=$MAIN_PROJECT
    [ "$GERRIT_REFNAME" = "devel" ] && TARGET_PROJECT="$MAIN_PROJECT:Devel"
    [ "$BRANCH_PREFIX" = "release" ] && TARGET_PROJECT="$MAIN_PROJECT:Pre-release"
    SPROJ=`echo "$TARGET_PROJECT" | sed 's/:/:\//g'`
else # patchset created - upload to the linked project
    # branch -> source repo mapping
    [ "$GERRIT_BRANCH" = "master" ] && SOURCE_PROJECT=$MAIN_PROJECT
    [ "$GERRIT_BRANCH" = "devel" ] && SOURCE_PROJECT="$MAIN_PROJECT:Devel"
    [ "$BRANCH_PREFIX" = "release" ] && SOURCE_PROJECT="$MAIN_PROJECT:Pre-release"
    TARGET_PROJECT_NAME="Tools-$PACKAGE$NAME_SUFFIX-$SUFFIX"
    TARGET_PROJECT="home:tester:$TARGET_PROJECT_NAME"
    SPROJ=`echo "$SOURCE_PROJECT" | sed 's/:/:\//g'`
fi

if [ "$role" != "Builder" ]; then
    # copy source tree to temp.copy
    SRC_TMPCOPY=`mktemp -d`
    cp -a "../$GERRIT_PROJECT" $SRC_TMPCOPY
else
    # Submit packages to OBS
    if [ -d packaging ] ; then
        pkg_dir=packaging
    elif [ -d rpm ] ; then
        pkg_dir=rpm
    else
        echo "Error: No packaging directory found"
        exit 1
    fi
    # Prepare packaging
    if [ -n "$GIT_URL" ]; then
       # if GIT_URL is provided create _service file for git-bildpackage source service
       revision=`git rev-parse FETCH_HEAD`
       echo "<services><service name='git-buildpackage'><param name='revision'>$revision</param><param name='url'>$GIT_URL</param></service></services>" > $pkg_dir/_service
       files="$pkg_dir/_service"
    elif [ -f $pkg_dir/Makefile ] ; then
       # If not - use make in packaging/
       make -C $pkg_dir all
       files="$pkg_dir/*"
    else
       echo "Error: No $pkg_dir/Makefile and no GIT_URL provided"
       exit 1
    fi

    # Builder uses fake reports to keep Jenkins reports processing happy
    mkdir -p "$WORKSPACE/reports"
    cp $JENKINS_HOME/coverage.xml-fake "$WORKSPACE"/reports/coverage.xml
    cp $JENKINS_HOME/nosetests.xml-fake "$WORKSPACE"/reports/nosetests.xml
    set +e
    arg_projects="--tproject $TARGET_PROJECT"
    [ -n "$SOURCE_PROJECT" ] && arg_projects="--sproject $SOURCE_PROJECT $arg_projects"
    timeout 60m build-package $arg_projects --package "$PACKAGE" $files
    buildval=$?
    [ -f $pkg_dir/_service ] && rm $pkg_dir/_service
    exit $buildval
fi

# Get OBS build log and show it
safeosc remotebuildlog "$TARGET_PROJECT" $PACKAGE "$OBS_REPO" "$OBS_ARCH"
# Get OBS build status
BSTAT=`safeosc results -r "$OBS_REPO" -a "$OBS_ARCH" "$TARGET_PROJECT" $PACKAGE | awk '{print $NF}'`
if [ "$BSTAT" = "failed" ]; then
    echo "Error: package build status is $BSTAT, build FAILED"
    exit 1
fi

# Get list of built binary packages
safeosc ls -b "$TARGET_PROJECT" -r "$OBS_REPO" -a "$OBS_ARCH" > "$WORKSPACE/packages.list"
PACKAGES=`sed -n 's/^\(.*\)\.\(deb\|rpm\)$/\1/p' "$WORKSPACE/packages.list"|tr '\n' ' '`
if [ -z "$PACKAGES" ]; then
  echo "Error: No packages were built by OBS"
  exit 1
fi

# prepare KVM disk image files and mount KVM home
KVM_SEED_HDA="$JENKINS_HOME/kvm-seed-hda-$label"
KVM_SEED_HDB="$JENKINS_HOME/kvm-seed-hdb"
KVM_ROOT="../kvm-$label-$BUILD_NUMBER"
KVM_HDA="$KVM_ROOT/kvm-hda-$label"
KVM_HDB="$KVM_ROOT/kvm-hdb"
sz_hda=`stat -c %s $KVM_SEED_HDA`
sz_hdb=`stat -c %s $KVM_SEED_HDB`
sz_hd=$((sz_hda + sz_hdb))
mkdir -p -m 777 $KVM_ROOT
sudo mount -t tmpfs -o size=$sz_hd -v tmpfs $KVM_ROOT
cp $KVM_SEED_HDA $KVM_HDA
cp $KVM_SEED_HDB $KVM_HDB
BUILDMOUNT="$KVM_ROOT/mnt"
mkdir $BUILDMOUNT
BUILDHOME="$BUILDMOUNT/build"
BUILDHOMEBIN="$BUILDHOME/bin"
TARGETBIN="/home/build/bin"
HDB_OFFSET=1048576
sudo mount -o loop,offset=$HDB_OFFSET -t ext4 -v $KVM_HDB $BUILDMOUNT

# create run script that will be auto-started in Virtual machine
cat > $BUILDHOME/run << EOF
#!/bin/sh -xe
TESTREQ_PACKAGES=""
if [ -f /home/build/$GERRIT_PROJECT/packaging/.test-requires -a -x $TARGETBIN/otc-tools-tester-system-what-release.sh ]; then
  OSREL=\`$TARGETBIN/otc-tools-tester-system-what-release.sh\`
  TESTREQ_PACKAGES=\`grep \$OSREL /home/build/$GERRIT_PROJECT/packaging/.test-requires | cut -d':' -f 2\`
fi
$TARGETBIN/install_package "$TARGET_PROJECT_NAME" "$OBS_REPO" "$PACKAGES" "$SPROJ" "\$TESTREQ_PACKAGES"
su - build -c "timeout 60m $TARGETBIN/run_tests /home/build/$GERRIT_PROJECT /home/build/reports/ 2>&1"
EOF

chmod a+x $BUILDHOME/run
# mv source tree from temp.copy to VM /home/build
mv "$SRC_TMPCOPY/$GERRIT_PROJECT" $BUILDHOME/
# copy scripts that run inside KVM session
mkdir -p $BUILDHOMEBIN
cp /usr/bin/install_package /usr/bin/otc-tools-tester-system-what-release.sh /usr/bin/run_tests $BUILDHOMEBIN
$UMOUNT $BUILDMOUNT
date
# Run tests by starting KVM, executes /home/build/run and shuts down.
qemu-kvm -name $label -M pc -m 2048 -boot d -hda $KVM_HDA -hdb $KVM_HDB -vnc :$EXECUTOR_NUMBER
date

# re-create directory for reports
rm -rf "$WORKSPACE/reports"
mkdir "$WORKSPACE/reports"

# Mount 2nd disk of VM again to copy the test result and logs
sudo mount -o loop,offset=$HDB_OFFSET -t ext4 -v $KVM_HDB $BUILDMOUNT
[ "$(ls -A $BUILDHOME/reports/)" ] && cp "$BUILDHOME/reports/"* "$WORKSPACE/reports/"
# make test run output visible in Jenkins job output
[ "$(ls -A $BUILDHOME/output)" ] && cat "$BUILDHOME/output"

# examine KVM session return value, written on last line, to form exit value,
RETVAL=`tail -1 "$BUILDHOME/output"`
if [ $RETVAL -eq 0 ]; then
    echo RUN SUCCESS
    exit 0
else
    if [ "$NAME_SUFFIX" = "-debug" ]; then
        # disable autorun, keep images, add helper script for startng the KVM
        LOC=$JENKINS_HOME/FAILED
        TAG=`echo $BUILD_TAG | sed 's/label=//'`
        mkdir -p $LOC
        mv $KVM_HDA $LOC/$TAG-hda
        mv $BUILDHOME/run $BUILDHOME/run.notactive
        $UMOUNT $BUILDMOUNT
        mv $KVM_HDB $LOC/$TAG-hdb
    fi
    echo RUN FAIL
    exit 1
fi
