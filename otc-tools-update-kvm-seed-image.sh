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
# we need slightly different kvm call, can not use snapshot mode for hda
# so we prepare hda copy and make own call instead of calling launch_kvm
KVM_CPU=$(kvm_cpu_name $OBS_ARCH)
KVM_HDA="$KVM_ROOT_ON_DISK/kvm-hda"
cp $KVM_SEED_HDA $KVM_HDA
qemu-kvm -name $label -M pc -cpu $KVM_CPU -m 2048 -drive file=$KVM_HDA -drive file=$KVM_HDB -vnc :$EXECUTOR_NUMBER
# move updated HDA image to Jenkins home, renamed as new
mv $KVM_HDA $JENKINS_HOME/kvm-seed-hda-$label.new
copy_back_from_kvm
