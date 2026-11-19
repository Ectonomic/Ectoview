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


class SnapshotOrder(unittest.TestCase):
    """COPR's snapshots carry the commit's date and time in their release, so a later commit's package
    is always newer: with the date alone, two commits from one day were ordered by their hashes, and
    dnf kept the older (November 18, 2026: gitd60a429 sorted below gitde834c0)."""

    def test_the_stamp_has_the_time(self):
        mk = (ROOT / '.copr/Makefile').read_text()
        self.assertRegex(mk, r'date=\$\$\(TZ=UTC git log -1 --format=%cd --date=format-local:%Y%m%d%H%M%S\)')


if __name__ == '__main__':
    unittest.main()
