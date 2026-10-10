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

// flix: shown when the video has been paused for a few seconds without any mouse
// activity: "You're watching" / title / season + episode, "Paused" in the corner.
// Player.qml calls activity() on every mouse event, which hides the screen again.
Item {
    id: root

    readonly property bool paused: Player.playingState === Player.PLAYING_STATE_PAUSED

    property bool armed: false

    // call on any mouse / key activity
    function activity() {
        armed = false
        if (paused)
            idleTimer.restart()
    }

    readonly property string display: MainCtx.cleanTitle(Player.title)
    readonly property var episode: display.match(/^(.*) - S(\d+)E(\d+)$/)

    visible: opacity > 0
    opacity: armed ? 1.0 : 0.0

    Behavior on opacity {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    onPausedChanged: {
        armed = false
        if (paused)
            idleTimer.restart()
        else
            idleTimer.stop()
    }

    // wait a few seconds so pausing for a moment does not flash the screen
    Timer {
        id: idleTimer
        interval: 4000
        repeat: false
        onTriggered: root.armed = root.paused
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
        anchors.bottomMargin: VLCStyle.dp(150, VLCStyle.scale)

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
