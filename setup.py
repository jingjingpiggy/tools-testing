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

from setuptools import setup

setup(name='pre_deployment_test',
      include_package_data=True,
      packages=[
        'pre_deployment_test',
        'pre_deployment_test.imgutil',
        ])
