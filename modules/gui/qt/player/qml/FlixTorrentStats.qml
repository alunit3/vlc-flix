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
Rectangle {
    id: root

    readonly property var stats: MainCtx.torrentStats
    readonly property bool active: stats.speedBps !== undefined

    property bool detailed: false

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
        return Math.round(v / 1048576) + " MB"
    }

    visible: opacity > 0
    opacity: active ? 0.92 : 0.0

    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    transform: Translate {
        y: root.active ? 0 : -VLCStyle.dp(12, VLCStyle.scale)

        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }

    width: content.implicitWidth + 2 * VLCStyle.dp(14, VLCStyle.scale)
    height: content.implicitHeight + 2 * VLCStyle.dp(8, VLCStyle.scale)
    radius: height / 2
    color: Qt.rgba(0.08, 0.08, 0.08, 0.82)
    border.color: "#3A3A3A"

    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Column {
        id: content

        anchors.centerIn: parent
        spacing: VLCStyle.dp(2, VLCStyle.scale)

        Row {
            spacing: VLCStyle.dp(14, VLCStyle.scale)

            Text {
                text: "↓ " + root._speed(root.stats.speedBps)
                color: "#34D399"
                font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                font.weight: Font.DemiBold
            }

            Text {
                text: "↑ " + root._speed(root.stats.upBps)
                color: "#60A5FA"
                font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                font.weight: Font.DemiBold
            }

            Text {
                text: qsTr("%1 peers").arg(root.stats.peers ?? 0)
                color: "#E5E5E5"
                font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
            }
        }

        Text {
            visible: root.detailed
            text: qsTr("Downloaded %1 of %2  •  Uploaded %3  •  %4 seeders")
                  .arg(root._size(root.stats.downloaded)).arg(root._size(root.stats.total))
                  .arg(root._size(root.stats.uploaded)).arg(root.stats.seeders ?? 0)
            color: "#B3B3B3"
            font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
        }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: root.detailed = !root.detailed }
}
