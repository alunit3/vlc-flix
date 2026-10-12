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

// flix: live numbers of the torrent that is being streamed: download / upload speed, peers and
// how much is cached. A click shows or hides the totals.
//
// The card is a Win11 floating panel, not a pill: a small fixed corner radius on a
// near-square box, real padding inside it, and every measurement labelled rather than
// left as a bare number. Spacing runs on a 4px grid so the rows line up with the rest
// of the shell.
Rectangle {
    id: root

    readonly property var stats: MainCtx.torrentStats
    readonly property bool active: stats.speedBps !== undefined

    // where the download progress is shown; the seek bar draws the same number itself
    readonly property string progressWhere: String(MainCtx.flixPref("torrent/progressWhere", "both"))
    readonly property bool showHere: progressWhere === "both" || progressWhere === "hud"

    // how much of the film is on disk. In stream mode this trails the playhead on
    // purpose; in download mode it climbs to 100.
    readonly property real donePct: {
        const total = Number(stats.total ?? 0)
        const done = Number(stats.downloaded ?? 0)
        if (!(total > 0))
            return 0
        return Math.max(0, Math.min(1, done / total))
    }

    property bool detailed: false
    // collapsed to a small button; the choice is remembered
    property bool hidden: String(MainCtx.flixPref("torrent/hud", "shown")) === "hidden"

    Connections {
        target: MainCtx

        // a new stream: honour the saved choice (it can be reset in the storage page)
        function onTorrentSessionChanged() {
            root.hidden = String(MainCtx.flixPref("torrent/hud", "shown")) === "hidden"
        }
    }

    function setHidden(value) {
        hidden = value
        MainCtx.setFlixPref("torrent/hud", value ? "hidden" : "shown")
    }

    function _speed(bps) {
        const v = Math.max(0, bps ?? 0)
        if (v >= 1048576)
            return (v / 1048576).toFixed(1) + " MB/s"
        return Math.round(v / 1024) + " KB/s"
    }

    function _size(bytes) {
        const v = Math.max(0, bytes ?? 0)
        if (v >= 1073741824)
            return (v / 1073741824).toFixed(2) + " GB"
        if (v >= 1048576)
            return (v / 1048576).toFixed(1) + " MB"
        return Math.round(v / 1024) + " KB"
    }

    // every number is written into a slot of this width, so a value that gains or
    // loses a digit ("9 KB/s" against "1024 KB/s") never shoves the layout sideways
    readonly property int colW: (VLCStyle.dp(264, VLCStyle.scale) - 2 * VLCStyle.dp(16, VLCStyle.scale)
                                  - VLCStyle.dp(24, VLCStyle.scale)) / 2
    readonly property int padX: VLCStyle.dp(16, VLCStyle.scale)
    readonly property int padY: VLCStyle.dp(14, VLCStyle.scale)
    readonly property int cardW: VLCStyle.dp(264, VLCStyle.scale)

    visible: opacity > 0
    opacity: active ? 0.94 : 0.0

    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    transform: Translate {
        y: root.active ? 0 : -VLCStyle.dp(12, VLCStyle.scale)

        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }

    width: hidden ? VLCStyle.dp(28, VLCStyle.scale) : root.cardW
    height: hidden ? VLCStyle.dp(28, VLCStyle.scale)
                   : content.implicitHeight + 2 * root.padY
    radius: hidden ? VLCStyle.dp(6, VLCStyle.scale) : VLCStyle.dp(8, VLCStyle.scale)
    color: Qt.rgba(0.10, 0.10, 0.11, 0.86)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.09)

    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // a hairline along the top edge, the way a floating Win11 card catches light
    Rectangle {
        visible: !root.hidden
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: 1
        color: Qt.rgba(1, 1, 1, 0.05)
    }

    // collapsed: a square button, not a pill
    Text {
        visible: root.hidden
        anchors.centerIn: parent
        text: VLCIcons.ic_fluent_arrow_download_24_regular
        font.family: VLCIcons.fontFamily
        color: "#B3B3B3"
        font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
    }

    Column {
        id: content

        visible: !root.hidden
        width: root.cardW - 2 * root.padX
        x: root.padX
        anchors.verticalCenter: parent.verticalCenter
        spacing: VLCStyle.dp(12, VLCStyle.scale)

        // header: what this panel is about, and the way to put it away
        Item {
            width: parent.width
            height: VLCStyle.dp(18, VLCStyle.scale)

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: VLCStyle.dp(6, VLCStyle.scale)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: VLCIcons.ic_fluent_arrow_download_24_regular
                    font.family: VLCIcons.fontFamily
                    color: "#34D399"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Torrent")
                    color: "#B3B3B3"
                    font.pixelSize: VLCStyle.dp(11, VLCStyle.scale)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.7
                }
            }

            Rectangle {
                id: closeButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: VLCStyle.dp(18, VLCStyle.scale)
                height: width
                radius: VLCStyle.dp(4, VLCStyle.scale)
                color: closeHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

                Behavior on color { ColorAnimation { duration: 140 } }

                Text {
                    anchors.centerIn: parent
                    text: VLCIcons.close
                    font.family: VLCIcons.fontFamily
                    color: closeHover.hovered ? "#FFFFFF" : "#8C8C8C"
                    font.pixelSize: VLCStyle.dp(9, VLCStyle.scale)
                }

                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.setHidden(true)
                }
            }
        }

        // the two speeds, labelled
        Row {
            width: parent.width
            spacing: VLCStyle.dp(24, VLCStyle.scale)

            Column {
                width: root.colW
                spacing: VLCStyle.dp(3, VLCStyle.scale)

                Text {
                    width: parent.width
                    text: qsTr("Download")
                    color: "#8C8C8C"
                    font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.7
                }

                Text {
                    width: parent.width
                    text: root._speed(root.stats.speedBps)
                    color: "#34D399"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    font.weight: Font.DemiBold
                }
            }

            Column {
                width: root.colW
                spacing: VLCStyle.dp(3, VLCStyle.scale)

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("Upload")
                    color: "#8C8C8C"
                    font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.7
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: root._speed(root.stats.upBps)
                    color: "#60A5FA"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    font.weight: Font.DemiBold
                }
            }
        }

        // a hairline, so the panel reads as sections rather than as a stack
        Rectangle {
            visible: !root.hidden
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        // how much of the film is on disk
        Row {
            id: progress

            visible: root.showHere
            width: parent.width
            spacing: VLCStyle.dp(12, VLCStyle.scale)

            Rectangle {
                id: track

                width: parent.width - pct.width - parent.spacing
                height: VLCStyle.dp(4, VLCStyle.scale)
                radius: height / 2
                color: "#FFFFFF"
                opacity: 0.09
                anchors.verticalCenter: parent.verticalCenter

                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                Rectangle {
                    width: parent.width * root.donePct
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#B00A1E" }
                        GradientStop { position: 1.0; color: "#FF4757" }
                    }

                    // a small cap at the end of the fill, so the bar reads as a
                    // position rather than a block
                    Rectangle {
                        visible: root.donePct > 0.02 && root.donePct < 0.999
                        anchors.right: parent.right
                        anchors.rightMargin: parent.height / 2
                        width: parent.height
                        height: parent.height
                        radius: width / 2
                        color: "#FF6B7A"
                    }
                }
            }

            Text {
                id: pct

                anchors.verticalCenter: parent.verticalCenter
                width: VLCStyle.dp(36, VLCStyle.scale)
                horizontalAlignment: Text.AlignRight
                text: qsTr("%1%").arg(Math.round(root.donePct * 100))
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(11, VLCStyle.scale)
            }
        }

        // who we are sharing with
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: qsTr("%1 peers  •  %2 seeders")
                  .arg(root.stats.peers ?? 0).arg(root.stats.seeders ?? 0)
            color: "#8C8C8C"
            font.pixelSize: VLCStyle.dp(11, VLCStyle.scale)
        }

        // the totals, on a click
        Column {
            width: parent.width
            spacing: VLCStyle.dp(12, VLCStyle.scale)
            visible: root.detailed

            // fold the panel open/closed by growing and shrinking the column
            height: visible ? implicitHeight : 0
            clip: true

            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on visible { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            Row {
                width: parent.width
                spacing: VLCStyle.dp(24, VLCStyle.scale)

                Column {
                    width: root.colW
                    spacing: VLCStyle.dp(3, VLCStyle.scale)

                    Text {
                        width: parent.width
                        text: qsTr("Downloaded")
                        color: "#8C8C8C"
                        font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.7
                    }

                    Text {
                        width: parent.width
                        text: root._size(root.stats.downloaded)
                        color: "#D4D4D4"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    width: root.colW
                    spacing: VLCStyle.dp(3, VLCStyle.scale)

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: qsTr("Total size")
                        color: "#8C8C8C"
                        font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.7
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: root._size(root.stats.total)
                        color: "#D4D4D4"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                        font.weight: Font.DemiBold
                    }
                }
            }

            Row {
                width: parent.width
                spacing: VLCStyle.dp(24, VLCStyle.scale)

                Column {
                    width: root.colW
                    spacing: VLCStyle.dp(3, VLCStyle.scale)

                    Text {
                        width: parent.width
                        text: qsTr("Uploaded")
                        color: "#8C8C8C"
                        font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.7
                    }

                    Text {
                        width: parent.width
                        text: root._size(root.stats.uploaded)
                        color: "#D4D4D4"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    width: root.colW
                    spacing: VLCStyle.dp(3, VLCStyle.scale)

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: qsTr("Seeders")
                        color: "#8C8C8C"
                        font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.7
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: qsTr("%1").arg(root.stats.seeders ?? 0)
                        color: "#D4D4D4"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: {
            // the close button has its own handler and runs first
            if (closeHover.hovered)
                return
            if (root.hidden)
                root.setHidden(false)
            else
                root.detailed = !root.detailed
        }
    }
}