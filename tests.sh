#!/bin/bash

push()
{
    branch=$1
    tcase=$2
    direct=$3
    git fetch
    git checkout $branch
    git reset --hard origin/$branch
    subject="`date +'%F %R:%S':` test case $tcase"
    echo "$subject" > test-case-$tcase
    git add test-case-$tcase
    git commit -m "$subject"
    if [ "$direct" = 'direct' ] ; then
        git push origin $branch
    else
        git push origin HEAD:refs/for/$branch
    fi
}

accept()
{
    branch=$1
    git checkout $branch
    change=$(echo "select change_id, patch_set_id from patch_sets where revision='`git rev-parse HEAD`';" | ssh Gerrit gerrit gsql --format json |sed -n 's/.*"change_id":"\([0-9]\+\)","patch_set_id":"\([0-9]\+\)".*/\1,\2/p')
    ssh Gerrit gerrit review --code-review +2 "$change"
    ssh Gerrit gerrit review --submit "$change"
}

title()
{
    echo
    echo '--------------------------------'
    echo "$1"
    echo '--------------------------------'
}

# Direct pushes
title '2.4 Direct push to devel'
push devel 2.4 direct
title '2.5 Direct push to release-'
push release-0.0.0 2.5 direct
title '2.6 Direct push to master'
push master 2.6 direct

# Submitting for review
title '1.1 Push for review to devel'
push devel 1.1
title '1.2 Push for review to release-'
push release-0.0.0 1.2
title '1.3 Push for review to master'
push master 1.3

# Accepting in Gerrit
declare -A tcases
tcases['devel']='2.1'
tcases['release-0.0.0']='2.2'
tcases['master']='2.3'

while true ; do
    for branch in devel release-0.0.0 master ; do
        if [ -n "${tcases[$branch]}" ] ; then
            git checkout $branch
            # make condition for the next gsql statement
            condition=$(echo "select change_id, patch_set_id from patch_sets where revision='`git rev-parse HEAD`';" | \
                ssh Gerrit gerrit gsql --format json |sed -n 's/.*"change_id":"\([0-9]\+\)","patch_set_id":"\([0-9]\+\)".*/change_id=\1 and patch_set_id=\2/p')
            # check if change is verified by Tester
            echo "select value from PATCH_SET_APPROVALS where $condition and category_id='VRIF';" | \
                ssh Gerrit gerrit gsql --format=json |grep -q '"rowCount":1'
            if [ $? -eq 0 ] ; then
                # change is verified - accepting
                title "${tcases[$branch]} Accept change in Gerrit for $branch branch"
                accept $branch
                tcases[$branch]=''
            else
                echo "branch $branch: change is not verified yet, sleeping 60 sec ..."
            fi
        fi
    done
    if [ -z "${tcases['master']}" -a -z "${tcases['devel']}" -a -z "${tcases['release-0.0.']}" ] ; then
        break
    fi
    sleep 60
done
