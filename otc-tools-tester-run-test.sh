#!/bin/sh

set -eu

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
BUILDHOME="$BUILDROOT/home/build"

OBS_PROJECT_NAME="Tools-$PACKAGE$NAME_SUFFIX-$BUILD_NUMBER"
OBS_PROJECT="home:tester:$OBS_PROJECT_NAME"

# Clean buildroot on exit
#trap "sudo rm -rf $BUILDROOT; exit" INT TERM EXIT

# see if we have buildroot with changes prepared
if [ -d $BUILDROOT ] ; then
    echo "buildroot named $BUILDROOT exists"
else
    echo "No buildroot named $BUILDROOT, done"
    exit 0
fi

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

# Get list of built binary packages
safeosc ls -b "$OBS_PROJECT" -r "$OBS_REPO" -a "$OBS_ARCH" > "$WORKSPACE/packages.list"
PACKAGES=`sed -n 's/^\(.*\)\.\(deb\|rpm\)$/\1/p' "$WORKSPACE/packages.list"|tr '\n' ' '`
if [ -z "$PACKAGES" ]; then
  echo "Error: No packages were built by OBS"
  exit 1
fi

# Install packages
SPROJ=`echo "$SOURCE_PROJECT" | sed 's/:/:\//g'`
if [ -f packaging/.test-requires -a -x /usr/bin/otc-tools-tester-system-what-release.sh ]; then
  OSREL=`/usr/bin/otc-tools-tester-system-what-release.sh`
  TESTREQ_PACKAGES=`grep $OSREL packaging/.test-requires | cut -d':' -f 2`
else
  TESTREQ_PACKAGES=""
fi
sudo chroot "$BUILDROOT" /usr/bin/install_package "$OBS_PROJECT_NAME" "$OBS_REPO" "$PACKAGES" "$SPROJ" "$TESTREQ_PACKAGES"

# copy source tree to buildroot
cp -a "../$PROJECT" "$BUILDHOME/"

# Run tests
sudo chroot "$BUILDROOT" su - build /usr/bin/run_tests "/home/build/$PROJECT" /home/build/reports/

# Copy test results
[ "$(ls -A $BUILDHOME/reports/)" ] && cp "$BUILDHOME/reports/"* "$WORKSPACE/reports/"

# remove buildroot
sudo rm -rf $BUILDROOT

echo 'done'
