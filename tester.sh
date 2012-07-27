set -eu

PROJECT=`basename "$(pwd)"`
BUILDROOT="../buildroot-$BUILD_NUMBER"
BUILDHOME="$BUILDROOT/home/build"
PACKAGE=`echo $GERRIT_PROJECT|cut -f1 -d-`
OBS_PROJECT="home:tester:Tools-$PACKAGE-$BUILD_NUMBER"

# Clean buildroot on exit
trap "sudo rm -rf $BUILDROOT; exit" INT TERM EXIT

# Submit packages to OBS
if test "${CAN_SUBMIT_TO_OBS+defined}" ; then
     
    if [ -d packaging ] ; then
        pkg_dir=packaging
    elif [ -d rpm ] ; then
        pkg_dir=rpm
    else
        echo "Error: No packaing directory found"
        exit 1
    fi
       
    make -C $pkg_dir all
    build-package --sproject home:tester:Tools --tproject "$OBS_PROJECT" --package "$PACKAGE" $pkg_dir/*
else
    build-package --wait --tproject "$OBS_PROJECT"
fi

# re-create directory for reports
rm -rf "$WORKSPACE/reports"
mkdir "$WORKSPACE/reports"

# Unpack buildroot.tar
sudo tar -xf ~/buildroot.tar
sudo mv buildroot "$BUILDROOT"

# Get list of built binary packages
osc ls -b "$OBS_PROJECT" -r "$OBS_REPO" -a "$OBS_ARCH" > "$WORKSPACE/packages.list"
PACKAGES=`sed -n 's/^\(.*\)\.\(deb\|rpm\)$/\1/p' "$WORKSPACE/packages.list"|tr '\n' ' '`

# Install packages
sudo chroot "$BUILDROOT" /usr/bin/install_package "Tools-$PACKAGE-$BUILD_NUMBER" "$OBS_REPO" "$PACKAGES"

# copy source tree to buildroot
cp -a "../$PROJECT" "$BUILDHOME/"

# Run tests
sudo chroot "$BUILDROOT" /usr/bin/run_tests "/home/build/$PROJECT" /home/build/reports/

# Copy test results
[ "$(ls -A $BUILDHOME/reports/)" ] && cp "$BUILDHOME/reports/"* "$WORKSPACE/reports/"

echo 'done'
