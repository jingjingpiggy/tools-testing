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

"This module provides commands to uncompress image file"
import logging
from subprocess import check_call
from os.path import splitext

logger = logging.getLogger('imgutil.uncompress')

# Map from ext array to cmd
HANDLERS = {
    ('.tar', '.tgz', '.tbz'):
        ('tar', 'xf'),
    ('.bz', '.bz2'):
        ('bunzip2', ),
    ('.gz', ):
        ('gunzip', ),
    ('.zip', ):
        ('unzip', ),
    }

# Map from ext name to its command
EXT2CMD = {
    ext: cmd
    for exts, cmd in HANDLERS.iteritems()
    for ext in exts
    }

def is_compressive_file(filename):
    "Returns true if we supported it"
    ext = splitext(filename)[1]
    return ext in EXT2CMD

def uncompress(filename):
    "uncompress file"
    base, ext = splitext(filename)
    cmd = EXT2CMD.get(ext)
    if not cmd:
        raise Exception("Can't uncompress:%s" % filename)

    cmd = list(cmd[:]) + [filename]
    logger.debug("%s => %s", ' '.join(cmd), base)
    check_call(cmd)
    return base
