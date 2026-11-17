/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    An ✕ or a + drawn from two bars, so it takes any color and stays sharp at any size.
*/

import QtQuick

Item {
    id: mark
    property real size: 12
    property color color: "white"
    property real thickness: 1.5
    property bool plus: false

    width: size
    height: size

    Repeater {
        model: 2
        Rectangle {
            required property int index
            anchors.centerIn: parent
            width: mark.plus ? mark.size : mark.size * Math.SQRT2
            height: mark.thickness
            radius: mark.thickness / 2
            color: mark.color
            rotation: (mark.plus ? 0 : 45) + index * 90
            antialiasing: true
        }
    }
}
