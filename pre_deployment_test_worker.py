#!/usr/bin/env python
'''This script accepts an URL of KS file, replace its repo macro and try
to run mic against this KS file in KVM. Finally it will copy log files
back and generate a xunit report xml.
'''
import os
import re
import time
import sys
import argparse
import subprocess

from pre_deployment_test_dispatcher import  URL, URLDirectoryService


RUN_MIC_IN_KVM_SH = os.path.join(os.path.dirname(os.path.realpath(__file__)),
    'run-mic-in-kvm.sh')

_CODEC = 'utf8'
_ILLEGAL_XML_CHARS_RE = \
    re.compile(u'[\x00-\x08\x0b\x0c\x0e-\x1F\uD800-\uDFFF\uFFFE\uFFFF]')


def replace_repo_macro(url, before, after):
    '''modify repo in ks file, make sure its reference is the same with
        where it is download'''

    prefix = url.url.split('/images/')[0]
    def _replace(line):
        '''replace BUILD_ID and insert user/passwd'''
        if line.find('@BUILD_ID@') > 0:
            line = re.sub(r'(--baseurl=).*@BUILD_ID@',
                          r'\1%s' % prefix,
                          line)

        if url.user and url.passwd:
            line = re.sub(r'(--baseurl=.*://)',
                          r'\1%s:%s@' % (url.user, url.passwd),
                          line)
        return line

    with open(after, 'w') as tofile:
        with open(before) as fromfile:
            for line in fromfile:
                if line.startswith('repo '):
                    line = _replace(line)
                tofile.write(line)


def escape_log(log):
    '''Escape some control characters which can't be recognized by xml.
    '''
    utext = log.decode(_CODEC, 'ignore')
    utext = escape_xml_illegal_chars(utext, '')
    return utext


def escape_xml_illegal_chars(val, replacement='?'):
    '''Replace special characters with value of replacement.

    x0 - x8 | xB | xC | xE - x1F
    (most control characters, though TAB, CR, LF allowed)
    xD800 - #xDFFF
    (unicode surrogate characters)
    xFFFE | #xFFFF |
    (unicode end-of-plane non-characters)
    >= 110000
    that would be beyond unicode!!!
    '''
    return _ILLEGAL_XML_CHARS_RE.sub(replacement, val)


def run_mic_in_kvm(ks_file, args):
    '''Call run-mic-in-kvm.sh to run mic inside KVM
    '''
    argv = [RUN_MIC_IN_KVM_SH, ks_file]
    argv.extend(args)

    start = time.time()
    try:
        status = subprocess.check_call(argv)
    except subprocess.CalledProcessError as err:
        print >> sys.stderr, str(err)
        status = 1
    except Exception:
        import traceback
        traceback.print_exc()
        status = -1
    cost = time.time() - start

    result = {
        'time': cost,
        'success': status == 0,
        }

    if status != 0:
        # this file contains all output and error when create image
        logfile = './reports/console.log'
        if os.path.exists(logfile):
            log = escape_log(open(logfile).read())
        else:
            log = "Unknown error since log file %s can't be found" % logfile
        result['log'] = log

    return result


def generate_xunit_report(result):
    '''Generate a report in xUnit format which treat each
    ks file as a test case
    '''
    xml = ['<?xml version="1.0" encoding="utf8"?>',
           '<testsuite>',
           ]
    if result['success']:
        xml.append(
            '<testcase classname="%(classname)s" name="%(name)s" '
            'time="%(time).3f" />'
            % result)
    else:
        xml.append(
            '<testcase classname="%(classname)s" name="%(name)s" '
            'time="%(time).3f">'
            '<failure message="%(message)s"><![CDATA[%(log)s]]>'
            '</failure></testcase>'
            % result)

    xml.append('</testsuite>')
    xml = '\n'.join(xml)

    xml_filename = 'report.xml'
    with open(xml_filename, 'w') as xmlfile:
        xmlfile.write(xml.encode(_CODEC))


def parse_args():
    '''Parse command line arguments'''
    parser = argparse.ArgumentParser()
    parser.add_argument('ksurl', help='URL point to a ks file')
    parser.add_argument('classname', help='test case class name')
    parser.add_argument('name', help='test case name')
    parser.add_argument('--user', help='user for ks url')
    parser.add_argument('--password', help='password for ks url')

    args, remaining = parser.parse_known_args()
    if '--' in remaining:
        remaining = remaining[remaining.index('--')+1:]

    return args, remaining


def main():
    '''Main'''
    args, remaining = parse_args()
    url = URL(args.ksurl, args.user, args.password, '', '', '')

    ks_filename = os.path.basename(url.url)
    origin = ks_filename + '.origin'
    serv = URLDirectoryService()
    serv.grab(url, origin)

    replace_repo_macro(url, origin, ks_filename)

    result = run_mic_in_kvm(ks_filename, remaining)
    result.update({
        'classname': args.classname,
        'name': args.name,
        'message': 'KS url: %s' % url.url,
        })

    generate_xunit_report(result)
    sys.exit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()
