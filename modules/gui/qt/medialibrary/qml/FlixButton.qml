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

import VLC.Style

// VLCFlix button: white (primary), red (danger) or grey. Shared by the settings page and
// the welcome flow.
Rectangle {
    id: btn

    property string text
    property bool primary: false
    property bool danger: false
    property bool large: false

    signal clicked()

    width: btnLabel.implicitWidth + 2 * VLCStyle.dp(large ? 26 : 18, VLCStyle.scale)
    height: VLCStyle.dp(large ? 44 : 34, VLCStyle.scale)
    radius: VLCStyle.dp(4, VLCStyle.scale)
    opacity: enabled ? 1.0 : 0.4
    color: danger ? (btnHover.hovered ? "#F6121D" : "#E50914")
                  : primary ? (btnHover.hovered ? "#BFBFBF" : "#FFFFFF")
                            : (btnHover.hovered ? Qt.rgba(0.43, 0.43, 0.45, 0.55) : Qt.rgba(0.43, 0.43, 0.45, 0.7))
    scale: btnTap.pressed ? 0.96 : 1.0

    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Text {
        id: btnLabel

        anchors.centerIn: parent
        text: btn.text
        color: (btn.primary && !btn.danger) ? "#141414" : "#FFFFFF"
        font.pixelSize: VLCStyle.dp(btn.large ? 16 : 14, VLCStyle.scale)
        font.weight: Font.Bold
    }

    HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: btnTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: btn.clicked() }
}
