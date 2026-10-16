/*****************************************************************************
 * Copyright (C) 2021 VLC authors and VideoLAN
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


import VLC.MainInterface
import VLC.Style
import VLC.Player
import VLC.Widgets
import VLC.Util

PopupIconToolButton {
    id: root

    // flix: a speedometer icon that opens the Netflix-style speed picker
    popup.width: popup.contentItem.implicitWidth + popup.leftPadding + popup.rightPadding
    popup.padding: 0
    popup.x: Math.min((root.width - popup.width) / 2,
                      root.width + VLCStyle.margin_large - popup.width)
    // above the seekbar, which runs just over the buttons
    popup.y: -popup.height - VLCStyle.dp(44, VLCStyle.scale)

    popup.background: Rectangle {
        color: "#262626"
        radius: VLCStyle.dp(4, VLCStyle.scale)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
    }

    text: qsTr("Playback Speed")

    description: qsTr("Playback speed (%1x)").arg(+Player.rate.toFixed(2))

    AccessibleCompat.id: "playbackSpeedButton"

    popup.contentItem: FlixSpeedPicker {
        focus: true
        onPicked: root.popup.close()
    }

    contentItem: Item {
        implicitHeight: root.font.pixelSize
        implicitWidth: gauge.width + (rateLabel.visible ? rateLabel.implicitWidth + VLCStyle.margin_xxsmall : 0)

        // the gauge: a ring with a needle and a hub, drawn so it takes the button colour
        // (Canvas and Shapes are not part of this Qt build)
        Item {
            id: gauge

            readonly property real s: root.font.pixelSize
            readonly property real stroke: Math.max(2, Math.round(s * 0.09))

            width: s
            height: s
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: gauge.s * 0.84
                height: width
                radius: width / 2
                color: "transparent"
                border.color: root.color
                border.width: gauge.stroke
            }

            // ticks at the top and the sides, like a speedometer dial
            Repeater {
                model: [-90, -45, 0, 45, 90]
                Rectangle {
                    required property var modelData
                    width: gauge.stroke
                    height: gauge.s * 0.12
                    radius: width / 2
                    color: root.color
                    x: (gauge.width - width) / 2
                    y: gauge.s * 0.16
                    transform: Rotation {
                        origin.x: gauge.stroke / 2
                        origin.y: gauge.s / 2 - gauge.s * 0.16
                        angle: modelData
                    }
                }
            }

            // the needle, pointing to the upper right
            Rectangle {
                width: gauge.stroke
                height: gauge.s * 0.30
                radius: width / 2
                color: root.color
                x: (gauge.width - width) / 2
                y: gauge.s / 2 - height
                transform: Rotation {
                    origin.x: gauge.stroke / 2
                    origin.y: gauge.s * 0.30
                    angle: 50
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: gauge.stroke * 2.2
                height: width
                radius: width / 2
                color: root.color
            }
        }

        // the speed, next to the gauge, when it is not the normal one
        Text {
            id: rateLabel

            anchors.left: gauge.right
            anchors.leftMargin: VLCStyle.margin_xxsmall
            anchors.verticalCenter: parent.verticalCenter

            visible: !root.paintOnly && Math.abs(Player.rate - 1) > 0.001
            text: qsTr("%1x").arg(+Player.rate.toFixed(2))
            color: root.color
            font.pixelSize: VLCStyle.fontSize_normal
            font.weight: Font.DemiBold
        }
    }

    // TODO: Qt bug 6.2: QTBUG-103604
    DoubleClickIgnoringItem {
        anchors.fill: parent

        z: -1

        WheelToVLCConverter {
            id: wheelToVLC

            // one wheel step moves one stop on the speed picker
            function handle(steps: int) {
                const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0]
                let i = 0
                while (i < speeds.length - 1 && speeds[i] < Player.rate - 0.001)
                    ++i
                if (steps > 0 && Math.abs(speeds[i] - Player.rate) < 0.001)
                    ++i
                else if (steps < 0)
                    --i
                Player.rate = speeds[Math.max(0, Math.min(speeds.length - 1, i))]
            }

            Component.onCompleted: {
                wheelUpDown.connect(wheelToVLC.handle)
                wheelLeftRight.connect(wheelToVLC.handle)
            }
        }

        WheelHandler {
            orientation: Qt.Vertical | Qt.Horizontal

            acceptedDevices: PointerDevice.AllDevices

            onWheel: (wheel) => {
                wheelToVLC.qmlWheelEvent(wheel)
                wheel.accepted = true
            }
        }

        TapHandler {
            acceptedButtons: Qt.RightButton

            gesturePolicy: TapHandler.ReleaseWithinBounds

            // right click: back to normal speed
            onTapped: (eventPoint, button) => {
                Player.rate = 1.0
            }
        }
    }
}
