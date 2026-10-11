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

// flix: "Top 10 this week": the movies TMDB reports as trending, with big rank numerals.
// A click opens its More Info card (IMDb / Heartive buttons).
Item {
    id: root

    property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)

    property var items: []

    // a click opens More Info (IMDb / Heartive buttons) instead of the browser
    signal infoRequested(var item)

    function reload() {
        items = MainCtx.topTen()
    }

    visible: items.length > 0
    implicitHeight: visible ? header.height + list.height + VLCStyle.dp(24, VLCStyle.scale) : 0

    Component.onCompleted: reload()

    Connections {
        target: MainCtx

        function onMetaUpdated(key) {
            if (key === "top10")
                root.reload()
        }
    }

    Text {
        id: header

        anchors.left: parent.left
        anchors.leftMargin: root.sideMargin
        anchors.top: parent.top
        text: qsTr("Top 10 Movies This Week")
        color: "#E5E5E5"
        font.pixelSize: VLCStyle.dp(22, VLCStyle.scale)
        font.weight: Font.DemiBold
        height: implicitHeight + VLCStyle.dp(10, VLCStyle.scale)
    }

    ListView {
        id: list

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        height: VLCStyle.dp(230, VLCStyle.scale)
        orientation: ListView.Horizontal
        spacing: VLCStyle.dp(8, VLCStyle.scale)
        leftMargin: root.sideMargin
        rightMargin: root.sideMargin
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.items

        delegate: Item {
            id: entry

            required property var modelData

            readonly property real posterWidth: VLCStyle.dp(150, VLCStyle.scale)
            readonly property real rankWidth: VLCStyle.dp(modelData.rank >= 10 ? 150 : 90, VLCStyle.scale)

            width: rankWidth + posterWidth
            height: list.height

            // outlined numeral, partly behind the poster as on the streaming services
            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: VLCStyle.dp(-6, VLCStyle.scale)
                text: String(entry.modelData.rank)
                font.pixelSize: VLCStyle.dp(190, VLCStyle.scale)
                font.weight: Font.Black
                font.letterSpacing: VLCStyle.dp(-14, VLCStyle.scale)
                color: "#141414"
                style: Text.Outline
                styleColor: "#6B6B6B"
            }

            Rectangle {
                id: posterFrame

                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: VLCStyle.dp(6, VLCStyle.scale)
                width: entry.posterWidth - VLCStyle.dp(12, VLCStyle.scale)
                radius: VLCStyle.dp(6, VLCStyle.scale)
                color: "#2A2A2A"
                scale: tap.hovered ? 1.05 : 1.0

                Behavior on scale { NumberAnimation { duration: 120 } }

                Image {
                    anchors.fill: parent
                    source: entry.modelData.poster
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 400
                }

                HoverHandler { id: tap; cursorShape: Qt.PointingHandCursor }

                TapHandler {
                    onTapped: root.infoRequested(entry.modelData)
                }
            }

        }
    }
}
