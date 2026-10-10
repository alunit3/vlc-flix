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

// flix: "Download subtitles for <title>?" shown when the subtitle service (flixsubs.lua)
// found a match for the video that is playing. Answered with Download / Not now; it
// counts as "Not now" after a while.
Item {
    id: root

    // {id, uri, title, language, release, hash_match} of the current offer, or null
    property var offer: null

    readonly property var languageNames: ({
        "en": "English", "id": "Indonesian", "es": "Spanish", "fr": "French",
        "de": "German", "it": "Italian", "pt-br": "Portuguese (Brazil)",
        "pt-pt": "Portuguese", "nl": "Dutch", "ru": "Russian", "ja": "Japanese",
        "ko": "Korean", "zh-cn": "Chinese", "zh-tw": "Chinese (Traditional)",
        "ar": "Arabic", "tr": "Turkish", "pl": "Polish", "sv": "Swedish",
        "th": "Thai", "vi": "Vietnamese", "ms": "Malay", "hi": "Hindi"
    })

    function answer(accept) {
        hideTimer.stop()
        if (offer !== null)
            MainCtx.answerSubtitleOffer(offer.id, accept)
        offer = null
    }

    visible: offer !== null
    width: card.width
    height: card.height

    Connections {
        target: MainCtx

        function onSubtitleOffered(json) {
            try {
                root.offer = JSON.parse(json)
            } catch (e) {
                return
            }
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: 20000
        onTriggered: root.answer(false)
    }

    Rectangle {
        id: card

        width: content.implicitWidth + 2 * VLCStyle.dp(18, VLCStyle.scale)
        height: content.implicitHeight + 2 * VLCStyle.dp(14, VLCStyle.scale)
        radius: VLCStyle.dp(8, VLCStyle.scale)
        color: Qt.rgba(0.08, 0.08, 0.08, 0.94)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Column {
            id: content

            anchors.centerIn: parent
            spacing: VLCStyle.dp(10, VLCStyle.scale)

            Row {
                spacing: VLCStyle.dp(10, VLCStyle.scale)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: ccLabel.implicitWidth + VLCStyle.dp(10, VLCStyle.scale)
                    height: ccLabel.implicitHeight + VLCStyle.dp(4, VLCStyle.scale)
                    radius: VLCStyle.dp(3, VLCStyle.scale)
                    color: "transparent"
                    border.width: VLCStyle.dp(2, VLCStyle.scale)
                    border.color: "#FFFFFF"

                    Text {
                        id: ccLabel

                        anchors.centerIn: parent
                        text: "CC"
                        color: "#FFFFFF"
                        font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                        font.weight: Font.Bold
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.offer ? qsTr("%1 subtitles for %2")
                                       .arg(root.languageNames[root.offer.language] ?? root.offer.language.toUpperCase())
                                       .arg(root.offer.title)
                          : ""
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                    font.weight: Font.DemiBold
                }
            }

            Row {
                spacing: VLCStyle.dp(10, VLCStyle.scale)

                Rectangle {
                    width: downloadLabel.implicitWidth + 2 * VLCStyle.dp(18, VLCStyle.scale)
                    height: VLCStyle.dp(34, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: downloadHover.hovered ? "#BFBFBF" : "#FFFFFF"

                    Text {
                        id: downloadLabel

                        anchors.centerIn: parent
                        text: qsTr("Download")
                        color: "#141414"
                        font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                        font.weight: Font.Bold
                    }

                    HoverHandler { id: downloadHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.answer(true) }
                }

                Rectangle {
                    width: laterLabel.implicitWidth + 2 * VLCStyle.dp(18, VLCStyle.scale)
                    height: VLCStyle.dp(34, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: laterHover.hovered ? Qt.rgba(0.43, 0.43, 0.45, 0.55) : Qt.rgba(0.43, 0.43, 0.45, 0.7)

                    Text {
                        id: laterLabel

                        anchors.centerIn: parent
                        text: qsTr("Not now")
                        color: "#FFFFFF"
                        font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                        font.weight: Font.Bold
                    }

                    HoverHandler { id: laterHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.answer(false) }
                }
            }
        }
    }
}
