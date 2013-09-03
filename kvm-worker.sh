#!/bin/sh

UMOUNT="sudo umount -l"

FUNCS_AT_EXEC=
FUNCS_AT_EXEC_CNT=0

at_exec() {
    # Register a function which will be called
    # when exception occurs or program exit.
    #
    # $1: callback function name which should
    # cleanup tmp resource created in script

    FUNCS_AT_EXEC[$FUNCS_AT_EXEC_CNT]=$1
    FUNCS_AT_EXEC_CNT=$(expr $FUNCS_AT_EXEC_CNT + 1)
}

handle_exec() {
    i=0
    while [ $i -lt $FUNCS_AT_EXEC_CNT ]; do
        cmd=${FUNCS_AT_EXEC[$i]}
        i=$(expr $i + 1)
        $cmd
    done
}

trap handle_exec INT TERM EXIT ABRT


prepare_kvm() {
    # Prepare KVM hda and hdb images
    # It sets several global variables for other functions to use:
    # KVM_INSTANCE_NAME: human-readable name for this kvm instance
    # KVM_HDA: hda image path
    # KVM_HDB: hdb image path
    # HDB_OFFSET: offset of mounting hdb image
    # BUILDHOME: mounted path in host for /home/build in image
    # KVM_ROOT: tmp dir for this instance, used in cleanup function
    # BUILDMOUNT: tmp mount path in host, also used in cleanup function
    label=$1
    additional_init=$2

    # register cleanup
    cleanup_tmp_kvm_root() {
        test "${BUILDMOUNT+defined}" && mountpoint -q $BUILDMOUNT && $UMOUNT $BUILDMOUNT
        if test "${KVM_ROOT+defined}" ; then
            mountpoint -q $KVM_ROOT && $UMOUNT $KVM_ROOT
            rm -fr $KVM_ROOT
        fi
        date
    }
    at_exec cleanup_tmp_kvm_root

    # prepare KVM disk image files and mount KVM home
    KVM_INSTANCE_NAME=$label
    KVM_SEED_HDA="$JENKINS_HOME/kvm-seed-hda-$label"
    KVM_SEED_HDB="$JENKINS_HOME/kvm-seed-hdb"
    KVM_ROOT="../kvm-$label-$BUILD_NUMBER"
    KVM_HDA="$KVM_ROOT/kvm-hda-$label"
    KVM_HDB="$KVM_ROOT/kvm-hdb"
    sz_hda=`stat -c %s $KVM_SEED_HDA`
    sz_hdb=`stat -c %s $KVM_SEED_HDB`
    sz_hd=$((sz_hda + sz_hdb))
    mkdir -p -m 777 $KVM_ROOT
    sudo mount -t tmpfs -o size=$sz_hd -v tmpfs $KVM_ROOT
    cp $KVM_SEED_HDA $KVM_HDA
    cp $KVM_SEED_HDB $KVM_HDB
    BUILDMOUNT="$KVM_ROOT/mnt"
    mkdir $BUILDMOUNT
    BUILDHOME="$BUILDMOUNT/build"
    BUILDHOMEBIN="$BUILDHOME/bin"
    TARGETBIN="/home/build/bin"
    HDB_OFFSET=1048576
    sudo mount -o loop,offset=$HDB_OFFSET -t ext4 -v $KVM_HDB $BUILDMOUNT

    # create run script that will be auto-started in Virtual machine
    cat > $BUILDHOME/run << EOF
#!/bin/sh -xe
End () {
  if [ -f /var/log/messages ]; then
    tail -50 /var/log/messages > /home/build/syslog
  elif [ -f /var/log/syslog ]; then
    tail -50 /var/log/syslog > /home/build/syslog
  fi
  dmesg | tail -50 > /home/build/dmesg
}
trap End INT TERM EXIT ABRT
EOF
    chmod a+x $BUILDHOME/run

    # copy scripts that run inside KVM session
    mkdir -p $BUILDHOMEBIN
    cp /usr/bin/install_package /usr/bin/otc-tools-tester-system-what-release.sh /usr/bin/run_tests $BUILDHOMEBIN

    $additional_init $BUILDHOME

    cat $BUILDHOME/run
    $UMOUNT $BUILDMOUNT
    date
}

launch_kvm() {
    if [ "$OBS_ARCH" = "i586" ]; then
        KVM_CPU="-cpu pentium2"
    else
        KVM_CPU="-cpu core2duo"
    fi

    # Run tests by starting KVM, executes /home/build/run and shuts down.
    qemu-kvm -name $KVM_INSTANCE_NAME -M pc $KVM_CPU -m 2048 -hda $KVM_HDA -hdb $KVM_HDB -vnc :$EXECUTOR_NUMBER
    date
}

copy_back_from_kvm() {
    if [ $# -eq 0 ]; then
        report_path=$BUILDHOME/reports
    else
        report_path=$BUILDHOME/$1
    fi

    # Mount 2nd disk of VM again to copy the test result and logs
    sudo mount -o loop,offset=$HDB_OFFSET -t ext4 -v $KVM_HDB $BUILDMOUNT

    # make test run output visible in Jenkins job output
    [ "$(ls -A $BUILDHOME/output)" ] && cat "$BUILDHOME/output"
    [ -f $BUILDHOME/syslog ] && cat $BUILDHOME/syslog
    [ -f $BUILDHOME/dmesg ] && cat $BUILDHOME/dmesg

    # re-create directory for reports
    rm -rf "$WORKSPACE/reports"
    mkdir "$WORKSPACE/reports"

    [ -d $report_path ] && [ "$(ls -A $report_path/)" ] && cp -r $report_path/* $WORKSPACE/reports/

    # examine KVM session return value, written on last line, to form exit value,
    RETVAL=`tail -1 "$BUILDHOME/output"`
    if [ "$RETVAL" = 0 ]; then
        echo RUN SUCCESS
        exit 0
    else
        if [ "$NAME_SUFFIX" = "-debug" ]; then
            # disable autorun, keep images, add helper script for startng the KVM
            LOC=$JENKINS_HOME/FAILED
            TAG=`echo $BUILD_TAG | sed 's/label=//'`
            mkdir -p $LOC
            mv $KVM_HDA $LOC/$TAG-hda
            mv $BUILDHOME/run $BUILDHOME/run.notactive
            # umount image before moving it
            $UMOUNT $BUILDMOUNT
            mv $KVM_HDB $LOC/$TAG-hdb
        fi
        echo RUN FAIL
        exit 1
    fi
}

target_project_basename() {
 gerrit_name=$1
 safename=`echo $gerrit_name | sed 's/\//-/g'`
 echo "Tools-$safename"
}
