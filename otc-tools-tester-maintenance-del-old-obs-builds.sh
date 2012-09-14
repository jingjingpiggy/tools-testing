#!/bin/sh

# OBS_PROJECT_NAME and BUILDS_TO_KEEP are Jenkins job arguments

echo "will trigger OBS clean of $OBS_PROJECT_NAME, keeping $BUILDS_TO_KEEP recent builds"

TO_DEL=`osc ls / | grep -e "^$OBS_PROJECT_NAME-[[:digit:]]\+$" | sort -Vr | tail -n+$BUILDS_TO_KEEP`
for P in ${TO_DEL}; do
  osc rdelete -r $P -m "Removed $P"
done
