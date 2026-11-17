/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A screen Ectoview leaves alone ("Only the primary screen"): the screen drawn as it is, live,
    while Ectoview is open on the primary one. KWin draws an effect's view over every screen,
    so this view shows what the screen would show: its desktop background, then every window on
    it in stacking order at its real place, as KWin's own window thumbnails (the way Overview
    keeps panels in place). A click here does nothing.
*/

import QtQuick
import org.kde.kwin as KWinComponents

FocusScope {
    id: root

    readonly property QtObject effect: KWinComponents.SceneView.effect.impl
    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property QtObject currentDesktop: KWinComponents.SceneView.currentDesktop
    readonly property real dpr: targetScreen.devicePixelRatio
    function snap(v) {
        return Math.round(v * dpr) / dpr;
    }

    KWinComponents.DesktopBackground {
        anchors.fill: parent
        activity: KWinComponents.Workspace.currentActivity
        desktop: root.currentDesktop
        outputName: root.targetScreen.name
    }

    Repeater {
        model: KWinComponents.WindowFilterModel {
            activity: KWinComponents.Workspace.currentActivity
            desktop: root.currentDesktop
            screenName: root.targetScreen.name
            windowModel: KWinComponents.WindowModel {}
            minimizedWindows: false
            windowType: ~KWinComponents.WindowFilterModel.Desktop
        }

        KWinComponents.WindowThumbnail {
            wId: model.window.internalId
            visible: !model.window.hidden
            // on whole device pixels, where KWin draws the window itself; a thumbnail between
            // pixels comes out resampled (soft text) on a scaled screen
            x: root.snap(model.window.x - root.targetScreen.geometry.x)
            y: root.snap(model.window.y - root.targetScreen.geometry.y)
            z: model.window.stackingOrder
            width: root.snap(model.window.x + model.window.width - root.targetScreen.geometry.x) - x
            height: root.snap(model.window.y + model.window.height - root.targetScreen.geometry.y) - y
        }
    }

    // Keys belong to the screen Ectoview is open on: hand them back if this screen gets them
    function giveKeysBack() {
        const primary = effect.primaryScreen ? effect.viewForScreen(effect.primaryScreen) : null;
        if (primary && effect.activeView !== primary) {
            effect.activateView(primary);
        }
    }
    onActiveFocusChanged: if (activeFocus) Qt.callLater(giveKeysBack)
    Component.onCompleted: Qt.callLater(giveKeysBack)

    // a click here does nothing: it doesn't reach the windows under it, and it doesn't close
    // Ectoview either (only a deliberate click on the desktop on the primary screen does)
    MouseArea {
        anchors.fill: parent
        z: 1000000
        acceptedButtons: Qt.AllButtons
    }
}
