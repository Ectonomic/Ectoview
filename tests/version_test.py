#!/usr/bin/env python3
"""Ectoview's version, said once in each place that carries it: CMake's project(), the effect's
metadata.json (what System Settings shows) and the Fedora package's spec. A release changes all
three or none. Run: python3 -I tests/version_test.py
"""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class Version(unittest.TestCase):
    def test_one_version_everywhere(self):
        cmake = re.search(r'^project\(ectoview VERSION ([0-9.]+)', (ROOT / 'CMakeLists.txt').read_text(), re.M).group(1)
        metadata = json.loads((ROOT / 'package/metadata.json').read_text())['KPlugin']['Version']
        spec = re.search(r'^Version:\s*(\S+)', (ROOT / 'packaging/ectoview.spec').read_text(), re.M).group(1)
        self.assertEqual({'cmake': cmake, 'metadata.json': metadata, 'spec': spec}, {'cmake': spec, 'metadata.json': spec, 'spec': spec})


if __name__ == '__main__':
    unittest.main()
