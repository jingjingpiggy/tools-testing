#!/bin/sh -xeu
. $(dirname $0)/kvm-worker.sh

additional_init() {
    # this function will be called when kvm images are ready
    # to do some additional initial work
    BUILDHOME=$1

    # create flag for runtester script
    # (the one that kicks tester going) indicating we need
    # clean shutdown instead of sudden poweroff
    touch $BUILDHOME/need_shutdown
    # add to run script that will be auto-started in Virtual machine
    # we re-use first part of install_package that runs "update all",
    # that is all we want this time
    cat >> $BUILDHOME/run << EOF
if [ -x $TARGETBIN/otc-tools-tester-system-what-release.sh ]; then
  OSREL=\`$TARGETBIN/otc-tools-tester-system-what-release.sh\`
  OSREL2=\`echo \$OSREL | sed s/-/_/g\`
  ADD_REPOS=\`egrep "^(\$OSREL|\$OSREL2)\\s*:" /home/build/tools-tester.d/base-repos*.conf | cut -d':' -f 2-\`
fi
$TARGETBIN/install_package "" "" "" "" "" "\$ADD_REPOS" "" ""
EOF
}

prepare_kvm $label additional_init
# We can not use snapshot mode for hda. Prepare writable hda copy
# and make own qemu-kvm call instead of calling launch_kvm.
KVM_HDA="$KVM_ROOT_ON_DISK/kvm-hda"
cp $KVM_SEED_HDA $KVM_HDA
chmod 644 $KVM_HDA
cpu_opt=$(compose_cpu_opt $OBS_ARCH)
mem_opt=$(compose_mem_opt)
net_opt=$(compose_net_opt)
vnc_opt=$(compose_vnc_opt)
qemu-kvm -name $label -M pc \
    $cpu_opt $mem_opt $net_opt \
    -drive file=$KVM_HDA \
    -drive file=$KVM_HDB $vnc_opt -nographic
# set updated image back to read-only, move to Jenkins home as .new
chmod 444 $KVM_HDA
mv $KVM_HDA $JENKINS_HOME/kvm-seed-hda-$label.new
copy_back_from_kvm
