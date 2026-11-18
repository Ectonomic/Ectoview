/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Ectoview's entry point, and nothing else. KWin compiles an effect's QML once per file path
    and keeps it until KWin restarts (ScriptedEffectLoader::loadDeclarativeEffect, KWin 6.7.5,
    never clears its engine's component cache), so an update installed over the same files
    wouldn't run before the next login. Everything Ectoview does lives in a folder named for its
    build (install.sh writes the name to Build), loaded from here: a new build is new paths,
    which KWin compiles fresh. This file stays the same from build to build; change it only
    knowing that a change here reaches a running KWin at its next start.
*/

import QtQuick
import org.kde.kwin as KWinComponents

KWinComponents.SceneEffect {
    id: host

    // the loaded build (impl/Effect.qml in the source tree); the views reach it as SceneView.effect.impl
    property QtObject impl: null
    readonly property string build: String(configuration.Build || "impl")

    function load() {
        if (impl && impl.objectName === build) {
            return;
        }
        let component = Qt.createComponent(Qt.resolvedUrl(build + "/Effect.qml"));
        // a build this install doesn't have (Build left in kwinrc by an earlier install from
        // source, under a package that carries its views in impl/): the views it does have.
        // Only for a missing folder; any other error is the build's own, and is reported.
        if (component.status !== Component.Ready && build !== "impl" && /No such file/.test(component.errorString())) {
            console.info("Ectoview: no build " + build + " here; loading impl");
            component = Qt.createComponent(Qt.resolvedUrl("impl/Effect.qml"));
        }
        if (component.status !== Component.Ready) {
            console.warn("Ectoview: couldn't load build " + build + ": " + component.errorString());
            return;
        }
        const old = impl;
        visible = false;
        impl = component.createObject(host, { host: host, objectName: build });
        delegate = impl.delegateComponent;
        if (old) {
            old.destroy();
        }
        console.info("Ectoview: loaded build " + build);
    }

    onBuildChanged: load()
    Component.onCompleted: load()
}
