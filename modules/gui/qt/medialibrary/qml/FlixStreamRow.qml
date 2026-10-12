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

// flix: "Continue Streaming" (torrent streams and web players) and "Continue Watching" (files on
// this computer) that were stopped part way; the positions are kept by MainCtx, see resumeList().
Item {
    id: root

    property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)

    // card clicked: continue a torrent / open the title of a web player
    signal resumeTorrent(var entry)
    signal resumeWeb(var entry)
    signal resumeLocal(var entry)
    // the user confirmed "Clear" (the page also clears the library's own history)
    signal clearRequested()

    // which entries this row shows, and what it is called
    property var kinds: ["local", "torrent", "web"]
    property string title: qsTr("Continue Watching")
    property bool confirmClear: false

    property int tick: 0
    readonly property var entries: {
        tick
        return MainCtx.resumeList().filter(e => root.kinds.indexOf(e.kind) >= 0)
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
        text: root.title
        color: "#E5E5E5"
        font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
        font.weight: Font.DemiBold
        height: implicitHeight + VLCStyle.dp(12, VLCStyle.scale)
        verticalAlignment: Text.AlignTop
    }

    // "Clear" with an inline question: nothing is forgotten without a second click
    Row {
        anchors.right: parent.right
        anchors.rightMargin: root.sideMargin
        anchors.verticalCenter: header.verticalCenter
        anchors.verticalCenterOffset: -VLCStyle.dp(6, VLCStyle.scale)
        spacing: VLCStyle.dp(14, VLCStyle.scale)

        Text {
            visible: root.confirmClear
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Clear Continue Watching?")
            color: "#B3B3B3"
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
        }

        Text {
            visible: root.confirmClear
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Yes, clear")
            color: yesHover.hovered ? "#FFFFFF" : "#E5E5E5"
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
            font.weight: Font.Bold
            font.underline: true

            HoverHandler { id: yesHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    root.confirmClear = false
                    root.clearRequested()
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.confirmClear ? qsTr("Cancel") : qsTr("Clear")
            color: clearHover.hovered ? "#FFFFFF" : "#B3B3B3"
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)

            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.confirmClear = !root.confirmClear }
        }
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

            // a stream started from a magnet link saved no poster of its own: show TMDB's,
            // looked up by title the way the billboard above already does
            FlixMeta {
                id: cardMeta

                name: (card.modelData.poster ?? "") ? "" : (card.modelData.title ?? "")
            }
            readonly property string posterUrl: (card.modelData.poster ?? "") || cardMeta.poster

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
                    source: card.posterUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 300
                }

                Text {
                    visible: card.posterUrl === ""
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
                    visible: card.modelData.kind !== "local"
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
                        text: VLCIcons.close
                        font.family: VLCIcons.fontFamily
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
                    else if (card.modelData.kind === "local")
                        root.resumeLocal(card.modelData)
                    else
                        root.resumeWeb(card.modelData)
                }
            }
        }
    }
}
