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
import VLC.Widgets as Widgets
import VLC.Style

// flix: one 16:9 card of a FlixRow with rounded corners. Scales up on hover / keyboard
// focus, shows the (cleaned) title over a gradient, a "NEW" tag for items that were
// never played, and, in "continue watching" rows, a progress bar under the card.
Item {
    id: root

    // Roles of the media library model (title, thumbnail, progress, id, ...)
    required property var model
    required property int index

    // true when this card is the current item of a row that has the keyboard focus
    property bool current: false

    // reserve room under the picture for the progress bar (continue watching rows)
    property bool progressBelow: false

    // allow the "NEW" tag (set by the row, for its first few cards only)
    property bool showNew: false

    property real cardWidth: VLCStyle.dp(264, VLCStyle.scale)
    readonly property real pictureHeight: Math.round(cardWidth * 9 / 16)
    readonly property real barSpace: progressBelow ? VLCStyle.dp(16, VLCStyle.scale) : 0
    readonly property bool active: hover.hovered || current
    readonly property real progress: Math.max(0, Math.min(1, root.model.progress ?? 0))
    readonly property real radius: VLCStyle.dp(6, VLCStyle.scale)

    signal activated()

    // TMDB artwork when the title is known (fetched in the background), else a video frame
    FlixMeta {
        id: tmdb

        name: root.model.title ?? ""
    }

    width: cardWidth
    height: pictureHeight + barSpace

    z: active ? 2 : 0
    scale: active ? 1.12 : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // appears with a short fade + rise, the first cards one after the other
    opacity: 0
    transform: Translate { id: rise; y: VLCStyle.dp(14, VLCStyle.scale) }

    ParallelAnimation {
        id: appear

        PauseAnimation { duration: Math.max(0, Math.min(root.index, 10)) * 40 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
            NumberAnimation { target: rise; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
        }
    }

    Component.onCompleted: appear.start()

    Item {
        id: picture

        width: parent.width
        height: root.pictureHeight

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "#2A2A2A"
        }

        Widgets.ImageExt {
            id: art

            anchors.fill: parent
            source: tmdb.backdrop !== "" ? tmdb.backdrop : (root.model.thumbnail || "")
            fillMode: Image.PreserveAspectCrop
            radius: root.radius
            backgroundColor: "transparent"
            opacity: status === Image.Ready ? 1.0 : 0.0

            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }

        Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: "▶"
            color: "#4D4D4D"
            font.pixelSize: VLCStyle.dp(30, VLCStyle.scale)
        }

        // darkens the lower part so the title is readable on any frame
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.6
            radius: root.radius

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
            anchors.margins: VLCStyle.dp(10, VLCStyle.scale)

            text: MainCtx.cleanTitle(root.model.title) || qsTr("Unknown title")
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        // "NEW": never played
        Rectangle {
            visible: root.showNew && root.model.isNew === true
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: VLCStyle.dp(8, VLCStyle.scale)
            width: newLabel.implicitWidth + 2 * VLCStyle.dp(7, VLCStyle.scale)
            height: newLabel.implicitHeight + VLCStyle.dp(4, VLCStyle.scale)
            radius: VLCStyle.dp(3, VLCStyle.scale)
            color: "#E50914"

            Text {
                id: newLabel

                anchors.centerIn: parent
                text: qsTr("NEW")
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                font.weight: Font.Bold
                font.letterSpacing: VLCStyle.dp(0.5, VLCStyle.scale)
            }
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
                text: "▶"
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
            }
        }

        // keyboard focus ring
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "transparent"
            border.width: root.current ? VLCStyle.dp(2, VLCStyle.scale) : 0
            border.color: "#FFFFFF"
        }
    }

    // watched progress, under the picture
    Item {
        visible: root.progressBelow && root.progress > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: VLCStyle.dp(4, VLCStyle.scale)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "#4D4D4D"
        }

        Rectangle {
            width: parent.width * root.progress
            height: parent.height
            radius: height / 2
            color: "#E50914"
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
