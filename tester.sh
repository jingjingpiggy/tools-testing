#!/bin/bash -ex

PROJECT=`basename $(pwd)`
BUILDHOME=./buildroot/home/build/
PACKAGE=gbs

# Submit packages to OBS
make -C packaging/ all
# TODO: Fix this build: $WORKSPACE/../../build-package --sproject Tools:Devel --tproject home:tester:Tools-$BUILD_NUMBER --package $PACKAGE packaging/*
$WORKSPACE/../../build-package --sproject home:tester:Tools --tproject home:tester:Tools-$PACKAGE-$BUILD_NUMBER --package $PACKAGE packaging/*

cd ..

# re-create directory for reports
rm -rf $WORKSPACE/reports
mkdir $WORKSPACE/reports

# Unpack buildroot.tar
sudo rm -rf ./buildroot
sudo tar -xf ../buildroot.tar

# Prepare installation script
cat > $BUILDHOME/install_package.sh <<-EOF
#!/bin/sh

mkdir -p /home/build/reports/
LOG=/home/build/reports/install.log

if [ -e /usr/bin/apt-get -a -d /etc/apt/sources.list.d/ ] ; then
   echo "deb http://archive.ubuntu.com/ubuntu/ precise universe" >> /etc/apt/sources.list.d/tools.list
   echo "deb http://archive.ubuntu.com/ubuntu/ precise-updates universe" >> /etc/apt/sources.list.d/tools.list
   echo "deb http://download.otctools.jf.intel.com/Tools:/Devel/xUbuntu_12.04/ /" >> /etc/apt/sources.list.d/tools.list
   echo "deb http://download.otctools.jf.intel.com/home:/tester:/Tools-$PACKAGE-$BUILD_NUMBER/xUbuntu_12.04/ /"
   apt-get update | tee \$LOG
   apt-get upgrade | tee -a \$LOG
   apt-get install -y --force-yes $PACKAGE | tee -a \$LOG
elif [ -e /usr/bin/zypper -a -d /etc/zypper/repos.d ] ; then
   # TODO: Add repos the same way as it's done for apt above
   zypper ref | tee \$LOG
   zypper install $PACKAGE | tee -a \$LOG
fi
EOF
chmod +x $BUILDHOME/install_package.sh

# Install packages
sudo chroot ./buildroot sh -x /home/build/install_package.sh

# copy source tree to buildroot
cp -a ./$PROJECT $BUILDHOME

# Prepare test script
cat > $BUILDHOME/tests.sh <<-EOF
#!/bin/sh

cd /home/build/$PROJECT

# Run pylint
mkdir -p ~/.pylint.d/
for f in \$(find . -name \*.py); do
    pylint --output-format=parseable --reports=y \$f >> /home/build/reports/pylint.log
done || :

# Run nosetests with coverage support
nosetests -v --with-coverage --with-xunit
coverage=\$(which coverage || which python-coverage)
\$coverage xml
mv nosetests.xml /home/build/reports/
cp coverage.xml /home/build/reports/

EOF
chmod +x $BUILDHOME/tests.sh 

# Run tests
sudo chroot ./buildroot sh -x /home/build/tests.sh

# Copy test results
cp $BUILDHOME/reports/* $WORKSPACE/reports

# Clean buildroot
sudo rm -rf ./buildroot

echo 'done'
exit 0

