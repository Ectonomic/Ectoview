/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    ^ and v: to the previous and next desktop group (design proposal 4's arrows). With the toolbar
    showing they sit beside it, ^ left of the groups' pill and v right of the settings gear; with
    the toolbar hidden they sit at the desktop bar's ends. A click goes to that group; a window
    held on one steps after a pause; a window dropped on one goes to that group, and you with it.
*/

import QtQuick

EctoStepArrow {
    id: groupArrow

    // the desktop bar, which knows the groups to step through (DesktopBar.neighborGroup)
    required property Item desktopBar
    required property int direction
    readonly property var target: desktopBar && desktopBar.neighborGroup ? desktopBar.neighborGroup(direction) : null

    theme: desktopBar.theme
    angle: direction < 0 ? -90 : 90
    label: target ? target.name : ""
    visible: !!desktopBar && !!desktopBar.groupArrowsShown && !!target
    // a window dropped here goes to that group (and you with it, as a drop on its row does)
    accepts: (window) => !!groupArrow.target
    onActivated: if (groupArrow.target && desktopBar.view) desktopBar.view.chooseGroup(groupArrow.target.id)
    onWindowDropped: (window) => {
        if (desktopBar.view) {
            desktopBar.view.sendWindowToGroup(window, groupArrow.target.id);
        }
    }
}
