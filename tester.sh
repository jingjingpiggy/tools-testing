#!/bin/sh -efu

PROJECT=`basename $(pwd)`
BUILDHOME=./buildroot/home/build/
PACKAGE=`echo $JOB_NAME|cut -f2- -d-|cut -f1 -d/`

# Submit packages to OBS
make -C packaging/ all
# TODO: Fix this build: build-package --sproject Tools:Devel --tproject home:tester:Tools-$BUILD_NUMBER --package $PACKAGE packaging/*
build-package --sproject home:tester:Tools --tproject home:tester:Tools-$PACKAGE-$BUILD_NUMBER --package $PACKAGE packaging/*

cd ..

# re-create directory for reports
rm -rf $WORKSPACE/reports
mkdir $WORKSPACE/reports

# Unpack buildroot.tar
sudo rm -rf ./buildroot
sudo tar -xf ~/buildroot.tar

mkdir -p /home/build/reports/

# Install packages
sudo chroot ./buildroot /usr/bin/install_package $PACKAGE $BUILD_NUMBER /home/build/reports/install.log

# copy source tree to buildroot
cp -a ./$PROJECT $BUILDHOME

# Run tests
sudo chroot ./buildroot /usr/bin/run_tests /home/build/$PROJECT /home/build/reports/ /home/build/reports/pylint.log

# Copy test results
cp $BUILDHOME/reports/* $WORKSPACE/reports

# Clean buildroot
sudo rm -rf ./buildroot

echo 'done'
