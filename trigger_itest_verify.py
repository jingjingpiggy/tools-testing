#!/usr/bin/python
import os
import argparse
import subprocess
import sys

TESTER_PROJECT = "Tools" \
    "-%(GERRIT_PROJECT_DASH)s"  \
    "-%(GERRIT_CHANGE_NUMBER)s" \
    ".%(GERRIT_PATCHSET_NUMBER)s"

# Rules defined by developing workflow, also be implemented by OTC-Tools-Tester
# Items are (Gerrit Project, OBS Project, Packages)
CHAINS = [
    ("gbs", "Tools", ["gbs"]),
    ("mic", "Tools", ["mic", "mic-native"]),
    ("itest/itest-core", "itest", ["itest-core"]),
    ("itest/itest-cases-gbs", "itest", ["itest-cases-gbs"]),
    ("itest/itest-cases-mic", "itest", ["itest-cases-mic"]),
    ]

# Mapping from Gerrit branch to OBS sub-project
BRANCH2SUBPROJ = {
     "master": "",
      "devel": "Devel",
    "release": "Pre-release",
}

#conf.py defines your own TESTER_PROJECT, CHAINS, BRANCH2SUBPROJ
#The format of the variable is the same with the one defined above
if os.path.exists('conf.py'):
    sys.path.append(os.getcwd())
    from conf import *

# All these vars are coming from Jenkins running env
GERRIT_PROJECT = os.environ['GERRIT_PROJECT']
GERRIT_CHANGE_NUMBER = os.environ['GERRIT_CHANGE_NUMBER']
GERRIT_PATCHSET_NUMBER = os.environ['GERRIT_PATCHSET_NUMBER']
GERRIT_BRANCH = os.environ['GERRIT_BRANCH']
GERRIT_EVENT_TYPE = os.environ['GERRIT_EVENT_TYPE']

# slash is not allowed in OBS project name
os.environ['GERRIT_PROJECT_DASH'] = GERRIT_PROJECT.replace('/', '-')
GERRIT_SERVER="ssh://Gerrit/"

def find_repo(given_pack):
    "pack => repo"
    def find_chain():
        for gproj, oproj, packs in CHAINS:
            for pack in packs:
                if pack == given_pack:
                    return gproj, oproj, pack

    gproj, oproj, pack = find_chain()
    if GERRIT_EVENT_TYPE == 'patchset-created' and \
       gproj == GERRIT_PROJECT:
        return TESTER_PROJECT % os.environ

    subproj = BRANCH2SUBPROJ[GERRIT_BRANCH[:7]]
    return '%s:%s' % (oproj, subproj)

def guess_test_suite():
    "guess suite"
    if GERRIT_EVENT_TYPE == 'patchset-created' :
        suite = query_cases_changed_in_current_patchset()
        if suite:
            return suite
    return GERRIT_EVENT_TYPE

def query_cases_changed_in_current_patchset():
    "get the value of test suite"
    tmp_dir = subprocess.check_output(["mktemp", "-d"]).rstrip()
    work_dir = os.getcwd()
    os.chdir(tmp_dir)
    subprocess.check_call(["git", "init"],stdout=subprocess.PIPE)
    subprocess.check_call(['git', 'fetch', '%s/%s'%(GERRIT_SERVER, GERRIT_PROJECT), os.environ['GERRIT_REFSPEC']], stdout=subprocess.PIPE)
    subprocess.check_call(['git', 'checkout', 'FETCH_HEAD'], stdout=subprocess.PIPE)
    changed_cases=subprocess.check_output("git diff HEAD^ --name-status | grep -v '^D' | awk '{print $2}' | grep -E '^cases/.*\.case$' || true", shell=True)
    test_suite = changed_cases.replace("\n", ",")
    os.chdir(work_dir)
    return test_suite

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-p', dest='package', nargs='+',
        help='package need to be installed')
    parser.add_argument('-a', '--add', dest="addarg", action='append',
        nargs='+', help='pkg dep_repo')
    return parser.parse_args()

def main():
    args = parse_args()
    pkg_repo = {}
    for pack in args.package:
        repo = find_repo(pack).replace(':', ':/')
        #generate pkg_repo ---> { pack, [repo] }
        #if repo == TESTER_PROJECT:
        if 'Tools-' in repo:
            pkg_repo[pack] = repo.split()
        else:
            pkg_repo[pack] = [ '', repo ]
        if args.addarg != None:
        #args.addarg is a list comprised of [[ pkg1, dep_repo1 ], [pkg2, dep_repo2]]
            for pkg_deprepo in args.addarg:
                if pkg_deprepo[0] == pack:
                    #/home:/tester:/ ---->  located as $project of install_package
                    #Tools:/Devel    ---->  located as $sproject of install_package
                    if True in map(lambda i: 'Tools-' in i, pkg_repo[pack]):
                        pkg_repo[pack].append(pkg_deprepo[1])
                    else:
                        pkg_repo[pack][0] = pkg_deprepo[1]
    for pkg in pkg_repo:
        if len(pkg_repo[pkg]) == 1:
            print '-p', '%s,%s' % (pkg_repo[pkg][0], pkg),
        elif len(pkg_repo[pkg]) == 2:
            print '-p', '%s,%s,%s' % (pkg_repo[pkg][0], pkg, pkg_repo[pkg][1]),
    print '-t', guess_test_suite()

if __name__ == '__main__':
    main()
