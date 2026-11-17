<h1 align="center">Ectoview</h1>

<p align="center">
  <strong>Overview, evolved.</strong><br>
  KDE Plasma's Overview, with desktop groups, notification beacons and desktops you can drag into order.<br>
  Keep your desktops sorted by what they're for, and see at a glance which one wants you.
</p>

<p align="center">
  <a href="#how-ectoview-improves-on-overview">Improvements</a> &nbsp;·&nbsp;
  <a href="#desktop-groups">Desktop groups</a> &nbsp;·&nbsp;
  <a href="#notification-beacons">Beacons</a> &nbsp;·&nbsp;
  <a href="#moving-desktops-and-windows">Moving things</a> &nbsp;·&nbsp;
  <a href="#your-screens">Screens</a> &nbsp;·&nbsp;
  <a href="#ectos-look-or-kdes">Look</a> &nbsp;·&nbsp;
  <a href="#installing">Installing</a>
</p>

<br>

<p align="center">
  <img src="docs/pictures/readme-hero.webp" width="100%" alt="Meta+W pressed on a desktop with a terminal and a text editor. Ectoview opens: the Work group's desktops Code, Review, Docs and Mail in the bar along the top, the groups' button reading Work with its up and down arrows, the search field and the settings gear, and the desktop large below. A window in the Play group asks for attention and a dot lights on the groups' button. The down arrow takes the bar to the Home group, its desktops rising in; the up arrow brings Work back. Review is chosen from the bar and Ectoview closes onto it">
</p>

Ectoview is a fork of Overview, the effect behind Meta+W in KDE Plasma 6. It keeps
everything Overview does: your windows laid out, the desktop bar, search through KRunner,
Grid View, dragging windows between desktops. It installs for you alone, in place of
Overview, with Overview's shortcuts and screen edges, and `./uninstall.sh` puts Overview
back as it was.

**Install it** on KDE Plasma 6.7 on Wayland: `./install.sh` from this folder builds the
settings page and switches Overview for Ectoview, no root needed. Ectoview itself is QML,
so a KWin update doesn't need it rebuilt. [Installing](#installing).

## How Ectoview improves on Overview

Each row is a change from Overview in KWin 6.7.5, the version Ectoview started from, the
biggest first. Each links to its section.

| | Overview | Ectoview |
|---|---|---|
| [Desktop groups](#desktop-groups) | ❌ One long row of every desktop | ✅ Desktops sorted into groups you name (Work, Home, Play), one group in the bar at a time, stepped through with ^ and v or four new shortcuts |
| [Notification beacons](#notification-beacons) | ❌ No: you find the desktop with the window that wants you | ✅ A dot beside each desktop's name lights when a window there asks for attention, and the groups' button lights for a group you aren't looking at |
| [Hidden desktops](#hidden-desktops) | ❌ No | ✅ A Hidden group: desktops kept out of the bar and out of Grid View until you open it |
| [Drag desktops into order](#drag-desktops-into-order) | Only in Grid View, by dropping a desktop on another | In the bar too, sliding the others aside, and the bar scrolls along when you reach its end |
| [Carry a window to another desktop](#carry-a-window-to-another-desktop) | Drop it on a desktop in the bar | Also hold it on the < or > beside the big view: after a pause the view moves on, carrying the window |
| [Group shortcuts with Ectoview closed](#step-through-groups) | — | The new group's desktop rises in where you are, instead of the screen sliding sideways past every desktop between |
| [Many desktops](#many-desktops) | The row scrolls when flicked, cut off sharply at its ends | < and > page along the row, and its ends fade into the backdrop |
| [Your screens](#your-screens) | On every screen | On every screen, or only its windows on the others, or the others left exactly as they are: for a screen you keep as a dashboard |
| [The scroll wheel](#the-scroll-wheel-and-clicks) | Switches desktops anywhere, even while Overview closes | Switches desktops only over the bar, and never while Ectoview closes |
| [Clicks that mean it](#the-scroll-wheel-and-clicks) | A click on the backdrop closes Overview | Only a click on a desktop or a window takes you somewhere; the backdrop and a faded arrow do nothing |
| [Ecto's look, or KDE's](#ectos-look-or-kdes) | Your KDE colors | Ecto's dark look in Geist, or your KDE colors and font, with an accent of your choice and how dark the backdrop gets |
| [Where the bar sits](#where-the-bar-sits) | Top | Top, bottom, left or right, with or without the toolbar |
| [A settings page in three tabs](#settings) | One page | General, Desktop groups and Shortcuts, a gear beside the search field to open it, and KWin's per-screen desktops switch and one-desktop shortcuts in it too |

<p align="center">
  <img src="docs/pictures/readme-vs-overview.webp" width="100%" alt="Overview and Ectoview on the same desktop, the divider sweeping from one to the other. Overview: every desktop in one row along the top and the search field. Ectoview: the Work group's four desktops, each with its dot beside its name, the groups' button with its arrows left of the search field, and the settings gear">
</p>

## Desktop groups

Sort your desktops by what they're for. The bar shows one group at a time: its desktops,
and the desktop you're on even when it's in another group. The groups' button left of the
search field names the group shown and opens the list of them.

<p align="center">
  <img src="docs/pictures/readme-groups.webp" width="70%" alt="The list of desktop groups open below the groups' button: Work with its first three desktops in small and 4 desktops, Home with 2, Play with 2, then Hidden with 1 desktop, not in the bar, and New desktop group">
</p>

- **Choose a group** from the list, and you go to the desktop you last used in it.
- **Make, rename, reorder and remove** groups in the list: New desktop group at its foot,
  the pencil and the cross on a row as you point at it, and a row dragged up or down.
  Removing a group moves its desktops to the first group; nothing is deleted.
- **Put a desktop in a group** by dragging it from the bar onto the groups' button and then
  onto a group's row, or with the move button on a desktop in the bar.

<p align="center">
  <img src="docs/pictures/readme-desktop-to-group.webp" width="70%" alt="Docs dragged from the bar onto the groups' button: the list opens, and Docs dropped on Home's row moves to Home">
</p>

### Step through groups

^ and v at the right end of the groups' button step to the previous and next group, at the
same place whatever the group is called. At the first or last group, the arrow with nowhere
to go dims. The bar's desktops lift away and the next group's rise in.

Four shortcuts, with no keys until you give them some in the settings: Next and Previous
Desktop Group, and Next and Previous Desktop in Desktop Group. They work with Ectoview
closed too. With it closed, a group shortcut brings the next group's desktop rising in over
the one you're on, the way a group changes in Ectoview, instead of KWin sliding the screen
sideways past every desktop between.

<p align="center">
  <img src="docs/pictures/readme-shortcut.webp" width="100%" alt="Next Desktop Group pressed with Ectoview closed: the Code desktop with its terminal and editor stays where it is while the Home group's Music desktop rises and fades in over it. Previous Desktop Group brings Code back the same way">
</p>

### Hidden desktops

Hidden is a group of its own: its desktops stay out of the bar and out of Grid View until
you choose Hidden in the list. The desktop you're on still shows in the bar, dimmed, with a
badge saying where it lives.

### Grid View, a row per group

Grid View lays your desktops out a row per group, each row headed with its group's name.
Drop a desktop on another row to move it to that group.

<p align="center">
  <img src="docs/pictures/readme-grid.webp" width="100%" alt="Grid View: a row for Work with Code, Review, Docs and Mail, a row for Home with Music and Photos, and a row for Play with Games and Chat, each row headed with its group's name">
</p>

### Search what you're working on

The caret at the end of the search field picks what search looks through: this desktop,
this group, or all desktops. KRunner's results for apps, files and more come after the
windows, as in Overview.

## Notification beacons

Every desktop has a dot left of its name. It's grey, and it lights in your accent with a
ring swelling from it when a window on that desktop asks for your attention. That's the
flag that makes a window's taskbar entry light up, so any app that asks for you lights its
desktop's dot, whatever the app. The dot goes out when you go to the window.

A desktop in a group you aren't looking at lights the groups' button, and its group's row
in the list.

<p align="center">
  <img src="docs/pictures/readme-beacons.webp" width="70%" alt="Ectoview open on the Work group. A window on Review asks for attention and the dot beside Review lights, a ring swelling from it. A window on Chat, in the Play group, asks too, and a dot lights on the groups' button. The list opens: Work and Play each have a lit dot beside their names">
</p>

## Moving desktops and windows

### Drag desktops into order

Drag a desktop along the bar and the others slide aside. Let go, and it moves in KWin's
own order, so the desktop switcher and the shortcuts follow. Near the bar's end it scrolls
along.

<p align="center">
  <img src="docs/pictures/readme-reorder.webp" width="70%" alt="Mail dragged from the end of the bar to the front, Code, Review and Docs sliding aside, and dropped first">
</p>

### Carry a window to another desktop

Drag a window onto a desktop in the bar, as in Overview, or onto a group's row in the list:
it goes to that group's desktop, and you with it. Hold a window on the < or > beside the
big view, and after a pause the view moves to the next desktop in the group, carrying it.
Let go there.

<p align="center">
  <img src="docs/pictures/readme-arrows.webp" width="100%" alt="The notes window dragged to the > at the right of the big view. After a pause the view slides on to the next desktop with the window still under the pointer, and it's let go there">
</p>

<p align="center">
  <img src="docs/pictures/readme-window-to-group.webp" width="100%" alt="The build terminal dragged from the big view onto the groups' button: the list opens, the terminal stays small over it, and dropped on Play's row it goes to Play's desktop, the view following">
</p>

### Many desktops

With more desktops than fit, < and > at the bar's ends page along it, and its ends fade
into the backdrop instead of stopping at a hard edge. The bar follows the desktop you
switch to.

<p align="center">
  <img src="docs/pictures/readme-overflow.webp" width="100%" alt="A group of twelve desktops: the bar shows as many as fit, its ends fading. The > at its right end pages along, then the < pages back">
</p>

## Your screens

Overview opens on every screen. Ectoview can, too, or on your other screens it can lay out
only that screen's windows, or leave the other screens exactly as they are, for one you
keep as a dashboard. A click on a screen left as it is closes Ectoview.

<p align="center">
  <img src="docs/pictures/readme-screens.webp" width="100%" alt="Two screens: a smaller one on the left showing a day's notes, and the main one. Ectoview opens on the main screen only; the notes screen stays exactly as it was">
</p>

## The scroll wheel and clicks

- **The wheel switches desktops only over the bar.** Over the big view it scrolls nothing,
  and a turn of the wheel just as Ectoview closes no longer switches you to another
  desktop.
- **Clicks that mean it.** Only a click on a desktop or a window takes you somewhere. A
  click on the backdrop around the view, or on a faded arrow, does nothing, so a near miss
  doesn't close Ectoview.

## Ecto's look, or KDE's

Ectoview comes in Ecto's dark look, in Geist, with Ecto green where you are. Or in your KDE
colors and font. Pick the accent (Ecto green, your KDE accent or a color of your own) and
how dark the backdrop gets.

<p align="center">
  <img src="docs/pictures/readme-ecto-look.webp" width="49%" alt="Ectoview's bar and toolbar in Ecto's look: near-black controls in Geist, the desktop you're on ringed in Ecto green">
  <img src="docs/pictures/readme-kde-look.webp" width="49%" alt="The same in KDE's Breeze Dark colors and Noto Sans, with KDE's blue accent">
</p>

### Where the bar sits

The bar goes along the top, bottom, left or right, and the toolbar can go: then the groups'
button and the gear sit at the bar's end.

## Settings

The gear beside the search field opens Ectoview's settings, also in System Settings under
Window Management, Desktop Effects. Three tabs:

- **General:** the look, the accent, the backdrop's darkness, where the bar sits and the
  toolbar, what the other screens show, and KWin's own Switch desktops independently for
  each screen.
- **Desktop groups:** your groups and which desktops are in each.
- **Shortcuts:** Ectoview's own, with KWin's one-desktop switches (left, right, up and
  down) beside them, like items together.

## Status

Ectoview 0.1, on KDE Plasma 6.7 (KWin 6.7.5) on Wayland. It's tested in a private,
off-screen KWin, never on the desktop you're using: every feature above has a scenario that
drives it with a real pointer and keys and checks what's drawn. What isn't done yet is in
[docs/deferred.md](docs/deferred.md).

## Installing

You need KDE Plasma 6.7 on Wayland, and to build the settings page CMake, KDE's Extra CMake
Modules and the development files for Qt 6 and KDE Frameworks 6 (Config, ConfigWidgets,
CoreAddons, GlobalAccel, I18n, KCMUtils, WidgetsAddons, XmlGui).

```bash
git clone https://github.com/Ectonomic/Ectoview.git
cd Ectoview
./install.sh
```

`install.sh`, with no root:

1. builds the settings page and installs it under `~/.local`;
2. installs the effect into `~/.local/share/kwin-wayland/effects/ectoview`;
3. tells the Plasma session where the settings page is, so System Settings finds it after
   you log out and in once (the gear finds it straight away);
4. turns Overview off and Ectoview on, carrying Overview's settings over;
5. moves Overview's shortcuts (Meta+W, Meta+G and the cycle keys) and screen edges to
   Ectoview.

Everything it changes is recorded in `~/.local/state/ectoview-install`. Run it again to
update: your settings and shortcuts stay, and the new build runs the next time you open
Ectoview, no logging out. `./uninstall.sh` puts Overview back, with its shortcuts.

## How it's built and tested

- `package/` is the effect: QML, loaded by KWin, Overview's views forked from KWin 6.7.5.
- `kcm/` is the settings page, C++ on KDE Frameworks 6, its settings generated from the
  effect's own `package/contents/config/main.xml` so the two can't drift.
- `tests/e2e/run.sh` runs a scenario in a headless KWin with its own D-Bus, Plasma and a
  fresh home, Ectoview installed as a stranger would install it: `SCENARIO=groups
  tests/e2e/run.sh OUT`. Each scenario checks what's drawn and what KWin holds, and fails on
  a QML error or a black screen. Planted faults (`SCENARIO=plant-…`) prove the checks catch
  what they guard.
- `tools/readme-pictures.sh` films this README's pictures in that same headless KWin.

## Staying close to KDE

`upstream/` holds Overview and the parts of KWin and Milou that Ectoview forks, untouched,
from KWin 6.7.5 and Plasma 6.7.5: diff against it to see every change Ectoview makes.

## License and credits

Ectoview is free software under the GNU General Public License, version 2 or later, as
KWin is: see [LICENSES/](LICENSES/). It's built from KWin's Overview by Vlad Zahorodnii and
KWin's contributors, and Milou's search results by its contributors. Geist is by Vercel,
under the SIL Open Font License. The wallpaper in the pictures is KDE Plasma's Waterfall by
Krystian Zajdel, under CC BY-SA 4.0.
