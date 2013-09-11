#!/bin/sh -xeu
. $(dirname $0)/kvm-worker.sh

additional_init() {
    # this function will be called when kvm images are ready
    # to do some additional initial work
    BUILDHOME=$1

    # add to run script that will be auto-started in Virtual machine
    # we re-use first part of install_package that runs "update all",
    # that is all we want this time
    cat >> $BUILDHOME/run << EOF
$TARGETBIN/install_package "" "" "" "" "" ""
EOF
}

OBS_ARCH=`echo $label|cut -f2 -d-`

prepare_kvm $label additional_init
launch_kvm
# move updated HDA image out of tester tmpfs and mark it as new
mv $KVM_HDA $JENKINS_HOME/kvm-seed-hda-$label
tar --remove-files -Scf $JENKINS_HOME/kvm-seed-hda-$label.new.tar $JENKINS_HOME/kvm-seed-hda-$label
copy_back_from_kvm
