#!/bin/sh
# arg1=root of LXC, example: "/srv/lxc/jworker-kvm-179-rootfs"
#
# This script is called by root crontab on server side, i.e.
# outside of LXC machine;
# Scan FAILED directory for new entries and create VM configs,
# delete VM config and storage if not changed during 7 days.
#

lxcroot=$1
dir=$lxcroot/var/lib/jenkins/FAILED
test -d $dir || exit 0
config_template=$lxcroot/usr/share/libvirt-templates/otc-tools-failedjob-vm-template.xml
files=`ls $dir/*hda 2>/dev/null`
current=`date +%s`
for hda in ${files}; do
  hdb=`echo $hda | sed s/-hda$/-hdb/`
  prj=`echo $hda | sed s/-hda$//`
  name=`basename $prj`
  vmconfig="/etc/libvirt/qemu/$name.xml"
  if [ ! -f $vmconfig ] ; then
    # refresh pools so that libvirtd knows about new files
    pools=`virsh pool-list | tail -n +3 | awk '{print $1}'`
    for pool in ${pools}; do
      virsh pool-refresh $pool
    done
    echo "`date`: VM $name does not exist, creating from template..."
    $lxcroot/usr/bin/otc-tools-create-failedjob-vm-config.sh $name $hda $hdb $config_template > $vmconfig
    chmod 600 $vmconfig
    virsh define $vmconfig
  else
    last_modified=`stat -c "%Y" $hda`
    age=$(($current-$last_modified))
    if [ $age -gt 604800 ] ; then
      echo "`date`: VM $name is more than 7d old, delete VM and images"
      virsh undefine $name --remove-all-storage
    fi
  fi
done
