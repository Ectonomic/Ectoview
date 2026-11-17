/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A notification beacon: a dot in Ectoview's accent (the owner's call, November 17, 2026), with a
    ring that swells and fades from it while Plasma's animations are on. Unlit (`lit: false`) it's
    a quiet grey dot with no ring: a desktop's beacon is always there, grey until a window on it asks
    for attention (the owner's call, the same day).
    Shown on a desktop where a window asks for attention, and on a desktop group holding one.
*/

import QtQuick

Item {
    id: beacon

    // how long one swell of the ring takes, 0 = no ring (Plasma's animations off)
    property real motion: 1
    property real size: 10
    // the theme's accent (EctoTheme.accent), and the grey it rests in (drawn at 70 %)
    required property color tone
    property color quiet: "#8b8b94"
    property bool lit: true

    width: size
    height: size

    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: beacon.size
        height: beacon.size
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: beacon.tone
        opacity: 0
        visible: beacon.lit && beacon.motion > 0
        ParallelAnimation {
            running: beacon.visible && beacon.lit && beacon.motion > 0
            loops: Animation.Infinite
            NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.6; duration: 1600 * beacon.motion; easing.type: Easing.OutCubic }
            NumberAnimation { target: ring; property: "opacity"; from: 0.9; to: 0; duration: 1600 * beacon.motion; easing.type: Easing.OutCubic }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: beacon.lit ? beacon.tone : beacon.quiet
        opacity: beacon.lit ? 1 : 0.7
        Behavior on color { ColorAnimation { duration: 150 * Math.max(beacon.motion, 0) } }
    }
}
