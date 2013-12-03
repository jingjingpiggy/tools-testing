"""This module provides Snapshot related classes
to easily handle download server html pages
"""
import os
import re
import argparse

from .url import URL
from .uncompress import is_compressive_file


class Snapshot(object):
    "A Snapshot"
    def __init__(self, basedir):
        self.baseurl = basedir
        self.builid = self.baseurl.basename
        self.infra = self.baseurl.netloc
        self.product = self.baseurl.join('..').basename

    def images(self):
        "Returns all images"
        for path in self.baseurl.join('images/').listdir():
            yield Image(path)

    @classmethod
    def find(cls, href):
        """Give a url href, try to find corresponding snapshot.
        Return None if can't find valid snapshot dir.
        """
        # \1 is quote
        # \2 href and text
        # \3 datetime such as 12-Nov-2013 23:11
        name_and_last_modified = re.compile(
            r'<a .*?href=(["\'])(.*?)\1.*?>\2</a>\s*'
            r'(\d{2}-[a-zA-Z]{3}-\d{4} \d{2}:\d{2})')

        def guess_latest(url):
            "Guess the real path of latest from last modified info"
            page = url.asdir().fetch()
            idx = {}
            latest_mod = None
            for _quote, name, lastmod in name_and_last_modified.findall(page):
                if name.startswith('latest'):
                    latest_mod = lastmod
                else:
                    idx[lastmod] = name
            if latest_mod and latest_mod in idx:
                return url.join(idx[latest_mod])
            raise Exception("Can't find latest snapshot in:%s" % url)

        url = URL(href)
        for base in url.prefixes:
            if base.join('builddata', 'build.xml').exists():
                if base.basename == 'latest':
                    base = guess_latest(base.join('..'))
                return cls(base)


def is_image_file(name):
    "Returns true if name is image file"
    _, ext = os.path.splitext(name)
    if ext.lower() in ('.img', '.usbimg', '.raw', '.iso'):
        return True
    return is_compressive_file(name)


class Image(object):
    "An Image"
    def __init__(self, basedir):
        self.baseurl = basedir
        self.ksurl, self.imgurl = self._parse()
        self.name = self.baseurl.basename
        self.iscreated = not not self.imgurl

    def _parse(self):
        "Parse image base dir"
        files = list(self.baseurl.listdir())

        ksurl = [i for i in files if i.href.endswith('.ks')]
        if len(ksurl) > 1:
            raise Exception("More than one KS files in image dir:%s:%s"
                % (str(self.baseurl), ','.join(ksurl)))
        elif ksurl:
            ksurl = ksurl[0]
        else:
            ksurl = None

        img = [i for i in files if is_image_file(i.href)]
        if len(img) > 1:
            raise Exception("More than one image files in image dir:%s:%s"
                % (str(self.baseurl), ','.join(img)))
        elif img:
            img = img[0]
        else:
            img = None
        return ksurl, img

    def download_image(self, localfile):
        "Download image"
        self.imgurl.download(localfile)

    def download_ks_and_update_repo(self, localfile, baseurl):
        """Download this KS file to localfile and replace
        repo to snapshot given by baseurl.
        """
        self.ksurl.download(localfile)
        self._update_repo(localfile, baseurl)

    def _update_repo(self, filename, baseurl):
        "Update repo in KS filename"
        with open(filename) as reader:
            kscontent = reader.read()

        updated = self._interpolate(kscontent, baseurl)

        with open(filename, 'w') as writer:
            writer.write(updated)

    def _interpolate(self, kscontent, baseurl):
        "Interpolate macro BUILDID in KS file"
        def hack_for_pc_repos(url):
            """Change pc repos"""
            u = URL(url)
            if u.path.startswith('/pc/repos/'):
                # We don't have access to the first link
                # but we use the second as alternative
                return url.replace('/pc/repos/', '/3rdparty/repos/pc/')
            return url

        def update(line):
            '''replace BUILD_ID and insert user/passwd'''
            if line.find('@BUILD_ID@') > 0:
                line = re.sub(r'(--baseurl=).*@BUILD_ID@',
                              r'\1%s' % baseurl.full,
                              line)
            elif line.find('--baseurl=') > 0:
                mres = re.search(r'--baseurl=([^ ]+)', line)
                if mres:
                    urlinks = hack_for_pc_repos(mres.group(1))
                    url = URL(urlinks, baseurl.user, baseurl.passwd)
                    line = re.sub(r'(--baseurl=)[^ ]+',
                                  r'\1%s' % url.full,
                                  line)
            return line

        updated = [ update(line)
            if line.startswith('repo ')
            else line
            for line in kscontent.splitlines() ]
        return os.linesep.join(updated)

    @staticmethod
    def guess_type(ksfilename):
        """Guess image type from the first magic line of ks file
# -*-mic2-options-*- -f loop --pack-to=@NAME@.zip --runtime=native -*-mic2-options-*-
        """
        with open(ksfilename) as reader:
            line = reader.readline()

        boundary = '-*-mic2-options-*-'
        if line.find(boundary) <= 0:
            return 'Unknown'
        options = line.split(boundary)[1].strip()

        parser = argparse.ArgumentParser()
        parser.add_argument('-f', default='Unknown')
        args, _ = parser.parse_known_args(options.split())
        return args.f
