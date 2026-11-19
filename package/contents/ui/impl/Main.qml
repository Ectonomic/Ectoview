/*
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2022 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2023 Niccolò Venerandi <niccolo@venerandi.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import org.kde.kwin.private.effects
import org.kde.milou as Milou
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kcmutils as KCM

FocusScope {
    id: container
    focus: true

    readonly property QtObject effect: KWinComponents.SceneView.effect.impl
    readonly property QtObject targetScreen: KWinComponents.SceneView.screen

    readonly property bool lightBackground: Math.max(Kirigami.Theme.backgroundColor.r,
                                                     Kirigami.Theme.backgroundColor.g,
                                                     Kirigami.Theme.backgroundColor.b) > 0.5

    property bool animationEnabled: false
    property bool organized: false

    // Ectoview: where the desktop bar sits (Top, Bottom, Left, Right; Left and Right are a vertical
    // list) and whether the toolbar (search and the settings gear) shows, from the settings page.
    // Overview put the bar on the left on its own when the desktop grid had a single column.
    readonly property int barPosition: effect.barPosition
    // Ectoview: a screen other than the primary set to show only its windows: no bar, no toolbar
    readonly property bool windowsOnly: effect.windowsOnlyOn(targetScreen)
    readonly property bool showToolbar: effect.showToolbar && !windowsOnly
    property bool verticalDesktopBar: barPosition >= 2
    property QtObject currentDesktop: KWinComponents.SceneView.currentDesktop
    property point targetScreenDesktopOffset: effect.desktopOffsetForScreen(targetScreen);

    // The values of overviewVal and gridVal might not be 0 on startup,
    // but we always want to animate from 0 to those values. So, we initially
    // always set them to 0 and bind their full values when the effect starts.
    // See start()
    property real overviewVal: 0
    property real gridVal: 0

    states: [
        State {
            name: "initial"
            PropertyChanges {
                target: container
                overviewVal: 0
                gridVal: 0
            }
        },
        State {
            name: "grid"
            PropertyChanges {
                target: container
                overviewVal: 0
                gridVal: 1
            }
        },
        State {
            name: "overview"
            PropertyChanges {
                target: container
                overviewVal: 1
                gridVal: 0
            }
        },
        State {
            name: "partialOverview"
            PropertyChanges {
                target: container
                overviewVal: effect.overviewPartialActivationFactor
                gridVal: 0
            }
        },
        State {
            name: "partialGrid"
            PropertyChanges {
                target: container
                overviewVal: 0
                gridVal: effect.gridPartialActivationFactor
            }
        },
        State {
            name: "transition"
            PropertyChanges {
                target: container
                overviewVal: 1 - effect.transitionPartialActivationFactor
                gridVal: effect.transitionPartialActivationFactor
            }
        }
    ]
    state: {
        // If the effect hasn't started, we remain on the initial state
        if (!organized) return "initial";

        // If a gesture is ongoing, we use a partial state
        if (effect.overviewGestureInProgress) return "partialOverview";
        if (effect.gridGestureInProgress) return "partialGrid";
        if (effect.transitionGestureInProgress) return "transition";

        // If either the overview or grid gestures are completed, either
        // by a touchpad/touchscreen gesture or through a shortcut, we use
        // that state
        if (effect.overviewPartialActivationFactor === 1) return "overview";
        if (effect.gridPartialActivationFactor === 1) return "grid";

        // If neither is active, we are in the initial state.
        if (effect.overviewPartialActivationFactor + effect.gridPartialActivationFactor === 0) return "initial";

        // If we are in between a state but no gesture is going on, we snap to
        // the closest state
        if (overviewVal >= 0.5) return "overview";
        if (gridVal >= 0.5) return "grid";
        return "initial";
    }
    transitions: Transition {
        to: "initial, grid, overview"
        NumberAnimation {
            duration: effect.animationDuration
            properties: "gridVal, overviewVal"
            easing.type: Easing.OutCubic
        }
    }

    // Ectoview: desktop groups (design proposal 4). The view shows one group: the current desktop's
    // when it opens and whenever you switch desktops. Moving the desktop you're on to another group
    // keeps this one shown (that desktop stays in the bar, dimmed, until you leave it).
    property string viewGroup: effect.groupOf(currentDesktop)
    onCurrentDesktopChanged: setViewGroup(effect.groupOf(currentDesktop), true)
    // Ectoview: changing the shown group (design proposal 11): the bar's desktops slide up and away as
    // the new group's slide up into place, down for a group higher in the pill's list; with `newView`
    // the big view switches desktops too, the one you were on sliding out of the view's frame as the
    // new one slides in (not sideways: that would say "next desktop"). Instant animations skip it.
    property bool switchingGroup: false
    function groupPlace(id) {
        const i = effect.groups.findIndex(g => g.id === id);
        return i >= 0 ? i : effect.groups.length;  // Hidden is last
    }
    function setViewGroup(id, newView) {
        if (id === viewGroup) {
            return;
        }
        const animate = organized && overviewVal === 1 && !windowsOnly && effect.animationDuration > 0;
        if (animate) {
            const direction = groupPlace(id) >= groupPlace(viewGroup) ? 1 : -1;
            bar.beginGroupTransition(direction);
            if (newView) {
                // the view you're on slides up and away inside the view's frame as the new group's
                // desktop slides up into it (down for a group higher in the list; design proposal 11)
                switchingGroup = true;
                slideDirection = direction;
                slideClip = viewRect;
                stepFrom = currentDesktop;
                openSliding = true;
                stepIn = 0;
                openSlide.restart();
            }
        }
        viewGroup = id;
    }
    NumberAnimation {
        id: openSlide
        target: container
        property: "stepIn"
        from: 0
        to: 1
        duration: effect.animationDuration
        easing.type: Easing.OutCubic
        onStopped: {
            container.openSliding = false;
            container.stepFrom = null;
            container.switchingGroup = false;
        }
    }
    // a group change sliding: the desktop left (stepFrom) and the one arrived, by stepIn (0 to 1),
    // up for a group further down the list (slideDirection 1), down for one higher (-1); open, inside
    // the view's frame as it stood (slideClip), closed, the whole screen
    property bool openSliding: false
    property int slideDirection: 1
    property rect slideClip: Qt.rect(0, 0, 0, 0)
    readonly property bool sliding: stepping || openSliding
    readonly property real slideDistance: openSliding ? slideClip.height + 24 : height
    // ---- a group shortcut with Ectoview closed (Effect.qml stepGroup): on your screen's view, in its
    // first frame (the desktop as it is), the desktop switches, the one you left slides up and off the
    // screen as the new one slides up into place (down for the previous group), as a group change
    // does in Ectoview
    readonly property bool stepping: effect.groupStepping && targetScreen === KWinComponents.Workspace.activeScreen
    onSteppingChanged: if (stepping) stepSwitch.start()
    property QtObject stepFrom: null
    property real stepIn: 1
    ParallelAnimation {
        id: stepAnimation
        NumberAnimation { target: container; property: "stepIn"; from: 0; to: 1; duration: effect.animationDuration; easing.type: Easing.OutCubic }
        onStopped: {
            container.stepFrom = null;
            container.switchingGroup = false;
            effect.endGroupStep();
        }
    }
    // (here on the view, not in the timer: KWin finds a screen's desktop from the view's own items)
    function stepNow() {
        if (!stepping || !effect.groupStepTarget) {
            return;
        }
        switchingGroup = true;
        stepIn = 0;
        slideDirection = effect.groupStepDirection;
        stepFrom = currentDesktop;
        KWinComponents.SceneView.currentDesktop = effect.groupStepTarget;
        stepAnimation.restart();
    }
    Timer {
        id: stepSwitch
        interval: 50
        onTriggered: container.stepNow()
    }

    // a group removed from under the view, or no choice of groups left (the pill is gone): show the
    // current desktop's
    readonly property bool viewGroupGone: !effect.hasGroup(viewGroup) || (!effect.hasGroups && viewGroup !== effect.groupOf(currentDesktop))
    // (later, not inside the binding that noticed: viewGroup is one of its inputs)
    onViewGroupGoneChanged: if (viewGroupGone) Qt.callLater(() => setViewGroup(effect.groupOf(currentDesktop), true))
    // a new desktop at the end of KWin's order, in group `id` (the shown group unless said)
    function addDesktop(id) {
        const before = KWinComponents.Workspace.desktops.slice();
        desktopModel.create(desktopModel.rowCount());
        const made = KWinComponents.Workspace.desktops.find(d => before.indexOf(d) < 0);
        if (made) {
            effect.moveToGroup(made, id === undefined ? viewGroup : id);
        }
        return made || null;
    }
    // choosing a group from the pill: the desktop you're on if it's in that group, else the group's
    // last-used desktop (an empty group gets a new one)
    function chooseGroup(id) {
        const target = effect.groupOf(currentDesktop) === id ? currentDesktop : (effect.desktopForGroup(id) || addDesktop(id));
        setViewGroup(id, target !== currentDesktop);
        if (target) {
            KWinComponents.SceneView.currentDesktop = target;
        }
    }
    // New desktop group from the pill: the group, one new desktop in it, and you're there; returns its id
    function newGroup() {
        const before = KWinComponents.Workspace.desktops.slice();
        desktopModel.create(desktopModel.rowCount());
        const made = KWinComponents.Workspace.desktops.find(d => before.indexOf(d) < 0);
        const id = effect.addGroup("", made);
        setViewGroup(id, true);
        if (made) {
            KWinComponents.SceneView.currentDesktop = made;
        }
        return id;
    }
    // the keys go back to the search field (or the view, without a toolbar) when a list closes
    function restoreFocus() {
        if (searchField.enabled) {
            searchField.forceActiveFocus();
        } else {
            container.forceActiveFocus();
        }
    }

    // ---- a window dragged onto the groups' pill (EctoGroupPill.qml)
    // over the pill or its open list: the dragged window keeps its size; leaving, it eases back
    readonly property bool dragOverGroupMenu: !!bar.dropPill && bar.dropPill.windowOverMenu
    property bool dragScaleEasing: false
    onDragOverGroupMenuChanged: if (!dragOverGroupMenu) {
        dragScaleEasing = true;
        scaleEasingEnd.restart();
    }
    Timer {
        id: scaleEasingEnd
        interval: Kirigami.Units.shortDuration + 50
        onTriggered: container.dragScaleEasing = false
    }
    // a window being dragged in this view, from any desktop's heap (an arrow can switch the view's
    // desktop while the window is held)
    property int draggingHeaps: 0
    readonly property bool windowDragging: draggingHeaps > 0
    // the bar showing another group for a moment, while a window is held over that group's row
    property bool peeking: false
    function peekGroup(id) {
        setViewGroup(id, false);
        peeking = true;
    }
    // when the drag is over, the bar shows your desktop's group again
    onWindowDraggingChanged: if (!windowDragging && peeking) {
        peeking = false;
        Qt.callLater(() => setViewGroup(effect.groupOf(currentDesktop), false));
    }
    // a window dropped on a group's row goes to the group's last-used desktop (an empty group gets
    // a new one), and you go with it; a window on every desktop stays on every desktop, as the bar's
    // drops leave it
    function sendWindowToGroup(window, id) {
        if (!window || window.desktops.length === 0) {
            return;
        }
        const target = effect.desktopForGroup(id) || addDesktop(id);
        if (target) {
            window.desktops = [target];
            followWindowTo(target);
        }
    }
    // a window dropped into another desktop group takes you to the desktop it landed on;
    // a drop within your own group leaves you where you are, as Overview does
    function followWindowTo(desktop) {
        if (!desktop || desktop === currentDesktop) {
            return;
        }
        const id = effect.groupOf(desktop);
        if (id === effect.groupOf(currentDesktop)) {
            return;
        }
        peeking = false;
        setViewGroup(id, true);
        KWinComponents.SceneView.currentDesktop = desktop;
    }
    // ---- Ectoview: the desktop view's arrows (design proposal 7, revised). A plain < and > beside
    // the desktop view lead to the previous and next desktop in the shown group; the first desktop has
    // no <, the last no > (so a switch always slides the way its arrow points). A click goes there. A
    // window held on one: after a pause the view moves there, and on again after the same pause while
    // the window stays; a window dropped on one goes to that desktop and you stay where you are.
    readonly property var groupDesktops: KWinComponents.Workspace.desktops.filter(d => effect.groupOf(d) === viewGroup)
    function neighborDesktop(side) {
        const list = groupDesktops;
        const at = list.indexOf(currentDesktop);
        if (at < 0) {
            return list.length > 0 ? list[side > 0 ? 0 : list.length - 1] : null;
        }
        return list[at + side] || null;
    }
    // the view's desktop, set from the view (SceneView is attached to an item on screen; a timer
    // isn't one, and setting it there did nothing)
    function showDesktop(desktop) {
        if (desktop) {
            KWinComponents.SceneView.currentDesktop = desktop;
        }
    }
    // the pause before a held window switches desktops, and between switches while it stays
    readonly property int arrowHoldMs: 1000
    readonly property bool arrowsShown: effect.showSideArrows && overviewVal > 0 && gridVal < 1 && !windowsOnly && groupDesktops.length > 1
    // where the desktop view is (read again whenever it could have moved), without the slide of a
    // desktop switch in progress: the arrows stay put while the desktops slide past
    readonly property rect viewRect: {
        overviewVal; gridVal; width; height; currentDesktop;
        const b = allDesktopHeaps.currentBackgroundItem;
        if (!b) {
            return Qt.rect(0, 0, 0, 0);
        }
        const p = b.area.mapToItem(container, 0, 0);
        return Qt.rect(p.x - b.deltaColumn * b.width * (1 - gridVal), p.y - b.deltaRow * b.height * (1 - gridVal), b.area.width, b.area.height);
    }
    component SideArrow: EctoStepArrow {
        id: sideArrow
        required property int side
        readonly property QtObject target: container.neighborDesktop(side)
        readonly property rect view: container.viewRect
        // the gutter between the view and what's beside it: the screen's edge, or the desktop bar's
        // inner edge when the bar is on this side (the arrow was drawn over the bar before, taking
        // the clicks meant for its desktops)
        readonly property real gutter: side < 0 ? view.x - container.barLeftEdge : container.barRightEdge - view.x - view.width
        // 64 px off the view's edge, or the middle of a narrower gutter
        readonly property real offset: Math.max(20, Math.min(64, gutter / 2))
        readonly property real centerX: side < 0 ? view.x - offset : view.x + view.width + offset
        theme: effect.theme
        angle: side < 0 ? 180 : 0
        label: target ? target.name : ""
        holdMs: container.arrowHoldMs
        width: 120
        height: 220
        x: centerX - width / 2
        y: view.y + view.height / 2 - height / 2
        // above a window being dragged (z 1000), which would otherwise hide it
        z: 1100
        visible: container.arrowsShown && !!target
        opacity: container.overviewVal * (1 - container.gridVal)
        // a window dropped here goes to that desktop, and you stay where you are
        accepts: (window) => !!sideArrow.target && window.desktops.indexOf(sideArrow.target) === -1
        onActivated: container.showDesktop(sideArrow.target)
        onWindowDropped: (window) => window.desktops = [sideArrow.target]
    }
    SideArrow {
        id: previousArrow
        objectName: "arrow-previous"
        side: -1
    }
    SideArrow {
        id: nextArrow
        objectName: "arrow-next"
        side: 1
    }
    // where the arrows sit, beside the view and the bar, once Ectoview has opened (for the tests:
    // "Ectoview: side arrows")
    readonly property string sideArrowPlaces: overviewVal === 1 && gridVal === 0 && !windowsOnly && groupDesktops.length > 1 ? JSON.stringify({
        shown: arrowsShown,
        previous: previousArrow.visible ? previousArrow.centerX : null, next: nextArrow.visible ? nextArrow.centerX : null,
        glyph: nextArrow.glyphSize, click: nextArrow.clickWidth, barLeft: barLeftEdge, barRight: barRightEdge,
        viewLeft: viewRect.x, viewRight: viewRect.x + viewRect.width }) : ""
    onSideArrowPlacesChanged: if (sideArrowPlaces) console.info("Ectoview: side arrows " + targetScreen.name + " " + sideArrowPlaces)

    // a window dropped on New desktop group: the group, with a new desktop holding the window
    function newGroupForWindow(window) {
        if (!window || window.desktops.length === 0) {
            return;
        }
        const before = KWinComponents.Workspace.desktops.slice();
        desktopModel.create(desktopModel.rowCount());
        const made = KWinComponents.Workspace.desktops.find(d => before.indexOf(d) < 0);
        if (made) {
            effect.addGroup("", made);
            window.desktops = [made];
            followWindowTo(made);
        }
    }

    // what "This desktop group" searches: every window on a desktop of the shown group (or on all desktops)
    readonly property var groupWindowIds: {
        if (effect.searchScope !== 1) {
            return [];
        }
        const ids = KWinComponents.Workspace.desktops.filter(d => effect.groupOf(d) === viewGroup).map(d => d.id);
        const out = KWinComponents.Workspace.stackingOrder
            .filter(w => w.desktops.length === 0 || w.desktops.some(d => ids.indexOf(d.id) >= 0))
            .map(w => w.internalId);
        // (an empty list means "every window" to the heap)
        return out.length > 0 ? out : ["none"];
    }
    // the current desktop shows no window for this search (in "This desktop group", windows outside it don't count)
    readonly property bool currentHeapEmpty: allDesktopHeaps.currentHeap
        && (allDesktopHeaps.currentHeap.count === 0 || (effect.searchScope === 1 && allDesktopHeaps.currentHeap.activeEmpty))

    // Ectoview: the desktops the bar and Grid View draw (the shown group's, and the current one), by
    // their place in KWin's order; stepping through desktops (arrows, wheel, Page Up/Down) and
    // Overview's number keys and F-keys count these.
    readonly property var shown: effect.shownIndices(currentDesktop, viewGroup)
    readonly property int shownCount: shown.length
    function heapAt(place) {
        return allDesktopHeaps.itemAt(shown[place]);
    }

    // the current desktop's place among the shown ones
    function currentDesktopIndex() {
        for (let i = 0; i < allDesktopHeaps.count; i++) {
            if (allDesktopHeaps.itemAt(i).current) {
                return shown.indexOf(i);
            }
        }
        return 0;
    }

    function switchTo(desktop) {
        KWinComponents.SceneView.currentDesktop = desktop;
        effect.deactivate();
    }

    // ---- Ectoview: Grid View with desktop groups (design proposal 6, option B): every group a row,
    // in the pill's order, headed by its name; Hidden out unless you're on a hidden desktop or ask
    // for its row. With no group choice (one group, nothing hidden) Grid View is Overview's own.
    readonly property bool groupGrid: effect.hasGroups
    property bool hiddenRowShown: false
    readonly property var hiddenDesktops: effect.desktopsIn(effect.hiddenGroup)
    readonly property var gridGroups: {
        const out = [];
        for (const g of effect.groups) {
            const ds = effect.desktopsIn(g.id);
            if (ds.length > 0) {
                out.push({ id: g.id, name: g.name, desktops: ds, hidden: false });
            }
        }
        if (hiddenDesktops.length > 0 && (hiddenRowShown || effect.isHidden(currentDesktop))) {
            out.push({ id: effect.hiddenGroup, name: effect.groupName(effect.hiddenGroup), desktops: hiddenDesktops, hidden: true });
        }
        return out;
    }
    // the grid's room: a column of group names left of the desktops, the "hidden" line at the bottom
    readonly property real gridHeadWidth: groupGrid ? 300 : 0
    readonly property real gridFootHeight: groupGrid && hiddenDesktops.length > 0 ? 64 : 0
    // Ectoview: the group grid's layout (design proposal 10, lined up in columns): of every column
    // count, the one that draws the desktops biggest; a group with more desktops than that wraps
    // onto more lines, each starting under the first column; the whole grid centered on the screen.
    // (Logged when it changes, for the tests: "Ectoview: grid layout")
    readonly property var gridLayout: {
        if (!groupGrid) {
            return null;
        }
        const label = 40, margin = 40, groupGap = 24;
        const ns = gridGroups.map(g => g.desktops.length);
        const longest = Math.max(1, ...ns);
        let best = null;
        for (let c = 1; c <= longest; c++) {
            const lines = ns.reduce((a, n) => a + Math.ceil(n / c), 0);
            const cw = (width - gridHeadWidth - 2 * margin) / c;
            const ch = (height - gridFootHeight - 2 * margin - Math.max(0, ns.length - 1) * groupGap) / Math.max(1, lines) - label;
            const sc = Math.min(cw / width, ch / height);
            // a tie goes to fewer lines
            if (!best || sc > best.s + 1e-6) {
                best = { cols: c, lines: lines, s: sc };
            }
        }
        const cellW = best.s * width, cellH = best.s * height + label;
        const usedCols = Math.min(best.cols, longest);
        const gridW = gridHeadWidth + usedCols * cellW;
        const gridH = best.lines * cellH + Math.max(0, ns.length - 1) * groupGap;
        const x0 = Math.max(0, (width - gridW) / 2), y0 = Math.max(0, (height - gridFootHeight - gridH) / 2);
        const tops = [];
        let y = y0;
        for (const n of ns) {
            tops.push(y);
            y += Math.ceil(n / best.cols) * cellH + groupGap;
        }
        return { cols: best.cols, lines: best.lines, s: best.s, cellW: cellW, cellH: cellH, x0: x0, y0: y0, head: gridHeadWidth, tops: tops };
    }
    onGridLayoutChanged: if (gridLayout) console.info("Ectoview: grid layout " + targetScreen.name + " " + JSON.stringify(gridLayout))
    // the grid's lines as drawn (a long group's desktops on more than one), top to bottom
    readonly property var gridLines: {
        const out = [];
        if (!gridLayout) {
            return out;
        }
        gridGroups.forEach((g, gi) => {
            for (let i = 0; i < g.desktops.length; i += gridLayout.cols) {
                out.push({ group: gi, desktops: g.desktops.slice(i, i + gridLayout.cols), y: gridLayout.tops[gi] + i / gridLayout.cols * gridLayout.cellH });
            }
        });
        return out;
    }
    // each desktop's line and column in the group grid, and where it's drawn, by KWin's id for it
    readonly property var gridPos: {
        const out = {};
        // (no layout: Grid View with groups is closing, or not shown)
        if (!gridLayout) {
            return out;
        }
        gridLines.forEach((l, li) => l.desktops.forEach((d, c) => out[d.id] = {
            row: li, col: c, x: gridLayout.x0 + gridLayout.head + c * gridLayout.cellW, y: l.y }));
        return out;
    }
    // (groupGrid can change a moment before gridLayout follows it)
    readonly property bool gridLaidOut: groupGrid && !!gridLayout
    readonly property int gridColumnsN: gridLaidOut ? gridLayout.cols : columns
    readonly property int gridRowsN: gridLaidOut ? Math.max(1, gridLayout.lines) : rows
    readonly property real gridCellW: gridLaidOut ? gridLayout.cellW : (width - gridHeadWidth) / gridColumnsN
    readonly property real gridCellH: gridLaidOut ? gridLayout.cellH : (height - gridFootHeight) / gridRowsN
    // how small a desktop is drawn in the grid (Overview's 1 / the larger of rows and columns)
    readonly property real gridScaleS: Math.min(gridCellW / width, gridCellH / height)
    // a desktop dragged over another group's row in the grid: that group, lit up
    property string gridDropGroup: ""
    // a desktop dropped in another group's row goes to that group, at the end of its row
    function moveDesktopToGroup(desktop, id) {
        effect.moveToGroup(desktop, id);
        const members = effect.desktopsIn(id).filter(d => d !== desktop);
        if (members.length > 0) {
            const all = KWinComponents.Workspace.desktops;
            const last = all.indexOf(members[members.length - 1]), from = all.indexOf(desktop);
            effect.beginDesktopMove();
            KWinComponents.Workspace.moveDesktop(desktop, from < last ? last : last + 1);
        }
    }
    // arrow keys in the group grid: across a line, and up and down between lines as drawn (a long
    // group's second line is below its first)
    function selectNextInGroupGrid(direction) {
        const at = gridPos[currentDesktop ? currentDesktop.id : ""];
        if (!at) {
            return false;
        }
        let r = at.row, c = at.col, inverted;
        switch (direction) {
        case EctoWindowHeap.Direction.Up: r--; inverted = EctoWindowHeap.Direction.Down; break;
        case EctoWindowHeap.Direction.Down: r++; inverted = EctoWindowHeap.Direction.Up; break;
        case EctoWindowHeap.Direction.Left: c--; inverted = EctoWindowHeap.Direction.Right; break;
        case EctoWindowHeap.Direction.Right: c++; inverted = EctoWindowHeap.Direction.Left; break;
        }
        if (r < 0 || r >= gridLines.length || c < 0) {
            return false;
        }
        const row = gridLines[r].desktops;
        if (c >= row.length) {
            if (r === at.row) {
                return false;
            }
            c = row.length - 1;
        }
        const target = row[c];
        const heap = allDesktopHeaps.itemAt(KWinComponents.Workspace.desktops.indexOf(target));
        KWinComponents.SceneView.currentDesktop = target;
        if (heap) {
            heap.nestedHeap.focus = true;
            heap.selectLastItem(inverted);
        }
        return true;
    }

    function selectNext(direction) {
        if (effect.searchText !== "") return false;
        if (groupGrid && gridVal === 1) return selectNextInGroupGrid(direction);
        const currentIndex = currentDesktopIndex();
        let x = currentIndex % container.columns;
        let y = Math.floor(currentIndex / container.columns);

        // the direction we move in is the opposite of the window to select
        // i.e pressing left should select the rightmost window on the desktop
        // to the left
        let invertedDirection;
        switch(direction) {
            case EctoWindowHeap.Direction.Up:
                y--;
                invertedDirection = EctoWindowHeap.Direction.Down;
                break;
            case EctoWindowHeap.Direction.Down:
                y++
                invertedDirection = EctoWindowHeap.Direction.Up;
                break;
            case EctoWindowHeap.Direction.Left:
                x--;
                invertedDirection = EctoWindowHeap.Direction.Right;
                break;
            case EctoWindowHeap.Direction.Right:
                x++;
                invertedDirection = EctoWindowHeap.Direction.Left;
                break;
        }

        if (x < 0 || x >= container.columns) {
            return false;
        }
        if (y < 0 || y >= container.rows) {
            return false;
        }
        let newIndex = y * container.columns + x;

        KWinComponents.SceneView.currentDesktop = heapAt(newIndex).desktop;
        heapAt(newIndex).nestedHeap.focus = true
        heapAt(newIndex).selectLastItem(invertedDirection);
        return true;
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            if (effect.searchText !== "") {
                effect.searchText = ""
            } else {
                effect.deactivate();
            }
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            addDesktop();
        } else if (event.key === Qt.Key_Minus) {
            desktopModel.remove(desktopModel.rowCount() - 1);
        } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
            const place = event.key - Qt.Key_F1;
            if (place < shownCount) {
                switchTo(heapAt(place).desktop);
            }
        } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            const place = event.key === Qt.Key_0 ? 9 : (event.key - Qt.Key_1);
            if (place < shownCount) {
                switchTo(heapAt(place).desktop);
            }
        } else if (event.key === Qt.Key_Up) {
            event.accepted = selectNext(EctoWindowHeap.Direction.Up);
            if (!event.accepted) {
                let view = effect.getView(Qt.TopEdge)
                if (view) {
                    effect.activateView(view)
                }
            }
        } else if (event.key === Qt.Key_Down) {
            event.accepted = selectNext(EctoWindowHeap.Direction.Down);
            if (!event.accepted) {
                let view = effect.getView(Qt.BottomEdge)
                if (view) {
                    effect.activateView(view)
                }
            }
        } else if (event.key === Qt.Key_Left) {
            event.accepted = selectNext(EctoWindowHeap.Direction.Left);
            if (!event.accepted) {
                let view = effect.getView(Qt.LeftEdge)
                if (view) {
                    effect.activateView(view)
                }
            }
        } else if (event.key === Qt.Key_Right) {
            event.accepted = selectNext(EctoWindowHeap.Direction.Right);
            if (!event.accepted) {
                let view = effect.getView(Qt.RightEdge)
                if (view) {
                    effect.activateView(view)
                }
            }
        } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            const oldIndex = currentDesktopIndex();
            const delta = event.key === Qt.Key_PageUp ? -1 : +1;

            let newIndex;
            if (KWinComponents.Workspace.virtualDesktopNavigationWrapsAround) {
                newIndex = (oldIndex + shownCount + delta) % shownCount;
            } else {
                newIndex = Math.max(0, Math.min(shownCount - 1, oldIndex + delta));
            }

            KWinComponents.Workspace.currentDesktop = heapAt(newIndex).desktop;
            event.accepted = (newIndex !== oldIndex);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
            for (let i = 0; i < allDesktopHeaps.count; i++) {
                if (allDesktopHeaps.itemAt(i).current) {
                    switchTo(allDesktopHeaps.itemAt(i).desktop)
                    break;
                }
            }
        }
    }
    Keys.priority: Keys.AfterItem
    Keys.forwardTo: [allDesktopHeaps.currentHeap, searchField, searchResults]

    WheelHandler {
        property int wheelDelta: 0
        acceptedDevices: PointerDevice.Mouse
        // Ectoview: only while Ectoview is open, not while it animates closed (Overview took the wheel
        // until the closing animation ended, so a scroll just after closing switched desktops)
        enabled: container.state !== "initial"

        onWheel: (event) => {
            // Ectoview: the wheel switches desktops only over the desktop bar, anywhere along
            // it, and only while it shows (not in Grid View). A bar with more
            // desktops than fit follows the current desktop (DesktopBar.ensureVisible).
            const atBar = desktopBar.mapFromItem(container, point.position.x, point.position.y);
            if (desktopBar.opacity <= 0 || !desktopBar.contains(atBar)) {
                return;
            }
            const delta = (event.inverted ? -1 : 1) * (event.angleDelta.y ? event.angleDelta.y : -event.angleDelta.x);
            wheelDelta += delta;

            let currentIndex = container.currentDesktopIndex();
            // Magic number 120 for common "one click"
            // See: https://qt-project.org/doc/qt-5/qml-qtquick-wheelevent.html#angleDelta-prop
            while (wheelDelta >= 120) {
                wheelDelta -= 120;
                if (KWinComponents.Workspace.virtualDesktopNavigationWrapsAround) {
                    currentIndex = (currentIndex - 1 + container.shownCount) % container.shownCount;
                } else {
                    currentIndex = Math.max(0, currentIndex - 1);
                }
            }
            while (wheelDelta <= -120) {
                wheelDelta += 120;
                if (KWinComponents.Workspace.virtualDesktopNavigationWrapsAround) {
                    currentIndex = (currentIndex + 1) % container.shownCount;
                } else {
                    currentIndex = Math.min(container.shownCount - 1, currentIndex + 1);
                }
            }
            KWinComponents.Workspace.currentDesktop = container.heapAt(currentIndex).desktop;
        }
    }

    Item {
        width: backgroundItem.width
        height: backgroundItem.height
        KWinComponents.DesktopBackground {
            id: backgroundItem
            activity: KWinComponents.Workspace.currentActivity
            desktop: currentDesktop
            outputName: targetScreen.name
            visible: false
        }
        FastBlur {
            anchors.fill: parent
            source: backgroundItem
            radius: 64
        }
    }

    Rectangle {
        id: underlay
        anchors.fill: parent
        opacity: effect.theme.dim
        color: effect.theme.c.bg

        // Ectoview: a click on the backdrop does nothing; only a deliberate click on the desktop
        // itself (or a window, or a desktop in the bar) closes Ectoview. (Overview closed on any
        // click here, so a stray click around the edges closed it.)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Item {
        id: desktopBar

        // (overviewVal, gridVal) represents the state of the overview
        // in a 2D coordinate plane. Math.atan2 returns the angle between
        // the x axis and that point. By using this to set the opacity,
        // we can have an opaque desktopBar when the point moves from
        // the origin to the "overviewVal" direction, which has angle pi/2,
        // and a transparent desktopBar when the point moves from
        // the origin to the "gridVal" direction, which has angle 0,
        // whilst still animating when the point moves from overviewVal to
        // gridVal too.
        opacity: overviewVal * Math.atan2(overviewVal, gridVal) / Math.PI * 2

        anchors.top: container.barPosition === 1 ? undefined : parent.top
        anchors.bottom: (container.barPosition === 1 || container.verticalDesktopBar) ? parent.bottom : undefined
        anchors.left: container.barPosition === 3 ? undefined : parent.left
        anchors.right: container.barPosition === 2 ? undefined : parent.right
        visible: !container.windowsOnly
        height: container.windowsOnly ? 0 : bar.implicitHeight + 2 * Kirigami.Units.smallSpacing
        width: container.windowsOnly ? 0 : bar.implicitWidth + 2 * Kirigami.Units.smallSpacing

        DesktopBar {
            id: bar
            anchors.fill: parent
            windowModel: stackModel
            desktopModel: desktopModel
            verticalDesktopBar: container.verticalDesktopBar
            barPosition: container.barPosition
            showToolbar: container.showToolbar
            selectedDesktop: currentDesktop
            viewGroup: container.viewGroup
            view: container
            groupPill: container.showToolbar ? toolbarPill : null
            heap: allDesktopHeaps.currentHeap
        }
    }

    Item {
        id: topBar
        opacity: desktopBar.opacity
        visible: container.showToolbar
        anchors.left: container.barPosition === 2 ? desktopBar.right : parent.left
        anchors.right: container.barPosition === 3 ? desktopBar.left : parent.right
        anchors.top: container.barPosition === 0 ? desktopBar.bottom : parent.top
        anchors.topMargin: container.showToolbar ? Kirigami.Units.largeSpacing : 0
        height: container.showToolbar ? searchField.height + 1 * Kirigami.Units.largeSpacing : 0

        // Ectoview: around the search field (which stays centered), the desktop groups' pill on its
        // left and the settings gear on its right. With the toolbar hidden, the desktop bar carries
        // both at its end.
        EctoGroupPill {
            id: toolbarPill
            attentionGroups: bar.attentionGroups
            // ^ and v are its right end (design proposal 8)
            desktopBar: bar
            anchors.right: searchField.left
            anchors.rightMargin: 8
            anchors.verticalCenter: searchField.verticalCenter
            ecto: effect
            view: container
            windowModel: stackModel
            opens: "down"
        }
        EctoSettingsButton {
            id: toolbarGear
            anchors.left: searchField.right
            anchors.leftMargin: 8
            anchors.verticalCenter: searchField.verticalCenter
            ecto: effect
        }
        EctoSearchField {
            id: searchField
            // hidden with the toolbar, it takes no typing either
            enabled: container.showToolbar
            anchors.centerIn: parent
            width: Math.min(parent.width - 2 * (8 + Math.max(toolbarPill.visible ? toolbarPill.width : 0, toolbarGear.width)), 360)
            focus: enabled
            readOnly: gridVal == 1
            onReadOnlyChanged: {
                text = ""
                effect.searchText = ""
                effect.searchTextChanged()
            }
            viewGroup: container.viewGroup
            text: effect.searchText
            // not onTextEdited so that the UI always stays in sync
            onTextChanged: {
                effect.searchText = text;
                allDesktopHeaps.currentHeap.resetSelected();
                allDesktopHeaps.currentHeap.selectNextItem(EctoWindowHeap.Direction.Down);
                searchField.focus = true;
            }
        }
    }

    property var currentGeometry: targetScreen.geometry

    // These are the minimum position of maximum size of the desktop preview in the overview
    // Ectoview: the room the bar and the toolbar take on each side (Overview's minX and minY, with
    // the bar on any side)
    // (with the bar on the left or right, the view keeps room beside it for the arrow on that side:
    // its click area and a little air, so it sits between the bar and the view, not on the bar)
    readonly property int sideArrowRoom: 80
    readonly property real barLeftEdge: barPosition === 2 && !windowsOnly ? desktopBar.width : 0
    readonly property real barRightEdge: barPosition === 3 && !windowsOnly ? width - desktopBar.width : width
    // (and on the other side too: a side bar leaves the view so wide on a 16:9 screen that the far
    // side's arrow fell off the screen's edge)
    readonly property bool sideBar: (barPosition === 2 || barPosition === 3) && !windowsOnly && effect.showSideArrows
    readonly property int reservedLeft: (barPosition === 2 ? desktopBar.width : 0) + (sideBar ? sideArrowRoom : 0)
    readonly property int reservedRight: (barPosition === 3 ? desktopBar.width : 0) + (sideBar ? sideArrowRoom : 0)
    readonly property int reservedTop: topBar.height + (barPosition === 0 ? desktopBar.height : 0)
    readonly property int reservedBottom: barPosition === 1 ? desktopBar.height : 0
    property int minX: Kirigami.Units.largeSpacing + reservedLeft
    property int minY: Kirigami.Units.largeSpacing + reservedTop
    property int maxWidth: currentGeometry.width - minX - reservedRight - Kirigami.Units.gridUnit * 2
    property int maxHeight: currentGeometry.height - minY - reservedBottom - Kirigami.Units.gridUnit * 2

    property int desktops: Math.max(shownCount, 2)
    property int columns: Math.ceil(desktops / rows)
    property int rows: KWinComponents.Workspace.desktopGridHeight

    // The desktop might shuffle around as soon as it's
    // created since the rows/columns are updated after
    // the desktop is added. We don't want to see that.
    property bool desktopJustCreated: false
    onDesktopsChanged: {
        desktopJustCreated = true
        startTimer.running = true
    }

    Timer {
        id: startTimer
        interval: effect.animationDuration
        running: false
        onTriggered: desktopJustCreated = false
    }

    // (while a group change slides with Ectoview open, the desktops are clipped to the view's frame as
    // it stood, so nothing slides over the toolbar or the bar; otherwise the whole screen)
    Item {
        id: viewClip
        readonly property bool clipping: container.openSliding
        x: clipping ? container.slideClip.x : 0
        y: clipping ? container.slideClip.y : 0
        width: clipping ? container.slideClip.width : container.width
        height: clipping ? container.slideClip.height : container.height
        clip: clipping
    Item {
        id: desktopGrid
        x: -viewClip.x
        y: -viewClip.y
        width: container.width
        height: container.height
        property var dndManagerStore: ({})

        // Ectoview: the group grid's rows: a band behind each (lit while a desktop from another group
        // is held over it, and a drop on it puts the desktop in that group) and its heading
        Repeater {
            model: container.groupGrid ? container.gridGroups : []
            delegate: Item {
                id: gridRowItem
                required property var modelData
                required property int index
                visible: gridVal > 0
                opacity: gridVal
                // the group's lines: from its first to its last, as many columns wide as its longest
                // (a row is made a moment before the layout has a place for it, as the Hidden row comes in)
                readonly property var layout: container.gridLayout
                readonly property int lineCount: layout ? Math.ceil(modelData.desktops.length / layout.cols) : 1
                x: layout ? layout.x0 : 0
                y: layout ? (layout.tops[index] ?? 0) : 0
                width: (layout ? layout.head + Math.min(modelData.desktops.length, layout.cols) * container.gridCellW : 0)
                height: lineCount * container.gridCellH
                Rectangle {
                    x: container.gridHeadWidth - 16
                    y: -12
                    width: (gridRowItem.layout ? Math.min(gridRowItem.modelData.desktops.length, gridRowItem.layout.cols) : 1) * container.gridCellW + 32
                    height: parent.height + 4
                    radius: 16
                    readonly property bool target: container.gridDropGroup === gridRowItem.modelData.id
                    color: target ? Qt.rgba(effect.theme.accent.r, effect.theme.accent.g, effect.theme.accent.b, 0.08) : "transparent"
                    border.width: target ? effect.theme.ringWidth : 0
                    border.color: effect.theme.accent
                    DropArea {
                        anchors.fill: parent
                        keys: ["kwin-desktop"]
                        onEntered: (drag) => {
                            drag.accepted = !!drag.source && !!drag.source.desktop && effect.groupOf(drag.source.desktop) !== gridRowItem.modelData.id;
                            if (drag.accepted) {
                                container.gridDropGroup = gridRowItem.modelData.id;
                            }
                        }
                        onExited: if (container.gridDropGroup === gridRowItem.modelData.id) container.gridDropGroup = ""
                        onDropped: (drop) => {
                            const desktop = drop.source.desktop, id = gridRowItem.modelData.id;
                            drop.accept(Qt.MoveAction);
                            container.gridDropGroup = "";
                            container.moveDesktopToGroup(desktop, id);
                        }
                    }
                }
                // the group's name beside its first line, halfway down that line's desktops
                Column {
                    x: 40
                    width: container.gridHeadWidth - 72
                    y: ((gridRowItem.layout ? gridRowItem.layout.s : 0) * container.height - implicitHeight) / 2
                    spacing: 4
                    Row {
                        spacing: 10
                        Kirigami.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18
                            source: Qt.resolvedUrl(gridRowItem.modelData.hidden ? "ectoview-eye-off.svg" : "ectoview-group.svg")
                            isMask: true
                            color: effect.theme.c.fgMuted
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, container.gridHeadWidth - 100)
                            elide: Text.ElideRight
                            text: gridRowItem.modelData.name
                            textFormat: Text.PlainText
                            font.family: effect.theme.sans
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: effect.theme.c.fg
                        }
                    }
                    Text {
                        leftPadding: 28
                        text: i18ncp("@info", "%1 desktop", "%1 desktops", gridRowItem.modelData.desktops.length)
                        font.family: effect.theme.sans
                        font.pixelSize: effect.theme.fontSize
                        color: effect.theme.c.fgSubtle
                    }
                }
            }
        }
        // "2 hidden": brings the Hidden row into the grid until Grid View closes (and takes it out again)
        Rectangle {
            id: hiddenLine
            visible: container.groupGrid && container.hiddenDesktops.length > 0 && gridVal > 0 && !effect.isHidden(container.currentDesktop)
            opacity: gridVal
            x: 40
            y: container.height - container.gridFootHeight + (container.gridFootHeight - height) / 2
            height: effect.theme.rowHeight
            width: hiddenLineRow.implicitWidth + 28
            radius: height / 2
            color: hiddenLineHover.hovered ? effect.theme.c.bgMuted : effect.theme.c.bgSubtle
            border.width: 1
            border.color: effect.theme.c.border
            Row {
                id: hiddenLineRow
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Kirigami.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    source: Qt.resolvedUrl("ectoview-eye-off.svg")
                    isMask: true
                    color: effect.theme.c.fgMuted
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: container.hiddenRowShown ? i18nc("@action:button take the hidden desktops' row out of Grid View", "Leave hidden out")
                        : i18ncp("@action:button show the hidden desktops' row in Grid View", "%1 hidden", "%1 hidden", container.hiddenDesktops.length)
                    font.family: effect.theme.sans
                    font.pixelSize: effect.theme.fontSize
                    color: effect.theme.c.fg
                }
            }
            HoverHandler {
                id: hiddenLineHover
                cursorShape: Qt.PointingHandCursor
            }
            MouseArea {
                anchors.fill: parent
                onClicked: container.hiddenRowShown = !container.hiddenRowShown
            }
        }

        ColumnLayout {
            x: Math.round(parent.width / 2) + Math.round(parent.width / 8)
            width: Math.round(parent.width / 2) - Math.round(parent.width / 8) * 2
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.desktopCount === 1
            opacity: gridVal
            spacing: Kirigami.Units.largeSpacing

            Kirigami.PlaceholderMessage {
                text: i18ndc("kwin", "@info:placeholder", "No other Virtual Desktops to show")
                icon.name: "virtual-desktops-symbolic"
            }

            PC3.Button {
                Layout.alignment: Qt.AlignHCenter
                text: i18ndc("kwin", "@action:button", "Add Virtual Desktop")
                icon.name: "list-add-symbolic"
                onClicked: container.addDesktop()
            }

            PC3.Button {
                Layout.alignment: Qt.AlignHCenter
                text: i18ndc("kwin", "@action:button", "Configure Virtual Desktops…")
                icon.name: "preferences-virtual-desktops"
                onClicked: {
                    KCM.KCMLauncher.openSystemSettings("kcm_kwin_virtualdesktops")
                    effect.deactivate();
                }
            }

        }


        Repeater {
            id: allDesktopHeaps
            model: desktopModel

            property Item currentHeap
            property Item currentBackgroundItem

            Item {
                id: mainBackground

                // visible when in the overview 'grid' mode, but also keep neighbouring items visible as they can appear during gestures
                // Ectoview: a desktop outside the shown group (not current) has no place in the grid
                // (in Grid View with desktop groups, every desktop in the group grid)
                // (and one whose window is being dragged stays, unseen, until the drop: an arrow can
                // move the view to another desktop while the window is held)
                visible: ((gridVal > 0 ? inGrid : place >= 0) && (gridVal > 0 || nearCurrent)) || heap.dragActive || leaving
                readonly property Item area: backgroundArea
                // a group change sliding (closed: stepping; open: openSliding): the desktop you left
                // slides away and the one you go to slides in, up or down (groupSlideY)
                readonly property bool leaving: container.sliding && container.stepFrom === desktop
                readonly property bool arriving: container.sliding && !!container.stepFrom && current && container.stepFrom !== desktop
                // how far a group change's slide has this desktop from its place (and its windows,
                // which are drawn on the view's own layer, follow it)
                readonly property real groupSlideY: arriving ? (1 - container.stepIn) * container.slideDistance * container.slideDirection
                    : leaving ? -container.stepIn * container.slideDistance * container.slideDirection : 0
                Connections {
                    target: heap
                    function onDragActiveChanged() {
                        container.draggingHeaps += heap.dragActive ? 1 : -1;
                    }
                }
                readonly property int place: container.shown.indexOf(index)
                readonly property var gridAt: container.groupGrid ? container.gridPos[desktop.id] : null
                readonly property bool inGrid: container.groupGrid ? !!gridAt : place >= 0
                readonly property real gridColumn: gridAt ? gridAt.col : column
                readonly property real gridRow: gridAt ? gridAt.row : row
                // Avoid handling drops for offscreen visible items
                enabled: gridVal > 0 || current || heap.dragActive

                anchors.fill: parent
                property bool shouldBeVisibleInOverview: !(effect.searchText.length > 0 && current) || (!(current && container.currentHeapEmpty) && heap.count !== 0 && effect.filterWindows)
                // (Ectoview: the Hidden row's desktops dimmed in the grid, except the one you're on)
                opacity: (1 - overviewVal * (shouldBeVisibleInOverview ? 0 : 1)) * (inHiddenRow && !current ? 1 - 0.45 * gridVal : 1) 
                readonly property bool inHiddenRow: !!gridAt && container.groupGrid && effect.isHidden(desktop)

                function selectLastItem(direction) {
                    heap.selectLastItem(direction);
                }


                required property QtObject desktop
                required property int index
                readonly property bool current: currentDesktop === desktop
                readonly property bool nearCurrent: Math.abs(deltaColumn) <= 1 && Math.abs(deltaRow) <= 1
                readonly property var nestedHeap: heap

                z: dragActive || arriving ? 1 : 0
                readonly property bool dragActive: heap.dragActive || dragHandler.active

                property int gridSize: Math.max(rows, columns)
                property real row: (Math.max(0, place) - column) / columns
                property real column: Math.max(0, place) % columns
                // deltaX and deltaY are used to move all the desktops together to 1:1 animate the
                // switching between different desktops
                property real deltaX: (!current ? targetScreenDesktopOffset.x :
                                       column == 0 ? Math.max(0, targetScreenDesktopOffset.x) :
                                       column == columns - 1 ? Math.min(0, targetScreenDesktopOffset.x) :
                                           targetScreenDesktopOffset.x)
                property real deltaY: (!current ? targetScreenDesktopOffset.y :
                                       row == 0 ? Math.max(0, targetScreenDesktopOffset.y) :
                                       row == rows - 1 ? Math.min(0, targetScreenDesktopOffset.y) :
                                           targetScreenDesktopOffset.y)
                // deltaColumn and deltaRows are the difference between the column/row of this desktop
                // compared to the column/row of the active one
                property real deltaColumn: column - allDesktopHeaps.currentBackgroundItem.column - deltaX
                property real deltaRow: row - allDesktopHeaps.currentBackgroundItem.row - deltaY
                onDeltaColumnChanged: heap.layout.updateCellsMapping()
                onDeltaRowChanged: heap.layout.updateCellsMapping()

                Behavior on deltaColumn {
                    enabled: overviewVal > 0 && !container.desktopJustCreated && !container.switchingGroup && !effect.desktopsMoving
                    NumberAnimation {
                        duration: effect.animationDuration
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on deltaRow {
                    enabled: overviewVal > 0 && !container.desktopJustCreated && !container.switchingGroup && !effect.desktopsMoving
                    NumberAnimation {
                        duration: effect.animationDuration
                        easing.type: Easing.OutCubic
                    }
                }

                // Note that transforms should be read from the last one to the first one
                transform: [
                    // Scales down further, still in grid, to have some gaps between
                    // the desktops.
                    Scale {
                        origin.x: width / 2
                        origin.y: height / 2
                        xScale: 1 - 0.02 * gridVal
                        yScale: xScale
                    },
                    // Scales down the desktops so that they do not overlap in the grid
                    // Ectoview: the grid's cells come from container.gridCellW/H (the group grid, with
                    // room for its headings), which for Overview's own grid works out to its
                    // 1 / gridSize scale and cell sizes
                    Scale {
                        id: gridScale
                        xScale: 1 + (container.gridScaleS - 1) * gridVal
                        yScale: xScale
                    },
                    // Further little translation in the grids to align the elements
                    // to the center of their cell
                    // (Ectoview: in the group grid a cell is the desktop's own width, and its name's
                    // room below, so the desktop sits at the cell's top)
                    Translate{
                        x: (container.gridCellW - width * container.gridScaleS) / 2 * gridVal
                        y: container.groupGrid ? 0 : (container.gridCellH - height * container.gridScaleS) / 2 * gridVal
                    },
                    // When in desktop grid, translates the desktop so that the whole
                    // grid fits in the view (Ectoview: the group grid's place for it, from gridPos)
                    Translate {
                        x: (mainBackground.gridAt ? mainBackground.gridAt.x : container.gridHeadWidth + mainBackground.gridColumn * container.gridCellW) * gridVal
                        y: (mainBackground.gridAt ? mainBackground.gridAt.y : mainBackground.gridRow * container.gridCellH) * gridVal
                    },
                    // Initially places transition desktops in a grid around the current one,
                    // and moves them slightly to avoid overlapping the UI
                    Translate {
                        id: desktopTranslation
                        x: (minX - reservedRight) * 0.5 * overviewVal + (mainBackground.leaving ? 0 : deltaColumn * width * (1 - gridVal))
                        y: (minY - reservedBottom) * 0.5 * overviewVal + (mainBackground.leaving ? 0 : deltaRow * height * (1 - gridVal)) + mainBackground.groupSlideY
                    }
                ]

                Item {
                    id: backgroundArea
                    property real sizeAdjust: Math.min(maxWidth / parent.width, maxHeight / parent.height)
                    width: parent.width * (1 + (sizeAdjust - 1) * overviewVal)
                    height: parent.height * (1 + (sizeAdjust - 1) * overviewVal)
                    x: parent.width / 2 - width / 2
                    y: parent.height / 2 - height / 2
                    KWinComponents.DesktopBackground {
                        id: desktopElement
                        anchors.fill: parent
                        anchors.margins: gridVal !== 0 ? Math.round(mainBackground.current * gridVal * (1.5 / gridScale.xScale)) : 0
                        activity: KWinComponents.Workspace.currentActivity
                        desktop: currentDesktop
                        outputName: targetScreen.name
                        visible: false
                    }

                    Kirigami.ShadowedTexture {
                        anchors.fill: parent

                        color: "transparent"
                        source: desktopElement

                        radius: effect.theme.viewRadius * overviewVal + effect.theme.gridRadius * gridVal / gridScale.xScale

                        shadow {
                            size: Kirigami.Units.gridUnit * 2
                            color: Qt.rgba(0, 0, 0, 0.3)
                            yOffset: 3
                        }

                        // Ectoview: the current desktop rings in the accent, a hovered one in gray; the ring keeps
                        // its width on screen however small the grid draws the desktop
                        property var borderWidth: (mainBackground.current || desktopHover.hovered) ? effect.theme.ringWidth / gridScale.xScale : 0
                        property var borderColor: mainBackground.current ? effect.theme.accent : (desktopHover.hovered ? effect.theme.c.fgMuted : "transparent")
                        border.width: gridVal == 1 ? borderWidth : 0
                        border.color: gridVal == 1 ? borderColor : "transparent"
                    }

                    DropArea {
                        anchors.fill: parent
                        // Ectoview: in the desktop view only the current desktop takes drops (a desktop
                        // kept for a window still being dragged, after an arrow moved the view on,
                        // lies under the new one and must leave the drop to it)
                        enabled: gridVal > 0 || mainBackground.current
                        // Ectoview: a desktop from another group's row lights this row up
                        readonly property string myGroup: effect.groupOf(mainBackground.desktop)
                        onEntered: (drag) => {
                            drag.accepted = true;
                            if (container.groupGrid && drag.keys.includes("kwin-desktop") && drag.source && drag.source.desktop
                                    && effect.groupOf(drag.source.desktop) !== myGroup) {
                                container.gridDropGroup = myGroup;
                            }
                        }
                        onExited: if (container.gridDropGroup === myGroup) container.gridDropGroup = ""
                        onDropped: (drop) => {
                            drop.accepted = true;
                            container.gridDropGroup = "";
                            if (drop.keys.includes("kwin-desktop")) {
                                // dragging a desktop as a whole
                                if (drag.source === mainBackground) {
                                    drop.action = Qt.IgnoreAction;
                                    return;
                                }
                                // Ectoview: into another group's row: that group, at the end of its row
                                if (container.groupGrid && effect.groupOf(drag.source.desktop) !== myGroup) {
                                    container.moveDesktopToGroup(drag.source.desktop, myGroup);
                                    return;
                                }
                                effect.beginDesktopMove();
                                KWinComponents.Workspace.moveDesktop(drag.source.desktop, desktop.x11DesktopNumber - 1);
                            } else {
                                // dragging a KWin::Window
                                if (drag.source.desktops.length === 0 || drag.source.desktops.indexOf(mainBackground.desktop) !== -1) {
                                    drop.action = Qt.IgnoreAction;
                                    return;
                                }
                                drag.source.desktops = [mainBackground.desktop];
                            }
                        }
                    }
                    Connections {
                        target: effect
                        function onItemDroppedOutOfScreen(globalPos, item, screen) {
                            if (screen !== targetScreen) {
                                return;
                            }
                            // Ectoview: only a desktop that's drawn there takes it: the current one in the
                            // desktop view, one in the grid in Grid View. (Desktops outside the shown group
                            // have no place, so they lie where the current one is; each claimed the window
                            // and the last, often a desktop not showing on this screen, kept it.)
                            if (gridVal > 0 ? !(mainBackground.visible && mainBackground.inGrid) : !mainBackground.current) {
                                return;
                            }
                            const pos = screen.mapFromGlobal(globalPos);
                            if (!mainBackground.contains(mainBackground.mapFromItem(null, pos.x, pos.y))) {
                                return;
                            }
                            // moving the window to the client screen is handled by WindowHeap's similarly named function that is also run
                            item.client.desktops = [mainBackground.desktop];
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: {
                            // Ectoview: a tap that opened a window is the window's, not the desktop's
                            // (it would switch back from a window found on another desktop)
                            if (heap.windowTapped) {
                                return;
                            }
                            container.KWinComponents.SceneView.currentDesktop = mainBackground.desktop;
                            container.effect.deactivate();
                        }
                    }
                    DragHandler {
                        id: dragHandler
                        target: heap
                        enabled: gridVal !== 0
                        grabPermissions: PointerHandler.ApprovesTakeOverByHandlersOfSameType
                        onActiveChanged: {
                            if (!active) {
                                heap.Drag.drop();
                                Qt.callLater(heap.resetPosition)
                            }
                        }
                    }

                    HoverHandler {
                        id: desktopHover
                    }
                }

                // Ectoview: each desktop's name under it in Grid View, kept at 13 px on screen however
                // small the grid draws the desktop
                Text {
                    anchors.top: backgroundArea.bottom
                    anchors.topMargin: 8 / gridScale.xScale
                    anchors.horizontalCenter: backgroundArea.horizontalCenter
                    width: backgroundArea.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: gridVal > 0
                    opacity: gridVal
                    text: mainBackground.desktop.name
                    textFormat: Text.PlainText
                    font.family: effect.theme.sans
                    font.pixelSize: effect.theme.fontSize / gridScale.xScale
                    font.weight: mainBackground.current ? Font.Medium : Font.Normal
                    color: mainBackground.current ? effect.theme.c.fg : effect.theme.c.fgMuted
                }

                EctoWindowHeap {
                    id: heap
                    theme: effect.theme
                    // (Ectoview: its desktop's slide, which a held window is moved back by)
                    slideX: mainBackground.deltaColumn * mainBackground.width * (1 - gridVal)
                    slideY: mainBackground.deltaRow * mainBackground.height * (1 - gridVal)
                    visible: !effect.filterWindows ? effect.searchText.length === 0 : true
                    width: parent.width * (1 + (backgroundArea.sizeAdjust - 1))
                    height: parent.height * (1 + (backgroundArea.sizeAdjust - 1))
                    x: parent.width / 2 - width / 2
                    y: parent.height / 2 - height / 2

                    function resetPosition() {
                        x = parent.width / 2 - width / 2;
                        y = parent.height / 2 - height / 2;
                    }
                    z: 9999
                    Drag.active: dragHandler.active
                    Drag.proposedAction: Qt.MoveAction
                    Drag.supportedActions: Qt.MoveAction
                    Drag.source: mainBackground
                    Drag.hotSpot: Qt.point(width * 0.5, height * 0.5)
                    Drag.keys: ["kwin-desktop"]

                    focus: current
                    padding: Kirigami.Units.largeSpacing
                    animationDuration: effect.animationDuration
                    animationEnabled:  (gridVal !== 0 || mainBackground.current) && organized
                    organized: container.state !== "initial"
                    dndManagerStore: desktopGrid.dndManagerStore
                    // Ectoview: searching all desktops, the current desktop's view shows matching windows
                    // from every desktop (hidden ones too); a click on one takes you to its desktop
                    // (and with "This desktop group", only the windows on the shown group's desktops)
                    readonly property bool everyDesktop: effect.searchScope > 0 && effect.searchText.length > 0 && mainBackground.current
                    showDesktopNames: everyDesktop
                    showOnly: everyDesktop && effect.searchScope === 1 ? container.groupWindowIds : []
                    model: KWinComponents.WindowFilterModel {
                        activity: KWinComponents.Workspace.currentActivity
                        desktop: heap.everyDesktop ? undefined : mainBackground.desktop
                        screenName: targetScreen.name
                        windowModel: stackModel
                        filter: effect.searchText
                        minimizedWindows: !effect.ignoreMinimized
                        windowType: ~KWinComponents.WindowFilterModel.Dock &
                                    ~KWinComponents.WindowFilterModel.Desktop &
                                    ~KWinComponents.WindowFilterModel.Notification &
                                    ~KWinComponents.WindowFilterModel.CriticalNotification
                    }
                    delegate: EctoWindowDelegate {
                        windowHeap: heap
                        offsetX: (mainBackground.leaving ? 0 : mainBackground.deltaColumn * container.width * (gridVal > 0 ? 0 : 1)) + (dragHandler.active ? (dragHandler.centroid.pressPosition.x - dragHandler.centroid.position.x) : 0)
                        offsetY: (mainBackground.leaving ? 0 : mainBackground.deltaRow * container.height * (1 - gridVal)) + mainBackground.groupSlideY + (dragHandler.active ? (dragHandler.centroid.pressPosition.y - dragHandler.centroid.position.y) : 0)

                        partialActivationFactor: container.overviewVal + container.gridVal * effect.organizedGrid
                        // Parent switch needed for the option "organize windows in gridview"  to work correctly
                        // (Ectoview: while a group change slides with Ectoview open, in the view's frame
                        // with their desktops, so they don't slide over the toolbar)
                        contentItemParent: container.gridVal > 0 ? mainBackground : (container.openSliding ? slideWindowLayer : container)

                        // This is preferable over using gestureInProgress values since gridVal and
                        // overviewVal are animated even after the gesture ends, and since the partial
                        // activation factor follows those two values, this results in a more
                        // fluent animation.
                        gestureInProgress: !Number.isInteger(gridVal) || !Number.isInteger(overviewVal)

                        targetScale: {
                            if (overviewVal != 1) return targetScale;
                            // Ectoview: over the groups' pill or its list, the window keeps the size it
                            // came in at, small on top of the list
                            if (container.dragOverGroupMenu) return targetScale;
                            let coordinate = container.verticalDesktopBar ? 'x' : 'y'
                            if (!activeDragHandler.active) {
                                return targetScale; // leave it alone, so it won't affect transitions before they start
                            }
                            var localPressPosition = activeDragHandler.centroid.scenePressPosition[coordinate] - heap.layout.Kirigami.ScenePosition[coordinate];
                            if (localPressPosition === 0) {
                                return 0.1;
                            } else {
                                var localPosition = activeDragHandler.centroid.scenePosition[coordinate] - heap.layout.Kirigami.ScenePosition[coordinate];
                                return Math.max(0.1, Math.min(localPosition / localPressPosition, 1));
                            }
                        }

                        // Ectoview: off the list again, it eases to the size for where it is
                        Behavior on targetScale {
                            enabled: container.dragScaleEasing
                            NumberAnimation {
                                duration: Kirigami.Units.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                        opacity: 1 - downGestureProgress
                        onDownGestureTriggered: window.closeWindow()
                        TapHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.MiddleButton | Qt.RightButton
                            onTapped: (eventPoint, button) => {
                                if (button === Qt.MiddleButton) {
                                    window.closeWindow();
                                } else if (button === Qt.RightButton) {
                                    if (window.desktops.length > 0) {
                                        window.desktops = [];
                                    } else {
                                        window.desktops = [mainBackground.desktop];
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        acceptedButtons: Qt.NoButton
                        cursorShape: dragHandler.active ? Qt.ClosedHandCursor : Qt.ArrowCursor
                    }

                    onActivated: effect.deactivate()
                }

                onCurrentChanged: {
                    if (current) {
                        allDesktopHeaps.currentHeap = heap;
                        allDesktopHeaps.currentBackgroundItem = mainBackground;
                    }
                }
                Component.onCompleted: {
                    if (current) {
                        allDesktopHeaps.currentHeap = heap;
                        allDesktopHeaps.currentBackgroundItem = mainBackground;
                    }
                    startTimer.running = true
                }
            }

        }

    }
    }
    // the windows' layer while a group change slides with Ectoview open: the same frame as the view's
    // clip, the windows (drawn on the view's own layer, as Overview draws them) clipped with it
    Item {
        id: slideWindowClip
        x: container.openSliding ? container.slideClip.x : 0
        y: container.openSliding ? container.slideClip.y : 0
        width: container.openSliding ? container.slideClip.width : container.width
        height: container.openSliding ? container.slideClip.height : container.height
        clip: container.openSliding
        Item {
            id: slideWindowLayer
            x: -slideWindowClip.x
            y: -slideWindowClip.y
            width: container.width
            height: container.height
        }
    }

    Loader {
        id: searchResults
        active: effect.searchText.length > 0 && (container.currentHeapEmpty || !effect.filterWindows)
        anchors.left: container.barPosition === 2 ? desktopBar.right : parent.left
        anchors.right: container.barPosition === 3 ? desktopBar.left : parent.right
        anchors.bottom: container.barPosition === 1 ? desktopBar.top : parent.bottom
        anchors.top: topBar.bottom

        sourceComponent: Item {
            width: parent.width
            height: parent.height - topBar.height
            opacity: overviewVal

            Text {
                id: placeholderMessage
                visible: container.currentHeapEmpty && effect.filterWindows
                anchors.top: parent.top
                anchors.topMargin: Kirigami.Units.smallSpacing
                anchors.horizontalCenter: parent.horizontalCenter
                height: visible ? implicitHeight + Kirigami.Units.largeSpacing : 0
                text: i18ndc("kwin", "@info:placeholder", "No matching windows")
                font.family: effect.theme.sans
                font.pixelSize: effect.theme.fontSize
                color: effect.theme.c.fgMuted
            }

            EctoResultsView {
                id: milouView
                anchors.top: placeholderMessage.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(780, parent.width - 2 * Kirigami.Units.largeSpacing)
                height: Math.min(contentHeight + topMargin + bottomMargin, parent.height - placeholderMessage.height - Kirigami.Units.largeSpacing)
                queryString: effect.searchText

                onActivated: {
                    effect.deactivate();
                }
            }

            Keys.forwardTo: milouView
        }

        Keys.forwardTo: item
    }

    Repeater {
        model: KWinComponents.WindowFilterModel {
            desktop: currentDesktop
            screenName: targetScreen.name
            windowModel: stackModel
            windowType: KWinComponents.WindowFilterModel.Dock
        }

        KWinComponents.WindowThumbnail {
            id: windowThumbnail
            visible: !model.window.hidden && opacity > 0
            wId: model.window.internalId
            x: model.window.x - targetScreen.geometry.x
            y: model.window.y - targetScreen.geometry.y
            z: model.window.stackingOrder
            width: model.window.width
            height: model.window.height
            opacity: 1 - (gridVal + overviewVal)
        }
    }

    KWinComponents.WindowModel {
        id: stackModel
    }

    KWinComponents.VirtualDesktopModel {
        id: desktopModel
    }

    Component.onCompleted: {
        // The following line unbinds the verticalDesktopBar, meaning that it
        // won't react to changes in number of desktops or rows. This is because we
        // don't want the desktop bar changing screenside whilst the user is
        // interacting with it, e.g. by adding desktops
        container.verticalDesktopBar = container.verticalDesktopBar
        organized = true
        // (a group shortcut with Ectoview closed shows this view only for its change; Ectoview
        // itself isn't opening, so the view stays in its first frame)
        if (stepping) {
            stepSwitch.start();
        }
    }

    Connections {
        target: effect
        function onDesktopOffsetChanged(screen) {
            if (screen !== container.targetScreen) {
                return;
            }

            container.targetScreenDesktopOffset = effect.desktopOffsetForScreen(screen);
        }
    }
}
