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

// flix: one 16:9 poster card of a FlixRow. Scales up on hover / keyboard focus,
// shows the title over a gradient and a red progress bar for partly watched items.
Item {
    id: root

    // Roles of the media library model (title, thumbnail, progress, id, ...)
    required property var model
    required property int index

    // true when this card is the current item of a row that has the keyboard focus
    property bool current: false

    property real cardWidth: VLCStyle.dp(264, VLCStyle.scale)
    readonly property real cardHeight: Math.round(cardWidth * 9 / 16)
    readonly property bool active: hover.hovered || current
    readonly property real progress: Math.max(0, Math.min(1, root.model.progress ?? 0))

    signal activated()

    width: cardWidth
    height: cardHeight

    z: active ? 2 : 0
    scale: active ? 1.12 : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: frame

        anchors.fill: parent
        radius: VLCStyle.dp(3, VLCStyle.scale)
        color: "#2A2A2A"

        Image {
            id: art

            anchors.fill: parent
            source: root.model.thumbnail || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }

        Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: "\u25B6"
            color: "#4D4D4D"
            font.pixelSize: VLCStyle.dp(30, VLCStyle.scale)
        }

        // darkens the lower part so the title is readable on any frame
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.6

            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
            }
        }

        Text {
            id: titleLabel

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: VLCStyle.dp(10, VLCStyle.scale)
            anchors.rightMargin: VLCStyle.dp(10, VLCStyle.scale)
            anchors.bottomMargin: VLCStyle.dp(10, VLCStyle.scale) + (root.progress > 0 ? VLCStyle.dp(4, VLCStyle.scale) : 0)

            text: root.model.title || qsTr("Unknown title")
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        // play badge, only while hovered / focused
        Rectangle {
            anchors.centerIn: parent
            width: VLCStyle.dp(46, VLCStyle.scale)
            height: width
            radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.55)
            border.width: VLCStyle.dp(2, VLCStyle.scale)
            border.color: "#FFFFFF"

            opacity: root.active ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: VLCStyle.dp(2, VLCStyle.scale)
                text: "\u25B6"
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
            }
        }

        // watched progress
        Rectangle {
            visible: root.progress > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: VLCStyle.dp(4, VLCStyle.scale)
            color: "#4D4D4D"

            Rectangle {
                width: parent.width * root.progress
                height: parent.height
                color: "#E50914"
            }
        }

        // keyboard focus ring
        Rectangle {
            anchors.fill: parent
            radius: frame.radius
            color: "transparent"
            border.width: root.current ? VLCStyle.dp(2, VLCStyle.scale) : 0
            border.color: "#FFFFFF"
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.activated()
    }
}
