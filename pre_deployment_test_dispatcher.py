#!/usr/bin/env python
'''This script search KS recursively from given image URL.
For each KS file found, it generate a trigger file which
will trigger a sub Jenkins project.
'''
import re
import os
import sys
import urllib
import urlparse
import argparse

from urlgrabber.grabber import URLGrabber, URLGrabError


class URL(object):
    '''URL object with corresponding user and password'''

    def __init__(self, url, user, passwd,
                 infrastructure, vertical, buildid):
        self.url, self.user, self.passwd = url, user, passwd
        self.infrastructure = infrastructure
        self.vertical = vertical
        self.buildid = buildid

    def __str__(self):
        '''String represent this url without user and password'''
        return self.url

    def full(self):
        '''return url embeded with user and passwd'''
        if not self.user or not self.passwd:
            return self.url

        parts = urlparse.urlsplit(self.url)

        userpass = '%s:%s' % (urllib.quote(self.user, safe=''),
                              urllib.quote(self.passwd, safe=''))
        netloc = '%s@%s' % (userpass, parts[1])
        comps = list(parts)
        comps[1] = netloc

        return urlparse.urlunsplit(comps)

    def join(self, *parts):
        '''url join'''
        return URL(os.path.join(self.url, *parts),
            self.user,
            self.passwd,
            self.infrastructure,
            self.vertical,
            self.buildid)

    @staticmethod
    def read(urlfile):
        '''Read URL info from urlfile in format of key/value pairs
        This file should contains information such as url address, user
        and password, infrastructure name, veritical name and build id
        '''
        info = {
            'user': None,
            'passwd': None,
            }
        for line in open(urlfile):
            if line.startswith('#'):
                continue
            line = line.rstrip()
            key, val = [ i.strip() for i in line.split('=', 1) ]
            info[key] = val

        for key in ('url', 'infrastructure', 'vertical', 'buildid'):
            if key not in info:
                raise Exception("Field %s is missing from urlfile %s"
                    % (key, urlfile))

        return URL(info['url'],
            info['user'],
            info['passwd'],
            info['infrastructure'],
            info['vertical'],
            info['buildid'])

    def write(self, filename):
        '''Gernerate a trigger file for the given URL
        '''
        data = '''url=%s
user=%s
passwd=%s
infrastructure=%s
vertical=%s
buildid=%s
''' % (self.url, self.user or '', self.passwd or '',
        self.infrastructure, self.vertical, self.buildid)

        with open(filename, 'w') as fileobj:
            fileobj.write(data)


class URLDirectoryService(object):
    '''Provide several API to query and fetch URL directores and files
    '''
    SOCKET_TIMEOUT = 60 * 10

    # we think that link with same text and href is a subdir
    SUBDIR_PATTERN = re.compile(r'<a .*?href=(["\'])(.*?)\1.*?>(.*?)</a>')

    _grabber = None

    def parse_dir(self, page):
        '''Parse html page return sub-directory names'''
        dirs = []
        for _quote, href, text in re.findall(self.SUBDIR_PATTERN, page):
            if href == text:
                dirs.append(text.rstrip('/'))
        return dirs

    def listdir(self, url):
        '''give a url return all its sub directories'''
        # we have to add a '/' at the end of url like here, otherwise sever
        # will raise 401 error
        url.url = url.url.rstrip('/') + '/'

        response = self.open(url)
        if response:
            return self.parse_dir(response.read())
        return []

    @staticmethod
    def join(base, *parts):
        '''join url path components'''
        return base.join(*parts)

    def open(self, url):
        '''open an url and return a file-like object'''
        try:
            return self.grabber.urlopen(url.full(),
                                        ssl_verify_host=False,
                                        ssl_verify_peer=False,
                                        http_headers=(('Pragma', 'no-cache'),),
                                        quote=0,
                                        timeout=self.SOCKET_TIMEOUT,
                                        )
        except URLGrabError, err:
            # 14 - HTTPError (includes .code and .exception attributes)
            if err.errno == 14:
                if err.code == 404:
                    print >> sys.stderr, 'No such url:404:%s' % url
                    return None
                elif err.code == 401:
                    print >> sys.stderr, 'Auth error:%s:%s' % (url, url.user)
                else:
                    print >> sys.stderr, 'URL error:%s:%s' % (url, err)
            raise

    def grab(self, url, path):
        '''grab url and save it as path'''
        # urlgrab returns a path which will be different from pass-in path, but
        # it only occurs when copy_local==0 and url starts with file://, so we
        # ignore this case here. We assume that pass-in path will always equals
        # to the returned path.
        return self.grabber.urlgrab(url.full(), path,
                                    ssl_verify_host=False,
                                    ssl_verify_peer=False,
                                    http_headers=(('Pragma', 'no-cache'),),
                                    quote=0,
                                    timeout=self.SOCKET_TIMEOUT,
                                    )

    @property
    def grabber(self):
        '''only created one time for each service object'''
        if self._grabber is None:
            self._grabber = URLGrabber()
        return self._grabber


TRIGGER_ID = 0
def next_trigger_filename():
    '''Generate sequence of trigger filenames'''
    global TRIGGER_ID
    name = 'trigger_%d.env' % TRIGGER_ID
    TRIGGER_ID += 1
    return name


def grab_all_ks(url):
    '''Grab all images start from this url
    For exmaple:
    http://download.tizen.org/snapshots/tizen/ivi/latest/images/
    http://download.tizen.org/snapshots/tizen/ivi/tizen_20130910.9/images/
    http://download.tizen.org/snapshots/tizen/mobile/latest/images/

    It will search and download all KS files recursively
    '''
    serv = URLDirectoryService()
    for profile in serv.listdir(url):
        path = serv.join(url, profile)
        for filename in serv.listdir(path):
            if filename.endswith('.ks'):
                ksurl = serv.join(path, filename)
                trigger_filename = next_trigger_filename()
                ksurl.write(trigger_filename)
                print 'found ks', filename, '->', trigger_filename


def parse_args():
    '''Parser command line arguments'''
    def filename_type(param):
        '''Argument of file name type'''
        if os.path.exists(param):
            return os.path.abspath(param)
        raise argparse.ArgumentError("Can't found %s" % param)

    parser = argparse.ArgumentParser()
    parser.add_argument('urlfile', nargs='+', type=filename_type,
        help='file name contains url info')
    return parser.parse_args()


def main():
    '''Main'''
    opts = parse_args()
    urls = [URL.read(i) for i in opts.urlfile]
    for url in urls:
        print 'search', url
        grab_all_ks(url)


if __name__ == '__main__':
    main()
