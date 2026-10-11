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

import VLC.MainInterface
import VLC.Style

// flix: "Continue Streaming": torrent streams and web players that were stopped part way
// (the positions are kept by MainCtx, see resumeList()).
Item {
    id: root

    property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)

    // card clicked: continue a torrent / open the title of a web player
    signal resumeTorrent(var entry)
    signal resumeWeb(var entry)

    property int tick: 0
    readonly property var entries: {
        tick
        return MainCtx.resumeList()
    }

    Connections {
        target: MainCtx

        function onResumeChanged() { root.tick++ }
    }

    visible: entries.length > 0
    implicitHeight: visible ? header.height + list.height + VLCStyle.dp(10, VLCStyle.scale) : 0
    height: implicitHeight

    Text {
        id: header

        x: root.sideMargin
        text: qsTr("Continue Streaming")
        color: "#E5E5E5"
        font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
        font.weight: Font.DemiBold
        height: implicitHeight + VLCStyle.dp(12, VLCStyle.scale)
        verticalAlignment: Text.AlignTop
    }

    ListView {
        id: list

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: VLCStyle.dp(268, VLCStyle.scale)
        orientation: ListView.Horizontal
        leftMargin: root.sideMargin
        rightMargin: root.sideMargin
        spacing: VLCStyle.dp(12, VLCStyle.scale)
        clip: false
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
        model: root.entries

        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 } }

        delegate: Item {
            id: card

            required property var modelData

            width: VLCStyle.dp(150, VLCStyle.scale)
            height: list.height

            Rectangle {
                id: poster

                width: parent.width
                height: VLCStyle.dp(225, VLCStyle.scale)
                radius: VLCStyle.dp(4, VLCStyle.scale)
                color: "#2A2A2A"
                clip: true
                scale: cardHover.hovered ? 1.05 : 1.0

                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Image {
                    anchors.fill: parent
                    source: card.modelData.poster ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 300
                }

                Text {
                    visible: !(card.modelData.poster ?? "")
                    anchors.fill: parent
                    anchors.margins: VLCStyle.dp(10, VLCStyle.scale)
                    text: card.modelData.title ?? ""
                    color: "#E5E5E5"
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                }

                // kind badge
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: VLCStyle.dp(6, VLCStyle.scale)
                    width: badge.implicitWidth + VLCStyle.dp(12, VLCStyle.scale)
                    height: VLCStyle.dp(20, VLCStyle.scale)
                    radius: VLCStyle.dp(3, VLCStyle.scale)
                    color: Qt.rgba(0, 0, 0, 0.7)

                    Text {
                        id: badge

                        anchors.centerIn: parent
                        text: card.modelData.kind === "torrent" ? "TORRENT" : "WEB"
                        color: "#FFFFFF"
                        font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                        font.weight: Font.Bold
                    }
                }

                // progress
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: VLCStyle.dp(4, VLCStyle.scale)
                    color: "#4D4D4D"

                    Rectangle {
                        width: parent.width * Math.min(1, card.modelData.fraction ?? 0)
                        height: parent.height
                        color: "#E50914"
                    }
                }

                // remove from the list
                Rectangle {
                    visible: cardHover.hovered
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: VLCStyle.dp(6, VLCStyle.scale)
                    width: VLCStyle.dp(22, VLCStyle.scale)
                    height: width
                    radius: width / 2
                    color: removeHover.hovered ? "#E50914" : Qt.rgba(0, 0, 0, 0.75)

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: "#FFFFFF"
                        font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                    }

                    HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: MainCtx.removeResume(card.modelData.key)
                    }
                }
            }

            Text {
                anchors.top: poster.bottom
                anchors.topMargin: VLCStyle.dp(6, VLCStyle.scale)
                width: parent.width
                text: (card.modelData.title ?? "")
                      + (card.modelData.mediaType === "tv" && card.modelData.season > 0
                         ? "  S" + card.modelData.season + "E" + card.modelData.episode : "")
                color: "#E5E5E5"
                elide: Text.ElideRight
                font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
            }

            HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    if (removeHover.hovered)
                        return
                    if (card.modelData.kind === "torrent")
                        root.resumeTorrent(card.modelData)
                    else
                        root.resumeWeb(card.modelData)
                }
            }
        }
    }
}
