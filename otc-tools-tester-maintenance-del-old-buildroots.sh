#!/bin/sh

# DAYS_TO_KEEP is Jenkins job argument
# older than that (not changed during DAYS_TO_KEEP days)
# buildroots are deleted

# 1st pass, delete buildroots under /tmp/
# There is sudo rule to delete them

TO_DEL=`find /tmp -maxdepth 1 -type d -ctime +$DAYS_TO_KEEP \
 -name 'buildroot-updated-*'`

for BR in ${TO_DEL}; do
  sudo rm -rf $BR
done

# 2nd pass, delete buildroots under Jenkins workspaces.
# We need to be in label/$NODE_NAME dir to make rm work by sudo rule

find $JENKINS_HOME/workspace/ -maxdepth 1 -mindepth 1 -type d | \
while read PROJ; do
  if [ -d "$PROJ/label/$NODE_NAME" ]; then
    cd "$PROJ/label/$NODE_NAME"
    find .. -maxdepth 1 -type d -ctime +$DAYS_TO_KEEP \
      -name 'buildroot-*' -exec sudo rm -rf {} \;
  fi
done
