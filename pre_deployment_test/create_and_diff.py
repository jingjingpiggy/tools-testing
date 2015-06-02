#!/usr/bin/env python
#
# Copyright (c) 2013, 2014, 2015 Intel, Inc.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; version 2 of the License
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.

"""This script accepts an URL of remote image base dir,
find KS there and create image at local, finally it
compare the new created local image with remote image
to report their differences.
"""
import os
import sys
import logging
import platform
import argparse
from subprocess import call, check_output, CalledProcessError

from .imgutil import URL, Snapshot, Image, is_image_file, uncompress


logger = logging.getLogger('pre_deployment_test_mic')


def guess_mic_version():
    "Guess MIC version"
    cmd = ["mic", "--version"]
    try:
        ver = check_output(cmd)
    except CalledProcessError:
        import traceback
        traceback.print_exc()
        ver = 'Unknown'
    return ver.strip()


def find_local_image():
    "Returns the image file created in local"
    path = 'mic-output'
    if not os.path.exists(path):
        return None
    for name in os.listdir(path):
        if is_image_file(name):
            return os.path.join(path, name)


def parse_args():
    "Parser arguments"
    parser = argparse.ArgumentParser()
    parser.add_argument('imgdirurl',
        help='image base url where we can find KS and image files')
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('-O', '--output', default='result.txt',
        help='output file name')
    parser.add_argument('--conf', default='unimportant.json',
        help='unimportant conf')
    return parser.parse_args()


def main():
    "Main"
    args = parse_args()
    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=level)

    sshot = Snapshot.find(args.imgdirurl)
    img = Image(URL(args.imgdirurl))
    localks = img.ksurl.basename
    micver = guess_mic_version()
    dist = platform.linux_distribution()

    # 1.download ks
    img.download_ks_and_update_repo(localks, sshot.baseurl)
    imgtyp = Image.guess_type(localks)

    def quit(exitcode, desc, reason):
        "Write result and quit"
        msg = """Image: %s
ImageType: %s
Result: %s
Reason: %s
MicVersion: %s
Infra: %s
Product: %s
BuildID: %s
Distribution: %s
KSURL: %s
SnapshotURL: %s
""" % (img.name, imgtyp,
    desc, reason,
    micver, sshot.infra, sshot.product, sshot.builid,
    '-'.join([i.strip() for i in dist]),
    img.ksurl, sshot.baseurl)
        print "-"*40
        print msg
        print "-"*40
        with open(args.output, 'w') as writer:
            writer.write(msg)
        sys.exit(exitcode)

    # 2.create local image
    cmd = ['timeout', '7200',
        'mic', 'cr', 'auto', localks,
        '--debug', '--verbose',
        '--logfile=mic.log',
        ]
    exitcode = call(cmd)
    localimg = find_local_image()

    if exitcode == 0 and localimg:
        if not img.iscreated:
            quit(0, "Fixed", "Local image is OK and remote failed")
        elif imgtyp != "raw":
            quit(0, "Passed", "Local image is OK "
                "and needn't imgdiff %s type" % imgtyp)
        elif dist[0].lower().startswith('opensuse') and dist[1] <= '12.1':
            quit(0, "Passed", "Local image is OK "
                "and needn't imgdiff on %s%s" % (dist[0], dist[1]))
        else: # local OK, remote OK => continue to diff
            imgname = os.path.basename(localimg)
            if localimg != imgname:
                # copy image from mic-output to current dir, keep the
                # origin image file for downstream job
                call(["/bin/cp", "-a", localimg, imgname])
                localimg = imgname
            localimg = uncompress(localimg)
    elif img.iscreated:
        quit(1, "Regression", "Local failed but remote is OK")
    else:
        quit(0, "Repeat", "Local failed and remote also failed")

    # 3.download remote image
    remoteimg = 'remote.' + img.imgurl.basename
    img.download_image(remoteimg)
    remoteimg = uncompress(remoteimg)

    # 4.image diff
    cmd = ['imgdiff', '-c', args.conf, localimg, remoteimg]
    logger.debug(" ".join(cmd))
    exitcode = call(cmd)
    if exitcode == 0:
        quit(0, "Passed", "Local and remote are the same")
    else:
        quit(0, "Diff(%d)" % exitcode, "Local and remote are different")


if __name__ == '__main__':
    main()
