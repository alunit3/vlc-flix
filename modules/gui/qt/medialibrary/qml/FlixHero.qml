/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
import QtQuick

import VLC.MediaLibrary
import VLC.MainInterface
import VLC.Style

// flix: full-width billboard showing the first item of `model`
// (partly watched item if any, otherwise the newest one).
Item {
    id: root

    property var model
    property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)

    implicitHeight: VLCStyle.dp(440, VLCStyle.scale)
    visible: view.count > 0

    ListView {
        id: view

        anchors.fill: parent
        model: root.model
        orientation: ListView.Horizontal
        interactive: false
        clip: true
        highlightRangeMode: ListView.StrictlyEnforceRange
        snapMode: ListView.SnapOneItem
        currentIndex: 0

        delegate: Item {
            id: slide

            required property var model
            required property int index

            readonly property bool resuming: (model.progress ?? 0) > 0

            width: view.width
            height: view.height

            Rectangle {
                anchors.fill: parent
                color: "#141414"
            }

            Image {
                id: art

                anchors.fill: parent
                source: slide.model.thumbnail || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            // left scrim: keeps the text readable
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(0.08, 0.08, 0.08, 0.95) }
                    GradientStop { position: 0.55; color: Qt.rgba(0.08, 0.08, 0.08, 0.35) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // bottom fade into the page background
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * 0.4
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#141414" }
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: root.sideMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: VLCStyle.dp(72, VLCStyle.scale)
                width: Math.min(parent.width * 0.5, VLCStyle.dp(620, VLCStyle.scale))
                spacing: VLCStyle.dp(14, VLCStyle.scale)

                Row {
                    spacing: VLCStyle.dp(8, VLCStyle.scale)

                    Rectangle {
                        width: VLCStyle.dp(4, VLCStyle.scale)
                        height: tag.implicitHeight
                        color: "#E50914"
                    }

                    Text {
                        id: tag

                        text: slide.resuming ? qsTr("CONTINUE WATCHING") : qsTr("NEW IN YOUR LIBRARY")
                        color: "#E5E5E5"
                        font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                        font.weight: Font.DemiBold
                        font.letterSpacing: VLCStyle.dp(2, VLCStyle.scale)
                    }
                }

                Text {
                    width: parent.width
                    text: slide.model.title || qsTr("Unknown title")
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(44, VLCStyle.scale)
                    font.weight: Font.Bold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    visible: text !== ""
                    text: slide.model.duration?.formatHMS() ?? ""
                    color: "#B3B3B3"
                    font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                }

                Rectangle {
                    id: playButton

                    width: playRow.implicitWidth + 2 * VLCStyle.dp(26, VLCStyle.scale)
                    height: VLCStyle.dp(44, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: playHover.hovered ? "#BFBFBF" : "#FFFFFF"

                    Row {
                        id: playRow

                        anchors.centerIn: parent
                        spacing: VLCStyle.dp(10, VLCStyle.scale)

                        Text {
                            text: "\u25B6"
                            color: "#141414"
                            font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: slide.resuming ? qsTr("Resume") : qsTr("Play")
                            color: "#141414"
                            font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }

                    TapHandler {
                        onTapped: {
                            if (slide.model.id !== undefined) {
                                MediaLib.addAndPlay(slide.model.id)
                                MainCtx.playerView = true
                            }
                        }
                    }
                }
            }
        }
    }
}
