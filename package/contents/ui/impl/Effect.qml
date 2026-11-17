/*
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Ectoview: KWin 6.7.5's Overview as a QML effect. This file is what Overview's C++ was
    (upstream/kwin-6.7.5-overview/overvieweffect.cpp): its three states, shortcuts, swipes and
    screen edges, and the properties its views read. The views are the forked Main.qml and,
    on a screen Ectoview leaves alone, Untouched.qml. ../main.qml (the KWin effect itself)
    loads this build and hands it `host`; the views reach this object as SceneView.effect.impl,
    and it passes on what they use of KWin's own effect object.
*/

import QtQuick
import QtQml
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import org.kde.kcmutils as KCM

QtObject {
    id: effect

    // KWin's effect object (../main.qml), and its settings (kwinrc [Effect-ectoview])
    required property QtObject host
    readonly property var configuration: host.configuration

    // ---- what the views use of KWin's own effect object (QuickSceneEffect), passed on
    readonly property QtObject activeView: host.activeView
    function getView(edge) {
        return host.getView(edge);
    }
    function activateView(view) {
        host.activateView(view);
    }
    function viewForScreen(screen) {
        return host.viewForScreen(screen);
    }
    function checkItemDraggedOutOfScreen(item) {
        host.checkItemDraggedOutOfScreen(item);
    }
    function checkItemDroppedOutOfScreen(globalPos, item) {
        host.checkItemDroppedOutOfScreen(globalPos, item);
    }
    signal itemDraggedOutOfScreen(var item, var screens)
    signal itemDroppedOutOfScreen(var globalPos, var item, var screen)
    property Connections hostSignals: Connections {
        target: effect.host
        function onItemDraggedOutOfScreen(item, screens) {
            effect.itemDraggedOutOfScreen(item, screens);
        }
        function onItemDroppedOutOfScreen(globalPos, item, screen) {
            effect.itemDroppedOutOfScreen(globalPos, item, screen);
        }
    }

    // ---- what Overview's views read from the effect (overvieweffect.h)
    // Overview's 300 ms, scaled by Plasma's animation speed as KWin's animationTime() is
    readonly property int animationDuration: Math.round(Kirigami.Units.longDuration * 1.5)
    readonly property bool ignoreMinimized: configuration.IgnoreMinimized
    readonly property bool filterWindows: configuration.FilterWindows
    readonly property bool organizedGrid: configuration.OrganizedGrid
    property string searchText: ""

    readonly property real overviewPartialActivationFactor: overviewState.partialActivationFactor
    readonly property bool overviewGestureInProgress: overviewState.inProgress
    readonly property real transitionPartialActivationFactor: transitionState.partialActivationFactor
    readonly property bool transitionGestureInProgress: transitionState.inProgress
    readonly property real gridPartialActivationFactor: gridState.partialActivationFactor
    readonly property bool gridGestureInProgress: gridState.inProgress

    // ---- Ectoview's own
    readonly property EctoTheme theme: EctoTheme {
        configuration: effect.configuration
    }
    // screens other than the primary: 0 all of Ectoview, 1 only their windows (no bar or toolbar),
    // 2 left as they are
    readonly property int otherScreens: Math.max(0, Math.min(2, Number(configuration.OtherScreens) || 0))
    // ---- what typing searches: 0 the current desktop's windows, 1 every desktop in the shown
    // group, 2 every desktop's (hidden ones too)
    readonly property int searchScope: Math.max(0, Math.min(2, Number(configuration.SearchScope) || 0))
    readonly property bool searchAll: searchScope === 2
    function setSearchScope(scope) {
        configuration.SearchScope = scope;
        configuration.writeConfig();
    }

    // ---- desktop groups (design proposal 4). The bar and Grid View show one group at a time; the
    // pill beside the search field switches groups. Hidden is a group of its own, never listed in
    // Groups. Desktops are kept by KWin's id, so renaming or moving one keeps its group.
    readonly property string hiddenGroup: "hidden"
    readonly property string defaultGroup: "desktops"
    function list(v) {
        return v ? (Array.isArray(v) ? v : String(v).split(",")).map(x => String(x)).filter(x => x.length > 0) : [];
    }
    function pairs(v, sep) {
        const out = {};
        for (const item of list(v)) {
            const at = item.indexOf(sep);
            if (at > 0) {
                out[item.slice(0, at)] = item.slice(at + 1);
            }
        }
        return out;
    }
    // the groups in the pill's order, [{ id, name }]; with none saved, one: Desktops
    readonly property var groups: {
        const out = list(configuration.Groups).map(item => {
            const at = item.indexOf(":");
            return at > 0 ? { id: item.slice(0, at), name: item.slice(at + 1) } : null;
        }).filter(g => g !== null && g.id !== hiddenGroup);
        return out.length > 0 ? out : [{ id: defaultGroup, name: i18nc("@item the one desktop group there is before any is made", "Desktops") }];
    }
    readonly property var membership: pairs(configuration.DesktopGroups, "=")
    property var lastDesktops: ({})
    property bool lastDesktopsDirty: false
    function hasGroup(id) {
        return id === hiddenGroup || groups.some(g => g.id === id);
    }
    function groupOf(desktop) {
        if (!desktop) {
            return groups[0].id;
        }
        const id = membership[desktop.id];
        return id && hasGroup(id) ? id : groups[0].id;
    }
    function groupName(id) {
        if (id === hiddenGroup) {
            return i18nc("@item the group of desktops hidden from Ectoview", "Hidden");
        }
        const g = groups.find(g => g.id === id);
        return g ? g.name : "";
    }
    function desktopsIn(id) {
        return KWinComponents.Workspace.desktops.filter(d => groupOf(d) === id);
    }
    // the pill shows once there's a choice: two groups, or a hidden desktop
    readonly property bool hasGroups: groups.length > 1 || KWinComponents.Workspace.desktops.some(d => groupOf(d) === hiddenGroup)
    function isHidden(desktop) {
        return !!desktop && groupOf(desktop) === hiddenGroup;
    }
    // Writes groups and membership. Every desktop that exists gets its group written, so a change to
    // the groups' order never moves a desktop that wasn't listed.
    function writeGroups(newGroups, newMembership) {
        const keep = newGroups.length === 1 && newGroups[0].id === defaultGroup && newGroups[0].name === groups[0].name && groups[0].id === defaultGroup;
        const valid = id => id === hiddenGroup || newGroups.some(g => g.id === id);
        const out = [];
        for (const d of KWinComponents.Workspace.desktops) {
            const id = valid(newMembership[d.id]) ? newMembership[d.id] : newGroups[0].id;
            // with a single group, only Hidden needs saying
            if (!(keep && id === defaultGroup)) {
                out.push(d.id + "=" + id);
            }
        }
        configuration.Groups = keep ? [] : newGroups.map(g => g.id + ":" + g.name);
        configuration.DesktopGroups = out;
        configuration.writeConfig();  // the map keeps changes in memory until told to write them
    }
    function currentMembership() {
        const m = {};
        for (const d of KWinComponents.Workspace.desktops) {
            m[d.id] = groupOf(d);
        }
        return m;
    }
    function moveToGroup(desktop, id) {
        if (!desktop || !hasGroup(id)) {
            return;
        }
        const m = currentMembership();
        m[desktop.id] = id;
        writeGroups(groups, m);
    }
    function hide(desktop) {
        moveToGroup(desktop, hiddenGroup);
    }
    function show(desktop) {
        moveToGroup(desktop, groups[0].id);
    }
    // a new group at the end of the list, holding `desktop` if one is given; returns its id
    function addGroup(name, desktop) {
        const id = "g" + Date.now().toString(36);
        const fresh = groups.concat([{ id: id, name: name.trim() || nextGroupName() }]);
        const m = currentMembership();
        if (desktop) {
            m[desktop.id] = id;
        }
        writeGroups(fresh, m);
        return id;
    }
    function nextGroupName() {
        for (let n = groups.length + 1; ; n++) {
            const name = i18nc("@item a new desktop group's name", "Desktop group %1", n);
            if (!groups.some(g => g.name === name)) {
                return name;
            }
        }
    }
    function renameGroup(id, name) {
        if (name.trim().length === 0 || id === hiddenGroup) {
            return;
        }
        writeGroups(groups.map(g => g.id === id ? { id: g.id, name: name.trim() } : g), currentMembership());
    }
    // removing a group moves its desktops to the first group left; nothing is deleted
    function removeGroup(id) {
        if (id === hiddenGroup || groups.length < 2) {
            return;
        }
        const rest = groups.filter(g => g.id !== id);
        const m = currentMembership();
        for (const key in m) {
            if (m[key] === id) {
                m[key] = rest[0].id;
            }
        }
        writeGroups(rest, m);
    }
    function moveGroup(id, place) {
        const from = groups.findIndex(g => g.id === id);
        if (from < 0) {
            return;
        }
        const reordered = groups.slice();
        const [g] = reordered.splice(from, 1);
        reordered.splice(Math.max(0, Math.min(reordered.length, place)), 0, g);
        writeGroups(reordered, currentMembership());
    }
    // the desktop a group opens on: the one it showed last, else its first; null for an empty group
    function desktopForGroup(id) {
        const inGroup = desktopsIn(id);
        const last = inGroup.find(d => d.id === lastDesktops[id]);
        return last || (inGroup.length > 0 ? inGroup[0] : null);
    }
    function noteCurrent(desktop) {
        if (!desktop) {
            return;
        }
        const id = groupOf(desktop);
        if (lastDesktops[id] !== desktop.id) {
            const next = Object.assign({}, lastDesktops);
            next[id] = desktop.id;
            lastDesktops = next;
            lastDesktopsDirty = true;
        }
    }
    function saveLastDesktops() {
        if (!lastDesktopsDirty) {
            return;
        }
        lastDesktopsDirty = false;
        configuration.GroupLastDesktop = Object.keys(lastDesktops).filter(id => hasGroup(id)).map(id => id + "=" + lastDesktops[id]);
        configuration.writeConfig();
    }
    property Connections desktopWatch: Connections {
        target: KWinComponents.Workspace
        function onCurrentDesktopChanged() {
            effect.noteCurrent(KWinComponents.Workspace.currentDesktop);
        }
    }
    // the desktops the bar and Grid View draw, by their place in KWin's order: the group's, and the
    // current one even when it's in another group (so you can see where you are)
    function shownIndices(current, groupId) {
        const all = KWinComponents.Workspace.desktops;
        const out = [];
        for (let i = 0; i < all.length; i++) {
            if (groupOf(all[i]) === groupId || all[i] === current) {
                out.push(i);
            }
        }
        return out;
    }
    // stepping through a group or the groups, outside Ectoview too (the four shortcuts below)
    function stepInGroup(direction) {
        const cur = KWinComponents.Workspace.currentDesktop;
        const inGroup = desktopsIn(groupOf(cur));
        if (inGroup.length < 2) {
            return;
        }
        const at = inGroup.indexOf(cur);
        KWinComponents.Workspace.currentDesktop = inGroup[(at + direction + inGroup.length) % inGroup.length];
    }
    function stepGroup(direction) {
        const cur = groupOf(KWinComponents.Workspace.currentDesktop);
        const live = groups.filter(g => desktopsIn(g.id).length > 0 || g.id === cur);
        const at = live.findIndex(g => g.id === cur);
        if (live.length < 2) {
            return;
        }
        // from Hidden, the first group (or the last, going back)
        const next = at < 0 ? (direction > 0 ? live[0] : live[live.length - 1]) : live[(at + direction + live.length) % live.length];
        const target = desktopForGroup(next.id);
        if (!target) {
            return;
        }
        // Ectoview closed: the change plays the group transition over the desktop as it is, not
        // KWin's slide sideways past every desktop between (the owner's ask, November 17, 2026).
        // Ectoview shows for a moment in its first frame, which looks just like the desktop; the
        // view on your screen keeps a picture of it, switches, and the new desktop rises and fades
        // in over it (Main.qml, stepping). A slide can't run meanwhile: KWin's slide stands aside
        // while a full-screen effect is up.
        if (overviewState.status === Togglable.Status.Inactive && !host.visible && animationDuration > 0) {
            groupStepTarget = target;
            groupStepping = true;
            host.visible = true;
            groupStepEnd.restart();
            return;
        }
        KWinComponents.Workspace.currentDesktop = target;
    }
    property bool groupStepping: false
    property QtObject groupStepTarget: null
    function endGroupStep() {
        groupStepEnd.stop();
        groupStepping = false;
        groupStepTarget = null;
        if (overviewState.status === Togglable.Status.Inactive) {
            host.visible = false;
        }
    }
    // (in case no view finishes it: back to the desktop, switched, however it went)
    property Timer groupStepEnd: Timer {
        interval: effect.animationDuration * 2 + 600
        onTriggered: {
            if (effect.groupStepTarget) {
                KWinComponents.Workspace.currentDesktop = effect.groupStepTarget;
            }
            effect.endGroupStep();
        }
    }
    // the settings from before groups and the three search scopes, carried over once
    function migrate() {
        let changed = false;
        const hidden = list(configuration.HiddenDesktops);
        if (hidden.length > 0) {
            const m = currentMembership();
            for (const id of hidden) {
                if (m[id] !== undefined) {
                    m[id] = hiddenGroup;
                }
            }
            configuration.HiddenDesktops = [];
            writeGroups(groups, m);
            changed = true;
        }
        if (configuration.PrimaryScreenOnly === true || String(configuration.PrimaryScreenOnly) === "true") {
            configuration.PrimaryScreenOnly = false;
            configuration.OtherScreens = 2;
            changed = true;
        }
        if (configuration.SearchAllDesktops === true || String(configuration.SearchAllDesktops) === "true") {
            configuration.SearchAllDesktops = false;
            configuration.SearchScope = 2;
            changed = true;
        }
        if (changed) {
            configuration.writeConfig();
            console.info("Ectoview: carried old settings over (desktop groups, search scope, other screens)");
        }
    }
    Component.onCompleted: {
        // (after loading: a settings write while ../main.qml is still making this build loops its binding)
        Qt.callLater(migrate);
        lastDesktops = pairs(configuration.GroupLastDesktop, "=");
        transitionState.stop();
    }

    // where the desktop bar sits: 0 top, 1 bottom, 2 left, 3 right (left and right: a vertical list)
    readonly property int barPosition: Math.max(0, Math.min(3, Number(configuration.BarPosition) || 0))
    // the toolbar: the search field and the settings gear
    readonly property bool showToolbar: configuration.ShowToolbar !== false && String(configuration.ShowToolbar) !== "false"
    // the primary screen: KWin's first in its screen order
    readonly property QtObject primaryScreen: KWinComponents.Workspace.screenOrder.length > 0 ? KWinComponents.Workspace.screenOrder[0] : null
    function showsOn(screen) {
        return otherScreens !== 2 || !primaryScreen || screen === primaryScreen;
    }
    // a screen that shows only its windows, laid out
    function windowsOnlyOn(screen) {
        return otherScreens === 1 && !!primaryScreen && screen !== primaryScreen;
    }

    // Overview slides desktops while KWin switches them under it; a QML effect isn't told the
    // offsets (EffectsHandler::desktopChanging), so desktops change without that slide.
    signal desktopOffsetChanged(var screen)
    function desktopOffsetForScreen(screen) {
        return Qt.point(0, 0);
    }

    function activate() {
        overviewState.activate();
        shutdownTimer.stop();
    }

    function deactivate() {
        saveLastDesktops();
        shutdownTimer.start();
        overviewState.deactivate();
    }

    // the gear beside the search field: Ectoview closes and its settings page opens
    function openSettings() {
        deactivate();
        KCM.KCMLauncher.open([String(configuration.SettingsModule || "kwin/effects/configs/kwin_ectoview_config")]);
    }

    function cycle() {
        if (overviewState.status === Togglable.Status.Inactive) {
            overviewState.activate();
        } else if (transitionState.status === Togglable.Status.Inactive) {
            transitionState.activate();
        } else if (gridState.status === Togglable.Status.Active) {
            overviewState.deactivate();
        }
    }

    function reverseCycle() {
        if (overviewState.status === Togglable.Status.Active) {
            overviewState.deactivate();
        } else if (transitionState.status === Togglable.Status.Active) {
            transitionState.deactivate();
        } else if (gridState.status === Togglable.Status.Inactive) {
            gridState.activate();
        }
    }

    // ---- the three states and how they hand over (OverviewEffect's constructor)
    // inactive -> overview
    property Togglable overviewState: Togglable {
        onStatusChanged: {
            const S = Togglable.Status;
            if (status === S.Activating || status === S.Active) {
                effect.searchText = "";
                effect.host.visible = true;
                gridState.stop();
            }
            if (status === S.Active) {
                transitionState.deactivate();
            }
            if (status === S.Inactive || status === S.Deactivating) {
                transitionState.stop();
            }
            if (status === S.Inactive) {
                gridState.deactivate();
                effect.deactivate();
            }
        }
    }
    // overview -> grid
    property Togglable transitionState: Togglable {
        onStatusChanged: {
            const S = Togglable.Status;
            if (status === S.Activating || status === S.Active) {
                overviewState.stop();
            }
            if (status === S.Inactive) {
                overviewState.activate();
            }
            if (status === S.Active) {
                gridState.activate();
            }
            if (status === S.Inactive || status === S.Deactivating) {
                gridState.stop();
            }
        }
    }
    // inactive -> grid
    property Togglable gridState: Togglable {
        onStatusChanged: {
            const S = Togglable.Status;
            if (status === S.Activating || status === S.Active) {
                effect.searchText = "";
                effect.host.visible = true;
                overviewState.stop();
            }
            if (status === S.Inactive) {
                overviewState.deactivate();
                effect.deactivate();
            }
            if (status === S.Active) {
                transitionState.activate();
            }
            if (status === S.Inactive || status === S.Deactivating) {
                transitionState.stop();
            }
        }
    }

    // Overview stays drawn until its closing animation has played
    // Ectoview: a desktop moved to a new place in KWin's order (the bar, Grid View, a group change):
    // every screen's view lays its desktops out afresh at once, without sliding them there (a moved
    // desktop swept across another screen's view, November 13, 2026). Set before KWin moves it, so
    // each view knows before its columns change
    property bool desktopsMoving: false
    function beginDesktopMove() {
        desktopsMoving = true;
        desktopsMovingEnd.restart();
    }
    property Timer desktopsMovingEnd: Timer {
        interval: effect.animationDuration + 50
        onTriggered: effect.desktopsMoving = false
    }
    property Timer shutdownTimer: Timer {
        interval: effect.animationDuration
        onTriggered: {
            if (overviewState.status === Togglable.Status.Inactive) {
                effect.host.visible = false;
            }
        }
    }

    // ---- each screen: Overview's view, or the screen as it is (../main.qml makes this KWin's delegate)
    property Component delegateComponent: Loader {
        id: screenLoader
        readonly property QtObject screen: KWinComponents.SceneView.screen
        focus: true
        source: effect.showsOn(screen) ? "Main.qml" : "Untouched.qml"
    }


    // ---- swipes: up for Ectoview and on to Grid View, down for Grid View (4 fingers on a
    // touchpad, 3 on a touchscreen), each following the fingers, as Overview's
    component UpSwipe: KWinComponents.SwipeGestureHandler {
        direction: KWinComponents.SwipeGestureHandler.Direction.Up
        onProgressChanged: {
            overviewState.setProgress(progress);
            transitionState.setProgress(progress);
            gridState.setRegress(progress);
        }
        function finish() {
            overviewState.finishActivating();
            transitionState.finishActivating();
            gridState.finishDeactivating();
        }
        onActivated: finish()
        onCancelled: finish()
    }
    component DownSwipe: KWinComponents.SwipeGestureHandler {
        direction: KWinComponents.SwipeGestureHandler.Direction.Down
        onProgressChanged: {
            overviewState.setRegress(progress);
            transitionState.setRegress(progress);
            gridState.setProgress(progress);
        }
        function finish() {
            overviewState.finishDeactivating();
            transitionState.finishDeactivating();
            gridState.finishActivating();
        }
        onActivated: finish()
        onCancelled: finish()
    }

    // ---- screen edges, from System Settings > Screen Edges (BorderActivate) and Ectoview's settings
    component Edge: KWinComponents.ScreenEdgeHandler {
        required property var modelData
        enabled: true
        edge: modelData
    }

    // the shortcut, swipe and screen-edge handlers
    property list<QtObject> handlers: [
        // ---- shortcuts (Overview's four; install.sh moves Overview's keys to these)
        KWinComponents.ShortcutHandler {
            name: "Ectoview"
            text: i18nc("@action Ectoview is the name of a KWin effect", "Toggle Ectoview")
            sequence: "Meta+W"
            onActivated: overviewState.toggle()
        },
        KWinComponents.ShortcutHandler {
            name: "Ectoview Grid View"
            text: i18nc("@action Grid View is a mode of Ectoview", "Toggle Grid View")
            sequence: "Meta+G"
            onActivated: gridState.toggle()
        },
        KWinComponents.ShortcutHandler {
            name: "Ectoview Cycle"
            text: i18nc("@action", "Cycle through Ectoview and Grid View")
            onActivated: effect.cycle()
        },
        KWinComponents.ShortcutHandler {
            name: "Ectoview Cycle Opposite"
            text: i18nc("@action", "Cycle through Grid View and Ectoview")
            onActivated: effect.reverseCycle()
        },
        // ---- desktop groups: four shortcuts with no keys until someone gives them some
        KWinComponents.ShortcutHandler {
            name: "Ectoview Next Desktop in Desktop Group"
            text: i18nc("@action", "Switch to the next desktop in the desktop group")
            onActivated: effect.stepInGroup(1)
        },
        KWinComponents.ShortcutHandler {
            name: "Ectoview Previous Desktop in Desktop Group"
            text: i18nc("@action", "Switch to the previous desktop in the desktop group")
            onActivated: effect.stepInGroup(-1)
        },
        KWinComponents.ShortcutHandler {
            name: "Ectoview Next Desktop Group"
            text: i18nc("@action", "Switch to the next desktop group")
            onActivated: effect.stepGroup(1)
        },
        KWinComponents.ShortcutHandler {
            name: "Ectoview Previous Desktop Group"
            text: i18nc("@action", "Switch to the previous desktop group")
            onActivated: effect.stepGroup(-1)
        },
        UpSwipe {
            fingerCount: 4
            deviceType: KWinComponents.SwipeGestureHandler.Device.Touchpad
        },
        DownSwipe {
            fingerCount: 4
            deviceType: KWinComponents.SwipeGestureHandler.Device.Touchpad
        },
        UpSwipe {
            fingerCount: 3
            deviceType: KWinComponents.SwipeGestureHandler.Device.Touchscreen
        },
        DownSwipe {
            fingerCount: 3
            deviceType: KWinComponents.SwipeGestureHandler.Device.Touchscreen
        },
        Instantiator {
            model: effect.configuration.BorderActivate
            delegate: Edge { onActivated: overviewState.toggle() }
        },
        Instantiator {
            model: effect.configuration.GridBorderActivate
            delegate: Edge { onActivated: gridState.toggle() }
        },
        Instantiator {
            model: effect.configuration.TouchBorderActivate
            delegate: Edge { mode: KWinComponents.ScreenEdgeHandler.Mode.Touch; onActivated: overviewState.toggle() }
        },
        Instantiator {
            model: effect.configuration.GridTouchBorderActivate
            delegate: Edge { mode: KWinComponents.ScreenEdgeHandler.Mode.Touch; onActivated: gridState.toggle() }
        }
    ]
}
