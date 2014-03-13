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
$TARGETBIN/install_package "" "" "" "" "" "" ""
EOF
}

prepare_kvm $label additional_init
# We can not use snapshot mode for hda. Prepare writable hda copy
# and make own qemu-kvm call instead of calling launch_kvm.
KVM_CPU=$(kvm_cpu_name $OBS_ARCH)
KVM_HDA="$KVM_ROOT_ON_DISK/kvm-hda"
netcmd=$(kvm_netcmd)
vnccmd=$(kvm_vnccmd)
cp $KVM_SEED_HDA $KVM_HDA
chmod 644 $KVM_HDA
qemu-kvm -name $label -M pc \
    -cpu $KVM_CPU -m 2048 $netcmd \
    -drive file=$KVM_HDA \
    -drive file=$KVM_HDB $vnccmd
# set updated image back to read-only, move to Jenkins home as .new
chmod 444 $KVM_HDA
mv $KVM_HDA $JENKINS_HOME/kvm-seed-hda-$label.new
copy_back_from_kvm
