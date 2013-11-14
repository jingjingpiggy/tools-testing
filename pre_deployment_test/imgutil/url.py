"This module provides URL component to parse and download http url"
import os
import re
import time
import base64
import urllib
import urllib2
from subprocess import check_call
from urlparse import urlsplit, urlunsplit
from collections import namedtuple

__ALL__ = ('URL', )


class URL(namedtuple("URL", "href user passwd full netloc path basename")):
    "Represent URL with user and passwd"

    def __new__(cls, href, user=None, passwd=None):
        "Immutable object"
        href, user1, passwd1 = split_userpass(href)
        if not user:
            user = user1
        if not passwd:
            passwd = passwd1

        full = join_userpass(href, user, passwd)
        parts = urlsplit(href)
        netloc, path = parts[1], parts[2]
        basename = os.path.basename(path.rstrip('/'))

        return super(URL, cls).__new__(cls,
            href, user, passwd,
            full,
            netloc, path, basename)

    def __str__(self):
        "Overwrite default string method of tuple"
        return self.href

    def join(self, *args):
        "Join url parts and reduce them"
        path = os.path.normpath(os.path.join(self.path, *args))
        return self._replace_path(path)

    @property
    def prefixes(self):
        """Returns all prefixes URLs including self.
        Self is the first and root is the last.
        """
        dirs = self.path.rstrip('/').split('/')
        count = len(dirs)
        for i in range(count):
            yield self._replace_path('/'.join(dirs[:count-i]))

    #-------------------------------
    def exists(self):
        "Check whether this exists"
        def head():
            "HTTP HEAD request"
            req = self._make_request()
            req.get_method = lambda : 'HEAD'
            return urllib2.urlopen(req)

        #retry for networking error
        tries = 2
        for i in range(tries):
            try:
                res = head()
            except urllib2.HTTPError as err:
                if err.code == 404:
                    return False
                elif i < tries - 1:
                    time.sleep(1)
                    continue
                else:
                    raise
            except urllib2.URLError:
                if i < tries - 1:
                    time.sleep(1)
                    continue
                else:
                    raise
            else:
                break
        return False if res.code == 404 else True

    def asdir(self):
        "the tailing / is required for our server"
        return self._replace_path(self.path + '/')

    def listdir(self):
        "Generator yields all children as URL classes"
        for path in self._parse_dir(self.asdir().fetch()):
            if path not in ('..', '../'):
                yield self.join(path)

    def fetch(self):
        "Returns HTTP response body"
        return urllib2.urlopen(self._make_request()).read()

    def download(self, localfile, verbosity=1):
        "Download this to local file"
        vopt = {0: '-q', 1: '-nv', 2: '-v'}.get(verbosity, 1)
        cmd = ['wget', vopt, '-O', localfile]
        if self.user:
            cmd.extend(['--user', self.user])
        if self.passwd:
            cmd.extend(['--password', self.passwd])
        cmd.append(self.href)
        return check_call(cmd)

    #-------------------------------
    def _replace_path(self, path):
        "Clone self and update path"
        parts = list(urlsplit(self.href))
        parts[2] = path
        href = urlunsplit(parts)
        return URL(href, self.user, self.passwd)

    # we assume that link with same text and href is a subdir
    # \1 is quote
    # \2 href and text
    SUBDIR_PATTERN = re.compile(r'<a .*?href=(["\'])(.*?)\1.*?>\2</a>')
    def _parse_dir(self, page):
        '''Parse html page return sub-directory names'''
        for _quote, href_or_text in re.findall(self.SUBDIR_PATTERN, page):
            yield href_or_text.strip()

    def _make_request(self):
        "Make urllib2.Request object"
        req = urllib2.Request(self.href)
        if self.user and self.passwd:
            auth = base64.encodestring('%s:%s'
                % (self.user, self.passwd)).rstrip()
            req.add_header("Authorization", "Basic %s" % auth)
        return req


def join_userpass(href, user, passwd):
    "Return authenticated URL with user and passwd embeded"
    if not user and not passwd:
        return href

    if passwd:
        userpass = '%s:%s' % (urllib.quote(user, safe=''),
                              urllib.quote(passwd, safe=''))
    else:
        userpass = urllib.quote(user, safe='')

    parts = urlsplit(href)
    netloc = '%s@%s' % (userpass, parts[1])
    comps = list(parts)
    comps[1] = netloc
    return urlunsplit(comps)

def split_userpass(href):
    "Returns (href, user, passwd) of an authenticated URL"
    parts = urlsplit(href)
    netloc = parts[1]
    if '@' not in netloc:
        return href, None, None

    userpass, netloc = netloc.split('@', 1)
    if ':' in userpass:
        user, passwd = [ urllib.unquote(i)
                           for i in userpass.split(':', 1) ]
    else:
        user, passwd = userpass, None

    comps = list(parts)
    comps[1] = netloc
    return urlunsplit(comps), user, passwd
