#!/bin/sh -eu
. $(dirname $0)/kvm-worker.sh

Cleanup () {
 test "${SRC_TMPCOPY+defined}" && rm -fr $SRC_TMPCOPY
 date
}

additional_init() {
    # this function will be called when kvm images are ready
    # to do some additional initial work
    BUILDHOME=$1

    # create run script that will be auto-started in Virtual machine
    cat >> $BUILDHOME/run << EOF
TESTREQ_PACKAGES=""
EXTRA_REPOS="${EXTRA_REPOS:=}"
TEST_REQUIRES="${TEST_REQUIRES:=}"
if [ -x $TARGETBIN/otc-tools-tester-system-what-release.sh ]; then
  OSREL=\`$TARGETBIN/otc-tools-tester-system-what-release.sh\`
  OSREL2=\`echo \$OSREL | sed s/-/_/g\`
  if [ -n "\$TEST_REQUIRES" ]; then
    TESTREQ_PACKAGES=\`echo "\$TEST_REQUIRES" | egrep "^(\$OSREL|\$OSREL2)\\s*:" | cut -d':' -f 2\`
  elif [ -f /home/build/$SRCDIR/packaging/.test-requires ]; then
    TESTREQ_PACKAGES=\`egrep "^(\$OSREL|\$OSREL2)\\s*:" /home/build/$SRCDIR/packaging/.test-requires | cut -d':' -f 2\`
  fi
  if [ -n "\$EXTRA_REPOS" ]; then
    EXTRA_REPOS=\`echo "\$EXTRA_REPOS" | egrep "^(\$OSREL|\$OSREL2)\\s*:" | cut -d':' -f 2-\`
  elif [ -f /home/build/$SRCDIR/packaging/.extra-repos ]; then
    EXTRA_REPOS=\`egrep "^(\$OSREL|\$OSREL2)\\s*:" /home/build/$SRCDIR/packaging/.extra-repos | cut -d':' -f 2-\`
  fi
fi
try=1
while [ \$try -lt 5 ]
do
 echo "====== Starting \$try. attempt to install packages"
 if $TARGETBIN/install_package "$TARGET_PROJECT_NAME" "$OBS_REPO" "$PACKAGES" "$SPROJ" "\$TESTREQ_PACKAGES" "\$EXTRA_REPOS" ""
   then break
 fi
 try=\$((try + 1))
 sleep 5
done
[ \$try -gt 4 ] && exit 1
su - build -c "timeout 60m $TARGETBIN/run_tests /home/build/$SRCDIR /home/build/reports/ 2>&1"
EOF

    # mv source tree from temp.copy to VM /home/build, checking size
    need_kb=`du -s $SRC_TMPCOPY/$SRCDIR | cut -f1`
    have_kb=`df -P $BUILDHOME | tail -1 | awk '{print $4}'`
    if [ $need_kb -gt $have_kb ]; then
      echo "*** Source ($need_kb KB) does not fit in data volume ($have_kb KB available)!"
      exit 1
    fi

    mv "$SRC_TMPCOPY/$SRCDIR" $BUILDHOME/
}

role=$OBS_REPO

if [ "$role" != "Builder" ]; then
    at_exec Cleanup
fi

if [ $# -lt 2 ]; then
  echo "Usage: PACKAGE SOURCE_PROJECT [-m KVM_MEMSZ] [-s NAME_SUFFIX] [-u GIT_URL]"
  exit 1
fi

NAME_SUFFIX=""
GIT_URL=""
SKIP_DISABLED_BUILDS=""
eval set -- $(getopt -l skip-disabled -o s:u:m: -- "$@")
while [ $# -gt 0 ]
do
    case "$1" in
    (-u) GIT_URL=$2; shift;;
    (-s) NAME_SUFFIX=$2; shift;;
    (-m)
         KVM_MEMSZ=$2
         check_kvm_args
         shift
         ;;
    (--skip-disabled) SKIP_DISABLED_BUILDS=1;;
    (--) shift; break;;
    (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
    (*)  break;;
    esac
    shift
done

PACKAGE=$1
MAIN_PROJECT=$2

date
SOURCE_PROJECT=''
SUFFIX="$BUILD_NUMBER"
if test "${GERRIT_CHANGE_NUMBER+defined}" ; then
    if [ -n "$GERRIT_CHANGE_NUMBER" -a -n "$GERRIT_PATCHSET_NUMBER" ] ; then
        SUFFIX="$GERRIT_CHANGE_NUMBER.$GERRIT_PATCHSET_NUMBER"
    fi
fi

if [ -n "${GERRIT_REFNAME+defined}" ] ; then
    EVENT="ref updated"
    BRANCH_PREFIX=`echo $GERRIT_REFNAME|cut -f1 -d-`
    REF_TO_FETCH=$GERRIT_REFNAME
    if [ "$BRANCH_PREFIX" = "test" ] ; then
        # Set variables needed for linked project creation
        GERRIT_BRANCH=`echo $GERRIT_REFNAME|cut -f2 -d-`
        SUFFIX=$GERRIT_REFNAME
    fi
elif [ -n "${GERRIT_REFSPEC+defined}" ] ; then
    EVENT="patchset created"
    BRANCH_PREFIX=`echo $GERRIT_BRANCH|cut -f1 -d-`
    REF_TO_FETCH=$GERRIT_REFSPEC
else
    echo 'GERRIT_REFNAME and GERRIT_REFSPEC are undefined.'
    exit 1
fi

if [ "$BRANCH_PREFIX" != "devel" -a "$BRANCH_PREFIX" != "master" \
     -a "$BRANCH_PREFIX" != "release" -a "$BRANCH_PREFIX" != "test" ] ; then
    echo 'Ref $BRANCH_PREFIX is not supported.'
    exit 1
fi

show_heading "     Get source and reset git state:"
set -x
# Get source tree and reset it to proper REF
SRCDIR=`echo $GERRIT_PROJECT |sed 's/.*\/\([^/]\+\)/\1/'`
if [ ! -d "$SRCDIR/.git" ] ; then
    [ -d "$SRCDIR" ] && rm -rf $SRCDIR
    git clone ssh://Gerrit/$GERRIT_PROJECT
fi
cd $SRCDIR
git clean -xdf
git fetch origin $REF_TO_FETCH
git reset --hard FETCH_HEAD
git submodule sync
git submodule update --init

if [ "$EVENT" = 'ref updated' -a "$BRANCH_PREFIX" != "test" ] ; then # ref updated - upload to base
    TARGET_PROJECT_NAME=""
    # branch -> target repo mapping
    [ "$GERRIT_REFNAME" = "master" ] && TARGET_PROJECT=$MAIN_PROJECT
    [ "$GERRIT_REFNAME" = "devel" ] && TARGET_PROJECT="$MAIN_PROJECT:Devel"
    [ "$BRANCH_PREFIX" = "release" ] && TARGET_PROJECT="$MAIN_PROJECT:Pre-release"
    INSTALL_PACKAGES_FROM=$TARGET_PROJECT
    SPROJ=`echo "$TARGET_PROJECT" | sed 's/:/:\//g'`
else # patchset created or test-<target branch> ref updated - upload to the linked project
    # branch -> source repo mapping
    [ "$GERRIT_BRANCH" = "master" ] && SOURCE_PROJECT=$MAIN_PROJECT
    [ "$GERRIT_BRANCH" = "devel" ] && SOURCE_PROJECT="$MAIN_PROJECT:Devel"
    [ "$BRANCH_PREFIX" = "release" -o "$GERRIT_BRANCH" = "release" ] && SOURCE_PROJECT="$MAIN_PROJECT:Pre-release"
    INSTALL_PACKAGES_FROM=$SOURCE_PROJECT
    TBNAME=$(target_project_basename "$GERRIT_PROJECT")
    TARGET_PROJECT_NAME="$TBNAME$NAME_SUFFIX-$SUFFIX"
    TARGET_PROJECT="home:tester:$TARGET_PROJECT_NAME"
    SPROJ=`echo "$SOURCE_PROJECT" | sed 's/:/:\//g'`
fi

if [ "$role" != "Builder" ]; then
    # copy source tree to temp.copy
    SRC_TMPCOPY=`mktemp -d`
    cp -a "../$SRCDIR" $SRC_TMPCOPY
else
    # Submit packages to OBS
    if [ -d packaging ] ; then
        pkg_dir=packaging
    elif [ -d rpm ] ; then
        pkg_dir=rpm
    else
        echo "Error: No packaging directory found"
        exit 1
    fi
    # Prepare packaging
    if [ -n "$GIT_URL" ]; then
       # if GIT_URL is provided create _service file for git-bildpackage source service
       revision=`git rev-parse FETCH_HEAD`
       echo "<services><service name='git-buildpackage'><param name='revision'>$revision</param><param name='url'>$GIT_URL</param></service></services>" > $pkg_dir/_service
       files="$pkg_dir/_service"
    elif [ -f $pkg_dir/Makefile ] ; then
       # If not - use make in packaging/
       make -C $pkg_dir all
       files="$pkg_dir/*"
    else
       echo "Error: No $pkg_dir/Makefile and no GIT_URL provided"
       exit 1
    fi

    # Builder uses fake reports to keep Jenkins reports processing happy
    mkdir -p "$WORKSPACE/reports"
    cp $JENKINS_HOME/coverage.xml-fake "$WORKSPACE"/reports/coverage.xml
    cp $JENKINS_HOME/nosetests.xml-fake "$WORKSPACE"/reports/nosetests.xml
    set +e
    arg_projects="--tproject $TARGET_PROJECT"
    [ -n "$SOURCE_PROJECT" ] && arg_projects="--sproject $SOURCE_PROJECT $arg_projects"
    set +x
    show_heading "     Send to OBS for building:"
    set -x
    timeout 60m build-package $arg_projects --package "$PACKAGE" $files
    buildval=$?
    [ -f $pkg_dir/_service ] && rm $pkg_dir/_service
    exit $buildval
fi

# Check if the repository exists
if ! safeosc repos "$TARGET_PROJECT" | grep -q -e "^$OBS_REPO\s\s*$OBS_ARCH"; then
    echo "Target $OBS_REPO/$OBS_ARCH does not exist in $TARGET_PROJECT, skipping testing"
    exit 0
fi

# Get OBS build status
set +x
show_heading "     OBS build status:"
set -x
BSTAT=`safeosc results -r "$OBS_REPO" -a "$OBS_ARCH" "$TARGET_PROJECT" $PACKAGE | awk '{print $NF}'`

if [ "$BSTAT" = "disabled" -a "$SKIP_DISABLED_BUILDS" ]; then
    echo "Build of $PACKAGE in $OBS_REPO/$OBS_ARCH is disabled, skipping testing"
    exit 0
fi

if [ "$BSTAT" = "excluded" ]; then
    echo "$PACKAGE in $OBS_REPO/$OBS_ARCH is excluded, skipping testing"
    exit 0
fi

# Get OBS build log and show it
set +x
show_heading "     OBS build log:"
set -x
safeosc remotebuildlog "$TARGET_PROJECT" $PACKAGE "$OBS_REPO" "$OBS_ARCH"

if [ "$BSTAT" = "failed" ]; then
    echo "Error: package build status is $BSTAT, build FAILED"
    exit 1
fi

# Get list of packages to be installed
set +x
show_heading "     OBS packages to be installed:"
set -x
safeosc ls -b "$INSTALL_PACKAGES_FROM" -r "$OBS_REPO" -a "$OBS_ARCH" > "$WORKSPACE/packages.list"
PACKAGES=`sed -n 's/^\(.*\)\.\(deb\|rpm\|pkg.tar.xz\)$/\1/p' "$WORKSPACE/packages.list"|tr '\n' ' '`
if [ -z "$PACKAGES" ]; then
  echo "Error: No packages listed in OBS project $INSTALL_PACKAGES_FROM"
  exit 1
fi

prepare_kvm $label additional_init
launch_kvm
copy_back_from_kvm
