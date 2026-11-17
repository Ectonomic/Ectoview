/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    KWin's EffectTogglableState (src/effect/effecttogglablestate.cpp, KWin 6.7.5) in QML, so a
    QML effect has Overview's states: a shortcut toggles one at once, a swipe moves it part way
    and lets it settle on release.
*/

import QtQuick

QtObject {
    id: state

    enum Status {
        Inactive,
        Activating,
        Deactivating,
        Active,
        Stopped
    }

    property int status: Togglable.Status.Inactive
    property real partialActivationFactor: 0
    property bool inProgress: false

    // Each sets the factor before the status, as KWin does, so whatever reacts to the
    // status sees the final factor.
    function activate() {
        inProgress = false;
        partialActivationFactor = 1;
        status = Togglable.Status.Active;
    }

    function deactivate() {
        inProgress = false;
        partialActivationFactor = 0;
        status = Togglable.Status.Inactive;
    }

    function stop() {
        inProgress = false;
        partialActivationFactor = 0;
        status = Togglable.Status.Stopped;
    }

    function toggle() {
        if (status !== Togglable.Status.Active) {
            activate();
        } else {
            deactivate();
        }
    }

    // A swipe toward the state (progress 0 to 1)
    function setProgress(progress) {
        if (status === Togglable.Status.Inactive || status === Togglable.Status.Activating) {
            partialActivationFactor = progress;
            inProgress = true;
            status = Togglable.Status.Activating;
        }
    }

    // A swipe away from it
    function setRegress(progress) {
        if (status === Togglable.Status.Active || status === Togglable.Status.Deactivating) {
            partialActivationFactor = 1 - progress;
            inProgress = true;
            status = Togglable.Status.Deactivating;
        }
    }

    // The swipe toward it ended (finished or not): settle on the nearer end
    function finishActivating() {
        if (status === Togglable.Status.Activating) {
            if (partialActivationFactor > 0.5) {
                activate();
            } else {
                deactivate();
            }
        }
    }

    // The swipe away from it ended
    function finishDeactivating() {
        if (status === Togglable.Status.Deactivating) {
            if (partialActivationFactor < 0.5) {
                deactivate();
            } else {
                activate();
            }
        }
    }
}
