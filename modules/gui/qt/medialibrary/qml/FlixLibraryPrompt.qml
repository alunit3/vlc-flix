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

import VLC.Style

// flix: tells the user where their movies come from. Big card while the library is empty
// (nothing is scanned until a folder is added), a small link otherwise.
Item {
    id: root

    property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)
    property bool empty: true

    signal addFolder()

    implicitHeight: empty ? card.height + VLCStyle.dp(24, VLCStyle.scale)
                          : link.implicitHeight + VLCStyle.dp(24, VLCStyle.scale)
    height: implicitHeight

    Rectangle {
        id: card

        visible: root.empty
        x: root.sideMargin
        width: parent.width - 2 * root.sideMargin
        height: VLCStyle.dp(150, VLCStyle.scale)
        radius: VLCStyle.dp(8, VLCStyle.scale)
        color: "#1F1F1F"
        border.color: "#333333"

        Column {
            anchors.centerIn: parent
            spacing: VLCStyle.dp(10, VLCStyle.scale)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Your movie library is empty")
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(22, VLCStyle.scale)
                font.weight: Font.Bold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Add the folder that holds your movies and series. Nothing is scanned until you do.")
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: addLabel.implicitWidth + 2 * VLCStyle.dp(26, VLCStyle.scale)
                height: VLCStyle.dp(40, VLCStyle.scale)
                radius: VLCStyle.dp(4, VLCStyle.scale)
                color: addHover.hovered ? "#BFBFBF" : "#FFFFFF"

                Text {
                    id: addLabel

                    anchors.centerIn: parent
                    text: "+  " + qsTr("Add movie folder")
                    color: "#141414"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    font.weight: Font.Bold
                }

                HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.addFolder() }
            }
        }
    }

    Text {
        id: link

        visible: !root.empty
        x: root.sideMargin
        text: qsTr("Manage library folders") + "  ›"
        color: linkHover.hovered ? "#FFFFFF" : "#808080"
        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)

        HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.addFolder() }
    }
}
