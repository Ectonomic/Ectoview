/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A plain arrow that steps somewhere: the desktop view's < and > (to the previous and next desktop
    in the group, design proposal 7) and the bar's ^ and v (to the previous and next desktop group).
    No box: a faint chevron that brightens when pointed at, with the name of where it leads; a click
    steps. A window held on it: after a pause it steps, and again after the same pause while the
    window stays (timed by the clock, with a guard that needs a full pause since the last step,
    whatever restarted the wait). A window dropped on it is offered to `accepts`, then `windowDropped`.
    The root is the drop target (a window is harder to aim than a pointer); the click target sits in
    its middle.
*/

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: arrow

    required property QtObject theme
    // which way the chevron points, in degrees: 0 right, 180 left, -90 up, 90 down
    property real angle: 0
    // where it leads, shown while it's pointed at or held
    property string label: ""
    // the name below the chevron, or above it (an arrow above a vertical bar)
    property bool labelAbove: false
    // which way the name grows from the chevron: centered, or away from what sits beside the arrow
    // ("left": ending at the arrow's right edge, for one left of the bar; "right": starting at its
    // left edge)
    property string labelGrows: "center"
    property real glyphSize: 32
    property real clickWidth: 72
    property real clickHeight: 120
    // the pause before a held window steps, and between steps while it stays
    property int holdMs: 1000
    // whether a window dropped here is taken (it isn't when it's already where this leads)
    property var accepts: (window) => false
    // a stepper inside a control (the groups' pill, design proposal 8): Ectoview's caret token for the
    // chevron (10 px, the muted grey, as every caret), a lighter fill when pointed at, an accent ring
    // while a window is held on it, its label under the control; `roundRight` for the one at the
    // control's round end. `dim`: nowhere to go, so no clicks or drops, the chevron at 35 %.
    property bool caret: false
    property bool roundRight: false
    property bool dim: false

    signal activated()
    signal windowDropped(var window)

    // a window over it (and still over it after the arrow itself moved: see lastSeen)
    readonly property bool held: {
        x; y; width; height;
        if (!windowDrop.containsDrag) {
            return false;
        }
        const at = mapFromItem(null, windowDrop.lastSeen.x, windowDrop.lastSeen.y);
        return contains(at);
    }
    onHeldChanged: if (!held) hold.stop()
    readonly property bool lit: held || pointer.containsMouse

    // the stepper's fill: square where it meets its neighbour, round at the control's end, inside the
    // control's 1 px border
    Item {
        visible: arrow.caret
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        anchors.rightMargin: arrow.roundRight ? 1 : 0
        clip: true
        Rectangle {
            x: arrow.roundRight ? -parent.height : 0
            width: parent.width + (arrow.roundRight ? parent.height : 0)
            height: parent.height
            radius: arrow.roundRight ? height / 2 : 0
            color: arrow.held || (pointer.containsMouse && !arrow.dim) ? arrow.theme.c.bgMuted : "transparent"
            border.width: arrow.held ? 2 : 0
            border.color: arrow.theme.accent
        }
        // (the ring's left side, which the round shape leaves outside the clip)
        Rectangle {
            visible: arrow.held && arrow.roundRight
            width: 2
            height: parent.height
            color: arrow.theme.accent
        }
    }
    MouseArea {
        id: pointer
        anchors.centerIn: parent
        width: arrow.clickWidth
        height: arrow.clickHeight
        hoverEnabled: true
        enabled: !arrow.dim
        cursorShape: Qt.PointingHandCursor
        onClicked: arrow.activated()
    }
    DropArea {
        id: windowDrop
        anchors.fill: parent
        keys: ["kwin-window"]
        enabled: !arrow.dim
        // where the held window's hot spot was last seen, on screen: an arrow that moves (the bar's,
        // when the next group has fewer desktops) can leave a still pointer behind without a word
        // from the drop area, which only hears of the window when it moves
        property point lastSeen
        onEntered: (drag) => {
            drag.accepted = true;
            lastSeen = mapToItem(null, drag.x, drag.y);
            hold.restart();
        }
        onPositionChanged: (drag) => lastSeen = mapToItem(null, drag.x, drag.y)
        onExited: hold.stop()
        onDropped: (drop) => {
            const window = drop.source;
            hold.stop();
            if (!window || window.desktops.length === 0 || !arrow.accepts(window)) {
                drop.accepted = true;
                drop.action = Qt.IgnoreAction;
                return;
            }
            drop.accept(Qt.MoveAction);
            arrow.windowDropped(window);
        }
    }
    onVisibleChanged: if (!visible) hold.stop()

    property real lastStep: 0
    Timer {
        id: hold
        interval: arrow.holdMs
        onTriggered: {
            const now = Date.now();
            if (now - arrow.lastStep < arrow.holdMs - 50) {
                hold.interval = arrow.holdMs - (now - arrow.lastStep);
                hold.restart();
                return;
            }
            hold.interval = arrow.holdMs;
            if (!arrow.visible || !arrow.held) {
                return;
            }
            arrow.lastStep = now;
            arrow.activated();
            // (again after the same pause, if the window is still over it then)
            if (arrow.held) {
                hold.restart();
            }
        }
    }

    // a stepper's chevron sits off center when its part carries padding (the pill's spacing)
    property real glyphShift: 0
    Kirigami.Icon {
        id: glyph
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: arrow.glyphShift
        width: arrow.glyphSize
        height: arrow.glyphSize
        source: Qt.resolvedUrl("ectoview-chevron.svg")
        isMask: true
        color: arrow.caret ? arrow.theme.c.fgMuted : arrow.held ? arrow.theme.accent : arrow.theme.c.fg
        rotation: arrow.angle
        opacity: arrow.caret ? (arrow.dim ? 0.35 : 1) : arrow.lit ? 1 : 0.5
        scale: pointer.pressed ? 0.88 : 1
        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }
    Text {
        anchors.top: arrow.labelAbove ? undefined : arrow.caret ? arrow.bottom : glyph.bottom
        anchors.bottom: arrow.labelAbove ? glyph.top : undefined
        anchors.topMargin: arrow.caret ? 8 : 10
        anchors.bottomMargin: 10
        width: Math.min(implicitWidth, 220)
        x: arrow.labelGrows === "left" ? arrow.width - width
            : arrow.labelGrows === "right" ? 0
            : (arrow.width - width) / 2
        horizontalAlignment: arrow.labelGrows === "left" ? Text.AlignRight : arrow.labelGrows === "right" ? Text.AlignLeft : Text.AlignHCenter
        elide: Text.ElideRight
        text: arrow.label
        textFormat: Text.PlainText
        font.family: arrow.theme.sans
        font.pixelSize: arrow.theme.fontSize
        font.weight: arrow.held ? Font.DemiBold : Font.Normal
        color: arrow.held ? arrow.theme.c.fg : arrow.theme.c.fgMuted
        opacity: arrow.lit ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }
    }
}
