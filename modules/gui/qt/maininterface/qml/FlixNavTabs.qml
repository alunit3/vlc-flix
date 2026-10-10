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

// flix: top navigation tabs (Home / Video / Music / ...) built from the same
// NavigationModel as the side navigation pane, drawn as pills.
Row {
    id: root

    // emitted with the model uri (e.g. ["video"]) of the clicked tab
    signal tabClicked(var uri)

    spacing: VLCStyle.dp(4, VLCStyle.scale)

    NavigationModel {
        id: navModel
        hasMedialib: MainCtx.mediaLibraryAvailable
    }

    // NavigationModel fills its rows in componentComplete() without emitting any
    // change signal, and QML completes the Repeater first. So the model is given
    // to the Repeater only once the whole component has completed.
    Component.onCompleted: tabs.model = navModel

    Repeater {
        id: tabs

        delegate: Item {
            id: tab

            required property string title
            required property var uri

            // only the top-level entries are tabs (one-element uri);
            // sub-entries (All, Playlists, ...) live inside their page
            visible: uri.length === 1
            width: visible ? (label.implicitWidth + 2 * VLCStyle.dp(16, VLCStyle.scale)) : 0
            height: VLCStyle.dp(34, VLCStyle.scale)

            readonly property bool active: History.match(History.viewPath, uri)

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: tab.active ? Qt.rgba(1, 1, 1, 0.20)
                                  : (hover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Text {
                id: label

                anchors.centerIn: parent
                text: tab.title
                color: tab.active ? "#FFFFFF" : "#E5E5E5"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                font.weight: tab.active ? Font.DemiBold : Font.Medium
            }

            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: root.tabClicked(tab.uri)
            }
        }
    }
}
