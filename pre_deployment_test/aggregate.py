#!/usr/bin/env python
"This script aggregate results from subprojects and make a summary"

import argparse
import datetime
from collections import defaultdict as dd, namedtuple

from jinja2 import Environment, PackageLoader

from .imgutil import Snapshot, URL


level3dict = lambda : dd(dict)
level4dict = lambda : dd(level3dict)
level5dict = lambda : dd(level4dict)
level6dict = lambda : dd(level5dict)


def summary(result_list):
    assert len(result_list) > 0
    try:
        mic_version = result_list[0]['MicVersion'].split('(')[0]
    except (IndexError, KeyError) as e:
        mic_version = ''
    result_count = len(result_list)
    pass_count = failed_count = repeat_count = fixed_count = 0
    for res in result_list:
        result = res.get('Result', '').strip()
        if result == 'Passed' or result.lower().find('diff') != -1:
            pass_count += 1
        elif result == 'Regression':
            failed_count += 1
        elif result == 'Fixed':
            fixed_count += 1
        elif result == 'Repeat':
            repeat_count += 1

    return {
        'Version': mic_version,
        'Report Time': datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        'Total': result_count,
        'Passed': pass_count,
        'Failed': failed_count,
        'Repeat': repeat_count,
        'Fixed': fixed_count,
        }


def detail(result_list):
    TD = namedtuple('TD', 'text rows_span title href css')

    def make_column_first_matrix(data):
        def _get_value(name, value, target):
            for res in result_list:
                if res[name] == value:
                    return res[target]

        def _css(result):
            res = result.get('Result', '')
            if res in ('Passed', 'Fixed'):
                return 'success'
            if res in ('Regression',):
                return 'failed'
            return 'warning'

        cmatrix = dd(list) # column first matrix

        # Column 1: Infrastructure
        for infra in data:
            td = TD(infra, count(infra), '', '', '')
            cmatrix[0].append(td)

        # Column 2: Product
        for infra , d1 in data.items():
            for product in d1:
                td = TD(product, count(infra, product), '', '', '')
                cmatrix[1].append(td)

        # Column 3: Snapshot
        for infra, d1 in data.items():
            for pro, d2 in d1.items():
                for snap in d2:
                    snap_link = _get_value('BuildID', snap, 'SnapshotURL')
                    td = TD(snap, count(infra, pro, snap), '', snap_link, '')
                    cmatrix[2].append(td)

        # Column 4: Image
        for infra, d1 in data.items():
            for pro, d2 in d1.items():
                for snap, d3 in d2.items():
                    for img, d4 in d3.items():
                        link = _get_value('Image', img, 'KSURL')
                        td = TD(img, 1, '', link, '')
                        cmatrix[3].append(td)


        # Column 5+: All distributions
        for i, dist in enumerate(distros):
            for infra, d1 in data.items():
                for pro, d2 in d1.items():
                    for snap, d3 in d2.items():
                        for img, d4 in d3.items():
                            result = d4.get(dist)
                            if result:
                                td = TD(result.get('Result', ''),
                                        1,
                                        result.get('Reason', ''),
                                        result.get('LogURL', ''),
                                        _css(result))
                            else:
                                td = TD('', 1, '', '', '')
                            cmatrix[4+i].append(td)
        return cmatrix

    def transpose_column_first_to_row_first(cmatrix):
        rmatrix = dd(dict) # row first matrix
        for j, col in cmatrix.items():
            i = 0
            for td in col:
                rmatrix[i][j] = td
                i += td.rows_span
        return rmatrix

    def make_multi_layers_dict():
        distros = set()
        data = level6dict()
        for res in result_list:
            infra = res.get('Infra', '')
            product = res.get('Product', '')
            buildid = res.get('BuildID', '')
            image = res.get('Image', '')
            distro = res.get('Distribution', '')

            distros.add(distro)
            data[infra][product][buildid][image][distro] = res

        distros = sorted(distros)
        return data, distros

    def make_row_count_helper(data):
        return [(infra, product, buildid, image)
            for infra, d2 in data.iteritems()
                for product, d3 in d2.iteritems()
                    for buildid, d4 in d3.iteritems()
                       for image in d4]

    # main start -----------------------
    data, distros = make_multi_layers_dict()

    helper = make_row_count_helper(data)
    def count(*key):
        return sum([ (row[:len(key)] == key) for row in helper ])

    thead = ['Infrastructure',
             'Product',
             'Snapshot',
             'Image'] + distros
    cmatrix = make_column_first_matrix(data)
    tbody = transpose_column_first_to_row_first(cmatrix)

    return {
        'thead': thead,
        'tbody': tbody,
        }


def html_report(results):
    env = Environment(loader=PackageLoader('pre_deployment_test', 'templates'))
    template = env.get_template('report.html')
    html = template.render(
        summary=summary(results),
        **detail(results))
    with open('index.html', 'w') as fobj:
        fobj.write(html)

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
    html_report(results)

if __name__ == '__main__':
    main()
