/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The settings gear: Ectoview closes and its settings page opens. In the toolbar after the search
    field, or at the end of the desktop bar when the toolbar is hidden.
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: gear

    required property QtObject ecto
    readonly property QtObject theme: ecto.theme
    readonly property string text: i18nc("@action:button", "Ectoview Settings")

    width: theme.rowHeight
    height: theme.rowHeight
    radius: height / 2
    color: gearHover.hovered ? theme.c.bgMuted : theme.c.bgSubtle
    border.width: 1
    border.color: theme.c.border
    Accessible.role: Accessible.Button
    Accessible.name: text
    Kirigami.Icon {
        anchors.centerIn: parent
        width: 16
        height: 16
        source: Qt.resolvedUrl("ectoview-gear.svg")
        isMask: true
        color: gearHover.hovered ? gear.theme.c.fg : gear.theme.c.fgMuted
    }
    HoverHandler {
        id: gearHover
        cursorShape: Qt.PointingHandCursor
    }
    // a MouseArea takes the click (a TapHandler would let it through to the backdrop)
    MouseArea {
        // the hand on the click area itself: one without a cursor of its own shows
        // whatever's under it (the text field's text cursor), whatever a hover handler says
        cursorShape: Qt.PointingHandCursor
        anchors.fill: parent
        onClicked: gear.ecto.openSettings()
    }
    PC3.ToolTip.text: text
    PC3.ToolTip.visible: gearHover.hovered
    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
}
