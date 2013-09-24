#!/bin/sh

# This is used after HDA seed updater script produces set of
# updated images named kvm-seed-hda-REPO-ARCH-debug.new
# No arguments are needed, all such files are deployed in all workers

. /etc/jenkins-worker/workers.env

cd $JENKINS_HOME
IMAGES=`ls kvm-seed-hda-*-debug.new`
for IMG in $IMAGES; do
  echo img=$IMG
  deploy-one-new-hda-to-all-workers.sh $IMG
done
