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

// flix: the title of what is playing, in the middle of the control bar.
// Movies: "Title (Year)". Episodes: bold "Show" followed by a lighter "S2:E5".
Item {
    id: root

    property bool paintOnly: false

    // upper bound for the width, set by the layout so the title never overlaps other controls
    property real maxWidth: VLCStyle.dp(560, VLCStyle.scale)

    readonly property string _display: MainCtx.cleanTitle(Player.title)
    readonly property var _episode: _display.match(/^(.*) - S(\d+)E(\d+)$/)

    // A label's implicitWidth is the width of its full text and does not depend on its
    // width, so these do not depend on each other.
    readonly property real _episodeWidth: (!paintOnly && _episode !== null) ? (episodeLabel.implicitWidth + row.spacing) : 0
    readonly property real _mainWidth: Math.min(mainLabel.implicitWidth, Math.max(0, maxWidth - _episodeWidth))

    implicitHeight: VLCStyle.icon_toolbar
    implicitWidth: paintOnly ? VLCStyle.icon_toolbar * 3 : (_mainWidth + _episodeWidth)


    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.ToolButton
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: VLCStyle.dp(10, VLCStyle.scale)

        Text {
            id: mainLabel

            width: root._mainWidth
            text: root.paintOnly ? qsTr("Title") : (root._episode ? root._episode[1] : root._display)
            color: theme.fg.primary
            font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
            font.weight: Font.Bold
            elide: Text.ElideRight
        }

        Text {
            id: episodeLabel

            visible: !root.paintOnly && root._episode !== null
            text: root._episode ? ("S" + Number(root._episode[2]) + ":E" + Number(root._episode[3])) : ""
            color: theme.fg.secondary
            font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
        }
    }
}
