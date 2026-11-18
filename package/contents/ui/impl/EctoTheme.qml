/*
    SPDX-FileCopyrightText: 2026 Ectoview contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Ectoview's look, as Ectolens has it (Ectolens src/Gui/EctoTheme.qml; design proposal 1,
    design/mock/index.html): Ectonomic's dark tokens, Geist, the accent only where you are.
    Settings: Look (Ecto, or your KDE colors and font), Accent (Ecto green, your KDE accent, or a
    color you pick) and Background (how dark the backdrop gets). One object for the whole effect
    (Effect.qml's `theme`); views read it as KWinComponents.SceneView.effect.impl.theme.
*/

import QtQuick
import org.kde.kirigami as Kirigami

QtObject {
    id: theme

    required property var configuration

    readonly property bool ectoLook: Number(configuration.Look) !== 1
    readonly property color ectoGreen: "#c8f22e"
    // the KDE accent: the color scheme's accent itself (DecorationFocus), as the mock shows it
    readonly property color accent: Number(configuration.Accent) === 1 ? Kirigami.Theme.focusColor
        : Number(configuration.Accent) === 2 ? configuration.CustomAccentColor
        : ectoGreen
    // what reads on top of the accent
    readonly property color onAccent: accent.hslLightness > 0.55 ? "#0a0a0a" : "#ffffff"
    // how dark the backdrop behind the windows gets (0 to 0.9)
    readonly property real dim: Math.max(0, Math.min(0.9, Number(configuration.BackgroundDim) / 100))

    readonly property string sans: ectoLook ? "Geist" : Kirigami.Theme.defaultFont.family

    // Ectonomic's design system, dark (globals.css :root.dark), as Ectolens
    readonly property var ecto: ({
        bg: "#0a0a0a", bgSubtle: "#111113", bgMuted: "#18181b", bgLift: "#2a2a2e",
        border: "#27272a", borderStrong: "#3f3f46",
        fg: "#fafafa", fgMuted: "#a1a1aa", fgSubtle: "#8b8b94",
        scrim: Qt.rgba(10 / 255, 10 / 255, 10 / 255, 0.82), shadow: Qt.rgba(0, 0, 0, 0.6)
    })
    // your KDE colors: the same roles read from the color scheme
    readonly property var kde: {
        const tx = Kirigami.Theme.textColor;
        const bg = Kirigami.Theme.backgroundColor;
        const a = v => Qt.rgba(tx.r, tx.g, tx.b, v);
        return {
            bg: bg, bgSubtle: bg, bgMuted: Kirigami.Theme.alternateBackgroundColor, bgLift: Qt.tint(bg, a(0.1)),
            border: a(0.15), borderStrong: a(0.3),
            fg: tx, fgMuted: a(0.72), fgSubtle: a(0.58),
            scrim: Qt.rgba(bg.r, bg.g, bg.b, 0.88), shadow: Qt.rgba(0, 0, 0, 0.4)
        };
    }
    readonly property var c: ectoLook ? ecto : kde

    // sizes (Ectolens's row rules: 36 px rows, 28 px buttons and labels, 4 px row inset)
    readonly property real rowHeight: 36
    readonly property real buttonSize: 28
    readonly property real rowInset: (rowHeight - buttonSize) / 2
    readonly property real controlPadding: 10
    readonly property real fontSize: 13
    readonly property real smallFontSize: 12
    // desktop previews keep small corners (the owner's ask, 2026-11-12: much smaller); menus keep 12
    readonly property real thumbRadius: 4
    readonly property real viewRadius: 6
    readonly property real gridRadius: 4
    readonly property real menuRadius: 12
    readonly property real menuItemRadius: menuRadius - rowInset
    readonly property real ringWidth: 2

    // Geist travels with Ectoview (SIL Open Font License 1.1, fonts/OFL.txt), so the Ecto look
    // draws the same on a computer without it
    property list<QtObject> fontLoaders: [
        FontLoader { source: Qt.resolvedUrl("../../fonts/Geist-Regular.ttf") },
        FontLoader { source: Qt.resolvedUrl("../../fonts/Geist-Medium.ttf") },
        FontLoader { source: Qt.resolvedUrl("../../fonts/Geist-SemiBold.ttf") }
    ]
}
