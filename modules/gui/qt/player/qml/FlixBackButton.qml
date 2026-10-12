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

// VLCFlix: "back to Home" that always answers on the first click. The player controls hide
// themselves after a few seconds (and their back arrow with them); this corner stays
// clickable while they are hidden and goes back at once.
//
// It draws nothing. It used to show an arrow of its own on hover, but hovering also brings
// the controls back, so for a moment there were two arrows a few pixels apart. The top bar's
// arrow is the one back button; this only makes the empty corner answer like it.
Item {
    id: root

    // the player's top bar: while it shows its arrow, that arrow takes the click itself
    property Item topBar: null

    signal clicked()

    readonly property bool _barShowsArrow: topBar !== null && topBar.visible && topBar.opacity > 0.5

    width: VLCStyle.dp(64, VLCStyle.scale)
    height: VLCStyle.dp(64, VLCStyle.scale)

    enabled: !_barShowsArrow

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.clicked()
    }
}
