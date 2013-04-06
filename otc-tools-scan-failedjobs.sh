#!/bin/sh
# scan given directory for entries which do not have corresponding
# VM virsh config yet, and create such config and VM
#

lxcroot=$1
dir=$lxcroot/var/lib/jenkins/FAILED
files=`ls $dir/*hda`
current=`date +%s`
for hda in ${files}; do
  hdb=`echo $hda | sed s/-hda$/-hdb/`
  prj=`echo $hda | sed s/-hda$//`
  name=`basename $prj`
  vmconfig="/etc/libvirt/qemu/$name.xml"
  if [ ! -f $vmconfig ] ; then
    echo "`date`: VM $name does not exist, creating from template..."
    $lxcroot/usr/bin/otc-tools-create-failedjob-vm-config.sh $name $hda $hdb > $vmconfig
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
