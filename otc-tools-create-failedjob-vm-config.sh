#!/bin/sh
# create VM config from template
#
name=$1
hda=$2
hdb=$3
config_template=$4
uuid=`uuidgen`
mac12=`printf '52:54:'`
mac36=`od /dev/urandom -N4 -t x1 -An | cut -c 2- | sed 's/ /:/g'`
mac=$mac12$mac36
hda2=`echo $hda | sed 's/\\//\\\\\//g'`
hdb2=`echo $hdb | sed 's/\\//\\\\\//g'`
dir=`dirname $hda`
arch=`echo $name | awk -F'-' '{print $(NF-2)}'`
if [ $arch = "i586" ]; then
  cpu="pentium2"
else
  cpu="core2duo"
fi
cat $config_template | \
sed s/UUID_PLACEHOLDER/$uuid/ | \
sed s/NAME_PLACEHOLDER/$name/ | \
sed s/HDA_PLACEHOLDER/$hda2/ | \
sed s/HDB_PLACEHOLDER/$hdb2/ | \
sed s/CPU_PLACEHOLDER/$cpu/ | \
sed s/MAC_PLACEHOLDER/$mac/

