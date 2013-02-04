#!/bin/sh
set -xeu
UMOUNT="sudo umount -l"
OBS_DELETION="$WORKSPACE/info"

Cleanup () {
 mountpoint -q $BUILDHOME && $UMOUNT $BUILDHOME
 mountpoint -q $KVM_ROOT && $UMOUNT $KVM_ROOT
 rm -fr $KVM_ROOT
 rm -fr $SRC_TMPCOPY
}

trap Cleanup INT TERM EXIT ABRT

if [ $# -lt 3 ]; then
  echo "at least 3 args needed: PACKAGE BUILDROOT SOURCE_PROJECT [NAME_SUFFIX]"
  exit 1
fi

PACKAGE=$1
BUILDROOT=$2
SOURCE_PROJECT=$3
if [ $# -gt 3 ]; then
  NAME_SUFFIX=$4
else
  NAME_SUFFIX=""
fi

PROJECT=`basename "$(pwd)"`
SPROJ=`echo "$SOURCE_PROJECT" | sed 's/:/:\//g'`

SUFFIX="$BUILD_NUMBER"
if test "${GERRIT_CHANGE_NUMBER+defined}" ; then
    if [ -n "$GERRIT_CHANGE_NUMBER" -a -n "$GERRIT_PATCHSET_NUMBER" ] ; then
        SUFFIX="$GERRIT_CHANGE_NUMBER.$GERRIT_PATCHSET_NUMBER"
    fi
fi
OBS_PROJECT_NAME="Tools-$PACKAGE$NAME_SUFFIX-$SUFFIX"
OBS_PROJECT="home:tester:$OBS_PROJECT_NAME"
KVM_ROOT="../kvm-$PROJECT-$BUILD_NUMBER"
BUILDHOME="$KVM_ROOT/mnt"

# copy source tree to temp.copy
SRC_TMPCOPY=`mktemp -d`
cp -a "../$PROJECT" $SRC_TMPCOPY

# re-create directory for reports
rm -rf "$WORKSPACE/reports"
mkdir "$WORKSPACE/reports"
echo > "$OBS_DELETION"

# Determine type of the event
EVENT='submit'
if test "${GERRIT_BRANCH+defined}" ; then
    git fetch --all
    # check if change is merged
    if git branch -r --contains $GIT_COMMIT | grep -q origin/$GERRIT_BRANCH ; then
        BRANCH_PREFIX=`echo $GERRIT_BRANCH|cut -f1 -d-`
        if [ "$GERRIT_BRANCH" == "devel" -o "$BRANCH_PREFIX" == "release" ] ; then
            EVENT='merge'
            # When change is merged sources should be put into :Devel for devel branch
            # or into :Pre-release for release-<rnum> branch
            OBS_PROJECT=`echo $SOURCE_PROJECT|cut -f1 -d:`
            if [ "$GERRIT_BRANCH" == "devel" ] ; then
                OBS_PROJECT="$OBS_PROJECT:Devel"
            else #release-<rnum> branch
                OBS_PROJECT="$OBS_PROJECT:Pre-release"
            fi
            SOURCE_PROJECT='DUMMY'
            OBS_PROJECT_NAME=""
            if [ "$label" = "Builder" ]; then
                # store record for removal of build projects
                RELATED_PROJECTS="home:tester:Tools-$PACKAGE$NAME_SUFFIX-$GERRIT_CHANGE_NUMBER\.[0-9]\+"
                echo -e "RELATED_PROJECTS=$RELATED_PROJECTS\nGERRIT_CHANGE_NUMBER=$GERRIT_CHANGE_NUMBER\nGERRIT_BRANCH=$GERRIT_BRANCH" > "$OBS_DELETION"
            fi
	fi
    fi
fi

if [ "$label" == "Builder" ]; then
    # Submit packages to OBS
    if [ -d packaging ] ; then
        pkg_dir=packaging
    elif [ -d rpm ] ; then
        pkg_dir=rpm
    else
        echo "Error: No packaging directory found"
        exit 1
    fi

    make -C $pkg_dir all
    cp $JENKINS_HOME/coverage.xml-fake "$WORKSPACE"/reports/coverage.xml
    cp $JENKINS_HOME/nosetests.xml-fake "$WORKSPACE"/reports/nosetests.xml
    set +e
    timeout 60m build-package --sproject "$SOURCE_PROJECT" --tproject "$OBS_PROJECT" --package "$PACKAGE" $pkg_dir/*
    exit 0
fi

# Get OBS build log and show it
safeosc remotebuildlog "$OBS_PROJECT" $PACKAGE "$OBS_REPO" "$OBS_ARCH"
# Get OBS build status
BSTAT=`safeosc results -r "$OBS_REPO" -a "$OBS_ARCH" "$OBS_PROJECT" $PACKAGE | awk '{print $NF}'`
if [ "$BSTAT" != "succeeded" ]; then
    echo "Error: package build status is not succeeded but $BSTAT, build FAILED"
    exit 1
fi

# Get list of built binary packages
safeosc ls -b "$OBS_PROJECT" -r "$OBS_REPO" -a "$OBS_ARCH" > "$WORKSPACE/packages.list"
PACKAGES=`sed -n 's/^\(.*\)\.\(deb\|rpm\)$/\1/p' "$WORKSPACE/packages.list"|tr '\n' ' '`
if [ -z "$PACKAGES" ]; then
  echo "Error: No packages were built by OBS"
  exit 1
fi

# prepare KVM disk image files and mount KVM home
TARGET="$OBS_REPO-$OBS_ARCH"
KVM_SEED_HDA="$JENKINS_HOME/kvm-seed-hda-$TARGET"
KVM_SEED_HDB="$JENKINS_HOME/kvm-seed-hdb"
KVM_HDA="$KVM_ROOT/kvm-hda-$TARGET"
KVM_HDB="$KVM_ROOT/kvm-hdb"
sz_hda=`stat -c %s $KVM_SEED_HDA`
sz_hdb=`stat -c %s $KVM_SEED_HDB`
sz_hd=$((sz_hda + sz_hdb))
mkdir -p -m 777 $KVM_ROOT
sudo mount -t tmpfs -o size=$sz_hd tmpfs $KVM_ROOT
cp --sparse=always $KVM_SEED_HDA $KVM_HDA
cp --sparse=always $KVM_SEED_HDB $KVM_HDB
mkdir $BUILDHOME
sudo mount -o loop,offset=1048576 $KVM_HDB $BUILDHOME

# create run script that will be auto-started in Virtual machine
cat > $BUILDHOME/build/run << EOF
#!/bin/sh
set -xe
TESTREQ_PACKAGES=""
EOF

if [ "$NAME_SUFFIX" = "-updates" ]; then
  echo "timeout 5m /usr/bin/otc-tools-tester-update-all-packages.sh" >> $BUILDHOME/build/run
fi

cat >> $BUILDHOME/build/run << EOF
if [ -f /home/build/$PROJECT/packaging/.test-requires -a -x /usr/bin/otc-tools-tester-system-what-release.sh ]; then
  OSREL=\`/usr/bin/otc-tools-tester-system-what-release.sh\`
  TESTREQ_PACKAGES=\`grep \$OSREL /home/build/$PROJECT/packaging/.test-requires | cut -d':' -f 2\`
fi
timeout 5m /usr/bin/install_package "$OBS_PROJECT_NAME" "$OBS_REPO" "$PACKAGES" "$SPROJ" "\$TESTREQ_PACKAGES"
timeout 10m su - build /usr/bin/run_tests "/home/build/$PROJECT" /home/build/reports/
EOF

chmod a+x $BUILDHOME/build/run
# mv source tree from temp.copy to VM /home/build
mv "$SRC_TMPCOPY/$PROJECT" $BUILDHOME/build/
$UMOUNT $BUILDHOME

(
 flock 9 || exit 1
 # under lock: Run tests by starting KVM, executes /home/build/run and shuts down.
 sudo qemu-kvm -name $TARGET -M pc -m 2048 -boot d -hda $KVM_HDA -hdb $KVM_HDB -vnc :1
) 9>/tmp/kvm-lockfile

# Mount 2nd disk of VM again to copy the test result and logs
sudo mount -o loop,offset=1048576 $KVM_HDB $BUILDHOME
[ "$(ls -A $BUILDHOME/build/reports/)" ] && cp "$BUILDHOME/build/reports/"* "$WORKSPACE/reports/"
# make test run output visible in Jenkins job output
[ "$(ls -A $BUILDHOME/build/output)" ] && cat "$BUILDHOME/build/output"

# examine KVM session return value, written on last line, to form exit value,
# store testing status to be examined by OBS projects deletion job in merge case
RETVAL=`tail -1 "$BUILDHOME/build/output"`
if [ $RETVAL -eq 0 ]; then
    echo "JENKINS_STATUS_SUCCESS=1" >> "$OBS_DELETION"
    echo RUN SUCCESS
    exit 0
else
    echo "JENKINS_STATUS_FAIL=1" >> "$OBS_DELETION"
    echo RUN FAIL
    exit 1
fi
