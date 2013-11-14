#!/usr/bin/env python
"This script aggregate results from subprojects and make a summary"
import argparse
from collections import defaultdict

from .imgutil import Snapshot, URL


def aggregate(results):
    """Aggregate all results like this:
    Image: mobile
    ImageType: loop
    Result: Regression
    MicVersion: 0.22
    Distribution: openSUSE-12.3-x86_64
    KSURL: http://xxx/pub/mirrors/tizen/snapshots/tizen/mobile/tizen_20131114.2/images/mobile/mobile.ks
    SnapshotURL: http://xxx/pub/mirrors/tizen/snapshots/tizen/mobile/tizen_20131114.2
    LogURL: xx
    """
    if not results:
        return
    micver = results[0]['MicVersion']
    rtype = lambda i: 'Diff' if i.startswith('Diff') else i

    count = defaultdict(int)
    for i in results:
        count[rtype(i['Result'])] += 1

    def cmp_result(res1, res2):
        "compare result"
        order = {'Regression': 1,
            'Diff': 2,
            'Repeat': 2,
            'Fixed': 3,
            'Passed': 4,
            }
        ret = cmp(order.get(rtype(res1['Result'])),
            order.get(rtype(res2['Result'])))
        if ret == 0:
            return cmp(res1['SnapshotURL'], res2['SnapshotURL'])
        return ret
    results.sort(cmp_result)

    print '#'*50
    print '##'
    print '##', 'Aggregate results of PreDeployment testing'
    print '##'
    print '#'*50
    print 'Summary:', ' '.join(['%s(%d)'%(k, v) for k, v in count.items()])
    print 'Version:', micver
    print
    for i in results:
        print '[%s] %s: %s' % (i['Result'], i['Image'], i['Reason'])
        shot = Snapshot(URL(i['SnapshotURL']))
        print 'Infra:', shot.infra
        print 'Product:', shot.product
        print 'Snapshot:', shot.baseurl
        print 'KS:', i['KSURL']
        print 'Log:', i['LogURL']
        print
    print '#'*50


def load(filename):
    "Load reuslt from filename"
    with open(filename) as reader:
        lines = reader.readlines()
    res = {}
    for line in lines:
        key, val = line.split(':', 1)
        res[key.strip()] = val.strip()
    return res

def parse_args():
    "Parse arguments"
    parser = argparse.ArgumentParser()
    parser.add_argument('results', nargs='+')
    return parser.parse_args()

def main():
    "Main"
    args = parse_args()
    results = [ load(i) for i in args.results ]
    aggregate(results)



if __name__ == '__main__':
    main()
