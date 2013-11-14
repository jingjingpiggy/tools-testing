#!/usr/bin/env python
'''This script search KS recursively from given image URL.
For each KS file found, it generate a trigger file which
will trigger a sub Jenkins project.
'''
import os
import sys
import logging
import argparse

from .imgutil import Snapshot

logger = logging.getLogger('dispatcher')


def parse_args():
    "Parse args"
    parser = argparse.ArgumentParser()
    parser.add_argument('urls', nargs='+',
                        help='snapshot urls to do testing')
    parser.add_argument('--debug', action='store_true')
    return parser.parse_args()


def main():
    "Main"
    args = parse_args()
    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=level)

    sshots = []
    for url in set(args.urls):
        sshot = Snapshot.find(url)
        if not sshot:
            logger.error("Can't find snapshot in this url: %s", url)
            return 1
        sshots.append(sshot)

    num = 1
    for sshot in sshots:
        logger.info("Snapshot base url: %s", sshot.baseurl)
        for img in sshot.images():
            name = "trigger-%d.env" % num
            num += 1
            text = "url=%s%s" % (img.baseurl.full, os.linesep)
            with open(name, 'w') as writer:
                writer.write(text)
            logger.info("New job %s: %s", name, img.baseurl)

    return 0


if __name__ == '__main__':
    sys.exit(main())
