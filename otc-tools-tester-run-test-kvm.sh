#!/bin/sh
set -eu

Cleanup () {
 mountpoint -q $BUILDHOME && sudo umount $BUILDHOME
 mountpoint -q $KVM_ROOT && sudo umount $KVM_ROOT
 rm -fr $SRC_TMPCOPY
}

trap Cleanup INT TERM EXIT

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
OBS_PROJECT_NAME="Tools-$PACKAGE$NAME_SUFFIX-$BUILD_NUMBER"
OBS_PROJECT="home:tester:$OBS_PROJECT_NAME"
KVM_ROOT="../kvm-$PROJECT-$BUILD_NUMBER"
BUILDHOME="$KVM_ROOT/mnt"

# copy source tree to temp.copy
SRC_TMPCOPY=`mktemp -d`
cp -a "../$PROJECT" $SRC_TMPCOPY

# Submit packages to OBS
if test "${CAN_SUBMIT_TO_OBS+defined}" ; then

    if [ -d packaging ] ; then
        pkg_dir=packaging
    elif [ -d rpm ] ; then
        pkg_dir=rpm
    else
        echo "Error: No packaging directory found"
        exit 1
    fi

    make -C $pkg_dir all
    build-package --sproject "$SOURCE_PROJECT" --tproject "$OBS_PROJECT" --package "$PACKAGE" $pkg_dir/*
else
    build-package --wait --tproject "$OBS_PROJECT" --timeout 120
fi

# re-create directory for reports
rm -rf "$WORKSPACE/reports"
mkdir "$WORKSPACE/reports"

# prepare KVM disks and mount KVM home
KVM_HDA="$KVM_ROOT/kvm-hda-$OBS_REPO"
KVM_HDB="$KVM_ROOT/kvm-hdb"
rm -rf $KVM_ROOT
mkdir -m 777 $KVM_ROOT
sudo mount -t tmpfs -o size=8G tmpfs $KVM_ROOT
cp /var/lib/jenkins/kvm-seed-hda-$OBS_REPO $KVM_HDA
cp /var/lib/jenkins/kvm-seed-hdb $KVM_HDB
mkdir $BUILDHOME
sudo mount -o loop,offset=1048576 $KVM_HDB $BUILDHOME

# Get list of built binary packages
safeosc ls -b "$OBS_PROJECT" -r "$OBS_REPO" -a "$OBS_ARCH" > "$WORKSPACE/packages.list"
PACKAGES=`sed -n 's/^\(.*\)\.\(deb\|rpm\)$/\1/p' "$WORKSPACE/packages.list"|tr '\n' ' '`
if [ -z "$PACKAGES" ]; then
  echo "Error: No packages were built by OBS"
  exit 1
fi

# create run script that will be auto-started in Virtual machine
cat > $BUILDHOME/build/run << EOF
#!/bin/sh
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
sudo umount $BUILDHOME

(
 flock 9 || exit 1
 # under lock: Run tests by starting KVM, executes /home/build/run and shuts down.
 sudo qemu-kvm -name $OBS_REPO -M pc -m 2048 -boot d -hda $KVM_HDA -hdb $KVM_HDB -vnc :0
) 9>/tmp/kvm-lockfile

# Mount 2nd disk of VM again to copy the test result and logs
sudo mount -o loop,offset=1048576 $KVM_HDB $BUILDHOME
[ "$(ls -A $BUILDHOME/build/reports/)" ] && cp "$BUILDHOME/build/reports/"* "$WORKSPACE/reports/"
[ "$(ls -A $BUILDHOME/build/output)" ] && cp "$BUILDHOME/build/output" $KVM_ROOT/

# make test output visible in Jenkins job output
cat $KVM_ROOT/output
echo 'done'
