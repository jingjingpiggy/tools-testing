#!/bin/sh

set -eu

if [ $# -lt 2 ]; then
  echo "2 args needed: BUILDROOT_SEED BUILDROOT"
  exit 1
fi

BUILDROOT_SEED=$1
BUILDROOT=$2

# Unpack buildroot.tar
sudo tar -xf "$BUILDROOT_SEED"
sudo mv buildroot "$BUILDROOT"
