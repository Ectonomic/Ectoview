/*
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2022 ivan tkachenko <me@ratijas.tk>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import org.kde.kwin.private.effects
import org.kde.plasma.components as PC3

Item {
    id: bar

    readonly property real desktopHeight: Kirigami.Units.gridUnit * 5
    readonly property real desktopWidth: desktopHeight * targetScreen.geometry.width / targetScreen.geometry.height
    readonly property real columnHeight: desktopHeight + Kirigami.Units.gridUnit
    readonly property real columnWidth: desktopWidth + Kirigami.Units.gridUnit
    readonly property int desktopCount: desktopRepeater.count

    property bool verticalDesktopBar
    property QtObject windowModel
    property alias desktopModel: desktopRepeater.model
    property QtObject selectedDesktop: null
    property var heap
    property int barPosition: 0
    property bool showToolbar: true
    // Ectoview: the group the view shows, the view itself (Main.qml: addDesktop, chooseGroup), and
    // the groups' pill a desktop can be dropped on (the toolbar's, or the bar's own without a toolbar)
    property string viewGroup
    property Item view
    property Item groupPill: null
    readonly property Item dropPill: groupPill || (barPill.visible ? barPill : null)

    readonly property QtObject ecto: KWinComponents.SceneView.effect.impl
    readonly property QtObject theme: ecto.theme

    // ---- Ectoview: desktop groups. The bar draws the desktops in `shown` (places in KWin's order:
    // the shown group's, and the current one even when it's in another); places below are places in it.
    readonly property var shown: ecto.shownIndices(selectedDesktop, viewGroup)
    readonly property int shownCount: shown.length
    // a desktop dragged over the groups' pill lands in a group instead of a place
    property bool overPill: false

    // ---- Ectoview: changing groups (design proposal 11): groups are a list from top to bottom, so the
    // leaving desktops slide up and out of the bar as the new group's slide up into place (300 ms,
    // easing out), down for a group higher in the list; up and down whichever side the bar is on.
    readonly property real motion: ecto.animationDuration / 300
    property bool transitioning: false
    // 1: the new group is further down the list (things move up), -1: further up
    property int transitionDirection: 1
    // the leaving desktops, drawn where they were: [{ desktop, x, y }]
    property var ghosts: []
    signal groupEntered()
    // how far a group change slides the bar's desktops: the bar's whole height, so the old group
    // leaves it entirely (the bar clips them while they move)
    readonly property real slideDistance: height
    clip: transitioning
    function beginGroupTransition(direction) {
        if (motion <= 0) {
            return;
        }
        const out = [];
        for (let i = 0; i < desktopRepeater.count; i++) {
            const d = desktopRepeater.itemAt(i);
            if (d && d.visible) {
                const at = d.mapToItem(bar, 0, 0);
                out.push({ desktop: d.desktop, x: at.x, y: at.y });
            }
        }
        transitionDirection = direction;
        ghosts = out;
        transitioning = true;
        transitionEnd.interval = 360 * motion;
        transitionEnd.restart();
        // the new group's places exist once the view has its new group
        Qt.callLater(() => bar.groupEntered());
    }
    Repeater {
        model: bar.ghosts
        delegate: Item {
            id: ghost
            required property var modelData
            x: modelData.x
            y: modelData.y
            z: 20
            width: bar.desktopWidth
            height: bar.desktopHeight
            Item {
                anchors.fill: parent
                clip: true
                DesktopView {
                    width: targetScreen.geometry.width
                    height: targetScreen.geometry.height
                    windowModel: bar.windowModel
                    desktop: ghost.modelData.desktop
                    scale: bar.desktopHeight / targetScreen.geometry.height
                    transformOrigin: Item.TopLeft
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: bar.theme.thumbRadius
                color: "transparent"
                border.width: 1
                border.color: bar.theme.c.border
            }
            // the old group's desktops slide up and out of the bar (down for a group higher in the
            // list), the whole way, as the new group's slide in (design proposal 11)
            NumberAnimation { running: true; target: ghost; property: "y"; to: ghost.modelData.y - bar.slideDistance * bar.transitionDirection; duration: 300 * bar.motion; easing.type: Easing.OutCubic }
        }
    }
    Timer {
        id: transitionEnd
        onTriggered: {
            bar.transitioning = false;
            bar.ghosts = [];
        }
    }

    // ---- Ectoview: a desktop's "Move to desktop group" list (one for the bar, opened from a desktop's button)
    EctoMoveMenu {
        id: moveMenu
        ecto: bar.ecto
        view: bar.view
    }

    // ---- Ectoview: drag a desktop to a new place
    // the desktop being dragged and the place it would land on (-1: none), as places in the bar
    property int dragIndex: -1
    property int dropIndex: -1
    // from one desktop's place to the next one's
    readonly property real step: (verticalDesktopBar ? columnHeight : desktopWidth) + Kirigami.Units.largeSpacing
    function placeFor(index, travel) {
        return Math.max(0, Math.min(shownCount - 1, Math.round(index + travel / step)));
    }
    // Moves a desktop to a place, as KWin's Workspace.moveDesktop, then renames desktops that still
    // have KWin's default names ("Desktop 2") for their new places; names someone gave stay.
    function moveDesktop(desktop, place) {
        const from = KWinComponents.Workspace.desktops.indexOf(desktop);
        if (from < 0 || place === from || place < 0 || place >= desktopCount) {
            return;
        }
        const defaults = KWinComponents.Workspace.desktops.map((d, i) => d.name === i18nd("kwin", "Desktop %1", i + 1));
        const wasDefault = defaults[from];
        bar.ecto.beginDesktopMove();
        KWinComponents.Workspace.moveDesktop(desktop, place);
        const now = KWinComponents.Workspace.desktops;
        // which desktops had default names, carried to their new places
        const moved = defaults.slice();
        moved.splice(from, 1);
        moved.splice(place, 0, wasDefault);
        for (let i = 0; i < now.length; i++) {
            if (moved[i] && now[i].name !== i18nd("kwin", "Desktop %1", i + 1)) {
                now[i].name = i18nd("kwin", "Desktop %1", i + 1);
            }
        }
    }

    implicitHeight: columnHeight + 2 * Kirigami.Units.smallSpacing
    implicitWidth: columnWidth + 2 * Kirigami.Units.smallSpacing

    // Ectoview: while a desktop is dragged near either end of a bar that doesn't fit, the bar
    // scrolls that way; the dragged desktop stays under the pointer and the others keep making room
    property real dragTravel: 0    // the pointer's travel along the bar since the drag began
    property real scrolled: 0      // how far the bar has scrolled since then
    property int edgeDirection: 0  // -1 toward the start, 1 toward the end, 0 not at an edge
    readonly property Item draggedDelegate: dragIndex >= 0 ? desktopRepeater.itemAt(shown[dragIndex]) : null
    function updateDrag() {
        if (draggedDelegate) {
            draggedDelegate.travel = dragTravel + scrolled;
            dropIndex = placeFor(dragIndex, draggedDelegate.travel);
        }
    }
    function updateEdge(pointerInBar) {
        const along = verticalDesktopBar ? pointerInBar.y : pointerInBar.x;
        const length = verticalDesktopBar ? flick.height : flick.width;
        const zone = Math.min(48, length / 6);
        edgeDirection = along < zone ? -1 : along > length - zone ? 1 : 0;
    }
    Timer {
        interval: 16
        repeat: true
        running: bar.dragIndex >= 0 && bar.edgeDirection !== 0 && flick.interactiveSize
        onTriggered: {
            const before = bar.verticalDesktopBar ? flick.contentY : flick.contentX;
            const lowest = bar.verticalDesktopBar ? -flick.topMargin : -flick.leftMargin;
            const highest = bar.verticalDesktopBar ? flick.contentHeight - flick.height : flick.contentWidth - flick.width;
            const after = Math.max(lowest, Math.min(highest, before + bar.edgeDirection * 10));
            if (bar.verticalDesktopBar) {
                flick.contentY = after;
            } else {
                flick.contentX = after;
            }
            bar.scrolled += after - before;
            bar.updateDrag();
        }
    }

    // ---- Ectoview: more desktops than fit (design proposal 2). Arrows at both ends page through the
    // bar, its cut-off ends fade into the backdrop, and it keeps the current desktop in view (the
    // wheel over the bar switches desktops, Main.qml, and the bar follows). (A press on a desktop starts a drag, so the bar can't be dragged.)
    // the gutter between anything in the bar and the screen's edge
    readonly property real edge: 24
    readonly property real arrowSize: theme.rowHeight
    readonly property real pillRoom: barEnd.visible ? (verticalDesktopBar ? barEnd.height : barEnd.width) + 12 : 0
    readonly property real barLength: verticalDesktopBar ? height : width
    readonly property real contentLength: verticalDesktopBar ? barGrid.height : barGrid.width
    readonly property bool overflowing: contentLength + pillRoom + 2 * groupRoom > barLength - 2 * edge
    readonly property real startInset: overflowing ? edge + groupRoom + arrowSize + 12 : 0
    readonly property real endInset: overflowing ? edge + arrowSize + 12 + groupRoom + pillRoom : 0
    readonly property real viewLength: verticalDesktopBar ? flick.height : flick.width
    readonly property real scrollPos: verticalDesktopBar ? flick.contentY : flick.contentX
    readonly property real scrollMax: Math.max(0, contentLength - viewLength)
    readonly property bool canBack: overflowing && scrollPos > 1
    readonly property bool canForward: overflowing && scrollPos < scrollMax - 1
    function scrollTo(pos, animate) {
        pos = Math.max(0, Math.min(scrollMax, pos));
        pageAnimation.stop();
        if (animate) {
            pageAnimation.property = verticalDesktopBar ? "contentY" : "contentX";
            pageAnimation.to = pos;
            pageAnimation.start();
        } else if (verticalDesktopBar) {
            flick.contentY = pos;
        } else {
            flick.contentX = pos;
        }
    }
    // a page: the view less one desktop, so the last one fully in view stays in view
    function page(direction) {
        scrollTo(scrollPos + direction * Math.max(step, viewLength - step), true);
    }
    function ensureVisible(place) {
        if (!overflowing || place < 0) {
            return;
        }
        const start = place * step, size = verticalDesktopBar ? columnHeight : desktopWidth;
        if (start < scrollPos) {
            scrollTo(start, false);
        } else if (start + size > scrollPos + viewLength) {
            scrollTo(start + size - viewLength, false);
        }
    }
    onSelectedDesktopChanged: Qt.callLater(() => ensureVisible(shown.indexOf(KWinComponents.Workspace.desktops.indexOf(selectedDesktop))))
    Component.onCompleted: Qt.callLater(() => ensureVisible(shown.indexOf(KWinComponents.Workspace.desktops.indexOf(selectedDesktop))))
    NumberAnimation {
        id: pageAnimation
        target: flick
        duration: Kirigami.Units.longDuration
        easing.type: Easing.OutCubic
    }

    // (a faded arrow still takes its click and does nothing: a disabled button would let the click
    // through to the backdrop)
    component Arrow: PC3.Button {
        property bool forward: false
        property bool live: true
        width: bar.arrowSize
        height: bar.arrowSize
        padding: 0
        display: PC3.AbstractButton.IconOnly
        opacity: live ? 1 : 0.35
        background: Rectangle {
            radius: width / 2
            color: parent.hovered && parent.live ? bar.theme.c.bgMuted : bar.theme.c.bgSubtle
            border.width: 1
            border.color: bar.theme.c.border
        }
        contentItem: Item {
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 14
                height: 14
                source: Qt.resolvedUrl("ectoview-chevron.svg")
                isMask: true
                color: bar.theme.c.fg
                rotation: (bar.verticalDesktopBar ? 90 : 0) + (parent.parent.forward ? 0 : 180)
            }
        }
        onClicked: if (live) bar.page(forward ? 1 : -1)
    }
    // the arrows sit level with the thumbnails (horizontal) or centered across them (vertical)
    readonly property real thumbCenter: verticalDesktopBar ? width / 2 : flick.topMargin + desktopHeight / 2
    Arrow {
        visible: bar.overflowing
        live: bar.canBack
        text: i18nc("@action:button", "Earlier desktops")
        x: bar.verticalDesktopBar ? bar.thumbCenter - width / 2 : bar.edge + bar.groupRoom
        y: bar.verticalDesktopBar ? bar.edge + bar.groupRoom : bar.thumbCenter - height / 2
    }
    Arrow {
        forward: true
        visible: bar.overflowing
        live: bar.canForward
        text: i18nc("@action:button", "Later desktops")
        x: bar.verticalDesktopBar ? bar.thumbCenter - width / 2 : bar.width - bar.endInset + 12
        y: bar.verticalDesktopBar ? bar.height - bar.endInset + 12 : bar.thumbCenter - height / 2
    }

    // ---- Ectoview: notification beacons. A desktop where a window asks for attention (KWin's
    // demandsAttention, the flag that lights a taskbar entry: a chat's ping, a terminal's bell, an
    // agent waiting on you) gets a beacon on its thumbnail, and its group one on the groups' pill
    // and in its list. KWin clears the flag when you go to that window. A window on every desktop
    // marks none of them, and a window on a Hidden desktop marks nothing at all.
    // (by id: the desktops a window is on and the bar's delegates are matched by name, not by
    // which wrapper object QML handed each one)
    property var attentionDesktops: []
    readonly property var attentionIds: attentionDesktops.map(d => String(d.id))
    function asksAttention(desktop) {
        return !!desktop && attentionIds.indexOf(String(desktop.id)) >= 0;
    }
    readonly property var attentionGroups: {
        const ids = [];
        for (const d of attentionDesktops) {
            const g = ecto.groupOf(d);
            if (g && ids.indexOf(g) < 0) {
                ids.push(g);
            }
        }
        return ids;
    }
    function countAttention() {
        const found = [];
        for (let i = 0; i < attentionWatch.count; i++) {
            const w = attentionWatch.objectAt(i);
            if (!w || !w.asking || w.everywhere) {
                continue;
            }
            for (const d of w.on) {
                // a Hidden desktop never asks: what's there was put out of the way on purpose
                // (the owner's ruling, November 17, 2026: Hidden desktops stay quiet)
                if (d && !ecto.isHidden(d) && !found.some(f => String(f.id) === String(d.id))) {
                    found.push(d);
                }
            }
        }
        attentionDesktops = found;
    }
    Instantiator {
        id: attentionWatch
        model: bar.windowModel
        delegate: QtObject {
            required property QtObject window
            readonly property bool asking: !!window && window.demandsAttention
            readonly property bool everywhere: !!window && window.onAllDesktops
            readonly property var on: window ? window.desktops : []
            onAskingChanged: Qt.callLater(bar.countAttention)
            onEverywhereChanged: Qt.callLater(bar.countAttention)
            onOnChanged: Qt.callLater(bar.countAttention)
        }
        onObjectAdded: Qt.callLater(bar.countAttention)
        onObjectRemoved: Qt.callLater(bar.countAttention)
    }

    // ---- Ectoview: the desktop groups to step through with the groups' pill's ^ and v (design
    // proposal 8): none past either end, so the group change always goes the way its arrow points;
    // Hidden isn't stepped to, nor an empty group.
    readonly property var liveGroups: ecto.groups.filter(g => g.id === viewGroup || ecto.desktopsIn(g.id).length > 0)
    function neighborGroup(direction) {
        const live = liveGroups;
        const at = live.findIndex(g => g.id === viewGroup);
        if (at < 0) {
            return live.length > 0 ? live[direction > 0 ? 0 : live.length - 1] : null;
        }
        return live[at + direction] || null;
    }
    readonly property bool groupArrowsShown: ecto.hasGroups && liveGroups.length > 1
    // ^ and v are the groups' pill's right end (design proposal 8), wherever the pill sits: they
    // take no room of their own in the bar
    readonly property real groupRoom: 0

    // ---- Ectoview: with the toolbar hidden, the groups' pill and the settings gear are the bar's last
    // things (after the add tile, below it in a vertical bar, after the forward arrow when the bar
    // overflows); design proposal 3, option A, and proposal 4 for the pill.
    // (no Grid: Qt's Grid adds a trailing gap when it has fewer items than columns, which made the
    // gear look 8 px wider and tipped a full bar into paging; a Row or Column of what's visible)
    Grid {
        id: barEnd
        visible: !bar.showToolbar
        spacing: 8
        columns: bar.verticalDesktopBar ? 1 : (barPill.visible ? 2 : 1)
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter
        EctoGroupPill {
            id: barPill
            ecto: bar.ecto
            attentionGroups: bar.attentionGroups
            desktopBar: bar
            view: bar.view
            windowModel: bar.windowModel
            visible: !bar.showToolbar && ecto.hasGroups
            opens: bar.barPosition === 1 ? "up" : bar.barPosition === 2 ? "right" : bar.barPosition === 3 ? "left" : "down"
        }
        EctoSettingsButton {
            ecto: bar.ecto
        }
        x: bar.verticalDesktopBar ? bar.thumbCenter - width / 2
            : bar.overflowing ? bar.width - bar.edge - width
            : flick.leftMargin + barGrid.width + 12 + bar.groupRoom
        y: bar.verticalDesktopBar ? (bar.overflowing ? bar.height - bar.edge - height : flick.topMargin + barGrid.height + 12 + bar.groupRoom)
            : bar.thumbCenter - height / 2
    }

    Flickable {
        id: flick
        readonly property bool interactiveSize: bar.verticalDesktopBar ? contentHeight > height : contentWidth > width
        anchors.fill: parent
        anchors.leftMargin: bar.verticalDesktopBar ? 0 : bar.startInset
        anchors.rightMargin: bar.verticalDesktopBar ? 0 : bar.endInset
        anchors.topMargin: bar.verticalDesktopBar ? bar.startInset : 0
        anchors.bottomMargin: bar.verticalDesktopBar ? bar.endInset : 0
        // the cut-off ends fade into the backdrop over 240 px
        // (not while groups change: the desktops slide past the bar's edges, clipped by the bar)
        layer.enabled: bar.overflowing && !bar.transitioning
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                id: fadeMask
                // (never under 480: a fade needs room for both ends, and a zero length on the first
                // frame would put the gradient's stops at infinity, which blacks out the whole screen)
                readonly property real len: Math.max(480, bar.verticalDesktopBar ? flick.height : flick.width)
                readonly property real a0: bar.canBack ? 0 : 1
                readonly property real a1: bar.canForward ? 0 : 1
                width: flick.width
                height: flick.height
                gradient: Gradient {
                    orientation: bar.verticalDesktopBar ? Gradient.Vertical : Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, fadeMask.a0) }
                    GradientStop { position: 90 / fadeMask.len; color: Qt.rgba(0, 0, 0, Math.max(fadeMask.a0, 0.35)) }
                    GradientStop { position: 170 / fadeMask.len; color: Qt.rgba(0, 0, 0, Math.max(fadeMask.a0, 0.8)) }
                    GradientStop { position: 240 / fadeMask.len; color: "black" }
                    GradientStop { position: 1 - 240 / fadeMask.len; color: "black" }
                    GradientStop { position: 1 - 170 / fadeMask.len; color: Qt.rgba(0, 0, 0, Math.max(fadeMask.a1, 0.8)) }
                    GradientStop { position: 1 - 90 / fadeMask.len; color: Qt.rgba(0, 0, 0, Math.max(fadeMask.a1, 0.35)) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, fadeMask.a1) }
                }
            }
        }
        // centered while there's room; with the gear after the add tile (toolbar hidden), shifted
        // toward the start just enough for the gear to keep its gutter from the screen's edge
        leftMargin: bar.verticalDesktopBar ? Math.max((width - contentWidth) / 2, 0)
            : Math.max(0, Math.min((width - contentWidth) / 2, width - contentWidth - bar.pillRoom - bar.groupRoom - bar.edge))
        topMargin: !bar.verticalDesktopBar ? Math.max((height - contentHeight) / 2, 0)
            : Math.max(0, Math.min((height - contentHeight) / 2, height - contentHeight - bar.pillRoom - bar.edge))
        // the desktops' grid alone sets the size (the drop slot beside it must not)
        contentWidth: barGrid.width
        contentHeight: barGrid.height
        interactive: contentWidth > width && bar.dragIndex < 0
        clip: !bar.transitioning
        flickableDirection: bar.verticalDesktopBar ? Flickable.VerticalFlick : Flickable.HorizontalFlick

        Rectangle {
            visible: bar.dragIndex >= 0
            x: bar.verticalDesktopBar ? 0 : Math.max(0, bar.dropIndex) * bar.step
            y: bar.verticalDesktopBar ? Math.max(0, bar.dropIndex) * bar.step : 0
            width: bar.desktopWidth
            height: bar.desktopHeight
            radius: bar.theme.thumbRadius
            color: Qt.rgba(bar.theme.c.bgSubtle.r, bar.theme.c.bgSubtle.g, bar.theme.c.bgSubtle.b, 0.35)
            border.width: 1
            border.color: bar.theme.c.borderStrong
        }

        Grid {
            id: barGrid
            spacing: Kirigami.Units.largeSpacing
            columns: verticalDesktopBar ? 1 : shownCount + 1

            Repeater {
                id: desktopRepeater

                Column {
                    id: delegate
                    activeFocusOnTab: true
                    width: bar.desktopWidth
                    height: bar.columnHeight
                    spacing: Kirigami.Units.smallSpacing

                    required property QtObject desktop
                    required property int index
                    // Ectoview: this desktop's place in the bar (-1: in another group, so not drawn)
                    readonly property int place: bar.shown.indexOf(index)
                    readonly property bool hiddenHere: bar.ecto.isHidden(desktop)
                    // the current desktop, in a group other than the one shown (moved, or hidden)
                    readonly property string groupHere: bar.ecto.groupOf(desktop)
                    readonly property bool elsewhere: groupHere !== bar.viewGroup
                    visible: place >= 0
                    // (over the pill, the desktop rides under the pointer in the pill's list instead)
                    opacity: dragged && bar.overPill ? 0 : 1
                    // sliding in with a group change (0: a bar's height away, 1: in place)
                    property real enter: 1
                    Connections {
                        target: bar
                        function onGroupEntered() {
                            if (delegate.place >= 0) {
                                delegate.enter = 0;
                                enterAnimation.restart();
                            }
                        }
                    }
                    NumberAnimation {
                        id: enterAnimation
                        target: delegate
                        property: "enter"
                        from: 0
                        to: 1
                        duration: 300 * bar.motion
                        easing.type: Easing.OutCubic
                    }

                    // Ectoview: while this desktop is dragged, how far the pointer has taken it;
                    // while another is, the room this one makes for it
                    readonly property bool dragged: place >= 0 && bar.dragIndex === place
                    property real travel: 0
                    readonly property real room: {
                        if (bar.dragIndex < 0 || dragged) {
                            return 0;
                        }
                        if (bar.dragIndex < place && place <= bar.dropIndex) {
                            return -bar.step;
                        }
                        if (bar.dropIndex <= place && place < bar.dragIndex) {
                            return bar.step;
                        }
                        return 0;
                    }
                    property real shift: dragged ? travel : room
                    Behavior on shift {
                        enabled: !delegate.dragged
                        NumberAnimation {
                            duration: Kirigami.Units.shortDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                    z: dragged ? 10 : 0
                    transform: [
                        Translate {
                            y: bar.slideDistance * bar.transitionDirection * (1 - delegate.enter)
                        },
                        Translate {
                            x: bar.verticalDesktopBar ? 0 : delegate.shift
                            y: bar.verticalDesktopBar ? delegate.shift : 0
                        }
                    ]

                    Keys.onEnterPressed: activate();
                    Keys.onReturnPressed: activate();
                    Keys.onSpacePressed: activate();
                    Keys.onDeletePressed: remove();

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_F2) {
                            event.accepted = true;
                            label.startEditing();
                        } else if (event.key === Qt.Key_H && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                            // Ectoview: H hides this desktop (or puts it back in the first group, when it's hidden and current)
                            event.accepted = true;
                            delegate.hiddenHere ? bar.ecto.show(delegate.desktop) : bar.ecto.hide(delegate.desktop);
                        } else if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)
                                   && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(event.key)) {
                            // Ectoview: Ctrl+Shift+arrow moves this desktop one place
                            event.accepted = true;
                            const back = bar.verticalDesktopBar ? event.key === Qt.Key_Up
                                : (event.key === Qt.Key_Left) !== LayoutMirroring.enabled;
                            const along = bar.verticalDesktopBar ? (event.key === Qt.Key_Up || event.key === Qt.Key_Down)
                                : (event.key === Qt.Key_Left || event.key === Qt.Key_Right);
                            const to = bar.shown[delegate.place + (back ? -1 : 1)];
                            if (along && to !== undefined) {
                                const me = delegate.desktop;
                                bar.moveDesktop(me, to);
                                Qt.callLater(() => {
                                    const item = desktopRepeater.itemAt(KWinComponents.Workspace.desktops.indexOf(me));
                                    if (item) {
                                        item.forceActiveFocus();
                                    }
                                });
                            }
                        }
                    }

                    Keys.onLeftPressed: nextItemInFocusChain(LayoutMirroring.enabled).forceActiveFocus(Qt.BacktabFocusReason);
                    Keys.onRightPressed: nextItemInFocusChain(!LayoutMirroring.enabled).forceActiveFocus(Qt.TabFocusReason);

                    function activate() {
                        if (KWinComponents.SceneView.currentDesktop === delegate.desktop) {
                            effect.deactivate()
                        } else {
                            KWinComponents.SceneView.currentDesktop = delegate.desktop;
                        }
                    }

                    function remove() {
                        if (desktopRepeater.count === 1) {
                            return;
                        }
                        if (delegate.activeFocus) {
                            if (delegate.index === 0) {
                                desktopRepeater.itemAt(1).forceActiveFocus();
                            } else {
                                desktopRepeater.itemAt(delegate.index - 1).forceActiveFocus();
                            }
                        }
                        bar.desktopModel.remove(delegate.index);
                    }

                    Item {
                        id: thumbnailArea
                        width: bar.desktopWidth
                        height: bar.desktopHeight
                        scale: delegate.dragged ? 1.06 : 1
                        layer.enabled: delegate.dragged
                        layer.effect: DropShadow {
                            transparentBorder: true
                            verticalOffset: 10
                            radius: 24
                            samples: 49
                            color: bar.theme.c.shadow
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Kirigami.Units.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }

                        HoverHandler {
                            id: thumbnailHover
                            cursorShape: delegate.dragged ? Qt.ClosedHandCursor : Qt.ArrowCursor
                        }

                        // Ectoview: press and drag moves the desktop; a click still switches to it.
                        // On a touchscreen the drag starts after holding the desktop for a moment.
                        function startDrag() {
                            delegate.travel = 0;
                            bar.dragTravel = 0;
                            bar.scrolled = 0;
                            bar.edgeDirection = 0;
                            bar.dragIndex = delegate.place;
                            bar.dropIndex = delegate.place;
                        }
                        property point lastScene
                        function follow(t, handler) {
                            bar.dragTravel = bar.verticalDesktopBar ? t.y : t.x;
                            bar.updateDrag();
                            bar.updateEdge(thumbnailArea.mapToItem(flick, handler.centroid.position));
                            // over the groups' pill (or its open list), the desktop goes to a group. Where
                            // the pointer is in the scene, from the handler itself: mapped from this tile,
                            // which moves with the drag, it came out off by the tile's own travel (78 px
                            // short of a pill the pointer was on, November 17, 2026)
                            lastScene = handler.centroid.scenePosition;
                            bar.overPill = !!bar.dropPill && bar.dropPill.dragOver(lastScene, delegate.desktop);
                        }
                        function endDrag() {
                            // landing on a place in the bar is landing on that desktop's place in KWin's order;
                            // desktops in other groups keep theirs around it
                            const place = bar.shown[bar.dropIndex], me = delegate.desktop;
                            const group = bar.overPill && bar.dropPill ? bar.dropPill.dropAt(lastScene) : "";
                            if (bar.dropPill) {
                                bar.dropPill.dragEnded();
                            }
                            bar.overPill = false;
                            bar.dragIndex = -1;
                            bar.dropIndex = -1;
                            bar.edgeDirection = 0;
                            delegate.travel = 0;
                            if (group !== "") {
                                bar.ecto.moveToGroup(me, group);
                            } else {
                                bar.moveDesktop(me, place);
                            }
                        }
                        DragHandler {
                            id: desktopDrag
                            target: null
                            enabled: bar.shownCount > 1 || !!bar.dropPill
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                            grabPermissions: PointerHandler.CanTakeOverFromAnything
                            xAxis.enabled: !bar.verticalDesktopBar
                            yAxis.enabled: bar.verticalDesktopBar
                            onActiveChanged: active ? thumbnailArea.startDrag() : thumbnailArea.endDrag()
                            onActiveTranslationChanged: if (active) thumbnailArea.follow(activeTranslation, desktopDrag)
                        }
                        TapHandler {
                            id: holdToDrag
                            acceptedDevices: PointerDevice.TouchScreen
                            longPressThreshold: 0.5
                            property bool armed: false
                            onLongPressed: armed = true
                            onPressedChanged: if (!pressed) armed = false
                        }
                        DragHandler {
                            id: touchDrag
                            target: null
                            enabled: (bar.shownCount > 1 || !!bar.dropPill) && holdToDrag.armed
                            acceptedDevices: PointerDevice.TouchScreen
                            grabPermissions: PointerHandler.CanTakeOverFromAnything
                            xAxis.enabled: !bar.verticalDesktopBar
                            yAxis.enabled: bar.verticalDesktopBar
                            onActiveChanged: active ? thumbnailArea.startDrag() : thumbnailArea.endDrag()
                            onActiveTranslationChanged: if (active) thumbnailArea.follow(activeTranslation, touchDrag)
                        }

                        DesktopView {
                            id: thumbnail
                            opacity: delegate.elsewhere ? 0.55 : 1

                            width: targetScreen.geometry.width
                            height: targetScreen.geometry.height
                            windowModel: bar.windowModel
                            desktop: delegate.desktop
                            scale: bar.desktopHeight / targetScreen.geometry.height
                            transformOrigin: Item.TopLeft


                            layer.textureSize: Qt.size(bar.desktopWidth, bar.desktopHeight)
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    anchors.centerIn: parent
                                    width: thumbnail.width
                                    height: thumbnail.height
                                    // Ectoview: the theme's corner, at thumbnail size (this mask is drawn full size, then scaled)
                                    radius: bar.theme.thumbRadius / thumbnail.scale
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: bar.theme.thumbRadius
                            color: "transparent"
                            border.width: 1
                            border.color: bar.theme.c.border
                        }

                        // Ectoview: a desktop you're on that's in another group says which (Hidden, or the group's name)
                        Rectangle {
                            visible: delegate.elsewhere
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            height: 22
                            width: hiddenRow.implicitWidth + 14
                            radius: height / 2
                            color: bar.theme.c.scrim
                            border.width: 1
                            border.color: bar.theme.c.borderStrong
                            Row {
                                id: hiddenRow
                                anchors.centerIn: parent
                                spacing: 5
                                Kirigami.Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 13
                                    height: 13
                                    source: Qt.resolvedUrl(delegate.hiddenHere ? "ectoview-eye-off.svg" : "ectoview-group.svg")
                                    isMask: true
                                    color: bar.theme.c.fg
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: bar.ecto.groupName(delegate.groupHere)
                                    font.family: bar.theme.sans
                                    font.pixelSize: 11
                                    color: bar.theme.c.fg
                                }
                            }
                        }

                        Highlight {
                            id: highlight
                            active: delegate.activeFocus || bar.selectedDesktop === delegate.desktop || delegate.dragged
                            hovered: thumbnailHover.hovered
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: mouse => {
                                mouse.accepted = true;
                                delegate.activate();
                            }
                        }

                        // Ectoview: on hover, Move to desktop group (its groups, Hidden, New desktop group) beside delete
                        Row {
                            LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 6
                            spacing: 4
                            visible: !bar.heap.dragActive && bar.dragIndex < 0 && (hoverHandler.hovered || Kirigami.Settings.tabletMode || Kirigami.Settings.hasTransientTouchInput)
                            RoundButton {
                                id: moveButton
                                text: i18nc("@info:tooltip", "Move to desktop group")
                                iconSource: Qt.resolvedUrl("ectoview-move-to-group.svg")
                                onClicked: moveMenu.openFor(delegate.desktop, moveButton)
                            }
                            RoundButton {
                                visible: desktopCount > 1
                                text: i18nd("kwin", "Delete Virtual Desktop")
                                cross: true
                                onClicked: delegate.remove()
                            }
                        }

                        DropArea {
                            anchors.fill: parent
                            onEntered: (drag) => {
                                drag.accepted = true;
                            }
                            onDropped: drop => {
                                drop.accepted = true;
                                // dragging a KWin::Window
                                if (drag.source.desktops.length === 0 || drag.source.desktops.indexOf(delegate.desktop) !== -1) {
                                    drop.action = Qt.IgnoreAction;
                                    return;
                                }
                                drag.source.desktops = [delegate.desktop];
                                // Ectoview: into another desktop group (the bar showing it while the
                                // window was held on its row), and you go with it
                                bar.view.followWindowTo(delegate.desktop);
                            }
                        }
                    }

                    Item {
                        id: label
                        width: bar.desktopWidth
                        height: Kirigami.Units.gridUnit
                        state: "normal"

                        // a name too long to leave room for the beacon beside it is shortened on both
                        // sides alike, so it stays centered
                        TextMetrics {
                            id: nameMetrics
                            font: nameText.font
                            text: delegate.desktop.name
                        }
                        Text {
                            id: nameText
                            anchors.fill: parent
                            readonly property real beaconRoom: nameBeacon.visible && nameMetrics.advanceWidth > label.width - 2 * (nameBeacon.width + 6) ? nameBeacon.width + 6 : 0
                            leftPadding: beaconRoom
                            rightPadding: beaconRoom
                            elide: Text.ElideRight
                            font.family: bar.theme.sans
                            font.pixelSize: bar.theme.fontSize
                            font.weight: (bar.selectedDesktop === delegate.desktop || delegate.dragged) ? Font.Medium : Font.Normal
                            color: (bar.selectedDesktop === delegate.desktop || delegate.dragged) ? bar.theme.c.fg : bar.theme.c.fgMuted
                            text: delegate.desktop.name
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: label.state === "normal"
                        }
                        // Ectoview: every desktop's notification beacon, just left of its name, set
                        // off from it, the name centered as ever: grey, and the accent while a window
                        // on this desktop asks for attention
                        EctoBeacon {
                            id: nameBeacon
                            objectName: "beacon-" + delegate.desktop.id
                            visible: label.state === "normal"
                            lit: bar.asksAttention(delegate.desktop)
                            quiet: bar.theme.c.fgSubtle
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, (parent.width - nameText.contentWidth) / 2 - 6 - width)
                            size: 8
                            tone: bar.theme.accent
                            motion: bar.motion
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: mouse => {
                                mouse.accepted = true;
                                label.startEditing();
                            }
                        }

                        // Ectoview: renaming in the Ecto look, a small field with an accent edge
                        // (that's where you are), the name selected so typing replaces it
                        Loader {
                            active: label.state === "editing"
                            anchors.centerIn: parent
                            width: parent.width
                            height: 26
                            sourceComponent: T.TextField {
                                padding: 0
                                leftPadding: 8
                                rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.family: bar.theme.sans
                                font.pixelSize: bar.theme.fontSize
                                font.weight: Font.Medium
                                color: bar.theme.c.fg
                                selectionColor: bar.theme.accent
                                selectedTextColor: bar.theme.onAccent
                                text: delegate.desktop.name
                                background: Rectangle {
                                    radius: 6
                                    color: bar.theme.c.bgSubtle
                                    border.width: 1
                                    border.color: bar.theme.accent
                                }
                                onEditingFinished: {
                                    // an empty name keeps the old one
                                    if (text.trim().length > 0) {
                                        delegate.desktop.name = text.trim();
                                    }
                                    label.stopEditing();
                                }
                                Keys.onEscapePressed: label.stopEditing();
                                Component.onCompleted: {
                                    forceActiveFocus();
                                    selectAll();
                                }
                            }
                        }

                        states: [
                            State {
                                name: "normal"
                            },
                            State {
                                name: "editing"
                            }
                        ]

                        function startEditing() {
                            state = "editing";
                        }
                        function stopEditing() {
                            state = "normal";
                        }
                    }

                    HoverHandler {
                        id: hoverHandler
                    }
                }
            }

            PC3.Button {
                width: bar.desktopWidth
                height: bar.desktopHeight

                text: if (desktopCount < desktopModel.maximum) {
                    i18nd("kwin", "Add Virtual Desktop")
                } else {
                    i18nd("kwin", "Virtual Desktop limit reached")
                }
                display: PC3.AbstractButton.IconOnly
                enabled: desktopCount < desktopModel.maximum
                padding: 0
                background: Rectangle {
                    radius: bar.theme.thumbRadius
                    color: parent.hovered && parent.enabled ? bar.theme.c.bgMuted : Qt.rgba(bar.theme.c.bgSubtle.r, bar.theme.c.bgSubtle.g, bar.theme.c.bgSubtle.b, 0.72)
                    border.width: 1
                    border.color: bar.theme.c.border
                }
                contentItem: Item {
                    EctoCross {
                        anchors.centerIn: parent
                        plus: true
                        size: 24
                        color: bar.theme.c.fgMuted
                        opacity: parent.parent.enabled ? 1 : 0.4
                    }
                }

                Highlight {
                    active: parent.activeFocus
                    hovered: parent.hovered && parent.enabled
                }

                PC3.ToolTip.text: text
                PC3.ToolTip.visible: hovered
                PC3. ToolTip.delay: Kirigami.Units.toolTipDelay
                Accessible.name: text

                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()

                Keys.onLeftPressed: nextItemInFocusChain(LayoutMirroring.enabled).forceActiveFocus(Qt.BacktabFocusReason);
                Keys.onRightPressed: nextItemInFocusChain(!LayoutMirroring.enabled).forceActiveFocus(Qt.TabFocusReason);

                // (a new desktop goes in the group shown)
                onClicked: bar.view.addDesktop()

                DropArea {
                    anchors.fill: parent
                    onEntered: drag => {
                        drag.accepted = desktopCount < desktopModel.maximum;
                    }
                    onDropped: drag => {
                        const made = bar.view.addDesktop();
                        if (made) {
                            drag.source.desktops = [made];
                            bar.view.followWindowTo(made);
                        }
                    }
                }
            }

            // Ectoview: a round 28 px button on a dark disc, with an icon or an ✕
            component RoundButton: PC3.Button {
                property url iconSource
                property bool cross: false
                display: PC3.AbstractButton.IconOnly
                width: bar.theme.buttonSize
                height: bar.theme.buttonSize
                padding: 0
                background: Rectangle {
                    radius: width / 2
                    color: parent.hovered ? bar.theme.c.bgMuted : bar.theme.c.scrim
                    border.width: 1
                    border.color: bar.theme.c.borderStrong
                }
                contentItem: Item {
                    EctoCross {
                        visible: parent.parent.cross
                        anchors.centerIn: parent
                        size: 10
                        color: bar.theme.c.fg
                    }
                    Kirigami.Icon {
                        visible: !parent.parent.cross
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        source: parent.parent.iconSource
                        isMask: true
                        color: bar.theme.c.fg
                    }
                }
                PC3.ToolTip.text: text
                PC3.ToolTip.visible: hovered
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            component Highlight: Rectangle {
                required property bool active
                required property bool hovered
                visible: active || hovered
                anchors.fill: parent
                anchors.margins: -(bar.theme.ringWidth + 3)
                radius: bar.theme.thumbRadius + 3 + bar.theme.ringWidth
                color: "transparent"
                border.width: bar.theme.ringWidth
                border.color: bar.theme.accent
                opacity: !active && hovered ? 0.5 : 1.0
                z: -10
            }
        }
    }
}
