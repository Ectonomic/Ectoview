/*
 * This file is part of the KDE Milou Project
 * SPDX-FileCopyrightText: 2013-2014 Vishesh Handa <me@vhanda.in>
 * SPDX-FileCopyrightText: 2015-2016 Kai Uwe Broulik <kde@privat.broulik.de>
 *
 * SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL
 *
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.milou as Milou
import org.kde.kwin as KWinComponents
import org.kde.ksvg 1.0 as KSvg

// Ectoview: Milou's result row (plasma-milou 6.7.5, upstream/milou/ResultDelegate.qml) in the
// Ecto look: 32 px rows, Geist 13, a 16 px icon, the kind of result in gray on the left.
PlasmaComponents3.ItemDelegate {
    id: resultDelegate
    readonly property QtObject theme: KWinComponents.SceneView.effect.impl.theme

    implicitHeight: Math.max(32, labelWrapper.implicitHeight + 8)
    leftPadding: 10
    rightPadding: 10
    topPadding: 0
    bottomPadding: 0
    background: Item {}
    down: tapHandler.pressed
    hoverEnabled: true

    readonly property int indexModifier: reversed ? 0 : 1
    property bool reversed: false

    readonly property bool isCurrent: ListView.isCurrentItem // cannot properly Connect {} to this
    readonly property bool sectionHasChanged: (reversed && ListView.section != ListView.nextSection)
                                           || (!reversed && ListView.section != ListView.previousSection)

    property int activeAction: -1

    property string typeText: sectionHasChanged ? ListView.section : ""
    property int categoryWidth: 128

    required property int index
    required property var model
    required property var actions

    property alias displayText: displayLabel.text

    displayText: model.display

    Accessible.role: Accessible.ListItem
    Accessible.name: displayLabel.text
    Accessible.description: {
        var section = ListView.section;
        if (!section) {
            return "";
        }
        var subtext = subtextLabel.text;
        if (subtext.length > 0) {
            return i18nd("milou", "%1, in category %2", subtext, section);
        } else {
            return i18nd("milou", "in category %1", section);
        }
    }

    onIsCurrentChanged: {
        if (!isCurrent) {
            activeAction = -1
        }
    }

    function activateNextAction() {
        if (activeAction === actionsRepeater.count - 1) { // last action, do nothing
            return false
        }
        ++activeAction
        return true
    }

    function activatePreviousAction() {
        if (activeAction < 0) { // no action, do nothing
            return false
        }
        --activeAction
        return true
    }

    function activateLastAction() {
        activeAction = actionsRepeater.count - 1
    }

    onClicked: {
        resultDelegate.ListView.view.currentIndex = index
        resultDelegate.ListView.view.runCurrentIndex()
    }

    onHoveredChanged: {
        if (hovered) {
            resultDelegate.ListView.view.currentIndex = index
        }
    }

    DragHandler {
        id: dragHandler
        parent: labelWrapper
        target: labelLayout
        grabPermissions: PointerHandler.TakeOverForbidden
        onActiveChanged: if (active) {
            typePixmap.grabToImage((result) => {
                const mimeData = resultDelegate.ListView.view.model.getMimeData(resultDelegate.ListView.view.model.index(resultDelegate.index, 0));
                if (!mimeData) {
                    return;
                }
                dragHelper.Drag.imageSource = result.url;
                dragHelper.Drag.mimeData = Milou.MouseHelper.generateMimeDataMap(mimeData);
                dragHelper.Drag.active = dragHandler.active;
            });
        } else {
            dragHelper.Drag.active = false;
        }
    }

    contentItem: Item {
        id: labelWrapper
        implicitHeight: labelLayout.implicitHeight

        // QTBUG-63395: DragHandler blocks ItemDelegate's clicked signal
        TapHandler {
            id: tapHandler
            onTapped: resultDelegate.clicked()
        }

        Rectangle {
            x: -resultDelegate.leftPadding
            width: resultDelegate.width
            height: 1
            anchors.bottom: parent.top
            anchors.bottomMargin: 0
            color: resultDelegate.theme.c.border
            visible: resultDelegate.sectionHasChanged
                     && !resultDelegate.isCurrent
                     && resultDelegate.index !== 0
                     && resultDelegate.ListView.view.currentIndex !== (resultDelegate.index - indexModifier)
            opacity: 0.5
        }

        PlasmaComponents3.Label {
            id: typeText
            anchors {
                left: parent.left
                verticalCenter: labelWrapper.verticalCenter
            }
            width: resultDelegate.categoryWidth - 20
            font.family: resultDelegate.theme.sans
            font.pixelSize: resultDelegate.theme.smallFontSize
            color: resultDelegate.theme.c.fgSubtle
            elide: Text.ElideRight
            text: resultDelegate.typeText
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        RowLayout {
            id: labelLayout
            anchors {
                left: parent.left
                leftMargin: resultDelegate.categoryWidth
                right: actionsRow.visible ? actionsRow.left : parent.right
                rightMargin: actionsRow.visible ? Kirigami.Units.smallSpacing : 0
                verticalCenter: parent.verticalCenter
            }

            Kirigami.Icon {
                id: typePixmap
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                Layout.rightMargin: 4
                Layout.alignment: Qt.AlignVCenter
                source: model.decoration
                animated: false
                selected: resultDelegate.down
            }

            PlasmaComponents3.Label {
                id: displayLabel

                elide: Text.ElideMiddle
                wrapMode: model.multiLine ? Text.WordWrap : Text.NoWrap
                maximumLineCount: model.multiLine ? Infinity : 1
                verticalAlignment: Text.AlignVCenter
                // For multiLine we offer styled text, otherwise we default to plain text
                textFormat: model.multiLine ? Text.StyledText : Text.PlainText
                font.family: resultDelegate.theme.sans
                font.pixelSize: resultDelegate.theme.fontSize
                color: resultDelegate.theme.c.fg
                // The extra spacing accounts for the right margin so the text doesn't overlap the actions
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.maximumWidth: labelLayout.width - typePixmap.implicitWidth

                PlasmaComponents3.ToolTip {
                    text: displayLabel.text
                    visible: displayLabelHoverHandler.hovered && displayLabel.truncated
                    timeout: -1
                }

                HoverHandler {
                    id: displayLabelHoverHandler
                }
            }

            PlasmaComponents3.Label {
                id: subtextLabel
                Layout.fillWidth: true
                // HACK If displayLabel is too long it will shift this label outside boundaries
                // but still render the text leading to it overlapping the action buttons looking horrible
                opacity: width > 0 ? 1 : 0
                font.family: resultDelegate.theme.sans
                font.pixelSize: resultDelegate.theme.fontSize
                color: resultDelegate.theme.c.fgSubtle
                // SourcesModel returns number of duplicates in this property
                // ResultsModel just has it as a boolean as you would expect from the name of the property
                text: model.isDuplicate === true || model.isDuplicate > 1 || resultDelegate.isCurrent ? String(model.subtext || "") : ""

                elide: Text.ElideMiddle
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText

                PlasmaComponents3.ToolTip {
                    text: subtextLabel.text
                    visible: subtextLabelHoverHandler.hovered && subtextLabel.truncated
                    timeout: -1
                }

                HoverHandler {
                    id: subtextLabelHoverHandler
                }
            }
        }

        // Ectoview: the selected answer shows the key that opens it
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: labelWrapper.verticalCenter
            visible: resultDelegate.isCurrent && !actionsRow.visible
            width: enterKey.implicitWidth + 12
            height: 18
            radius: 4
            color: resultDelegate.theme.c.bgLift
            Text {
                id: enterKey
                anchors.centerIn: parent
                text: i18nc("@info the Enter key", "Enter")
                font.family: resultDelegate.theme.sans
                font.pixelSize: 11
                font.weight: Font.Medium
                color: resultDelegate.theme.c.fgMuted
            }
        }

        Row {
            id: actionsRow
            anchors.right: parent.right
            anchors.verticalCenter: labelWrapper.verticalCenter
            visible: resultDelegate.isCurrent && actionsRepeater.count > 0

            Repeater {
                id: actionsRepeater
                model: resultDelegate.actions

                PlasmaComponents3.ToolButton {
                    width: height
                    height: Kirigami.Units.iconSizes.medium
                    visible: modelData.visible || true
                    enabled: modelData.enabled || true

                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.text
                    checkable: checked
                    checked: resultDelegate.activeAction === index
                    focus: resultDelegate.activeAction === index

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                        // ToolButton cannot cope with QIcon
                        source: modelData.iconSource || ""
                        active: parent.hovered || parent.checked
                    }

                    PlasmaComponents3.ToolTip {
                        text: {
                            var text = modelData.text || ""
                            if (index === 0) { // Shift+Return will invoke first action
                                text = i18ndc("milou", "placeholder is action e.g. run in terminal, in parenthesis is shortcut", "%1 (Shift+Return)", text)
                            }
                            return text
                        }
                    }

                    onClicked: resultDelegate.ListView.view.runAction(index)
                }
            }
        }
    }
}
