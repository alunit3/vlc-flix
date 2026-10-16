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
import QtQuick.Templates as T

import VLC.Style
import VLC.Player
import VLC.Util

// flix: "Playback Speed" as on Netflix: a line with one stop per speed, the current one
// drawn as a large ring. A speed set some other way (keyboard, menu) that is not one of
// the stops is shown in the title.
FocusScope {
    id: root

    signal picked()

    readonly property var speeds: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    readonly property int currentIndex: {
        for (let i = 0; i < speeds.length; ++i)
            if (Math.abs(Player.rate - speeds[i]) < 0.01)
                return i
        return -1
    }

    property int focusIndex: Math.max(0, currentIndex)

    implicitWidth: VLCStyle.dp(560, VLCStyle.scale)
    implicitHeight: VLCStyle.dp(150, VLCStyle.scale)

    function _pick(i) {
        Player.rate = speeds[i]
        root.picked()
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Left) {
            focusIndex = Math.max(0, focusIndex - 1)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            focusIndex = Math.min(speeds.length - 1, focusIndex + 1)
            event.accepted = true
        } else if (KeyHelper.matchOk(event)) {
            _pick(focusIndex)
            event.accepted = true
        }
    }

    Text {
        id: title

        x: VLCStyle.margin_large
        y: VLCStyle.margin_normal

        text: (root.currentIndex < 0) ? qsTr("Playback Speed (%1x)").arg(+Player.rate.toFixed(2))
                                      : qsTr("Playback Speed")
        color: "#FFFFFF"
        font.pixelSize: VLCStyle.dp(24, VLCStyle.scale)
        font.weight: Font.Bold
    }

    Item {
        id: track

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: VLCStyle.dp(48, VLCStyle.scale)
        anchors.rightMargin: VLCStyle.dp(48, VLCStyle.scale)

        readonly property real lineY: height * 0.42
        readonly property real step: width / (root.speeds.length - 1)

        Rectangle {
            x: 0
            width: parent.width
            y: track.lineY - height / 2
            height: VLCStyle.dp(2, VLCStyle.scale)
            color: "#808080"
        }

        Repeater {
            model: root.speeds.length

            delegate: T.AbstractButton {
                id: stop

                required property int index

                readonly property bool current: index === root.currentIndex
                readonly property bool focused: root.activeFocus && index === root.focusIndex

                x: index * track.step - width / 2
                y: 0
                width: VLCStyle.dp(72, VLCStyle.scale)
                height: track.height

                hoverEnabled: true
                focusPolicy: Qt.NoFocus

                Accessible.role: Accessible.RadioButton
                Accessible.name: label.text
                Accessible.checkable: true
                Accessible.checked: current

                onClicked: root._pick(index)

                // the ring for the current speed, a dot for the others
                Rectangle {
                    property real size: stop.current ? VLCStyle.dp(26, VLCStyle.scale)
                                                              : (stop.hovered || stop.focused) ? VLCStyle.dp(14, VLCStyle.scale)
                                                                                               : VLCStyle.dp(10, VLCStyle.scale)
                    width: size
                    height: size
                    radius: size / 2
                    x: (stop.width - width) / 2
                    y: track.lineY - height / 2

                    color: stop.current ? "transparent" : ((stop.hovered || stop.focused) ? "#FFFFFF" : "#B3B3B3")
                    border.color: "#FFFFFF"
                    border.width: stop.current ? VLCStyle.dp(3, VLCStyle.scale) : 0

                    Rectangle {
                        visible: stop.current
                        anchors.centerIn: parent
                        width: parent.width * 0.45
                        height: width
                        radius: width / 2
                        color: "#FFFFFF"
                    }

                    Behavior on size { NumberAnimation { duration: VLCStyle.duration_short } }
                }

                Text {
                    id: label

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: track.lineY + VLCStyle.dp(22, VLCStyle.scale)

                    text: (root.speeds[stop.index] === 1.0) ? qsTr("1x (Normal)")
                                                             : qsTr("%1x").arg(root.speeds[stop.index])
                    color: (stop.current || stop.hovered || stop.focused) ? "#FFFFFF" : "#B3B3B3"
                    font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                    font.weight: stop.current ? Font.Bold : Font.Normal
                }
            }
        }
    }
}
