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

// VLCFlix: "back to Home" that always answers on the first click. The player controls hide
// themselves after a few seconds (and their back arrow with them); this hot corner stays
// clickable, shows the arrow when the mouse is over it and goes back at once.
Item {
    id: root

    // the player's top bar: while it shows its own arrow, ours stays invisible
    property Item topBar: null

    signal clicked()

    readonly property bool _barShowsArrow: topBar !== null && topBar.visible && topBar.opacity > 0.5

    width: VLCStyle.dp(64, VLCStyle.scale)
    height: VLCStyle.dp(64, VLCStyle.scale)

    Rectangle {
        anchors.centerIn: parent
        width: VLCStyle.dp(40, VLCStyle.scale)
        height: width
        radius: width / 2
        color: Qt.rgba(0.08, 0.08, 0.08, 0.7)
        opacity: (hover.hovered && !root._barShowsArrow) ? 1.0 : 0.0
        scale: tap.pressed ? 0.92 : 1.0

        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: VLCIcons.back
            font.family: VLCIcons.fontFamily
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(22, VLCStyle.scale)
        }
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tap

        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.clicked()
    }
}
