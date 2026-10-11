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
import VLC.Style

// flix: "Resuming from 12:34 - Start over", shown for a few seconds after a title was resumed
// (MainCtx.resumeNotice holds the position in seconds, 0 when there is nothing to say).
Rectangle {
    id: root

    readonly property int seconds: MainCtx.resumeNotice
    readonly property bool playing: Player.playingState === Player.PLAYING_STATE_PLAYING

    function _clock(total) {
        const h = Math.floor(total / 3600)
        const m = Math.floor(total % 3600 / 60)
        const s = total % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(s).padStart(2, "0")
    }

    // starts counting down once the video really plays
    property bool armed: seconds > 0 && playing

    onArmedChanged: {
        if (armed)
            hideTimer.restart()
    }

    visible: opacity > 0
    opacity: armed ? 1.0 : 0.0

    Behavior on opacity { NumberAnimation { duration: 250 } }

    width: row.implicitWidth + 2 * VLCStyle.dp(22, VLCStyle.scale)
    height: VLCStyle.dp(48, VLCStyle.scale)
    radius: VLCStyle.dp(6, VLCStyle.scale)
    color: Qt.rgba(0.08, 0.08, 0.08, 0.92)
    border.color: "#4D4D4D"

    Timer {
        id: hideTimer

        interval: 7000
        onTriggered: MainCtx.resumeNotice = 0
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: VLCStyle.dp(18, VLCStyle.scale)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Resuming from %1").arg(root._clock(root.seconds))
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
            font.weight: Font.DemiBold
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Start over")
            color: startHover.hovered ? "#FFFFFF" : "#B3B3B3"
            font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
            font.weight: Font.Bold
            font.underline: true

            HoverHandler { id: startHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    Player.position = 0
                    MainCtx.resumeNotice = 0
                }
            }
        }
    }
}
