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
import VLC.Player
import VLC.Playlist
import VLC.Style

// flix: shown when the video is paused and the controls have auto-hidden.
// "You're watching" / title / season + episode, "Paused" in the corner.
// Any mouse movement (which brings the controls back) hides it again.
Item {
    id: root

    // true while the player controls are hidden (idle)
    property bool idle: false

    readonly property bool paused: Player.playingState === Player.PLAYING_STATE_PAUSED
    readonly property bool wanted: paused && idle

    property bool armed: false

    readonly property string display: MainCtx.cleanTitle(Player.title)
    readonly property var episode: display.match(/^(.*) - S(\d+)E(\d+)$/)

    visible: opacity > 0
    opacity: armed ? 1.0 : 0.0

    Behavior on opacity {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    onWantedChanged: {
        if (!wanted)
            armed = false
    }

    // wait a moment so a quick pause does not flash the screen
    Timer {
        interval: 1500
        running: root.wanted && !root.armed
        repeat: false
        onTriggered: root.armed = true
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.78)
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: Math.max(VLCStyle.dp(48, VLCStyle.scale), parent.width * 0.06)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.6
        spacing: VLCStyle.dp(10, VLCStyle.scale)

        Text {
            text: qsTr("You're watching")
            color: "#B3B3B3"
            font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
        }

        Text {
            width: parent.width
            text: root.episode ? root.episode[1] : root.display
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(52, VLCStyle.scale)
            font.weight: Font.Bold
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Text {
            visible: root.episode !== null
            text: root.episode ? qsTr("Season %1").arg(Number(root.episode[2])) : ""
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(26, VLCStyle.scale)
            font.weight: Font.Bold
        }

        Text {
            visible: root.episode !== null
            text: root.episode ? qsTr("Episode %1").arg(Number(root.episode[3])) : ""
            color: "#E5E5E5"
            font.pixelSize: VLCStyle.dp(22, VLCStyle.scale)
            font.weight: Font.DemiBold
        }
    }

    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: VLCStyle.dp(64, VLCStyle.scale)
        anchors.bottomMargin: VLCStyle.dp(64, VLCStyle.scale)

        text: qsTr("Paused")
        color: "#FFFFFF"
        font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
        font.weight: Font.DemiBold
    }

    // a click on the screen resumes playback
    TapHandler {
        enabled: root.armed
        onTapped: MainPlaylistController.togglePlayPause()
    }
}
