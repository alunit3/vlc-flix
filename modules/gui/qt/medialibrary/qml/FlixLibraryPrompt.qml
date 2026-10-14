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

// flix: tells the user where their movies come from. While the library is empty: a setup
// card with the three things that make VLCFlix useful (a folder, TMDB, OpenSubtitles),
// each ticked off once done. Otherwise a row of small links.
Item {
    id: root

    property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)
    property bool empty: true

    signal addFolder()
    signal streamMagnet()

    // TMDB and OpenSubtitles state; the settings and the welcome flow save after a
    // successful test, so read it again a moment after each result
    property bool tmdbDone: false
    property bool subsDone: false

    function refresh() {
        tmdbDone = MainCtx.metaEnabled()
        subsDone = MainCtx.hasVlcOption("flixsubs-api-key") && MainCtx.hasVlcOption("flixsubs-password")
    }

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()

    Connections {
        target: MainCtx

        function onAccountTestResult() { refreshTimer.restart() }
    }

    Timer {
        id: refreshTimer

        interval: 300
        onTriggered: root.refresh()
    }

    // the empty card is usually the first thing on the page, right under the top bar
    readonly property real cardTop: VLCStyle.dp(64, VLCStyle.scale)

    implicitHeight: empty ? cardTop + card.height + VLCStyle.dp(24, VLCStyle.scale)
                          : links.implicitHeight + VLCStyle.dp(24, VLCStyle.scale)
    height: implicitHeight

    // one of the three setup steps
    component Tile: Rectangle {
        id: tile

        property string number
        property string title
        property string text
        property string action
        property bool done: false
        property bool main: false

        signal activated()

        height: VLCStyle.dp(176, VLCStyle.scale)
        radius: VLCStyle.dp(8, VLCStyle.scale)
        color: tileHover.hovered ? "#262626" : "#1C1C1C"
        border.color: tile.main && !tile.done ? "#E50914" : "#2E2E2E"
        border.width: tile.main && !tile.done ? 2 : 1
        scale: tileTap.pressed ? 0.98 : 1.0

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Rectangle {
            id: badge

            x: VLCStyle.dp(18, VLCStyle.scale)
            y: VLCStyle.dp(18, VLCStyle.scale)
            width: VLCStyle.dp(30, VLCStyle.scale)
            height: width
            radius: width / 2
            color: tile.done ? "#1F7A4D" : (tile.main ? "#E50914" : "#333333")

            Text {
                anchors.centerIn: parent
                text: tile.done ? "✓" : tile.number
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                font.weight: Font.Bold
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: badge.bottom
            anchors.margins: VLCStyle.dp(18, VLCStyle.scale)
            anchors.topMargin: VLCStyle.dp(12, VLCStyle.scale)
            spacing: VLCStyle.dp(6, VLCStyle.scale)

            Text {
                width: parent.width
                text: tile.title
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: tile.text
                color: "#999999"
                font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: VLCStyle.dp(18, VLCStyle.scale)
            text: (tile.done ? qsTr("Done") : tile.action) + "  ›"
            color: tile.done ? "#34D399" : (tileHover.hovered || tile.main ? "#FFFFFF" : "#B3B3B3")
            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            font.weight: Font.DemiBold
        }

        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tileTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: tile.activated() }
    }

    component Link: Text {
        id: linkText

        signal activated()

        color: linkHover.hovered ? "#FFFFFF" : "#808080"
        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
        // a bigger target than the 13dp text itself
        topPadding: VLCStyle.dp(8, VLCStyle.scale)
        bottomPadding: VLCStyle.dp(8, VLCStyle.scale)

        HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: linkText.activated() }
    }

    Rectangle {
        id: card

        visible: root.empty
        x: root.sideMargin
        y: root.cardTop
        width: parent.width - 2 * root.sideMargin
        height: cardCol.implicitHeight + 2 * VLCStyle.dp(32, VLCStyle.scale)
        radius: VLCStyle.dp(10, VLCStyle.scale)
        border.color: "#2A2A2A"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#2A0A0D" }
            GradientStop { position: 0.45; color: "#181818" }
            GradientStop { position: 1.0; color: "#141414" }
        }

        Column {
            id: cardCol

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: VLCStyle.dp(32, VLCStyle.scale)
            spacing: VLCStyle.dp(10, VLCStyle.scale)

            Text {
                text: qsTr("Let's set up your library")
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(30, VLCStyle.scale)
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: qsTr("Add the folder that holds your films and series - nothing is scanned until you do. Connect TMDB for posters and details, and OpenSubtitles for subtitles.")
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: VLCStyle.dp(10, VLCStyle.scale) }

            Row {
                id: tiles

                width: parent.width
                spacing: VLCStyle.dp(14, VLCStyle.scale)

                readonly property real tileWidth: (width - 2 * spacing) / 3

                Tile {
                    width: tiles.tileWidth
                    main: true
                    number: "1"
                    title: qsTr("Add a movie folder")
                    text: qsTr("Pick where your films live. Sub-folders are included.")
                    action: qsTr("Choose folder")
                    onActivated: root.addFolder()
                }

                Tile {
                    width: tiles.tileWidth
                    number: "2"
                    done: root.tmdbDone
                    title: qsTr("Connect TMDB")
                    text: qsTr("Posters, synopses, search and the Top 10. Free token.")
                    action: qsTr("Add token")
                    onActivated: MainCtx.openFlixSettings("accounts")
                }

                Tile {
                    width: tiles.tileWidth
                    number: "3"
                    done: root.subsDone
                    title: qsTr("Connect OpenSubtitles")
                    text: qsTr("Subtitles in your languages, found for you. Free account.")
                    action: qsTr("Log in")
                    onActivated: MainCtx.openFlixSettings("accounts")
                }
            }

            Item { width: 1; height: VLCStyle.dp(4, VLCStyle.scale) }

            Row {
                spacing: VLCStyle.dp(24, VLCStyle.scale)

                Link {
                    text: qsTr("Guide me through it") + "  ›"
                    onActivated: MainCtx.openWelcome()
                }

                Link {
                    text: qsTr("Stream a magnet link") + "  ›"
                    onActivated: root.streamMagnet()
                }
            }
        }
    }

    Row {
        id: links

        visible: !root.empty
        x: root.sideMargin
        spacing: VLCStyle.dp(24, VLCStyle.scale)

        Link {
            text: qsTr("Add another folder") + "  ›"
            onActivated: root.addFolder()
        }

        Link {
            text: qsTr("Manage folders") + "  ›"
            onActivated: MainCtx.openFlixSettings("library")
        }

        Link {
            text: qsTr("Stream a magnet link") + "  ›"
            onActivated: root.streamMagnet()
        }
    }
}
