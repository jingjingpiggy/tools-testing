#!/bin/sh

# DAYS_TO_KEEP is Jenkins job argument
# older than that (not changed during last DAYS_TO_KEEP days) buildroots
# will be deleted

TO_DEL=`find /tmp -maxdepth 1 -type d -ctime +$DAYS_TO_KEEP \
 -name 'buildroot-updated-*'`

for BR in ${TO_DEL}; do
  sudo rm -rf $BR
done

TO_DEL=`find $JENKINS_HOME/workspace/*/label -maxdepth 1 \
 -type d -ctime +$DAYS_TO_KEEP -name 'buildroot-*'`

for BR in ${TO_DEL}; do
  echo $BR
done

