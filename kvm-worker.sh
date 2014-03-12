#!/bin/sh

UMOUNT="sudo umount -l"
test "${label+defined}" && \
  OBS_REPO=`echo $label|cut -f1 -d-` && \
  OBS_ARCH=`echo $label|cut -f2 -d-`

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
    # KVM_HDB: hdb image path
    # HDB_OFFSET: offset of mounting hdb image
    # BUILDHOME: mounted path in host for /home/build in image
    # KVM_ROOT_ON_DISK: tmp dir for HDB, used in cleanup function
    # BUILDMOUNT: tmp mount path in host, also used in cleanup function
    label=$1
    additional_init=$2

    # register cleanup
    cleanup_tmp_kvm_root() {
        test "${BUILDMOUNT+defined}" && mountpoint -q $BUILDMOUNT && $UMOUNT $BUILDMOUNT
        if test "${KVM_ROOT_ON_DISK+defined}" ; then
            rm -fr $KVM_ROOT_ON_DISK
        fi
        date
    }
    at_exec cleanup_tmp_kvm_root

    # prepare KVM disk image files and mount KVM home
    KVM_SEED_HDA="$JENKINS_HOME/kvm-seed-hda-$label"
    KVM_SEED_HDB="$JENKINS_HOME/kvm-seed-hdb.tar"
    KVM_ROOT_ON_DISK="../kvm-$label-$BUILD_NUMBER-disk"
    KVM_HDB="$KVM_ROOT_ON_DISK/kvm-hdb"
    mkdir -p $KVM_ROOT_ON_DISK
    tar SxfO - < $KVM_SEED_HDB > $KVM_HDB
    BUILDMOUNT="$KVM_ROOT_ON_DISK/mnt"
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
  elif [ -x /usr/bin/journalctl ]; then
    /usr/bin/journalctl --no-pager | tail -50 > /home/build/syslog
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

check_kvm_args() {
    KVM_MEMSZ_MAX=8192
    if [ $KVM_MEMSZ -lt 0 ] ; then
        echo "ERROR: requested KVM memory must be positive"
        exit 1
    elif [ $KVM_MEMSZ -gt $KVM_MEMSZ_MAX ] ; then
        echo "ERROR: requested KVM memory can not exceed $KVM_MEMSZ_MAX MB"
        exit 1
    fi
}

launch_kvm() {
    numacmd=""
    if [ $(which numactl) ]; then
      # Bind to CPUs and mem of one node on a NUMA system.
      numanodes=`numactl --hardware | grep 'available:' | awk '{print $2}'`
      if [ $numanodes -gt 1 ]; then
        idx=$((EXECUTOR_NUMBER%numanodes))
        numacmd="numactl --preferred=$idx --cpunodebind=$idx"
      fi
    fi

    KVM_MEMSZ_DEFAULT=2048
    KVM_CPU=$(kvm_cpu_name $OBS_ARCH)

    if [ ! "${KVM_MEMSZ+defined}" ] ; then
        KVM_MEMSZ=$KVM_MEMSZ_DEFAULT
    fi

    netcmd=$(kvm_netcmd)
    vnccmd=$(kvm_vnccmd)
    # Run tests by starting KVM, executes /home/build/run and shuts down.
    $numacmd qemu-kvm -name $label -M pc \
        -cpu $KVM_CPU -m $KVM_MEMSZ $netcmd \
        -drive file=$KVM_SEED_HDA,snapshot=on \
        -drive file=$KVM_HDB $vnccmd
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
        echo RUN FAIL
        exit 1
    fi
}

target_project_basename() {
 gerrit_name=$1
 safename=`echo $gerrit_name | sed 's/\//-/g'`
 echo "Tools-$safename"
}

kvm_cpu_name() {
 arch=$1
 if [ $arch = "i586" ]; then
   echo "pentium3"
 else
   echo "core2duo"
 fi
}

kvm_netcmd() {
  # create unique MAC address from static part=52, node IP, slot number, process number
  # node IP last octet comes from SSH_CONNECTION="10.237.71.24 44908 10.237.71.173 22"
  nodenum=`echo "$SSH_CONNECTION" | awk '{print $3}' | awk -F\. '{printf("%02x", $4);}'`
  slotnum=`printf "%02x" $((EXECUTOR_NUMBER%256))`
  pid=$$
  p1=$((pid/65536))
  p1x=`printf "%02x" $p1`
  pid=$((pid-p1*65536))
  p2=$((pid/256))
  p2x=`printf "%02x" $p2`
  pid=$((pid-p2*256))
  p3x=`printf "%02x" $pid`
  echo "-net nic,macaddr=52:$nodenum:$slotnum:$p1x:$p2x:$p3x -net user"
}

kvm_vnccmd() {
  # find free VNC number.
  # Start with Jenkins slot number. If this socket is taken,
  # increment to next range area. We assume max 20 slots per Jenkins worker.
  # That makes sure our session does not fail because of leftover qemu process
  # or some manually started process with same vnc number, or some random socket.

  slots_range=20
  vncnum=$EXECUTOR_NUMBER
  while [ $vncnum -lt 200 ]; do
      vncsock=`printf "00000000:%04X 00000000:0000" $((5900 + vncnum))`
      if ! grep "$vncsock" /proc/net/tcp  ; then
          break
      fi
      vncnum=$((vncnum + slots_range))
  done
  echo "-vnc :$vncnum"
}

setenv_to_run() {
    #set defined env variable in script run
    if [ "$#" -gt "0" ]; then
        for val in "$@"
        do
            local name=$val
            eval val=\${$val=undefined}
            if [ "$val" != "undefined" ]; then
                echo "export $name=\"$val\"" >> $BUILDHOME/run
            fi
        done
    fi
}
