/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The search field in Ectolens's row drawing: a 36 px round row, a search mark 14 px from its
    round end, and an accent edge once there is text (that's where you are). Same text field
    underneath as the PlasmaExtras.SearchField it replaces, so focus, keys and readOnly behave
    as in Overview.
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

T.TextField {
    id: field

    readonly property QtObject ecto: KWinComponents.SceneView.effect.impl
    readonly property QtObject theme: ecto.theme
    // what typing searches: 0 this desktop, 1 this group, 2 all desktops
    readonly property int scope: ecto.searchScope
    // the group the view shows (Main.qml)
    property string viewGroup
    // the shown group's desktops, named in "This desktop group"'s line
    readonly property var groupDesktops: KWinComponents.Workspace.desktops.filter(d => ecto.groupOf(d) === viewGroup).map(d => d.name)

    implicitHeight: theme.rowHeight
    leftPadding: 14 + 16 + 10
    // room for what sits inside the right end: the "All desktops" tag, ✕, and the scope caret
    rightPadding: 7 + 22 + (clearButton.visible ? 22 + 2 : 0) + (allTag.visible ? allTag.width + 6 : 0) + 6
    verticalAlignment: TextInput.AlignVCenter
    font.family: theme.sans
    font.pixelSize: theme.fontSize
    color: theme.c.fg
    selectionColor: theme.accent
    selectedTextColor: theme.onAccent
    placeholderText: scope === 2 ? i18nc("@info:placeholder in Ectoview's search field", "Search all desktops and apps")
                   : scope === 1 ? i18nc("@info:placeholder in Ectoview's search field", "Search this desktop group and apps")
                   : i18nc("@info:placeholder in Ectoview's search field", "Search windows and apps")
    placeholderTextColor: theme.c.fgSubtle

    background: Rectangle {
        radius: height / 2
        color: field.theme.c.bgSubtle
        border.width: 1
        border.color: field.text.length > 0 ? field.theme.accent : field.theme.c.border

        // the search mark: a ring and a handle, drawn so it takes the theme's color
        Item {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            Rectangle {
                x: 1.5; y: 1.5
                width: 10; height: 10
                radius: 5
                color: "transparent"
                border.width: 1.5
                border.color: field.theme.c.fgSubtle
            }
            Rectangle {
                x: 10; y: 9.5
                width: 6; height: 1.5
                radius: 0.75
                rotation: 45
                transformOrigin: Item.Left
                color: field.theme.c.fgSubtle
            }
        }
    }

    // the placeholder (a bare text field draws none)
    Text {
        x: field.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        visible: field.text.length === 0 && field.preeditText.length === 0
        text: field.placeholderText
        font: field.font
        color: field.placeholderTextColor
        elide: Text.ElideRight
        width: field.width - field.leftPadding - field.rightPadding
    }

    // what typing searches, said inside the field while it's more than this desktop
    Text {
        id: allTag
        visible: field.scope > 0 && field.text.length > 0
        anchors.right: clearButton.visible ? clearButton.left : scopeCaret.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: field.scope === 2 ? i18nc("@info searching every desktop", "All desktops") : field.ecto.groupName(field.viewGroup)
        textFormat: Text.PlainText
        font.family: field.theme.sans
        font.pixelSize: field.theme.smallFontSize
        color: field.theme.c.fgSubtle
    }

    // the scope caret at the field's right end: This desktop, This group (once there are groups) or All desktops
    Rectangle {
        id: scopeCaret
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 22
        radius: 11
        color: caretHover.hovered || scopeMenu.opened ? field.theme.c.bgMuted : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: i18nc("@action:button", "What to search")
        Kirigami.Icon {
            anchors.centerIn: parent
            width: 10
            height: 10
            source: Qt.resolvedUrl("ectoview-chevron.svg")
            isMask: true
            rotation: 90
            color: field.scope > 0 ? field.theme.accent : field.theme.c.fgMuted
        }
        HoverHandler {
            id: caretHover
            cursorShape: Qt.PointingHandCursor
        }
        MouseArea {
            // the hand on the click area itself: one without a cursor of its own shows
            // whatever's under it (the text field's text cursor), whatever a hover handler says
            cursorShape: Qt.PointingHandCursor
            anchors.fill: parent
            onClicked: scopeMenu.opened ? scopeMenu.close() : scopeMenu.open()
        }
    }

    // its menu: a panel over everything in this view, below the field's right end, with a catcher
    // behind it so a click outside closes the menu and nothing else
    Item {
        id: scopeMenu
        property bool opened: false
        property real panelX: 0
        property real panelY: 0
        function open() {
            const at = field.mapToItem(scopeMenu, 0, 0);
            panelX = at.x + field.width - 300;
            panelY = at.y + field.height + 8;
            opened = true;
        }
        function close() {
            opened = false;
            field.forceActiveFocus();
        }
        parent: field.Window.window ? field.Window.window.contentItem : field
        anchors.fill: parent
        visible: opened
        z: 1000
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: scopeMenu.close()
        }
        Rectangle {
            x: scopeMenu.panelX
            y: scopeMenu.panelY
            width: 300
            height: scopeColumn.implicitHeight + 8
            radius: field.theme.menuRadius
            color: field.theme.c.bg
            border.width: 1
            border.color: field.theme.c.border
            MouseArea {
                anchors.fill: parent
            }
            Column {
                id: scopeColumn
                x: 4
                y: 4
                Repeater {
                    model: [
                        { scope: 0, text: i18nc("@item:inmenu search scope", "This desktop"), sub: i18nc("@info", "Windows on the desktop you're on") }
                    ].concat(field.ecto.hasGroups || field.scope === 1 ? [
                        { scope: 1, text: i18nc("@item:inmenu search scope", "This desktop group"), sub: field.groupLine() }
                    ] : []).concat([
                        { scope: 2, text: i18nc("@item:inmenu search scope", "All desktops"), sub: i18nc("@info", "Every desktop's windows, hidden ones too") }
                    ])
                    delegate: Rectangle {
                        id: scopeRow
                        required property var modelData
                        width: 292
                        height: 46
                        radius: field.theme.menuItemRadius
                        color: rowHover.hovered ? field.theme.c.bgMuted : "transparent"
                        HoverHandler {
                            id: rowHover
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                field.ecto.setSearchScope(scopeRow.modelData.scope);
                                scopeMenu.close();
                            }
                        }
                        Kirigami.Icon {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            visible: field.scope === scopeRow.modelData.scope
                            source: "checkmark"
                            isMask: true
                            color: field.theme.accent
                        }
                        Column {
                            x: 10 + 16 + 10
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: scopeRow.modelData.text
                                font.family: field.theme.sans
                                font.pixelSize: field.theme.fontSize
                                color: field.theme.c.fg
                            }
                            Text {
                                width: 292 - 36 - 10
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: scopeRow.modelData.sub
                                font.family: field.theme.sans
                                font.pixelSize: field.theme.smallFontSize
                                color: field.theme.c.fgSubtle
                            }
                        }
                    }
                }
            }
        }
    }

    // "This desktop group"'s line: the group's desktops by name, up to three
    function groupLine() {
        const n = groupDesktops;
        if (n.length === 0 || n.length > 3) {
            return i18nc("@info %1 is a desktop group's name", "Windows on any desktop in %1", ecto.groupName(viewGroup));
        }
        if (n.length === 1) {
            return i18nc("@info %1 is a desktop's name", "Windows on %1", n[0]);
        }
        return i18nc("@info %1 is a list of desktop names, %2 the last one", "Windows on %1 and %2", n.slice(0, -1).join(", "), n[n.length - 1]);
    }

    // clears the search, as Overview's field does
    Rectangle {
        id: clearButton
        visible: field.text.length > 0 && !field.readOnly
        anchors.right: scopeCaret.left
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 22
        radius: 11
        color: clearHover.hovered ? field.theme.c.bgMuted : "transparent"
        EctoCross {
            anchors.centerIn: parent
            size: 10
            color: field.theme.c.fgMuted
        }
        HoverHandler {
            id: clearHover
            cursorShape: Qt.PointingHandCursor
        }
        // a MouseArea takes the click (a TapHandler lets it through to the backdrop, which closes Ectoview)
        MouseArea {
            // the hand on the click area itself: one without a cursor of its own shows
            // whatever's under it (the text field's text cursor), whatever a hover handler says
            cursorShape: Qt.PointingHandCursor
            anchors.fill: parent
            onClicked: {
                field.clear();
                field.forceActiveFocus();
            }
        }
    }
}
