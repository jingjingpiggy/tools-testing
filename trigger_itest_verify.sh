#!/bin/sh -xeu
# This script should run after "OTC-Tools-Tester-itest-cases-gbs" successfully build packages
# It will try to generate a trigger file for the downstream job "itest-gbs-daily" which
# can install the latest packages and verify the change
. $(dirname $0)/kvm-worker.sh

# trigger file which contains a vaialbe of RUN_ITEST_KVM_ARGV
TRIGGER_FILE=trigger.env
GERRIT_SERVER=ssh://Gerrit/

########## for Debug {
#label=openSUSE_12.1-i586-debug
#GERRIT_SERVER=ssh://gerrit.tools
#GERRIT_EVENT_TYPE=ref-updated
#GERRIT_REFNAME=devel
#--
#GERRIT_EVENT_TYPE=patchset-created
#GERRIT_BRANCH=devel
#GERRIT_CHANGE_NUMBER=6064
#GERRIT_PATCHSET_NUMBER=1
#GERRIT_PROJECT=itest/itest-cases-gbs
#GERRIT_REFSPEC=refs/changes/64/6064/1
#cd /tmp/xx
########## for Debug }

# array of package name and corresponding project name
install_package_name=
install_package_proj=
install_package_cnt=0
add_pack() {
    install_package_proj[$install_package_cnt]=$1
    install_package_name[$install_package_cnt]=$2
    install_package_cnt=$(expr $install_package_cnt + 1)
}

# checkout source code by GERRIT_* env variables
checkout_src() {
    git init
    git fetch $GERRIT_SERVER/$GERRIT_PROJECT $GERRIT_REFSPEC
    git checkout FETCH_HEAD
}

detect_case_changes() {
    # filter tests, modified and add, ignore deleted
    # Only filter test case files inside 'cases/' directory;
    # We may have manual test case in test env but not reside in 'cases/'.
    git diff HEAD^ --name-status | grep -v '^D' | awk '{print $2}' | grep -E '^cases/.*\.case$'
}

# generate extra arguments for run-itest-kvm.sh
generate_arguments() {
    i=0
    while [ $i -lt $install_package_cnt ]; do
        proj=${install_package_proj[$i]}
        pack=${install_package_name[$i]}
        echo -n \-p $proj,$pack " "
        i=$(expr $i + 1)
    done

    if [ -n "${test_suite+defined}" ]; then
        echo -n \-t $(echo $test_suite|tr ' ' ,) " "
    fi
    echo
}

# trigger by ref-updated event, it should install test cases and test
# target from corresponding project and run "ref-updated" test suite
trigger_by_ref_updated() {
    branch=$GERRIT_REFNAME

    if [ $branch = devel ]; then
        subfix=":/Devel"
    elif [ $(echo $branch|cut -c -7) = release ]; then
        subfix=":/Pre-release"
    elif [ $branch = master ]; then
        subfix=""
    else
        echo "Only verify ref update for master,devel,release branches, not $branch."
        exit 0
    fi
    add_pack "${TEST_CASE_BASE_PROJECT}${subfix}" $TEST_CASE_PACKAGE
    add_pack "${TEST_TARGET_BASE_PROJECT}${subfix}" $TEST_TARGET_PACKAGE

    test_suite=ref-updated
}

# trigger by patchset-created, it should install tests from
# current patchset and only run changed tests
trigger_by_patchset_created() {
    branch=$GERRIT_BRANCH

    prefix=$(target_project_basename "$TEST_CASE_GERRIT_PROJECT")
    suffix="${GERRIT_CHANGE_NUMBER}.${GERRIT_PATCHSET_NUMBER}"
    projname=$(echo "home:tester:${prefix}-${suffix}"|sed 's#:#:/#g')

    add_pack "$projname" $TEST_CASE_PACKAGE

    if [ $branch = devel ]; then
        subfix=":/Devel"
    elif [ $(echo $branch|cut -c -7) = release ]; then
        subfix=":/Pre-release"
    else
        echo "Only verify patchset for devel,release branches, not $branch."
        exit 0
    fi
    add_pack "${TEST_TARGET_BASE_PROJECT}${subfix}" $TEST_TARGET_PACKAGE

    # make temp path to check file changed in that
    tmp_src=$(mktemp -d)
    trap "rm -rf $tmp_src" INT TERM EXIT ABRT
    cd $tmp_src # better to use pushd and popd

    checkout_src
    test_suite=$(detect_case_changes)
    if [ -z "$test_suite" ]; then
        test_suite=patchset-created
    fi
    cd - # better to use pushd and popd
}

usage() {
    echo "Usage: $0 <test_case_gerrit_project> <test_case_package> <test_case_base_project> <test_target_package> <test_target_base_project>"
    echo "    test_case_gerrit_project: Gerrit project name of test cases"
    echo "        for example: itest/itest-cases-gbs, itest/itest-cases-mic"
    echo
    echo "    test_case_package: package contains test cases"
    echo "        for example: itest-cases-gbs, itest-cases-mic"
    echo
    echo "    test_case_base_project: base project name for above package"
    echo "        to construct different project name for different branch."
    echo "        for example: if the base project is itest,"
    echo "        for devel branch, project name will be itest:/Devel,"
    echo "        for release branch, it will be itest:/Pre-release,"
    echo "        for master branch, it will be the same as itest"
    echo
    echo "    test_target_package: package name of test target"
    echo "        for example: gbs, mic"
    echo
    echo "    test_target_base_project: base project name for above package"
    echo "        for example: Tools"
}

################
## Main
################

set -- $(getopt h "$@")
while [ $# -gt 0 ]; do
    case "$1" in
        (-h) usage; exit 0;;
        (--) shift; break;;
        (-*) echo "Unrecognized option $1"; exit 1;;
        (*) break;;
    esac
    shift
done
if [ $# -lt 4 ]; then
    usage
    exit 1
fi
TEST_CASE_GERRIT_PROJECT=$1
TEST_CASE_PACKAGE=$2
TEST_CASE_BASE_PROJECT=$3
TEST_TARGET_PACKAGE=$4
TEST_TARGET_BASE_PROJECT=$5

#if [ -z "$label" ] || [ "$(echo $label|cut -c -7)" != "Builder" ]; then
    # Only make trigger file on Builder node, since this file only need one copy
#    exit 0
#fi

if [ $GERRIT_EVENT_TYPE = ref-updated ]; then
    trigger_by_ref_updated
elif [ $GERRIT_EVENT_TYPE = patchset-created ]; then
    trigger_by_patchset_created
else
    echo "Unsupported Gerrit event type:$GERRIT_EVENT_TYPE"
    exit 1
fi

echo -n "RUN_ITEST_KVM_ARGV=" > $TRIGGER_FILE
generate_arguments >> $TRIGGER_FILE
cat $TRIGGER_FILE
