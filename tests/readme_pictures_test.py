#!/usr/bin/env python3
"""The README's pictures, the cuts that make them and the files: each held to the others.

Every picture the README shows is a cut in tools/readme-pictures.py (so it can be made again),
every cut is shown in the README, every cut's file is in docs/pictures/, and every picture has
words for a screen reader (alt). Every scene a cut films is in readme-scenes.sh's SCENES.
Run: python3 -I tests/readme_pictures_test.py
"""
import ast
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
README = (ROOT / 'README.md').read_text()
TOOL = (ROOT / 'tools/readme-pictures.py').read_text()
SCENES_SH = (ROOT / 'tests/e2e/readme-scenes.sh').read_text()


def cuts():
    tree = ast.parse(TOOL)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, 'id', '') == 'CUTS' for t in node.targets):
            # the cut names and their scenes, read without running the tool
            return {k.value: {kk.value: vv for kk, vv in zip(v.keys, v.values)} for k, v in zip(node.value.keys, node.value.values)}
    raise AssertionError('no CUTS in tools/readme-pictures.py')


class ReadmePictures(unittest.TestCase):
    def test_every_picture_shown_is_a_cut(self):
        shown = set(re.findall(r'docs/pictures/([\w-]+)\.webp', README))
        self.assertTrue(shown, 'the README shows no pictures')
        self.assertEqual(shown - set(cuts()), set(), 'pictures in the README that no cut makes')

    def test_every_cut_is_shown(self):
        shown = set(re.findall(r'docs/pictures/([\w-]+)\.webp', README))
        self.assertEqual(set(cuts()) - shown, set(), 'cuts the README never shows')

    def test_every_cut_has_its_file(self):
        missing = [n for n in cuts() if not (ROOT / 'docs/pictures' / f'{n}.webp').exists()]
        self.assertEqual(missing, [], 'run tools/readme-pictures.sh')

    def test_every_picture_has_words(self):
        # (an alt may hold a ">", the arrow it describes: each picture's alt is read to its closing quote)
        pictures = re.findall(r'<img src="([^"]+)"[^>]*?alt="([^"]*)"', README)
        self.assertEqual(len(pictures), README.count('<img '), 'a picture without an alt')
        for src, alt in pictures:
            self.assertTrue(len(alt) > 20, f'a picture without real alt words: {src}')

    def test_every_scene_is_filmed(self):
        scenes = set(re.search(r'^SCENES="(.*)"$', SCENES_SH, re.M).group(1).split())
        for name, c in cuts().items():
            for key in ('scene',):
                self.assertIn(c[key].value, scenes, name)
            before = c.get('before')
            if before is not None:
                self.assertIn(before.elts[0].value, scenes, name)
            self.assertIn(f'scene_{c["scene"].value}()', SCENES_SH, name)


class CutScale(unittest.TestCase):
    """A cut takes the whole area it names at the scale the frame was filmed at: KWin films an area
    at the highest scale of the screens it touches (1.75 with the README's dashboard attached), not
    the main screen's 1.5. Assuming 1.5 cut every picture 17% too close, with its right and bottom
    edges gone (November 17, 2026)."""

    def test_a_cut_keeps_the_far_corner_at_any_scale(self):
        import importlib.util
        from PIL import Image
        spec = importlib.util.spec_from_file_location('rp', ROOT / 'tools/readme-pictures.py')
        rp = importlib.util.module_from_spec(spec); spec.loader.exec_module(rp)
        for scale in (1.5, 1.75, 2):
            w, h = round(1707 * scale), round(960 * scale)
            frame = Image.new('RGB', (w, h), (0, 0, 0))
            frame.paste((255, 0, 0), (w - round(20 * scale), h - round(20 * scale), w, h))
            cut = rp.cut_area(frame, (0, 0, 1707, 960), 800)
            corner = cut.getpixel((cut.width - 3, cut.height - 3))
            self.assertGreater(corner[0], 200, f'at scale {scale}, the far corner of the screen is cut off')


if __name__ == '__main__':
    unittest.main()
