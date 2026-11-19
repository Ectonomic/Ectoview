#!/usr/bin/env python3
"""Judges an e2e run's pictures and logs. usage: check.py OUT_DIR SCENARIO

Screenshots are both screens side by side at twice the logical size (Spectacle takes the
highest scale): the dashboard screen at (0, 617, 1966x823), the main one at (1966, 0, 3440x1440).
A plant-* scenario runs a copy with one boundary broken: it passes only when the check it
targets fails."""
import os
import json
import re
import sys
import pathlib
from PIL import Image, ImageChops

out = pathlib.Path(sys.argv[1]); scenario = sys.argv[2]
results = []
# the screens as KWin reported them (inner.sh's placement script prints them)
_log = (out / 'kwin.log').read_text(errors='replace') if (out / 'kwin.log').exists() else ''
_m = re.search(r'js: screens (.*) order', _log)
_screens = {}
if _m:
    for part in _m.group(1).split(' | '):
        name, geo = part.split(' ', 1)
        g = __import__('json').loads(geo)
        _screens[name] = (round(g['x']), round(g['y']), round(g['width']), round(g['height']))
LEFT = min(_screens.values(), key=lambda r: r[0]) if _screens else (0, 617, 1966, 823)
MAIN = max(_screens.values(), key=lambda r: r[0]) if _screens else (1966, 0, 3440, 1440)
_any = next(out.glob('*.png'), None)
S = Image.open(_any).width / (MAIN[0] + MAIN[2]) if _any else 2   # Spectacle draws at the highest scale

def check(name, ok, detail='', known=None):
    """known: the reason this boundary doesn't hold yet; the check still runs and reports XFAIL
    (or XPASS once it holds, when the reason should come out)"""
    results.append((name, bool(ok), detail, known))

def img(n):
    p = out / f'{n}.png'
    return Image.open(p).convert('RGB') if p.exists() else None

def region(im, r):
    x, y, w, h = r
    return im.crop((round(x * S), round(y * S), round((x + w) * S), round((y + h) * S)))

def changed(a, b, r):
    """share of pixels that differ by more than 6 levels in any channel, and the largest difference"""
    d = ImageChops.difference(region(a, r), region(b, r))
    px = list(d.get_flattened_data()) if hasattr(d, 'get_flattened_data') else list(d.getdata())
    n = sum(1 for p in px if max(p) > 6)
    return n / len(px), max(max(p) for p in px)

log = (out / 'kwin.log').read_text(errors='replace') if (out / 'kwin.log').exists() else ''
qml_errors = [l for l in log.splitlines() if 'effects/ectoview/contents' in l and re.search(r'Error|error|is not defined|Cannot|Unable|failed|undefined|deprecated|Invalid|unavailable|not a type|Unknown|Duplicate|[Bb]inding loop', l)]

def icon_faults(impl=pathlib.Path(__file__).resolve().parents[2] / 'package/contents/ui/impl'):
    """icons named in the QML that Kirigami might take from the icon theme, or that aren't there
    (Kirigami.Icon looked "group.svg" up as the theme's "group" and drew people)"""
    bad = []
    for qml in impl.glob('*.qml'):
        for name in re.findall(r'"([\w.-]+\.svg)"', qml.read_text()):
            if not name.startswith('ectoview-') or not (impl / name).exists():
                bad.append(f'{qml.name}: {name}')
    return sorted(set(bad))

def common():
    check('installed from the package', 'Successfully installed' in (out / 'install.log').read_text(errors='replace'))
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    m = re.search(r'loaded effects: (.*)', steps)
    loaded = m.group(1).split() if m else []
    check('KWin loaded Ectoview, not Overview', 'ectoview' in loaded and 'overview' not in loaded, ' '.join(loaded))
    names = (out / 'shortcut-names.txt').read_text().splitlines() if (out / 'shortcut-names.txt').exists() else []
    # every shortcut the effect declares (its ShortcutHandlers' names), not a list typed here
    effect_qml = (pathlib.Path(__file__).resolve().parents[2] / 'package/contents/ui/impl/Effect.qml').read_text()
    want = re.findall(r'ShortcutHandler \{\s*name: "([^"]+)"', effect_qml)
    check(f'its {len(want)} shortcuts are registered', len(want) >= 8 and all(n in names for n in want), ', '.join(n for n in want if n not in names))
    check('no QML errors from Ectoview', not qml_errors, '\n      '.join(qml_errors[:8]))
    check('every icon Ectoview draws is its own file (prefixed ectoview-, so an icon theme with that name can\'t replace it)', not icon_faults(), ', '.join(icon_faults()))
    check('every click area beside a hand-cursor hover handler shows the hand itself', not hand_faults(), ', '.join(hand_faults()))
    # a frame KWin couldn't draw comes out black (an overflowing bar's fade once blacked out every screen)
    black = [p.name for p in sorted(out.glob('*.png')) if max(Image.open(p).convert('L').resize((160, 48)).getdata()) < 8]
    check('no black screens', not black, ', '.join(black))

def hand_faults():
    """Click areas (MouseArea) in Ectoview's own files that sit in the same item as a hover handler
    showing the hand, without setting the hand themselves: Qt then shows whatever is under them (the
    search field's text cursor, November 17, 2026). Read from the package, every file."""
    faults = []
    pkg = pathlib.Path(os.environ.get('ECTOVIEW_PACKAGE') or pathlib.Path(__file__).resolve().parents[2] / 'package')
    for f in sorted((pkg / 'contents/ui/impl').glob('Ecto*.qml')):
        lines = f.read_text().split('\n')
        for i, l in enumerate(lines):
            if not re.match(r'^\s*MouseArea \{\s*$', l):
                continue
            body, depth, j = [], 1, i + 1
            while j < len(lines) and depth > 0:
                depth += lines[j].count('{') - lines[j].count('}')
                if depth >= 1:
                    body.append(lines[j])
                j += 1
            own = any('cursorShape:' in b for b in body)
            # the same item: the lines just before it at its own indent, back to its parent's opening
            ind = len(l) - len(l.lstrip())
            k, near = i - 1, []
            while k >= 0 and (len(lines[k]) - len(lines[k].lstrip()) >= ind or not lines[k].strip()):
                near.append(lines[k])
                k -= 1
            if not own and any('PointingHandCursor' in n for n in near):
                faults.append(f'{f.name}:{i + 1}')
    return faults

def update_rules():
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    m = re.search(r'builds loaded: (\S*)', steps)
    builds = m.group(1).split(',') if m and m.group(1) else []
    check('an update installed over a running Ectoview loads as a new build', 'update exit 0' in steps and len(builds) >= 2 and builds[-1] != builds[0], ', '.join(builds))
    a, b = img('ectoview-open'), img('ectoview-updated')
    if a and b:
        # the search field: 360 px, centered on the main screen, 132 to 168 px down
        field = (MAIN[0] + MAIN[2] // 2 - 180, 132, 360, 36)
        share, _ = changed(a, b, field)
        check("and runs at once: the update's new search text is on screen", share > 0.01, f'{share:.1%} of the search field changed')

def windows_rules():
    d, o, e = img('desktop'), img('overview'), img('every')
    if not (d and o and e):
        check('pictures taken', False); return
    share, _ = changed(d, o, LEFT)
    check('with "only their windows", Ectoview lays out the dashboard screen\'s windows', share > 0.2, f'{share:.1%} of it changed')
    # the band where the bar and toolbar sit with "all of Ectoview" (they take about 180 px)
    band = (LEFT[0], LEFT[1], LEFT[2], 170)
    share, _ = changed(o, e, band)
    check('and draws no desktop bar or toolbar there (the band differs from "all of Ectoview")', share > 0.2, f'{share:.1%} of the band differs')
    share, _ = changed(o, e, MAIN)
    check("the primary screen is the same either way", share < 0.05, f'{share:.1%} differs')

def primary_rules():
    d, o, c = img('desktop'), img('overview'), img('after-click')
    if not (d and o and c):
        check('pictures taken', False); return
    share, peak = changed(d, o, MAIN)
    check('Ectoview opens on the primary screen', share > 0.2, f'{share:.1%} of the main screen changed')
    share, peak = changed(d, o, LEFT)
    scale = float((out / 'left-scale.txt').read_text()) if (out / 'left-scale.txt').exists() else 1.75
    fractional = abs(scale - round(scale)) > 1e-6
    check('the dashboard screen is left as it was (no more than 0.01% of pixels off)', share <= 0.0001,
          f'{share:.4%} of its pixels changed, largest difference {peak}, screen scale {scale}',
          known=('on a fractionally scaled screen KWin resamples window thumbnails (WindowThumbnailSource renders into a texture '
                 'sized to the window\'s whole-pixel rect, drawn back over its fractional one), so text and line edges soften '
                 'while Ectoview is open; docs/deferred.md') if fractional else None)
    if fractional:
        check('the dashboard screen differs only by that resampling (under 3% of pixels)', share < 0.03, f'{share:.2%}')
    share, _ = changed(d, c, MAIN)
    check('a click on the dashboard screen does nothing: Ectoview stays open', share > 0.2, f'{share:.1%} of the main screen differs from the desktop')
    share, peak = changed(d, c, LEFT)
    check("and doesn't reach the dashboard (it's still as it was)", share < 0.03, f'{share:.2%}')

if scenario == 'smoke':
    common()
    d = img('desktop')
    for n, want in [('overview', 'open'), ('closed', 'shut'), ('grid', 'open'), ('search', 'open'), ('search-apps', 'open'), ('after-esc', 'shut')]:
        im = img(n)
        if not (d and im):
            check(f'{n}: picture taken', False); continue
        share, _ = changed(d, im, MAIN)
        check(f'{n}: Ectoview {"is drawn" if want == "open" else "has closed"}', share > 0.2 if want == 'open' else share < 0.01, f'{share:.1%} of the main screen differs from the desktop')
    o, g, s, a = img('overview'), img('grid'), img('search'), img('search-apps')
    if o and g:
        check('Grid View is not Ectoview\'s overview', changed(o, g, MAIN)[0] > 0.2)
    if o and s:
        check('typing filters the windows', changed(o, s, MAIN)[0] > 0.05)
    if s and a:
        check('a search with no window shows other answers', changed(s, a, MAIN)[0] > 0.05)
elif scenario == 'layout':
    common()
    d = img('desktop')
    for n, want in [('overview', 'open'), ('closed', 'shut'), ('grid', 'open')]:
        im = img(n)
        if d and im:
            share, _ = changed(d, im, MAIN)
            check(f'{n}: Ectoview {"is drawn" if want == "open" else "has closed"}', share > 0.2 if want == 'open' else share < 0.01, f'{share:.1%}')
elif scenario == 'rename':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    m = re.search(r'after rename: (\S+)', steps)
    check('clicking a name, typing and Enter renames the desktop in KWin', m and m.group(1).startswith('Work,notes,Design,Music'), m.group(1) if m else '')
elif scenario == 'migrate':
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    o, n = img('old-open'), img('new-open')
    field = (MAIN[0] + MAIN[2] // 2 - 180, 132, 360, 36)
    red = lambda im: sum(1 for p in region(im, MAIN).resize((172, 72)).getdata() if p[0] > 200 and p[1] < 40 and p[2] < 40) / (172 * 72)
    check('the old install ran first (its solid red screen)', o is not None and red(o) > 0.9, f'{red(o):.0%} red' if o else 'no picture')
    check('install.sh over it finished', re.search(r'^install exit 0$', steps, re.M) is not None, (out / 'install-run.log').read_text(errors='replace')[-400:])
    m = re.search(r'folders: old=(\S*) new=(\S*)', steps)
    check('the effect moved to kwin-wayland/effects and left kwin/effects', m and 'ectoview' not in m.group(1) and 'ectoview' in m.group(2), m.group(0) if m else '')
    bl = re.search(r'builds loaded: (\S*)', steps)
    check('without restarting KWin, the new build loads', bl is not None and bl.group(1).startswith('b'), bl.group(0) if bl else '')
    if o and n:
        share, _ = changed(o, n, field)
        check("and runs: Ectoview is on screen, not the old build's red", red(n) < 0.05 and share > 0.2, f'{red(n):.0%} red, {share:.0%} of the search field changed')
elif scenario == 'hide':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    mig = line('migrated')
    check('hidden desktops from before groups become the Hidden group, and the old list goes',
          'groups=d2=hidden ' in mig + ' ' and 'hidden= ' in mig, mig)
    check('"search all desktops" from before becomes the All desktops scope, and the old switch goes', 'scope=2' in mig and 'all= ' in mig + ' ', mig)
    check('"only the primary screen" from before becomes "other screens stay as they are", and the old switch goes', 'others=2' in mig and mig.endswith('primaryonly='), mig)
    check("the pill's Hidden row switches to the hidden desktop and keeps it hidden",
          line('on hidden').endswith('current Code') and 'd2=hidden' in line('on hidden'), line('on hidden'))
    check('Move to desktop group > Desktops brings a hidden desktop back', 'd2=hidden' not in line('after show') and line('after show').endswith('current Code'), line('after show'))
    check("with nothing hidden and one group left, the bar shows every desktop again (a click on the first is Work)", line('back to Work').endswith('current Work'), line('back to Work'))
    check('Move to desktop group > Hidden hides it again, by KWin\'s id', 'd2=hidden' in line('after hide'), line('after hide'))
    check('hiding changes nothing in KWin itself', 'Work,Code,Design,Music' in line('after hide'), line('after hide'))
    h, sh = img('hidden'), img('shown')
    if h and sh:
        check('the bar closes up when a desktop is hidden', changed(h, sh, (MAIN[0] + MAIN[2] // 2 - 600, 0, 1200, 120))[0] > 0.05)
    check('a drag past a hidden desktop lands between the shown ones; the hidden one keeps its place',
          'Work,Code,Music,Design' in line('after drag') and 'd2=hidden' in line('after drag'), line('after drag'))
elif scenario in ('groups', 'plant-tokens'):
    if scenario == 'groups':
        common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    def heights_ok():
        m = dict(re.findall(r'(\w+)=([0-9.]+)', line('heights')))
        hs = [float(m.get(k, 0)) for k in ('pill', 'search', 'gear')]
        return min(hs) > 20 and max(hs) - min(hs) <= 1.5, line('heights')
    ok, detail = heights_ok()
    check('the groups pill, the search field and the gear are drawn the same height (one token)', ok, detail)
    if scenario == 'groups':
        new = line('new group')
        gm = re.search(r'groups=desktops:Desktops,(g[0-9a-z]+):games ', new + ' ')
        gid = gm.group(1) if gm else '?'
        check('Move to desktop group > New desktop group… makes a named group holding the desktop', gm and f'd3={gid}' in new, new)
        check('the first group is written with every desktop in it', 'd1=desktops' in new and 'd2=desktops' in new and 'd4=desktops' in new, new)
        check("dragging a desktop onto the pill and a group's row moves it there (not to a new place)",
              f'd4={gid}' in line('after drop') and 'Work,Code,Design,Music' in line('after drop'), line('after drop'))
        check("choosing a group in the pill's list takes you to its desktop", line('chose games').endswith('current Design'), line('chose games'))
        check("the pencil renames the group", f'{gid}:play' in line('renamed'), line('renamed'))
        check('"Next Desktop in Desktop Group" stays in the group', line('next in group').endswith('current Music'), line('next in group'))
        check('"Previous Desktop in Desktop Group" goes back within it', line('previous in group').endswith('current Design'), line('previous in group'))
        check('"Next Desktop Group" goes to the next group\'s last desktop', line('next group').endswith('current Work'), line('next group'))
        check('"Previous Desktop Group" goes back to the last desktop used there', line('previous group').endswith('current Design'), line('previous group'))
        check('the search caret picks "This desktop group"', line('scope') == '1', line('scope'))
        check('"This desktop group" finds a window on another desktop of the group, and a click goes there', line('after search click').endswith('current Music'), line('after search click'))
        nfp = line('new from pill')
        nm = re.search(r'groups=desktops:Desktops,' + gid + r':play,(g[0-9a-z]+):misc ', nfp + ' ')
        check("New desktop group in the pill's list makes a group with a new desktop, takes you there and names it",
              nm and 'Work,Code,Design,Music,Desktop 5 current Desktop 5' in nfp and re.search(r'=' + (nm.group(1) if nm else 'x') + r'\b', nfp), nfp)
        rm = line('removed')
        check("removing a group moves its desktops to the first group and deletes nothing",
              gid not in rm and ':misc' in rm and 'd3=desktops' in rm and 'd4=desktops' in rm, rm)
        a, b = img('nopill'), img('after-new')
        if a and b:
            pill = (MAIN[0] + MAIN[2] // 2 - 188 - 140, 132, 140, 36)
            check('the pill shows once there are two groups', changed(a, b, pill)[0] > 0.2, f'{changed(a, b, pill)[0]:.0%} of its place changed')
elif scenario == 'deadclicks':
    common()
    d = img('desktop')
    for n, what in [('after-backdrop', 'a click on the backdrop beside the desktop'), ('after-arrow', 'a click on the faded back arrow')]:
        im = img(n)
        if d and im:
            share, _ = changed(d, im, MAIN)
            check(f"{what} leaves Ectoview open", share > 0.2, f'{share:.1%} of the main screen differs from the desktop')
    im = img('after-desktop')
    if d and im:
        share, _ = changed(d, im, MAIN)
        check('a click on the desktop itself closes Ectoview', share < 0.01, f'{share:.2%} still differs')
elif scenario == 'gutter':
    common()
    o = img('overview')
    if o:
        # the bar's row through the thumbnails' middle: the rightmost dark thing (the gear, the add
        # tile or an arrow) keeps a gutter from the screen's edge
        row = region(o, (MAIN[0], 40, MAIN[2], 26)).convert('L').resize((MAIN[2], 1))
        px = list(row.get_flattened_data()) if hasattr(row, 'get_flattened_data') else list(row.getdata())
        dark = [x for x, v in enumerate(px) if v < 32]
        right = max(dark) if dark else -1
        check("the bar's last control keeps at least a 16 px gutter from the screen's edge", right >= 0 and MAIN[2] - 1 - right >= 16,
              f'rightmost dark pixel {MAIN[2] - 1 - right} px from the edge' if right >= 0 else 'nothing dark found')
elif scenario == 'searchall':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    check("the caret's menu picks All desktops, and it's remembered", line('scope') == '2', line('scope'))
    t, a = img('this'), img('all')
    if t and a:
        view = (MAIN[0] + 300, 300, MAIN[2] - 600, 900)
        check('with All desktops, a window on another desktop shows up in the search', changed(t, a, view)[0] > 0.2, f'{changed(t, a, view)[0]:.0%} of the view changed')
    check("a click on it takes you to its desktop", line('after click').endswith('current Code'), line('after click'))
elif scenario == 'primary':
    common(); primary_rules()
elif scenario in ('transition', 'plant-transition'):
    if scenario == 'transition':
        common()
    b, a2 = img('before'), img('after')
    mids = [img(n) for n in ('t1', 't2', 't3')]
    bar = (MAIN[0] + MAIN[2] // 2 - 700, 0, 1400, 175)
    if b and a2 and all(mids):
        # (the two groups' desktops are alike: the same wallpaper, few windows)
        check('the bar shows another group after the change', changed(b, a2, bar)[0] > 0.02, f'{changed(b, a2, bar)[0]:.0%} of the bar changed')
        between = [min(changed(m, b, bar)[0], changed(m, a2, bar)[0]) for m in mids]
        check('and moves between the two (pictures mid-change match neither end)', max(between) > 0.03, ', '.join(f'{x:.1%}' for x in between))
    else:
        check('pictures taken', False)
elif scenario in ('groupshortcut', 'plant-groupshortcut'):
    if scenario == 'groupshortcut':
        common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    m = re.search(r'after: (.*)', steps)
    check('"Next Desktop Group" with Ectoview closed goes to the next group', bool(m) and m.group(1).endswith('current D8'), m.group(1) if m else 'no reading')
    v = re.search(r'visible after: (.*)', steps)
    check('and Ectoview is gone again afterwards', bool(v) and 'ectoview' not in v.group(1), v.group(1) if v else 'no reading')
    # the group change slides up and down (design proposal 11): a picture mid-change holds the next
    # group's desktop coming up from below, the settled picture shifted down part of the screen and
    # not sideways; KWin's own slide moves sideways past the desktops between
    from PIL import Image, ImageChops, ImageStat
    def frame(name):
        im = Image.open(out / f'{name}.png').convert('L')
        s = im.height / 1440
        ox = im.width - round(3440 * s)
        return im.crop((ox, 0, im.width, im.height)).resize((430, 180))
    def best_offset(mid, after):
        """(dx, dy) that best lines up the settled picture's part with the picture mid-change: the
        settled picture moved right dx and down dy, compared where both are on the screen"""
        best = None
        for dy in range(0, 171, 3):
            for dx in range(-60, 61, 6):
                a = ImageChops.offset(after, dx, dy)
                x0, x1 = max(0, dx), min(430, 430 + dx)
                y0 = dy
                if x1 - x0 < 100 or 180 - y0 < 10:
                    continue
                score = ImageStat.Stat(ImageChops.difference(mid.crop((x0, y0, x1, 180)), a.crop((x0, y0, x1, 180)))).mean[0]
                if best is None or score < best[0]:
                    best = (score, dx, dy)
        return best
    if all((out / f'{n}.png').exists() for n in ('before', 't1', 't2', 'after')):
        after = frame('after')
        offs = [best_offset(frame(n), after) for n in ('t1', 't2')]
        # (only a picture that lines up well says where things are: mid-change it holds parts of both)
        moving = [o for o in offs if 8 <= o[2] <= 165 and o[0] < 12]
        check("and slides the next group's desktop up into place over the desktop, not KWin's slide sideways (a picture mid-change: the settled one shifted down, not sideways)",
              bool(moving) and all(abs(o[1]) <= 6 for o in moving), f'best (score, dx, dy) for t1, t2: {[tuple(round(v, 1) for v in o) for o in offs]} (of 430x180)')
    else:
        check('pictures taken', False)
elif scenario == 'shortcuts':
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    m = re.search(r'keys: (.*)', steps)
    # Meta+K: Qt's Meta modifier (0x10000000) plus K (0x4b)
    check("a shortcut set on the settings page's Shortcuts tab (key editor, Custom, Meta+K, Apply) is what KDE's shortcut service holds",
          m and '268435531' in m.group(1), m.group(1) if m else 'no reading')
    # the window shows Ectoview's name and icon, not "kcmshell6" and Wayland's W (November 17, 2026)
    named = re.search(r'settings named (\{.*\})', steps)
    named = json.loads(named.group(1)) if named else {}
    check('the settings window is named Ectoview, from the settings module\'s own description',
          named.get('caption') == 'Ectoview', str(named))
    # and Plasma shows it: the title bar's icon (the window is placed at the main screen's x + 200, y 10)
    # is Ectoview's green mark, not the orange W it showed while Plasma couldn't find the icon
    top = img('settings-top')
    if top:
        px = list(region(top, (MAIN[0] + 204, 14, 20, 20)).getdata())
        green = sum(1 for r, g, b in px if g > 170 and b < 110 and g > r + 10) / len(px)
        orange = sum(1 for r, g, b in px if r > 200 and b < 110 and r > g + 30) / len(px)
        check("Plasma shows Ectoview's icon in the settings window's title bar, not Wayland's W",
              green > 0.12 and orange < 0.04, f'{green:.0%} of the icon green, {orange:.0%} orange')
    else:
        check('pictures taken', False)
    icon = re.search(r'settings icon: (\d+) sizes; entry: (.*)', steps)
    check("its entry (kwin_ectoview_config.desktop, the name kcmshell6 gives the window) shows Ectoview's icon, installed at every size",
          named.get('desktopFile') == 'kwin_ectoview_config' and icon and int(icon.group(1)) >= 7 and icon.group(2).strip() == 'Icon=ectoview',
          f"{named.get('desktopFile')}; {icon.group(0) if icon else 'no reading'}")
elif scenario == 'gridgroups':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    check("Grid View shows another group's desktop in its row, and a click there goes to it", line('clicked design').endswith('current Design'), line('clicked design'))
    check('"1 hidden" brings the Hidden row in, and its desktop can be chosen (and stays hidden)', 'current Music' in line('clicked music') and 'd4=hidden' in line('clicked music'), line('clicked music'))
    dc = line('dragged code')
    check("a desktop dragged into another group's row joins that group, at the end of its row", 'Work,Design,Code,Music' in dc and re.search(r'd2=g1\b', dc), dc)
    check('arrow keys move between rows in the group grid', line('down').endswith('current Design'), line('down'))
elif scenario in ('arrowsside', 'plant-arrowsside'):
    common()
    places = [json.loads(m) for m in re.findall(r'Ectoview: side arrows Virtual-1 (\{.*\})', log)]
    def clear(p, side):
        """the arrow on SIDE (-1 previous, 1 next): its caret clear of the view and on the screen,
        its click area clear of the bar"""
        c = p['previous'] if side < 0 else p['next']
        if c is None:
            return False, 'not shown'
        g, k = p['glyph'] / 2, p['click'] / 2
        if side < 0:
            ok = c + g <= p['viewLeft'] - 4 and c - k >= p['barLeft'] and c - g >= 0
        else:
            ok = c - g >= p['viewRight'] + 4 and c + k <= p['barRight'] and c + g <= 3440
        return ok, f"caret {c - g:.0f} to {c + g:.0f}, clicks {c - k:.0f} to {c + k:.0f}; view {p['viewLeft']:.0f} to {p['viewRight']:.0f}, bar edge {p['barLeft'] if side < 0 else p['barRight']:.0f}"
    for name, pick in (('right', lambda p: p['barRight'] < 3440 and p['shown']), ('left', lambda p: p['barLeft'] > 0 and p['shown'])):
        p = next((p for p in places if pick(p)), None)
        if not p:
            check(f'the arrows beside a {name}-hand bar were logged', False, f'{len(places)} placings')
            continue
        for side, what in ((-1, '<'), (1, '>')):
            ok, detail = clear(p, side)
            check(f'with the bar on the {name}, the {what} arrow sits whole between the view and the {"bar" if (side > 0) == (name == "right") else "screen edge"}', ok, detail)
    # the arrows turned off on the settings page: neither drawn, and the view takes their room
    left_on = next((p for p in places if p['barLeft'] > 0 and p['shown']), None)
    off = next((p for p in places if p['barLeft'] > 0 and not p['shown']), None)
    if off and left_on:
        check('with the arrows off, neither is drawn and the view takes their room on both sides',
              off['previous'] is None and off['next'] is None and off['viewLeft'] < left_on['viewLeft'] - 40 and off['viewRight'] > left_on['viewRight'] + 40,
              f"arrows {off['previous']}, {off['next']}; view {off['viewLeft']:.0f} to {off['viewRight']:.0f}, with arrows {left_on['viewLeft']:.0f} to {left_on['viewRight']:.0f}")
    else:
        check('the view with the arrows off was logged', False, f'{len(places)} placings')
elif scenario in ('gridstack', 'plant-gridstack'):
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    lays = re.findall(r'Ectoview: grid layout Virtual-1 (\{.*\})', log)
    places = dict((k, float(v)) for k, v in re.findall(r'(\w+)=(-?[\d.]+)', (re.search(r'places: (.*)', steps) or [None, ''])[1]))
    im = img('grid')
    if lays and places and im:
        L = json.loads(lays[-1]); cols = L['cols']
        mw = places['mw']; s = im.height / 1440; ox = im.width - round(3440 * s)
        lum = lambda x, y: sum(im.getpixel((ox + round(x * s), round(y * s)))) / 3
        # what's drawn along the middle of Development's first line: the desktops (Plasma's bright
        # wallpaper) against the dimmed backdrop, measured across the whole screen
        y1 = L['tops'][2] + L['s'] * 1440 / 2
        lit = [x for x in range(0, int(mw), 2) if lum(x, y1) > 120]
        runs, start = [], None
        for a_, b_ in zip(lit, lit[1:] + [None]):
            start = a_ if start is None else start
            if b_ is None or b_ - a_ > 6:
                runs.append((start, a_)); start = None
        # a desktop's width, from the accent ring around the one you're on (D11, Development's fifth):
        # the same on any wallpaper (a dark one breaks the bright runs up)
        cx = L['x0'] + L['head'] + 4 * L['cellW'] + L['s'] * mw / 2
        ring = [x for x in range(int(cx - L['cellW']), int(cx + L['cellW']))
                if (lambda r, g, b: g > 200 and 150 < r < 245 and b < 110)(*im.getpixel((ox + round(x * s), round(y1 * s))))]
        widest = (max(ring) - min(ring)) if ring else 0
        one_line_w = (mw - 300) / 11
        check("Development's eleven desktops stack onto lines, drawn wider than one line per group allows",
              cols < 11 and widest > one_line_w * 1.3, f'{cols} columns; desktops drawn {widest} px wide, one line per group {one_line_w:.0f}')
        # its second line is really there: its first desktop drawn where the layout puts it
        y2 = y1 + L['cellH']
        x2 = L['x0'] + L['head'] + L['s'] * mw / 2
        check("and its second line is drawn below the first, lined up under the first column", lum(x2, y2) > 120 and lum(x2 - L['s'] * mw * 0.6, y2) < 110,
              f'brightness {lum(x2, y2):.0f} inside its first desktop, {lum(x2 - L["s"] * mw * 0.6, y2):.0f} left of it')
        # centered: the desktops of the full line span the middle, the names' column to their left
        if runs:
            left, right = runs[0][0], runs[-1][1]
            mid = (left + right) / 2
            check('the grid is centered on the screen (its desktops with the names\' column beside them)', abs(mid - (mw / 2 + L['head'] / 2)) < 40,
                  f'desktops from {left} to {right} px; their middle {mid:.0f}, the grid\'s {mw / 2 + L["head"] / 2:.0f}')
        want_down = f'D{11 + cols}' if 4 + cols < 11 else 'D11'
        check('Down goes to the desktop below, on the next line', (re.search(r'down: current (\S+)', steps) or [None, ''])[1] == want_down,
              (re.search(r'down: (.*)', steps) or [None, ''])[1] + f' (wanted {want_down})')
        want_click = f'D{7 + cols}'
        check("a click on the second line's first desktop goes there", (re.search(r'clicked: current (\S+)', steps) or [None, ''])[1] == want_click,
              (re.search(r'clicked: (.*)', steps) or [None, ''])[1] + f' (wanted {want_click})')
    else:
        check('the grid pictured and its layout logged', False, f'{len(lays)} layouts, places {places}')
elif scenario in ('arrows', 'plant-arrows'):
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    check("a click on > goes to the next desktop in the group", line('clicked next').endswith('current Code'), line('clicked next'))
    check("a click on < goes back to the previous one", line('clicked previous').endswith('current Work'), line('clicked previous'))
    check("a window dropped on > goes to the next desktop in the group, and you stay where you are",
          line('kate').startswith('Code ') and line('kate').endswith('current Work'), line('kate'))
    check("the group's first desktop has no <: a window held there switches nothing",
          line('held previous on first').endswith('current Work'), line('held previous on first'))
    # each switch while Dolphin is held on >, after it arrived: the first after the pause, the next
    # after another as long (the owner's ruling: not almost at once), none past the group's last desktop
    arrived = int(line('arrived') or 0)
    times = [(n, int(t)) for n, t in re.findall(r'(\w+) (\d+);', line('switches'))]
    held = [(n, t) for n, t in times if t >= arrived]
    gaps = [b - a for (_, a), (_, b) in zip([('', arrived)] + held, held)]
    detail = f'switches after arriving: {[(n, t - arrived) for n, t in held]}; pauses {gaps} ms'
    check("held on >, the view moves to the next desktop after a pause of about a second",
          len(held) >= 1 and held[0][0] == 'Code' and 850 <= gaps[0] <= 1400, detail)
    check("still held, it moves on again only after an equally long pause",
          len(held) >= 2 and held[1][0] == 'Design' and 950 <= gaps[1] <= 1300, detail)
    check("at the group's last desktop the switching stops (no > there)", len(held) == 2, detail)
    check("the held window, dropped on the view, lands on the desktop it was carried to",
          line('dolphin').startswith('Design ') and line('dolphin').endswith('current Design'), line('dolphin'))
elif scenario == 'arrowsback':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    sw = re.search(r'switches: (.*)', steps)
    names = re.findall(r'(\w+) \d+;', sw.group(1)) if sw else []
    check('carried on > and back on <, the view went to Code and back to Work', names == ['Code', 'Work'], names)
    # Work's left half (the held window is at the right edge) a moment into the slide back, against
    # the same once settled: a desktop that slides in differs there; one that stands still doesn't
    from PIL import Image, ImageChops, ImageStat
    def main_region(name):
        im = Image.open(out / name).convert('RGB')
        s = im.height / 1440
        x0 = im.width - round(3440 * s)
        return im.crop((x0 + round(300 * s), round(250 * s), x0 + round(1700 * s), round(1380 * s)))
    if (out / 'mid.png').exists() and (out / 'settled.png').exists():
        diff = ImageStat.Stat(ImageChops.difference(main_region('mid.png'), main_region('settled.png'))).mean
        moved = sum(diff) / 3
        check('back on its home desktop, the desktop slides in (it stood still before)', moved > 4, f'mean difference mid-slide against settled: {moved:.1f}')
    else:
        check('back on its home desktop, the desktop slides in (it stood still before)', False, 'no pictures')
elif scenario == 'grouparrows':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    cur = lambda k: line(k).split(' current ')[-1] if ' current ' in line(k) else ''
    check('the dimmed ^ in the first group does nothing', cur('dimmed') == 'Work', line('dimmed'))
    check('v goes to the next desktop group', cur('down') == 'Design', line('down'))
    check('and on to the one after', cur('down again') == 'Music', line('down again'))
    # an arrow drawn or not: the spread of the pixels in a 36 px box where it sits, level with the
    # toolbar (a faint chevron over the blurred backdrop, against the backdrop alone)
    from PIL import Image, ImageStat
    places = dict(re.findall(r'(\w+)=(-?\d+)', line('places')))
    def ink(name, x):
        im = Image.open(out / name).convert('L')
        s = im.height / 1440
        x0 = im.width - round(3440 * s)
        row = int(places.get('row', 52))
        box = im.crop((x0 + round((x - 14) * s), round((row - 14) * s), x0 + round((x + 14) * s), round((row + 14) * s)))
        return ImageStat.Stat(box).stddev[0]
    if places and (out / 'rest.png').exists() and (out / 'last.png').exists():
        r_up, r_down = ink('rest.png', int(places['up3'])), ink('rest.png', int(places['down3']))
        l_up, l_down = ink('last.png', int(places['up2'])), ink('last.png', int(places['down2']))
        # an arrow with nowhere to go stays, dimmed (to 35 %)
        check("in the first group ^ is dimmed and v isn't", r_up > 0.5 and r_down > 1.8 * r_up, f'ink at ^ {r_up:.1f}, at v {r_down:.1f}')
        check("in the last group v is dimmed and ^ isn't", l_down > 0.5 and l_up > 1.8 * l_down, f'ink at ^ {l_up:.1f}, at v {l_down:.1f}')
        # in the middle group (Games: a name of another length) both sit where they sat in the first
        if (out / 'middle.png').exists():
            m_up, m_down = ink('middle.png', int(places['up3'])), ink('middle.png', int(places['down3']))
            check('with another group\'s name in the pill, ^ and v stay where they were, both lit', m_up > 1.8 * r_up and m_down > 0.5,
                  f'ink at ^ {m_up:.1f}, at v {m_down:.1f}')
        # pointed at, v shows the next group's name, growing left from v, clear of the pill beside it
        # (a label sat under the add tile, November 13, 2026): what changes in the label's rows
        # ends no further right than v
        if (out / 'pointed.png').exists():
            from PIL import ImageChops
            def band(name):
                im = Image.open(out / name).convert('L')
                s = im.height / 1440
                x0 = im.width - round(3440 * s)
                row = int(places.get('row', 52))
                return im.crop((x0, round((row + 14) * s), im.width, round((row + 48) * s))), s, x0
            a, s, x0 = band('rest.png')
            b, _, _ = band('pointed.png')
            diff = ImageChops.difference(a, b).point(lambda v: 255 if v > 40 else 0)
            box = diff.getbbox()
            v_right = int(places['down3']) + 20
            right = (box[2] / s) if box else None
            check("v's label grows away from the pill", box is not None and right <= v_right + 2,
                  f'label to {right:.0f} px, v to {v_right} px' if box else 'no label drawn')
    else:
        check('the arrows drawn where they belong', False, 'no pictures or places')
    check('^ goes back a group, and to the desktop you last used there', cur('up') == 'Design' and cur('up again') == 'Work', f"{line('up')} / {line('up again')}")
    arrived = int(line('arrived') or 0)
    held = [(n, int(t) - arrived) for n, t in re.findall(r'(\w+) (\d+);', line('switches')) if int(t) >= arrived]
    check('a window held on v moves the view to the next group after the pause', len(held) >= 1 and held[0][0] == 'Design' and 850 <= held[0][1] <= 1400, held)
    check('and let go on the view, it lands there', line('dolphin').startswith('Design ') and cur('dolphin') == 'Design', line('dolphin'))
elif scenario in ('beacons', 'plant-beacons'):
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    places = dict((k, float(v)) for k, v in re.findall(r'(\w+)=(-?[\d.]+)', (re.search(r'places: (.*)', steps) or [None, ''])[1]))
    check('the test windows asked for attention', 'kate true' in steps and 'konsole true' in steps, (re.search(r'asking: (.*)', steps) or [None, 'none'])[1])
    from PIL import Image
    def orange(name, x0l, y0l, x1l, y1l):
        """How many pixels in a box (logical px on the main screen) sit inside a solid patch of the
        accent (Ecto green, the test's default): each one and its eight neighbours that color (a
        beacon's dot is; the colored fringes of subpixel-rendered text, a pixel wide, aren't)."""
        im = Image.open(out / name).convert('RGB')
        s = im.height / 1440
        ox = im.width - round(3440 * s)
        box = im.crop((ox + round(x0l * s), round(y0l * s), ox + round(x1l * s), round(y1l * s)))
        bw, bh = box.size
        px = box.load()
        hit = {(x, y) for y in range(bh) for x in range(bw)
               if (lambda r, g, b: abs(r - 200) < 45 and g > 200 and b < 110)(*px[x, y])}
        return sum(1 for (x, y) in hit if all((x + dx, y + dy) in hit for dx in (-1, 0, 1) for dy in (-1, 0, 1)))
    if places and all((out / n).exists() for n in ('asking.png', 'list.png', 'one.png', 'none.png')):
        mw = places['mw']
        w = 90 * mw / 1440
        x0 = (mw - (3 * w + 2 * 8)) / 2
        # the beacon sits after the desktop's name, under its thumbnail (the thumbnail 90 tall from
        # y 7, the name's row below it)
        tile = lambda i: (x0 + i * (w + 8), 105, x0 + i * (w + 8) + w, 125)
        pill = (places['pr'] - places['mx'] - 14, 128, places['pr'] - places['mx'] + 8, 148)
        on_code, on_work = orange('asking.png', *tile(1)), orange('asking.png', *tile(0))
        check('a desktop where a window asks for attention gets a beacon', on_code >= 6, f'{on_code} attention pixels at Code')
        check('and a desktop where none asks gets none', on_work == 0, f'{on_work} at Work')
        # every desktop keeps a grey dot left of its name: Work's, just left of its centered name
        def grey(name, x0l, y0l, x1l, y1l):
            im = Image.open(out / name).convert('RGB')
            s = im.height / 1440
            ox = im.width - round(3440 * s)
            box = im.crop((ox + round(x0l * s), round(y0l * s), ox + round(x1l * s), round(y1l * s)))
            bw, bh = box.size
            px = box.load()
            hit = {(x, y) for y in range(bh) for x in range(bw)
                   if (lambda r, g, b: max(r, g, b) - min(r, g, b) < 32 and 75 < (r + g + b) / 3 < 160)(*px[x, y])}
            return sum(1 for (x, y) in hit if all((x + dx, y + dy) in hit for dx in (-1, 0, 1) for dy in (-1, 0, 1)))
        work_c = x0 + w / 2
        on_work_grey = grey('asking.png', work_c - 52, 105, work_c - 20, 125)
        check('a desktop where none asks keeps a grey dot', on_work_grey >= 6, f'{on_work_grey} grey pixels left of Work')
        on_pill = orange('asking.png', *pill)
        check("the groups' pill gets one for a group that isn't shown", on_pill >= 4, f'{on_pill} at the pill')
        rows = places['pr'] - places['mx'] - 80, places['pr'] - places['mx'] + 250
        row = lambda i: (rows[0], 176 + 4 + 30 + 44 * i, rows[1], 176 + 4 + 30 + 44 * (i + 1))
        # Desktops holds Code (Kate asks) and Games holds Design (Konsole asks); Hidden, below the
        # line, holds Music, where nothing asks
        r_desk, r_games = orange('list.png', *row(0)), orange('list.png', *row(1))
        r_hidden = orange('list.png', rows[0], 176 + 4 + 30 + 44 * 2 + 9, rows[1], 176 + 4 + 30 + 44 * 3 + 9)
        check("and each group's row in the list where a desktop asks, and no other", r_desk >= 4 and r_games >= 4 and r_hidden == 0,
              f'{r_desk} on Desktops, {r_games} on Games, {r_hidden} on Hidden')
        one_pill, one_code = orange('one.png', *pill), orange('one.png', *tile(1))
        check("when only the shown group asks, the pill's beacon goes and the desktop's stays", one_pill == 0 and one_code >= 6, f'pill {one_pill}, Code {one_code}')
        none = orange('none.png', *tile(1)) + orange('none.png', *pill)
        check('when nothing asks, no beacons', none == 0, f'{none} attention pixels left')
        # a window on a Hidden desktop asks: nothing lights (the owner's ruling, 2026-11-17: Hidden
        # desktops stay quiet; proven on the build that lit them: pill 144, Hidden row 104)
        if (out / 'hidden.png').exists() and (out / 'hidden-list.png').exists():
            h_pill = orange('hidden.png', *pill)
            h_row = orange('hidden-list.png', rows[0], 176 + 4 + 30 + 44 * 2 + 9, rows[1], 176 + 4 + 30 + 44 * 3 + 9)
            check("a window asking on a Hidden desktop lights nothing: not the groups' pill, not the Hidden row",
                  h_pill == 0 and h_row == 0, f'pill {h_pill}, Hidden row {h_row}')
        else:
            check('the Hidden beacon pictured', False, 'no hidden.png or hidden-list.png')
    else:
        check('the beacons pictured', False, 'no pictures or places')
elif scenario == 'terminalbeacon':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    if 'skipped: no HOOK given' in steps:
        print('  SKIP  no HOOK given')
    else:
        asks = (re.search(r'asks: (.*)', steps) or [None, ''])[1]
        flagged = [e.rsplit(' ', 1)[0] for e in asks.split(';') if e.endswith(' true')]
        check('the helper flagged its own terminal window, and only that one',
              len(flagged) == 1 and 'beacon-test' in flagged[0], asks)
        from PIL import Image
        places = dict((k, float(v)) for k, v in re.findall(r'(\w+)=(-?[\d.]+)', (re.search(r'places: (.*)', steps) or [None, ''])[1]))
        if places and (out / 'asking.png').exists():
            im = Image.open(out / 'asking.png').convert('RGB')
            s = im.height / 1440
            ox = im.width - round(3440 * s)
            mw = places['mw']; w = 90 * mw / 1440; x0 = (mw - (5 * w + 4 * 8)) / 2
            def solid(i):
                box = im.crop((ox + round((x0 + i * (w + 8)) * s), round(105 * s), ox + round((x0 + i * (w + 8) + w) * s), round(125 * s)))
                bw, bh = box.size; px = box.load()
                hit = {(x, y) for y in range(bh) for x in range(bw) if (lambda r, g, b: abs(r - 200) < 45 and g > 200 and b < 110)(*px[x, y])}
                return sum(1 for (x, y) in hit if all((x + dx, y + dy) in hit for dx in (-1, 0, 1) for dy in (-1, 0, 1)))
            check("Ectoview shows a beacon on the terminal's desktop", solid(1) >= 6 and solid(0) == 0, f'Code {solid(1)}, Work {solid(0)}')
        else:
            check('the beacon pictured', False, 'no picture or places')
elif scenario == 'groupreorder':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    ids = lambda v: [p.split(':')[0] for p in v.split(',') if p]
    check("a desktop group dragged by its row in the pill's list to the top goes to the top", ids(line('media up')) == ['g2', 'desktops', 'g1'], line('media up'))
    check('then dragged down a place, it goes down a place', ids(line('media down')) == ['desktops', 'g2', 'g1'], line('media down'))
elif scenario == 'reorderstill':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    m = re.search(r'after drag: (.*)', steps)
    after = m.group(1).strip() if m else ''
    check('Music dragged to the front of the bar goes to the front, and you stay on Work', after == 'Music,Work,Code,Design current Work', after)
    # the big view (below the toolbar) a moment after the drop against the same once settled: the view
    # shows the same desktop throughout, so nothing should move there
    from PIL import Image, ImageChops, ImageStat
    def view_region(name):
        im = Image.open(out / name).convert('RGB')
        s = im.height / 1440
        x0 = im.width - round(3440 * s)
        return im.crop((x0 + round(260 * s), round(260 * s), x0 + round(3180 * s), round(1400 * s)))
    if (out / 'mid.png').exists() and (out / 'settled.png').exists():
        d = ImageStat.Stat(ImageChops.difference(view_region('mid.png'), view_region('settled.png'))).mean
        moved = sum(d) / 3
        check('the big view stays still while the bar reorders (no desktop sweeps across it)', moved < 1.5, f'mean difference just after the drop against settled: {moved:.1f}')
        # and the other screen's view, below its bar and toolbar (it slid there, between two desktops)
        def other_region(name):
            im = Image.open(out / name).convert('RGB')
            s = im.height / 1440
            x0 = im.width - round(3440 * s)
            return im.crop((0, round(im.height * 0.6), x0, im.height))
        d = ImageStat.Stat(ImageChops.difference(other_region('mid.png'), other_region('settled.png'))).mean
        moved = sum(d) / 3
        check("the other screen's view stays still too", moved < 1.5, f'mean difference just after the drop against settled: {moved:.1f}')
    else:
        check('the big view stays still while the bar reorders (no desktop sweeps across it)', False, 'no pictures')
elif scenario == 'wheelclose':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    # the wheel comes through KWin's EIS input (eis-wheel.py), with its 120-unit step
    opened = line('open wheel').endswith('current Code')
    check('with Ectoview open the wheel over the bar switches desktops (the test wheel reaches it)', opened, line('open wheel'))
    check('once Ectoview is closing, the wheel switches nothing', opened and line('closing wheel').endswith('current Work'), line('closing wheel'))
elif scenario in ('wheelbar', 'plant-wheelbar'):
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search('^' + k + r': (.*)$', steps, re.M)
        return m.group(1).strip() if m else ''
    def parse(k):
        m = re.match(r'(\S+) current (.+)$', line(k))
        return (m.group(1).split(','), m.group(2)) if m else ([], '')
    names, first = parse('start')
    nxt = names[names.index(first) + 1] if first in names and names.index(first) + 1 < len(names) else '?'
    check('the wheel over the big desktop view switches nothing', parse('view wheel')[1] == first, line('view wheel'))
    check('the wheel below the bar, low in the view, switches nothing', parse('low wheel')[1] == first, line('low wheel'))
    check('one detent toward you over the bar is the next desktop', parse('bar wheel')[1] == nxt, f"{line('bar wheel')} (expected {nxt})")
    check('one detent away over the bar is the desktop before', parse('bar wheel back')[1] == first, line('bar wheel back'))
elif scenario == 'crossscreen':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    after = line('after')
    m = re.match(r'(\S+) on (\S+) left (\S+)', after)
    check("a window dragged onto the windows-only screen lands there, on that screen's own desktop",
          m and m.group(2) == 'Virtual-0' and m.group(1) == m.group(3), f'before: {line("before")}; after: {after}')
elif scenario == 'windrag':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    # (a window dropped into another desktop group takes you to the desktop it landed on)
    check("a window dropped on a desktop group's row in the pill's list goes to that group's desktop, and you go with it",
          line('kate').startswith('Design ') and line('kate').endswith('current Design'), line('kate'))
    check("held on a row, the bar shows that group, and the window dropped on one of its desktops lands there, and so do you",
          line('dolphin').startswith('Music ') and line('dolphin').endswith('current Music'), line('dolphin'))
    check("held on a row and brought back to the view, the window stays and so do you",
          line('konsole back').startswith('Work ') and line('konsole back').endswith('current Work'), line('konsole back'))
    kon = line('konsole')
    check("a window dropped on New desktop group gets a new group and desktop of its own, and you go with it",
          kon.startswith('Desktop 5 ') and re.search(r'groups=desktops:Desktops,g1:Games,g[0-9a-z]+:Desktop group 3 ', kon) and kon.endswith('current Desktop 5'), kon)
    a, b = img('peek-back'), img('after-peek')
    if a and b:
        bar = (MAIN[0] + MAIN[2] // 2 - 600, 0, 1200, 120)
        check('after the drop the bar shows your own group again', changed(a, b, bar)[0] > 0.05, f'{changed(a, b, bar)[0]:.0%} of the bar changed')
elif scenario in ('windows', 'plant-windows'):
    if scenario == 'windows':
        common()
    windows_rules()
elif scenario == 'every':
    common()
    d, o = img('desktop'), img('overview')
    share, _ = changed(d, o, LEFT)
    check('with "Every screen", Ectoview opens on the dashboard screen too', share > 0.2, f'{share:.1%} changed')
elif scenario == 'install':
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    def field(text, name):
        m = re.search(r'(?:^|\s)' + re.escape(name) + r'=(\(.*?\))(?=\s+\w+=|$)', text)
        return m.group(1) if m else ''
    before, after, gone = line('before'), line('after install'), line('after uninstall')
    none = ('(@a(ai) [],)', '([],)', '')
    check('to start, KWin runs Overview with Meta+W', 'loaded=overview' in before and field(before, 'Overview') not in none, before)
    installed_ok = re.search(r'^install exit 0$', steps, re.M) is not None
    check('install.sh finished', installed_ok, '' if installed_ok else (out / 'install-run.log').read_text(errors='replace')[-600:])
    check('after install KWin runs Ectoview and not Overview', 'loaded=ectoview' in after and 'overview' not in field(after, 'loaded'), after)
    check("Overview's Meta+W moved to Ectoview", field(after, 'Ectoview') == field(before, 'Overview') and field(after, 'Overview') in none, after)
    check("Overview's Meta+G moved to Ectoview's Grid View", field(after, 'EctoviewGrid') not in none and field(after, 'GridView') in none, after)
    check('kwinrc has Overview off and Ectoview on', 'overviewEnabled=false' in line('plugins') and 'ectoviewEnabled=true' in line('plugins'), line('plugins'))
    d, so, eo, sa = img('desktop'), img('stock-open'), img('ectoview-open'), img('stock-again')
    if d and so and eo and sa:
        check('Meta+W opened Overview before the install', changed(d, so, MAIN)[0] > 0.2)
        check('the real Meta+W key opens Ectoview after it (not Overview)', changed(d, eo, MAIN)[0] > 0.2 and changed(so, eo, MAIN)[0] > 0.05, f'{changed(so, eo, MAIN)[0]:.1%} differs from stock Overview')
        check('after uninstall Meta+W opens Overview again', changed(d, sa, MAIN)[0] > 0.2 and changed(so, sa, MAIN)[0] < 0.02, f'{changed(so, sa, MAIN)[0]:.2%} differs from stock Overview before')
    else:
        check('pictures taken', False)
    kcm_log = (out / 'kcmshell.log').read_text(errors='replace') if (out / 'kcmshell.log').exists() else ''
    m = re.search(r'settings window .*"width":(\d+),"height":(\d+)', steps)
    big = m and int(m.group(1)) > 560 and int(m.group(2)) > 500
    found = big and not re.search(r'module .*not found|could not (find|load)|cannot load', kcm_log, re.I)
    check('System Settings finds the settings page through the session script (its window, not an error)', found, (m.group(0) if m else 'no window') + ' ' + kcm_log[-300:])
    g = re.search(r'gear window .*"width":(\d+),"height":(\d+)', steps)
    check("the gear beside search opens Ectoview's settings page (its window, before any new login)", g and int(g.group(1)) > 560 and int(g.group(2)) > 500, g.group(0) if g else 'no window')
    ag = img('after-gear')
    if d and ag:
        check('and Ectoview closes as it opens', changed(d, ag, MAIN)[0] < 0.25, f'{changed(d, ag, MAIN)[0]:.1%} of the main screen differs from the desktop (the settings window is open on it)')
    update_rules()
    uninstalled_ok = re.search(r'^uninstall exit 0$', steps, re.M) is not None
    check('uninstall.sh finished', uninstalled_ok, '' if uninstalled_ok else (out / 'uninstall-run.log').read_text(errors='replace')[-600:])
    check('after uninstall KWin runs Overview again, not Ectoview', 'loaded=overview' in gone and 'ectoview' not in field(gone, 'loaded'), gone)
    check("Overview has its own keys back", field(gone, 'Overview') == field(before, 'Overview'), gone)
    check('uninstall leaves nothing behind (effect, settings page, session script, records, kwinrc entries)', line('leftovers').strip() == '0', line('leftovers'))
elif scenario == 'overflow':
    common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    m = re.search(r'after drag: (\S+)', steps)
    order = m.group(1).split(',') if m else []
    # 15 thumbnails fit across the test's 3440 px screen; a drop past them needs the bar to scroll
    place = order.index('D2') if 'D2' in order else -1
    check('held at the end of a bar that overflows, a dragged desktop scrolls it and lands past the first screenful', place >= 15, f'D2 landed at place {place + 1} of {len(order)}: {",".join(order)}')
    check('the other desktops keep their order', [d for d in order if d != 'D2'] == [f'D{i}' for i in range(1, 21) if i != 2], ','.join(order))
elif scenario in ('reorder', 'plant-reorder'):
    if scenario == 'reorder':
        common()
    steps = (out / 'steps.log').read_text(errors='replace') if (out / 'steps.log').exists() else ''
    def line(k):
        m = re.search(k + r': (.*)', steps)
        return m.group(1).strip() if m else ''
    check('the test started from Work, Code, Design, Music', line('before').startswith('Work,Code,Design,Music'), line('before'))
    check('dragging Music onto the second place moves it there in KWin', line('after drag').startswith('Work,Music,Code,Design'), line('after drag'))
    check('the desktop you were on stays current', line('after drag').endswith('current Work'), line('after drag'))
    check('a plain click on a desktop still switches to it', line('after click').endswith('current Code'), line('after click'))
if scenario.startswith('plant-'):
    if scenario == 'plant-primary':
        primary_rules()
    if scenario == 'plant-update':
        update_rules()
    caught = any(not ok for _, ok, _, k in results)
    for name, ok, detail, known in results:
        print(f'  {"pass" if ok else "FAIL"}  {name}  {detail}')
    print(f'{"PLANT CAUGHT" if caught else "PLANT MISSED"}: {scenario}')
    sys.exit(0 if caught else 1)

bad = 0
for name, ok, detail, known in results:
    word = ('XPASS' if ok else 'XFAIL') if known else ('PASS' if ok else 'FAIL')
    print(f'  {word}  {name}' + (f'  ({detail})' if detail else '') + (f'\n         known: {known}' if known and not ok else ''))
    bad += (not ok) and not known
print(f'{scenario}: {sum(1 for r in results if r[1])} of {len(results)} passed' + (f', {sum(1 for r in results if r[3] and not r[1])} known failure' if any(r[3] and not r[1] for r in results) else ''))
sys.exit(1 if bad else 0)
