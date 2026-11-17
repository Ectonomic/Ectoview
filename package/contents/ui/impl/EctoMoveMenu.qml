/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    "Move to desktop group" (design proposal 4): the short list a desktop's hover button opens. Its groups
    (a check on the one it's in), Hidden, and New desktop group…, which makes a group holding this desktop
    once you've typed its name.
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

Item {
    id: menu

    required property QtObject ecto
    readonly property QtObject theme: ecto.theme
    readonly property real panelWidth: 230
    property bool opened: false
    property QtObject desktop: null
    property bool naming: false
    property real panelX: 0
    property real panelY: 0

    // opens under `anchorItem` (the desktop's button), inside the screen
    function openFor(desktop, anchorItem) {
        menu.desktop = desktop;
        naming = false;
        const at = anchorItem.mapToItem(menu, 0, 0);
        const h = column.implicitHeight + 8;
        panelX = Math.max(8, Math.min(menu.width - panelWidth - 8, at.x));
        panelY = at.y + anchorItem.height + 6 + h > menu.height - 8 ? at.y - h - 6 : at.y + anchorItem.height + 6;
        opened = true;
        forceActiveFocus();
    }
    // the view (Main.qml), for the keys to go back to its search when the list closes
    property Item view
    function close() {
        const was = opened;
        opened = false;
        naming = false;
        if (was && view) {
            view.restoreFocus();
        }
    }
    function moveTo(id) {
        const d = menu.desktop;
        close();
        ecto.moveToGroup(d, id);
    }

    parent: Window.window ? Window.window.contentItem : null
    anchors.fill: parent
    visible: opened
    z: 1000
    Keys.onEscapePressed: close()
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
    }
    Rectangle {
        x: menu.panelX
        y: menu.panelY
        width: menu.panelWidth
        height: column.implicitHeight + 8
        radius: menu.theme.menuRadius
        color: menu.theme.c.bg
        border.width: 1
        border.color: menu.theme.c.border
        MouseArea {
            anchors.fill: parent
        }
        Column {
            id: column
            x: 4
            y: 4
            Text {
                width: menu.panelWidth - 8
                leftPadding: 10
                rightPadding: 10
                topPadding: 8
                bottomPadding: 6
                elide: Text.ElideRight
                text: menu.desktop ? i18nc("@title:menu %1 is a desktop's name", "Move %1 to", menu.desktop.name) : ""
                textFormat: Text.PlainText
                font.family: menu.theme.sans
                font.pixelSize: menu.theme.smallFontSize
                color: menu.theme.c.fgSubtle
            }
            Repeater {
                model: menu.ecto.groups
                delegate: GroupEntry {
                    required property var modelData
                    groupId: modelData.id
                    label: modelData.name
                }
            }
            Line {}
            GroupEntry {
                groupId: menu.ecto.hiddenGroup
                label: menu.ecto.groupName(menu.ecto.hiddenGroup)
                icon: "ectoview-eye-off.svg"
            }
            Line {}
            // New desktop group…: a name field in its place; Enter makes the group with this desktop in it
            Rectangle {
                width: menu.panelWidth - 8
                height: 34
                radius: menu.theme.menuItemRadius
                color: newHover.hovered && !menu.naming ? menu.theme.c.bgMuted : "transparent"
                Row {
                    visible: !menu.naming
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    EctoCross {
                        anchors.verticalCenter: parent.verticalCenter
                        plus: true
                        size: 12
                        color: menu.theme.c.fgMuted
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18nc("@action make a desktop group holding this desktop", "New desktop group…")
                        font.family: menu.theme.sans
                        font.pixelSize: menu.theme.fontSize
                        color: menu.theme.c.fg
                    }
                }
                HoverHandler {
                    id: newHover
                    cursorShape: menu.naming ? Qt.IBeamCursor : Qt.PointingHandCursor
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !menu.naming
                    // the hand on the click area itself (see EctoSearchField's caret)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menu.naming = true
                }
                Loader {
                    active: menu.naming
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 12
                    height: 26
                    sourceComponent: T.TextField {
                        padding: 0
                        leftPadding: 8
                        rightPadding: 8
                        verticalAlignment: Text.AlignVCenter
                        font.family: menu.theme.sans
                        font.pixelSize: menu.theme.fontSize
                        color: menu.theme.c.fg
                        selectionColor: menu.theme.accent
                        selectedTextColor: menu.theme.onAccent
                        text: menu.ecto.nextGroupName()
                        background: Rectangle {
                            radius: 6
                            color: menu.theme.c.bgSubtle
                            border.width: 1
                            border.color: menu.theme.accent
                        }
                        onAccepted: {
                            const d = menu.desktop, name = text;
                            menu.close();
                            menu.ecto.addGroup(name, d);
                        }
                        Keys.onEscapePressed: {
                            menu.naming = false;
                            menu.forceActiveFocus();
                        }
                        Component.onCompleted: {
                            forceActiveFocus();
                            selectAll();
                        }
                    }
                }
            }
        }
    }

    component Line: Item {
        width: menu.panelWidth - 8
        height: 9
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: menu.theme.c.border
        }
    }

    // a group to move the desktop to; a check on the one it's in
    component GroupEntry: Rectangle {
        id: entry
        property string groupId
        property string label
        property string icon: ""
        readonly property bool here: menu.desktop && menu.ecto.groupOf(menu.desktop) === groupId
        width: menu.panelWidth - 8
        height: 34
        radius: menu.theme.menuItemRadius
        color: entryHover.hovered ? menu.theme.c.bgMuted : "transparent"
        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Kirigami.Icon {
                visible: entry.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                source: entry.icon !== "" ? Qt.resolvedUrl(entry.icon) : ""
                isMask: true
                color: menu.theme.c.fgMuted
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, menu.panelWidth - 70)
                elide: Text.ElideRight
                text: entry.label
                textFormat: Text.PlainText
                font.family: menu.theme.sans
                font.pixelSize: menu.theme.fontSize
                color: menu.theme.c.fg
            }
        }
        Kirigami.Icon {
            visible: entry.here
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            source: "checkmark"
            isMask: true
            color: menu.theme.accent
        }
        HoverHandler {
            id: entryHover
            cursorShape: Qt.PointingHandCursor
        }
        MouseArea {
            anchors.fill: parent
            // the hand on the click area itself (see EctoSearchField's caret)
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!entry.here) menu.moveTo(entry.groupId)
        }
    }
}
