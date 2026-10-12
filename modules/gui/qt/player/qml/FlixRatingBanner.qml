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

// flix: "| RATING 16+" in the top left corner for a few seconds when a title starts.
// Only shown when TMDB knows the age rating (nothing is made up), once per title and play,
// and only near the start of the title (a rating that arrives late is still shown while the
// first seconds are on screen).
Item {
    id: root

    // what is playing (FlixNowPlaying.qml), set by Player.qml
    property var np: null

    readonly property bool playing: Player.playingState === Player.PLAYING_STATE_PLAYING
    readonly property string rating: np ? np.ageText : ""
    readonly property string titleKey: np ? np.key : ""

    property string shownFor: ""
    property bool shown: false
    // when this title started to play (ms since epoch)
    property double startedAt: 0

    onTitleKeyChanged: {
        shown = false
        shownFor = ""
        startedAt = 0
    }

    function evaluate() {
        if (!playing || titleKey === "" || titleKey === "f:" || titleKey === "s:") {
            return
        }
        if (startedAt === 0)
            startedAt = Date.now()
        if (rating !== "" && shownFor !== titleKey && Date.now() - startedAt < 20000) {
            shownFor = titleKey
            shown = true
            hideTimer.restart()
        }
    }

    onPlayingChanged: evaluate()
    onRatingChanged: evaluate()
    Component.onCompleted: evaluate()

    Timer {
        id: hideTimer

        interval: 5000
        onTriggered: root.shown = false
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    visible: opacity > 0
    opacity: shown ? 1.0 : 0.0

    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

    Row {
        id: row

        spacing: VLCStyle.dp(14, VLCStyle.scale)

        Rectangle {
            width: VLCStyle.dp(4, VLCStyle.scale)
            height: label.implicitHeight * 1.15
            anchors.verticalCenter: parent.verticalCenter
            color: "#D81F26"
        }

        Text {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("RATING %1").arg(root.rating)
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(30, VLCStyle.scale)
            font.weight: Font.Black
            font.letterSpacing: 0.5
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.55)
        }
    }
}
