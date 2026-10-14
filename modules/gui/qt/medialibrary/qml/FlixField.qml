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

// VLCFlix text box with a label and a hint; secret fields show dots. Shared by the settings
// page and the welcome flow.
Column {
    id: field

    property string label
    property string hint
    property string placeholder
    property bool secret: false
    property alias text: input.text
    property alias input: input

    signal committed()

    width: parent ? parent.width : 0
    spacing: VLCStyle.dp(6, VLCStyle.scale)

    Text {
        visible: field.label !== ""
        text: field.label
        color: "#FFFFFF"
        font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
        font.weight: Font.DemiBold
    }

    Rectangle {
        width: parent.width
        height: VLCStyle.dp(40, VLCStyle.scale)
        radius: VLCStyle.dp(4, VLCStyle.scale)
        color: "#1F1F1F"
        border.color: input.activeFocus ? "#FFFFFF" : "#4D4D4D"

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: VLCStyle.dp(12, VLCStyle.scale)
            anchors.rightMargin: VLCStyle.dp(12, VLCStyle.scale)
            verticalAlignment: TextInput.AlignVCenter
            color: "#FFFFFF"
            selectionColor: "#E50914"
            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            clip: true
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            onEditingFinished: field.committed()

            Text {
                visible: input.text === "" && !input.activeFocus
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                elide: Text.ElideRight
                text: field.placeholder
                color: "#808080"
                font: input.font
            }
        }
    }

    Text {
        visible: field.hint !== ""
        width: parent.width
        text: field.hint
        color: "#808080"
        font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        linkColor: "#FFFFFF"
        onLinkActivated: (link) => Qt.openUrlExternally(link)

        HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
}
