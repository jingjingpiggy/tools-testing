#!/bin/bash -ex

PROJECT=`basename $(pwd)`
BUILDHOME=./buildroot/home/build/
PACKAGE=`echo $JOB_NAME|cut -f2- -d-|cut -f1 -d/`

# Submit packages to OBS
make -C packaging/ all
# TODO: Fix this build: build-package --sproject Tools:Devel --tproject home:tester:Tools-$BUILD_NUMBER --package $PACKAGE packaging/*
# build-package --sproject home:tester:Tools --tproject home:tester:Tools-$PACKAGE-$BUILD_NUMBER --package $PACKAGE packaging/*

cd ..

# re-create directory for reports
rm -rf $WORKSPACE/reports
mkdir $WORKSPACE/reports

# Unpack buildroot.tar
sudo rm -rf ./buildroot
sudo tar -xf ~/buildroot.tar

# Prepare installation script
cat > $BUILDHOME/install_package.sh <<-EOF
#!/bin/sh -ex

mkdir -p /home/build/reports/
LOG=/home/build/reports/install.log

if [ -e /usr/bin/apt-get -a -d /etc/apt/sources.list.d/ ] ; then
   ubuntu_release=\$(grep DISTRIB_RELEASE /etc/lsb-release | cut -f2 -d=)
   echo "deb http://download.otctools.jf.intel.com/Tools:/Devel/xUbuntu_\$ubuntu_release/ /" > /etc/apt/sources.list.d/tools.list
   #echo "deb http://download.otctools.jf.intel.com/home:/tester:/Tools-$PACKAGE-$BUILD_NUMBER/xUbuntu_\$ubuntu_release/ /" >>  /etc/apt/sources.list.d/tools.list
   apt-get update | tee \$LOG
   apt-get upgrade | tee -a \$LOG
   apt-get install -y --force-yes $PACKAGE | tee -a \$LOG
elif [ -e /usr/bin/zypper -a -d /etc/zypp/repos.d ] ; then
   zypper ar -fG http://download.otctools.jf.intel.com/Tools:/Devel/openSUSE12.1/ Tools
   #zypper ar -fG http://download.otctools.jf.intel.com/home:/tester:/Tools-$PACKAGE-$BUILD_NUMBER/openSUSE12.1/ Tools-$PACKAGE-$BUILD_NUMBER
   zypper ref | tee \$LOG
   zypper --non-interactive install $PACKAGE | tee -a \$LOG
fi
EOF
chmod +x $BUILDHOME/install_package.sh

# Install packages
sudo chroot ./buildroot sh -x /home/build/install_package.sh

# copy source tree to buildroot
cp -a ./$PROJECT $BUILDHOME

# Prepare test script
cat > $BUILDHOME/tests.sh <<-EOF
#!/bin/sh -ex

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
