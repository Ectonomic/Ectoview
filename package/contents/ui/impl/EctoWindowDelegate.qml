/*
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2022 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2024 Marco Martin <mart@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import org.kde.kwin.private.effects
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.ksvg as KSvg

ExpoCell {
    id: thumb

    required property QtObject window
    required property int index
    required property Item windowHeap

    readonly property bool selected: windowHeap.selectedIndex === index
    property bool gestureInProgress: effect.gestureInProgress
    // Where the internal contentItem will be parented to
    property Item contentItemParent: this
    // Ectoview: a group shortcut's change with Ectoview closed fades the desktop you left out under the
    // one rising in; its windows are drawn above every desktop, so they fade with it here (Main.qml)
    property real stepFade: 1

    // no desktops is a special value which means "All Desktops"
    readonly property bool presentOnCurrentDesktop: !window.desktops.length || window.desktops.indexOf(KWinComponents.Workspace.currentDesktop) !== -1
    readonly property bool initialHidden: window.minimized
    readonly property bool activeHidden: {
        if (window.skipSwitcher) {
            return true;
        } else if (windowHeap.showOnly === "activeClass") {
            if (!KWinComponents.Workspace.activeWindow) {
                return true;
            } else {
                return KWinComponents.Workspace.activeWindow.resourceName !== window.resourceName;
            }
        } else {
            return windowHeap.showOnly.length !== 0
                && windowHeap.showOnly.indexOf(window.internalId) === -1;
        }
    }

    // Show a close button on this thumbnail
    property bool closeButtonVisible: true
    // Show a text label under this thumbnail
    property bool windowTitleVisible: true

    // Same as for window heap
    property bool animationEnabled: false

    //scale up and down the whole thumbnail without affecting layouting
    property real targetScale: 1.0

    property DragManager activeDragHandler: dragHandler

    // Swipe down gesture by touch, in some effects will close the window
    readonly property alias downGestureProgress: touchDragHandler.downGestureProgress
    signal downGestureTriggered()

    property bool isReady: width !== 0 && height !== 0

    function restoreDND(oldGlobalRect: rect) {
        thumbSource.restoreDND(oldGlobalRect);
    }

    layout: windowHeap.layout
    shouldLayout: !thumb.activeHidden
    partialActivationFactor: effect.partialActivationFactor
    naturalX: thumb.window.x - thumb.window.output.geometry.x
    naturalY: thumb.window.y - thumb.window.output.geometry.y
    naturalWidth: thumb.window.width
    naturalHeight: thumb.window.height
    persistentKey: thumb.window.internalId
    bottomMargin: (caption.visible ? caption.height + 12 : 0) + Kirigami.Units.largeSpacing

    Behavior on x {
        enabled: thumb.isReady
        NumberAnimation {
            duration: thumb.windowHeap.animationDuration
            easing.type: Easing.InOutCubic
        }
    }
    Behavior on y {
        enabled: thumb.isReady
        NumberAnimation {
            duration: thumb.windowHeap.animationDuration
            easing.type: Easing.InOutCubic
        }
    }
    Behavior on width {
        enabled: thumb.isReady
        NumberAnimation {
            duration: thumb.windowHeap.animationDuration
            easing.type: Easing.InOutCubic
        }
    }
    Behavior on height {
        enabled: thumb.isReady
        NumberAnimation {
            duration: thumb.windowHeap.animationDuration
            easing.type: Easing.InOutCubic
        }
    }

    contentItem: Item {
        id: mainContent
        parent: contentItemParent
        visible: opacity > 0 && (!activeHidden || !initialHidden)
        opacity: (1 - downGestureProgress) * (initialHidden ? partialActivationFactor : 1) * thumb.stepFade
        z: (activeDragHandler.active || returnAnimation.running) ? 1000
            : thumb.window.stackingOrder * (presentOnCurrentDesktop ? 1 : 0.001)

        KWinComponents.WindowThumbnail {
            id: thumbSource
            wId: thumb.window.internalId
            // Ectoview: held, it stays under the pointer while its desktop slides (see slideX): moved
            // back by each step of the slide (the drag handler places it from the pointer on the next
            // move, which already counts the slide, and a drop is found from where it is)
            Connections {
                target: thumb.windowHeap
                // (plain values, set once: a binding here would follow the slide itself, and the
                // first step of each slide went missing, about 520 px)
                property real lastX: 0
                property real lastY: 0
                Component.onCompleted: {
                    lastX = thumb.windowHeap.slideX;
                    lastY = thumb.windowHeap.slideY;
                }
                function onSlideXChanged() {
                    const d = thumb.windowHeap.slideX - lastX;
                    lastX = thumb.windowHeap.slideX;
                    if (thumb.activeDragHandler.active) {
                        thumbSource.x -= d;
                    }
                }
                function onSlideYChanged() {
                    const d = thumb.windowHeap.slideY - lastY;
                    lastY = thumb.windowHeap.slideY;
                    if (thumb.activeDragHandler.active) {
                        thumbSource.y -= d;
                    }
                }
            }
            scale: targetScale
            width: mainContent.width
            height: mainContent.height

            Binding on width {
                value: mainContent.width
                when: !returnAnimation.active
            }
            Binding on height {
                value: mainContent.height
                when: !returnAnimation.active
            }

            Drag.proposedAction: Qt.MoveAction
            Drag.supportedActions: Qt.MoveAction
            Drag.source: thumb.window
            Drag.hotSpot: Qt.point(
                thumb.activeDragHandler.centroid.pressPosition.x,
                thumb.activeDragHandler.centroid.pressPosition.y)
            Drag.keys: ["kwin-window"]

            onXChanged: effect.checkItemDraggedOutOfScreen(thumbSource)
            onYChanged: effect.checkItemDraggedOutOfScreen(thumbSource)

            function saveDND() {
                const oldGlobalRect = mapToItem(null, 0, 0, width, height);
                thumb.windowHeap.saveDND(thumb.window.internalId, oldGlobalRect);
            }
            function restoreDND(oldGlobalRect: rect) {
                const newGlobalRect = mapFromItem(null, oldGlobalRect);
                // We need proper mapping for the heap geometry because they are positioned with
                // translation transformations
                const heapRect = thumb.windowHeap.mapToItem(null, Qt.size(thumb.windowHeap.width, thumb.windowHeap.height));
                // Disable bindings
                returnAnimation.active = true;
                x = newGlobalRect.x;
                y = newGlobalRect.y;
                width = newGlobalRect.width;
                height = newGlobalRect.height;

                returnAnimation.restart();

                // If we dropped on another desktop, don't make the window fly off  the screen
                if ((oldGlobalRect.x < heapRect.x && heapRect.x + heapRect.width < oldGlobalRect.x + oldGlobalRect.width) ||
                    (oldGlobalRect.y < heapRect.y && heapRect.y + heapRect.height < oldGlobalRect.y + oldGlobalRect.height)) {
                    returnAnimation.complete();
                }
            }
            function deleteDND() {
                thumb.windowHeap.deleteDND(thumb.window.internalId);
            }

            // Ectoview: the window under the pointer (or chosen by keys) wears a 2 px ring in the
            // accent, 5 px out (Overview drew a 6 px band in the highlight color)
            Rectangle {
                readonly property QtObject theme: thumb.windowHeap.theme
                border.width: theme.ringWidth
                border.color: theme.accent
                anchors.fill: parent
                anchors.margins: -(theme.ringWidth + 5)
                radius: 8 + 5
                color: "transparent"
                visible: !thumb.windowHeap.dragActive && (hoverHandler.hovered || (thumb.selected && Window.window.activeFocusItem)) && windowHeap.effectiveOrganized
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: thumb.activeDragHandler.active ? Qt.ClosedHandCursor : Qt.ArrowCursor
            }
            ParallelAnimation {
                id: returnAnimation
                property bool active: false
                onRunningChanged: active = running
                NumberAnimation {
                    target: thumbSource
                    properties: "x,y"
                    to: 0
                    duration: thumb.windowHeap.animationDuration
                    easing.type: Easing.InOutCubic
                }
                NumberAnimation {
                    target: thumbSource
                    property: "width"
                    to: mainContent.width
                    duration: thumb.windowHeap.animationDuration
                    easing.type: Easing.InOutCubic
                }
                NumberAnimation {
                    target: thumbSource
                    property: "height"
                    to: mainContent.height
                    duration: thumb.windowHeap.animationDuration
                    easing.type: Easing.InOutCubic
                }
                NumberAnimation {
                    target: thumbSource
                    property: "scale"
                    to: 1
                    duration: thumb.windowHeap.animationDuration
                    easing.type: Easing.InOutCubic
                }
            }
        }

        PC3.Label {
            anchors.fill: thumbSource
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: i18nd("kwin", "Drag Down To Close")
            visible: !thumb.activeHidden && touchDragHandler.active
            background: Rectangle {
                anchors.centerIn: parent
                height: parent.contentHeight + Kirigami.Units.smallSpacing
                width: parent.contentWidth + Kirigami.Units.smallSpacing
                color: Kirigami.Theme.backgroundColor
                radius: Kirigami.Units.cornerRadius
            }
        }

        // Ectoview: one label under the window, the app's icon and title in a 28 px pill
        // (Overview had the icon over the window's bottom edge and the title in a box under it)
        Rectangle {
            id: caption
            readonly property QtObject theme: thumb.windowHeap.theme
            readonly property bool hot: !thumb.windowHeap.dragActive && (hoverHandler.hovered || (thumb.selected && Window.window.activeFocusItem)) && windowHeap.effectiveOrganized
            visible: !thumb.activeHidden && !activeDragHandler.active && !returnAnimation.running
            opacity: partialActivationFactor
            scale: Math.min(1.0, mainContent.width / Math.max(0.01, thumb.width))
            transformOrigin: Item.Top
            anchors.horizontalCenter: thumbSource.horizontalCenter
            anchors.top: thumbSource.bottom
            anchors.topMargin: 12 * scale
            height: theme.buttonSize
            // 8 px before the icon, 8 between, 12 after the title
            width: Math.min(8 + 16 + (titleText.visible ? 8 + titleText.implicitWidth : 0) + 12, thumb.width)
            radius: height / 2
            color: theme.c.scrim
            border.width: 1
            border.color: hot ? theme.accent : theme.c.border
            Row {
                id: captionRow
                anchors.verticalCenter: parent.verticalCenter
                x: 8
                spacing: 8
                Kirigami.Icon {
                    id: icon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    source: thumb.window.icon
                }
                Text {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: thumb.window.caption.length > 0 && thumb.windowTitleVisible
                    width: Math.max(0, Math.min(implicitWidth, caption.width - 8 - 16 - 8 - 12))
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: thumb.windowHeap.showDesktopNames && thumb.window.desktops.length > 0
                        ? i18nc("@label window title · the desktop it's on", "%1 · %2", thumb.window.caption, thumb.window.desktops[0].name)
                        : thumb.window.caption
                    textFormat: Text.PlainText
                    font.family: caption.theme.sans
                    font.pixelSize: caption.theme.fontSize
                    color: caption.theme.c.fg
                }
            }
        }

        HoverHandler {
            id: hoverHandler
            onHoveredChanged: if (hovered !== selected) {
                thumb.windowHeap.resetSelected();
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: {
                thumb.windowHeap.windowTapped = true;
                Qt.callLater(() => thumb.windowHeap.windowTapped = false);
                // Ectoview: a window from another desktop (searching all desktops) takes you to its desktop
                if (thumb.window.desktops.length > 0 && thumb.window.desktops.indexOf(KWinComponents.SceneView.currentDesktop) < 0) {
                    KWinComponents.SceneView.currentDesktop = thumb.window.desktops[0];
                }
                KWinComponents.Workspace.activeWindow = thumb.window;
                thumb.windowHeap.activated();
            }
            onPressedChanged: {
                if (pressed) {
                    thumbSource.Drag.active = true;
                } else if (!thumb.activeDragHandler.active) {
                    thumbSource.Drag.active = false;
                }
            }
        }

        component DragManager : DragHandler {
            target: thumbSource
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            // This does not work when moving pointer fast and pressing along the way
            // See also QTBUG-105903, QTBUG-105904
            // enabled: thumb.state !== "active-normal"

            onActiveChanged: {
                thumb.windowHeap.dragActive = active;
                if (active) {
                    thumb.activeDragHandler = this;
                } else {
                    thumbSource.saveDND();
                    returnAnimation.restart();

                    var action = thumbSource.Drag.drop();
                    if (action === Qt.MoveAction) {
                        // This whole component is in the process of being destroyed due to drop onto
                        // another virtual desktop (not another screen).
                        if (typeof thumbSource !== "undefined") {
                            // Except the case when it was dropped on the same desktop which it's already on, so let's return to normal state anyway.
                            thumbSource.deleteDND();
                        }
                        return;
                    }

                    var globalPos = targetScreen.mapToGlobal(centroid.scenePosition);
                    effect.checkItemDroppedOutOfScreen(globalPos, thumbSource);

                    if (typeof thumbSource !== "undefined") {
                        // else, return to normal without reparenting
                        thumbSource.deleteDND();
                    }
                }
            }
        }

        DragManager {
            id: dragHandler
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        }

        DragManager {
            id: touchDragHandler
            acceptedDevices: PointerDevice.TouchScreen
            readonly property double downGestureProgress: {
                if (!active) {
                    return 0.0;
                }

                const startDistance = thumb.windowHeap.Kirigami.ScenePosition.y + thumb.windowHeap.height - centroid.scenePressPosition.y;
                const localPosition = thumb.windowHeap.Kirigami.ScenePosition.y + thumb.windowHeap.height - centroid.scenePosition.y;
                return 1 - Math.min(localPosition/startDistance, 1);
            }

            onActiveChanged: {
                if (!active) {
                    if (downGestureProgress > 0.6) {
                        thumb.downGestureTriggered();
                    }
                }
            }
        }

        Loader {
            id: closeButton
            LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft

            anchors {
                right: thumbSource.right
                top: thumbSource.top
                rightMargin: -10
                topMargin: -10
            }
            active: thumb.closeButtonVisible && (hoverHandler.hovered || Kirigami.Settings.tabletMode || Kirigami.Settings.hasTransientTouchInput) && thumb.window.closeable && !thumb.activeDragHandler.active && !returnAnimation.running

            // Ectoview: a round 28 px button on the window's corner
            sourceComponent: Rectangle {
                readonly property QtObject theme: thumb.windowHeap.theme
                readonly property string text: i18ndc("kwin", "@info:tooltip as in: 'close this window'", "Close window")
                width: theme.buttonSize
                height: theme.buttonSize
                radius: width / 2
                color: closeHover.hovered ? theme.c.bgMuted : theme.c.bgSubtle
                border.width: 1
                border.color: theme.c.borderStrong
                Accessible.role: Accessible.Button
                Accessible.name: text
                EctoCross {
                    anchors.centerIn: parent
                    size: 10
                    color: parent.theme.c.fg
                }
                HoverHandler {
                    id: closeHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: thumb.window.closeWindow()
                }
                PC3.ToolTip.text: text
                PC3.ToolTip.visible: closeHover.hovered
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        Component.onDestruction: {
            if (selected) {
                windowHeap.resetSelected();
            }
        }
    }
}
