/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The desktop groups' pill (design proposal 4): the shown group's name, and a list of every group
    with small pictures of its first three desktops, how many it holds, rename and remove on hover,
    then Hidden and New desktop group. Choosing a group takes you to its last-used desktop. A desktop
    dragged from the bar onto the pill opens the list and drops into the group under the pointer.
    It sits in the toolbar left of the search field, or at the end of the desktop bar when the
    toolbar is hidden. It shows once there's a choice: two groups, or a hidden desktop.
*/

import QtQuick
import QtQuick.Templates as T
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import org.kde.plasma.components as PC3

Rectangle {
    id: pill

    required property QtObject ecto
    // the view (Main.qml): the group it shows, chooseGroup(), newGroup()
    property Item view
    property QtObject windowModel
    // the groups holding a desktop where a window asks for attention (DesktopBar.attentionGroups):
    // a beacon on the pill when one isn't the group shown, and on each such group's row
    property var attentionGroups: []
    readonly property bool attentionElsewhere: attentionGroups.some(g => g !== currentGroup)
    // where the list opens: "down", "up", "left" or "right" (away from the edge the pill is near)
    property string opens: "down"
    // the desktop bar, which knows the groups to step through (DesktopBar.neighborGroup): with two
    // or more, ^ and v are the pill's right end, behind a divider (design proposal 8)
    property Item desktopBar
    readonly property bool steppers: !!desktopBar && desktopBar.groupArrowsShown
    // the name half: the group's icon and name, which opens the list
    readonly property real nameWidth: pillRow.implicitWidth + 12 + 14
    readonly property QtObject theme: ecto.theme
    readonly property QtObject screen: KWinComponents.SceneView.screen
    readonly property string currentGroup: view ? view.viewGroup : ecto.groupOf(KWinComponents.SceneView.currentDesktop)
    readonly property var hiddenDesktops: KWinComponents.Workspace.desktops.filter(d => ecto.groupOf(d) === ecto.hiddenGroup)
    // the group being renamed in the list ("" for none)
    property string editingId: ""
    // a group's row being dragged to a new place in the list: where it was and where it would go
    // (the rows between slide aside to show the gap)
    property int reorderFrom: -1
    property int reorderTo: -1
    readonly property real panelWidth: 380

    visible: ecto.hasGroups
    onVisibleChanged: if (!visible) menu.close()
    height: theme.rowHeight
    // the steppers' parts: 29 and 31 px, so their chevrons sit 13 px from the divider, 12 apart and
    // 15 from the round end (the mock's spacing)
    width: nameWidth + (steppers ? 1 + 29 + 31 : 0)
    radius: height / 2
    color: theme.c.bgSubtle
    // the name half lightens when pointed at (square where it meets the divider), inside the border
    Item {
        x: 1
        y: 1
        width: pill.nameWidth - (pill.steppers ? 1 : 2)
        height: parent.height - 2
        clip: true
        Rectangle {
            width: parent.width + (pill.steppers ? parent.height : 0)
            height: parent.height
            radius: height / 2
            color: pillHover.hovered ? pill.theme.c.bgMuted : "transparent"
        }
    }
    border.width: menu.dragging && menu.overPill ? 2 : 1
    border.color: menu.opened ? theme.accent : theme.c.border
    Accessible.role: Accessible.Button
    Accessible.name: i18nc("@action:button %1 is a desktop group's name", "Desktop group: %1", pillText.text)
    Row {
        id: pillRow
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        spacing: 8
        Kirigami.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            source: Qt.resolvedUrl(pill.currentGroup === pill.ecto.hiddenGroup ? "ectoview-eye-off.svg" : "ectoview-group.svg")
            isMask: true
            color: pill.theme.c.fgMuted
        }
        Text {
            id: pillText
            anchors.verticalCenter: parent.verticalCenter
            // a new group's name fades in with the shelf's rise (100 ms in, 160 ms long)
            onTextChanged: if (pill.ecto.animationDuration > 0) nameFade.restart()
            SequentialAnimation {
                id: nameFade
                PropertyAction { target: pillText; property: "opacity"; value: 0 }
                PauseAnimation { duration: 100 * pill.ecto.animationDuration / 300 }
                NumberAnimation { target: pillText; property: "opacity"; to: 1; duration: 160 * pill.ecto.animationDuration / 300; easing.type: Easing.OutCubic }
            }
            text: pill.ecto.groupName(pill.currentGroup)
            textFormat: Text.PlainText
            font.family: pill.theme.sans
            font.pixelSize: pill.theme.fontSize
            color: pill.theme.c.fg
        }
    }
    // a desktop in another group asks for attention
    EctoBeacon {
        objectName: "beacon-pill"
        visible: pill.attentionElsewhere
        size: 9
        tone: pill.theme.accent
        x: parent.width - width * 0.8
        y: -height * 0.2
        motion: pill.ecto.animationDuration / 300
    }
    Item {
        id: nameHalf
        width: pill.nameWidth
        height: parent.height
        HoverHandler {
            id: pillHover
            cursorShape: Qt.PointingHandCursor
        }
    }
    // a MouseArea takes the click; a TapHandler would let it through to the backdrop
    MouseArea {
        // the hand on the click area itself: one without a cursor of its own shows
        // whatever's under it (the text field's text cursor), whatever a hover handler says
        cursorShape: Qt.PointingHandCursor
        anchors.fill: nameHalf
        onClicked: menu.opened ? menu.close() : menu.open()
    }

    // a dragged window over the pill or its open list (Main.qml keeps it at the size it came in at)
    readonly property bool windowOverMenu: menu.windowDrag && (pillDrop.containsDrag || (menu.opened && (panelDrop.containsDrag || menu.dropTarget !== "")))

    // ---- a window dragged from the view: over the pill, the list opens; on a group's row it drops
    // there, and held on a row the bar switches to that group so it can go on a desktop of it
    DropArea {
        id: pillDrop
        anchors.fill: nameHalf
        keys: ["kwin-window"]
        onEntered: (drag) => {
            drag.accepted = true;
            menu.windowDrag = true;
            if (!menu.opened) {
                menu.open();
            }
        }
    }
    Connections {
        target: pill.view
        // (a drag is marked over before its drop is delivered: the list stays for the drop, then goes)
        function onWindowDraggingChanged() {
            if (!pill.view.windowDragging && menu.windowDrag) {
                peekTimer.stop();
                Qt.callLater(() => {
                    menu.windowDrag = false;
                    menu.dropTarget = "";
                    menu.close();
                });
            }
        }
    }
    Timer {
        id: peekTimer
        property string groupId
        interval: 700
        onTriggered: {
            menu.close();
            if (pill.view) {
                pill.view.peekGroup(groupId);
            }
        }
    }

    // ---- a desktop dragged from the bar (DesktopBar.qml calls these with scene positions)
    // ---- ^ and v: the pill's right end, behind a divider (design proposal 8). They sit at the pill's
    // right end, which stays put, so a group name of another length doesn't move them. An arrow with
    // nowhere to go dims and takes no clicks or drops. (After the drop area above, so a window held
    // on one reaches it first.)
    Rectangle {
        visible: pill.steppers
        x: pill.nameWidth
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: parent.height - 18
        color: pill.theme.c.borderStrong
    }
    EctoGroupArrow {
        objectName: "group-previous"
        visible: pill.steppers
        desktopBar: pill.desktopBar || pill
        direction: -1
        caret: true
        dim: !target
        x: pill.nameWidth + 1
        width: 29
        height: parent.height
        glyphSize: 10
        glyphShift: 3.5
        clickWidth: width
        clickHeight: height
        labelGrows: "left"
    }
    EctoGroupArrow {
        objectName: "group-next"
        visible: pill.steppers
        desktopBar: pill.desktopBar || pill
        direction: 1
        caret: true
        roundRight: true
        dim: !target
        x: pill.nameWidth + 1 + 29
        width: 31
        height: parent.height
        glyphSize: 10
        glyphShift: -4.5
        clickWidth: width
        clickHeight: height
        labelGrows: "left"
    }

    // true while the pointer is over the pill or its open list
    function dragOver(scenePos, desktop) {
        const onPill = pill.contains(pill.mapFromItem(null, scenePos.x, scenePos.y));
        if (onPill && !menu.opened) {
            menu.open();
        }
        menu.dragging = true;
        menu.overPill = onPill;
        menu.ghostDesktop = desktop;
        const local = menu.mapFromItem(null, scenePos.x, scenePos.y);
        menu.ghostPos = local;
        const onPanel = menu.opened && panel.contains(panel.mapFromItem(null, scenePos.x, scenePos.y));
        menu.dropTarget = onPanel ? menu.groupAt(scenePos) : "";
        return onPill || onPanel;
    }
    // the group the desktop would land in there ("" for none)
    function dropAt(scenePos) {
        return menu.opened ? menu.groupAt(scenePos) : "";
    }
    function dragEnded() {
        menu.dragging = false;
        menu.dropTarget = "";
        menu.ghostDesktop = null;
        menu.close();
    }

// the list: a panel over everything in this view (the window's own content item), with a catcher
// behind it, so a click outside closes the list and nothing else
Item {
    id: menu
    property bool opened: false
    property real panelX: 0
    property real panelY: 0
    // a desktop being dragged onto a group
    property bool dragging: false
    property bool overPill: false
    property string dropTarget: ""
    // a window from the view is being dragged over the list
    property bool windowDrag: false
    property QtObject ghostDesktop: null
    property point ghostPos
    function open() {
        const at = pill.mapToItem(menu, 0, 0);
        const h = menuColumn.implicitHeight + 8;
        // the list opens away from the screen edge the pill sits on, inside the screen
        const x = pill.opens === "left" ? at.x - pill.panelWidth - 8 : pill.opens === "right" ? at.x + pill.width + 8 : at.x;
        panelX = Math.max(8, Math.min(menu.width - pill.panelWidth - 8, x));
        panelY = pill.opens === "up" ? at.y - h - 8 : pill.opens === "down" ? at.y + pill.height + 8 : Math.max(8, at.y + pill.height - h);
        opened = true;
        forceActiveFocus();
    }
    function close() {
        const was = opened;
        opened = false;
        pill.editingId = "";
        // typing goes to the search again
        if (was && pill.view) {
            pill.view.restoreFocus();
        }
    }
    // the group whose row is under a scene position
    function groupAt(scenePos) {
        for (let i = 0; i < groupRows.count; i++) {
            const row = groupRows.itemAt(i);
            if (row && row.contains(row.mapFromItem(null, scenePos.x, scenePos.y))) {
                return row.groupId;
            }
        }
        if (hiddenRow.visible && hiddenRow.contains(hiddenRow.mapFromItem(null, scenePos.x, scenePos.y))) {
            return pill.ecto.hiddenGroup;
        }
        return "";
    }
    // in the view (Main.qml), above everything in it but a dragged window, which is drawn at 1000 and
    // so stays on top of the list it's being dropped into
    parent: pill.view ? pill.view : (pill.Window.window ? pill.Window.window.contentItem : pill)
    anchors.fill: parent
    visible: opened
    z: 900
    Keys.onEscapePressed: close()
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        enabled: !menu.dragging && !menu.windowDrag
        onPressed: menu.close()
    }
    Rectangle {
        id: panel
        x: menu.panelX
        y: menu.panelY
        width: pill.panelWidth
        height: menuColumn.implicitHeight + 8
        radius: pill.theme.menuRadius
        color: pill.theme.c.bg
        border.width: 1
        border.color: pill.theme.c.border
        // clicks on the panel stay on the panel
        MouseArea {
            anchors.fill: parent
        }
        // a dragged window anywhere on the panel (its rows take it over their own areas)
        DropArea {
            id: panelDrop
            anchors.fill: parent
            keys: ["kwin-window"]
            onEntered: (drag) => drag.accepted = true
        }
        Column {
            id: menuColumn
            x: 4
            y: 4
            Text {
                leftPadding: 10
                topPadding: 8
                bottomPadding: 6
                text: i18nc("@title:menu", "Desktop groups")
                font.family: pill.theme.sans
                font.pixelSize: pill.theme.smallFontSize
                color: pill.theme.c.fgSubtle
            }
            Repeater {
                id: groupRows
                model: pill.ecto.groups
                delegate: GroupRow {
                    required property var modelData
                    required property int index
                    groupId: modelData.id
                    groupIndex: index
                }
            }
            Separator {}
            GroupRow {
                id: hiddenRow
                groupId: pill.ecto.hiddenGroup
                visible: pill.hiddenDesktops.length > 0
            }
            Separator {
                visible: hiddenRow.visible
            }
            // New desktop group: the group, a new desktop in it, you're there, and its name ready to type
            Rectangle {
                width: pill.panelWidth - 8
                height: 34
                radius: pill.theme.menuItemRadius
                color: newHover.hovered || menu.dropTarget === "new" ? pill.theme.c.bgMuted : "transparent"
                border.width: menu.dropTarget === "new" ? pill.theme.ringWidth : 0
                border.color: pill.theme.accent
                Row {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    EctoCross {
                        anchors.verticalCenter: parent.verticalCenter
                        plus: true
                        size: 12
                        color: pill.theme.c.fgMuted
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18nc("@action make a new desktop group", "New desktop group")
                        font.family: pill.theme.sans
                        font.pixelSize: pill.theme.fontSize
                        color: pill.theme.c.fg
                    }
                }
                HoverHandler {
                    id: newHover
                    cursorShape: Qt.PointingHandCursor
                }
                MouseArea {
                    // the hand on the click area itself: one without a cursor of its own shows
                    // whatever's under it (the text field's text cursor), whatever a hover handler says
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    enabled: !menu.dragging
                    onClicked: {
                        if (pill.view) {
                            pill.editingId = pill.view.newGroup();
                        }
                    }
                }
                // a window dropped here gets a new desktop group of its own
                DropArea {
                    anchors.fill: parent
                    keys: ["kwin-window"]
                    onEntered: (drag) => {
                        drag.accepted = true;
                        menu.dropTarget = "new";
                    }
                    onExited: if (menu.dropTarget === "new") menu.dropTarget = ""
                    onDropped: (drop) => {
                        const window = drop.source, view = pill.view;
                        drop.accept(Qt.MoveAction);
                        menu.close();
                        if (view) {
                            view.newGroupForWindow(window);
                        }
                    }
                }
            }
        }
    }

    // the dragged desktop, small, riding under the pointer
    Rectangle {
        visible: menu.dragging && !!menu.ghostDesktop
        x: menu.ghostPos.x + 14
        y: menu.ghostPos.y + 14
        width: 118
        height: Math.round(118 * pill.screen.geometry.height / pill.screen.geometry.width)
        radius: pill.theme.thumbRadius
        color: pill.theme.c.bgMuted
        border.width: pill.theme.ringWidth
        border.color: pill.theme.accent
        clip: true
        layer.enabled: visible
        layer.effect: DropShadow {
            transparentBorder: true
            verticalOffset: 8
            radius: 20
            samples: 41
            color: pill.theme.c.shadow
        }
        DesktopView {
            visible: !!menu.ghostDesktop
            width: pill.screen.geometry.width
            height: pill.screen.geometry.height
            windowModel: pill.windowModel
            desktop: menu.ghostDesktop
            scale: parent.width / pill.screen.geometry.width
            transformOrigin: Item.TopLeft
        }
    }
}

    // a line between parts of the list
    component Separator: Item {
        width: pill.panelWidth - 8
        height: 9
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: pill.theme.c.border
        }
    }

    // a group's row: its first three desktops, its name and count; a check on the shown group;
    // rename and remove on hover; drag up or down to reorder
    component GroupRow: Rectangle {
        id: row
        property string groupId
        property int groupIndex: -1
        readonly property bool isHidden: groupId === pill.ecto.hiddenGroup
        readonly property var desktops: KWinComponents.Workspace.desktops.filter(d => pill.ecto.groupOf(d) === row.groupId)
        readonly property bool editing: pill.editingId === groupId && !isHidden
        readonly property bool target: menu.dropTarget === groupId
        width: pill.panelWidth - 8
        height: 44
        radius: pill.theme.menuItemRadius
        color: (rowHover.hovered && !menu.dragging) || target ? pill.theme.c.bgMuted : "transparent"
        border.width: target ? pill.theme.ringWidth : 0
        border.color: pill.theme.accent
        z: reorder.active ? 5 : 0
        // while another row is dragged past this one, it slides a row's height to make the gap
        readonly property real reorderShift: {
            const from = pill.reorderFrom, to = pill.reorderTo, i = row.groupIndex;
            if (from < 0 || i < 0 || i === from) {
                return 0;
            }
            if (from < to && i > from && i <= to) {
                return -row.height;
            }
            if (from > to && i >= to && i < from) {
                return row.height;
            }
            return 0;
        }
        transform: Translate {
            y: reorder.active ? reorder.activeTranslation.y : row.reorderShift
            Behavior on y {
                enabled: !reorder.active
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        HoverHandler {
            id: rowHover
            cursorShape: Qt.PointingHandCursor
        }
        MouseArea {
            // the hand on the click area itself: one without a cursor of its own shows
            // whatever's under it (the text field's text cursor), whatever a hover handler says
            cursorShape: Qt.PointingHandCursor
            anchors.fill: parent
            enabled: !menu.dragging && !row.editing
            onClicked: {
                const id = row.groupId;
                menu.close();
                if (pill.view) {
                    pill.view.chooseGroup(id);
                }
            }
        }
        // a window dropped on the row goes to the group; held here, the bar shows the group
        DropArea {
            anchors.fill: parent
            keys: ["kwin-window"]
            onEntered: (drag) => {
                drag.accepted = true;
                menu.dropTarget = row.groupId;
                peekTimer.groupId = row.groupId;
                peekTimer.restart();
            }
            onExited: {
                if (menu.dropTarget === row.groupId) {
                    menu.dropTarget = "";
                    peekTimer.stop();
                }
            }
            onDropped: (drop) => {
                const window = drop.source, view = pill.view, id = row.groupId;
                drop.accept(Qt.MoveAction);
                peekTimer.stop();
                menu.close();
                if (view) {
                    view.sendWindowToGroup(window, id);
                }
            }
        }
        DragHandler {
            id: reorder
            target: null
            enabled: !row.isHidden && !row.editing && !menu.dragging && pill.ecto.groups.length > 1
            xAxis.enabled: false
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            // (the place is kept as the row moves: by the time the drag ends, Qt has put its
            // translation back to zero, and the drop moved nothing)
            onActiveTranslationChanged: if (active) {
                pill.reorderTo = Math.max(0, Math.min(pill.ecto.groups.length - 1, row.groupIndex + Math.round(activeTranslation.y / row.height)));
            }
            onActiveChanged: {
                if (active) {
                    pill.reorderFrom = row.groupIndex;
                    pill.reorderTo = row.groupIndex;
                    return;
                }
                const to = pill.reorderTo;
                pill.reorderFrom = -1;
                pill.reorderTo = -1;
                if (to >= 0 && to !== row.groupIndex) {
                    pill.ecto.moveGroup(row.groupId, to);
                }
            }
        }

        // the group's first three desktops, small (an empty slot for each it doesn't have)
        Row {
            id: strip
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater {
                model: 3
                delegate: Rectangle {
                    id: slot
                    required property int index
                    readonly property QtObject desktop: index < row.desktops.length ? row.desktops[index] : null
                    width: 41
                    height: 18
                    radius: 3
                    color: desktop ? pill.theme.c.bgMuted : "transparent"
                    border.width: 1
                    border.color: pill.theme.c.border
                    clip: true
                    DesktopView {
                        visible: !!slot.desktop
                        width: pill.screen.geometry.width
                        height: pill.screen.geometry.height
                        windowModel: pill.windowModel
                        desktop: slot.desktop
                        scale: slot.width / pill.screen.geometry.width
                        transformOrigin: Item.TopLeft
                    }
                }
            }
        }
        Column {
            anchors.left: strip.right
            anchors.leftMargin: 12
            anchors.right: ends.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            Row {
                spacing: 6
                visible: !row.editing
                Kirigami.Icon {
                    visible: row.isHidden
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    source: Qt.resolvedUrl("ectoview-eye-off.svg")
                    isMask: true
                    color: pill.theme.c.fgMuted
                }
                Text {
                    width: Math.min(implicitWidth, 160)
                    elide: Text.ElideRight
                    text: pill.ecto.groupName(row.groupId)
                    textFormat: Text.PlainText
                    font.family: pill.theme.sans
                    font.pixelSize: pill.theme.fontSize
                    color: pill.theme.c.fg
                }
                // a desktop in this group asks for attention
                EctoBeacon {
                    objectName: "beacon-group-" + row.groupId
                    visible: pill.attentionGroups.indexOf(row.groupId) >= 0
                    anchors.verticalCenter: parent.verticalCenter
                    size: 8
                    tone: pill.theme.accent
                    motion: pill.ecto.animationDuration / 300
                }
            }
            Loader {
                active: row.editing
                visible: active
                width: 170
                height: active ? 24 : 0
                sourceComponent: T.TextField {
                    padding: 0
                    leftPadding: 8
                    rightPadding: 8
                    verticalAlignment: Text.AlignVCenter
                    font.family: pill.theme.sans
                    font.pixelSize: pill.theme.fontSize
                    color: pill.theme.c.fg
                    selectionColor: pill.theme.accent
                    selectedTextColor: pill.theme.onAccent
                    text: pill.ecto.groupName(row.groupId)
                    background: Rectangle {
                        radius: 6
                        color: pill.theme.c.bgSubtle
                        border.width: 1
                        border.color: pill.theme.accent
                    }
                    // an empty name keeps the old one (the rename rebuilds the list's rows, this field
                    // with them, so everything it needs is taken first)
                    // (the list takes the keys back, so Esc closes it)
                    onAccepted: {
                        const ecto = pill.ecto, list = menu, id = row.groupId, name = text;
                        pill.editingId = "";
                        list.forceActiveFocus();
                        ecto.renameGroup(id, name);
                    }
                    Keys.onEscapePressed: {
                        const list = menu;
                        pill.editingId = "";
                        list.forceActiveFocus();
                    }
                    Component.onCompleted: {
                        forceActiveFocus();
                        selectAll();
                    }
                }
            }
            Text {
                text: row.desktops.length === 0 ? i18nc("@info a desktop group with no desktops", "Empty")
                    : row.isHidden ? i18ncp("@info", "%1 desktop, not in the bar", "%1 desktops, not in the bar", row.desktops.length)
                    : i18ncp("@info", "%1 desktop", "%1 desktops", row.desktops.length)
                font.family: pill.theme.sans
                font.pixelSize: pill.theme.smallFontSize
                color: pill.theme.c.fgSubtle
            }
        }
        // the shown group's check, or rename and remove while hovered
        Row {
            id: ends
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            readonly property bool actions: rowHover.hovered && !row.isHidden && !row.editing && !menu.dragging && !menu.windowDrag
            Kirigami.Icon {
                visible: !ends.actions && row.groupId === pill.currentGroup
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                source: "checkmark"
                isMask: true
                color: pill.theme.accent
            }
            RowButton {
                visible: ends.actions
                text: i18nc("@info:tooltip", "Rename desktop group")
                iconSource: Qt.resolvedUrl("ectoview-pencil.svg")
                onClicked: pill.editingId = row.groupId
            }
            RowButton {
                visible: ends.actions && pill.ecto.groups.length > 1
                text: i18nc("@info:tooltip", "Remove desktop group (its desktops move to the first one)")
                cross: true
                onClicked: pill.ecto.removeGroup(row.groupId)
            }
        }
    }

    // a round 26 px button in a row, with an icon or an ✕
    component RowButton: PC3.Button {
        property url iconSource
        property bool cross: false
        display: PC3.AbstractButton.IconOnly
        width: 26
        height: 26
        padding: 0
        background: Rectangle {
            radius: width / 2
            color: parent.hovered ? pill.theme.c.bgLift : pill.theme.c.bgSubtle
            border.width: 1
            border.color: pill.theme.c.borderStrong
        }
        contentItem: Item {
            EctoCross {
                visible: parent.parent.cross
                anchors.centerIn: parent
                size: 9
                color: pill.theme.c.fg
            }
            Kirigami.Icon {
                visible: !parent.parent.cross
                anchors.centerIn: parent
                width: 13
                height: 13
                source: parent.parent.iconSource
                isMask: true
                color: pill.theme.c.fg
            }
        }
        PC3.ToolTip.text: text
        PC3.ToolTip.visible: hovered
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
