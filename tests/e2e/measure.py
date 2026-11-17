#!/usr/bin/env python3
"""Measures Ectoview's toolbar in an e2e screenshot, in the main screen's logical pixels.

usage: measure.py OUT_DIR SHOT pill-left    the groups pill's left edge (its right edge is 8 px left
                                            of the 360 px search field centered on the main screen)
       measure.py OUT_DIR SHOT heights      the drawn heights of the pill, the search field and the gear

The pill, the field and the gear share one fill (the theme's bgSubtle, whichever look); a pixel is
theirs when it's within FILL_TOLERANCE of the fill, sampled inside the search field between its
search mark and its text. Borders don't count, alike for all three. Heights are measured where each is straight-sided
(the pill and the field) or from a chord of the round gear, so text and icons don't count."""
import json
import math
import pathlib
import re
import sys
from PIL import Image

FILL_TOLERANCE = 5


def screens(out):
    log = (pathlib.Path(out) / 'kwin.log').read_text(errors='replace')
    m = re.search(r'js: screens (.*) order', log)
    found = {}
    for part in m.group(1).split(' | '):
        name, geo = part.split(' ', 1)
        g = json.loads(geo)
        found[name] = (g['x'], g['y'], g['width'], g['height'])
    return max(found.values(), key=lambda r: r[0])


class Shot:
    def __init__(self, out, shot):
        self.main = screens(out)
        self.im = Image.open(pathlib.Path(out) / shot).convert('L')
        self.s = self.im.width / (self.main[0] + self.main[2])
        self.fill = self.lum(self.search_left + 34, 150)

    def lum(self, x, y):
        """the luminance at logical (x, y) on the main screen"""
        return self.im.getpixel((min(self.im.width - 1, round((self.main[0] + x) * self.s)), min(self.im.height - 1, round((self.main[1] + y) * self.s))))

    def dark(self, x, y):
        return abs(self.lum(x, y) - self.fill) <= FILL_TOLERANCE

    def run(self, x, y0, y1):
        """the longest dark run down column x between y0 and y1, in logical pixels"""
        best = cur = 0
        step = 1 / self.s
        y = y0
        while y <= y1:
            cur = cur + 1 if self.dark(x, y) else 0
            best = max(best, cur)
            y += step
        return best * step

    @property
    def search_left(self):
        return self.main[2] / 2 - 180

    @property
    def pill_right(self):
        # (^ and v are the pill's own right end, design proposal 8: it still ends here)
        return self.search_left - 8

    def pill_left(self, y=150):
        # walk left from inside the pill's right end; text and icons are short light gaps
        x, last, gap = self.pill_right - 2, None, 0
        while x > 0 and gap < 14:
            if self.dark(x, y):
                last, gap = x, 0
            else:
                gap += 1
            x -= 1
        return last

    def heights(self):
        left = self.pill_left()
        out = {}
        # the pill: a column in its straight part, between the icon and the name
        out["pill"] = self.run(left + 32, 110, 200) if left is not None else 0
        # the search field: a column in its straight part, right of the search mark
        out['search'] = self.run(self.search_left + 34, 110, 200)
        # the gear: 36 px round, 8 px right of the field; a chord 12 px off its center misses the icon
        cx = self.search_left + 360 + 8 + 18
        chords = [self.run(cx + dx, 110, 200) for dx in (-12, 12)]
        chord = sum(chords) / 2
        out['gear'] = 2 * math.sqrt((chord / 2) ** 2 + 12 ** 2) if chord > 0 else 0
        return out


if __name__ == '__main__':
    out, shot, what = sys.argv[1:4]
    m = Shot(out, shot)
    if what == 'pill-left':
        left = m.pill_left()
        print(round(m.main[0] + left) if left is not None else -1)
    else:
        print(' '.join(f'{k}={v:.1f}' for k, v in m.heights().items()))
