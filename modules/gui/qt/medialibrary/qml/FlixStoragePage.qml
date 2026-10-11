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

// VLCFlix: what the app stores on this PC (torrent downloads, posters, subtitles, ...) with a
// "Clear" button for each, and the user's own torrent trackers.
Item {
    id: root

    property bool shown: false
    property bool ready: false              // on screen (kept until the exit animation ends)

    property var storage: []
    property string confirming: ""          // kind waiting for a second click
    property string message: ""
    property string trackerMessage: ""

    function refresh() {
        storage = MainCtx.storageInfo()
    }

    function open() {
        closeTimer.stop()
        ready = true
        shown = true
        confirming = ""
        message = ""
        trackerMessage = ""
        trackerInput.text = MainCtx.userTrackers()
        refresh()
        forceActiveFocus()
    }

    function close() {
        if (!shown)
            return
        shown = false
        closeTimer.restart()
    }

    function _size(bytes) {
        if (bytes >= 1073741824)
            return (bytes / 1073741824).toFixed(2) + " GB"
        if (bytes >= 1048576)
            return (bytes / 1048576).toFixed(1) + " MB"
        if (bytes > 0)
            return Math.max(1, Math.round(bytes / 1024)) + " KB"
        return qsTr("empty")
    }

    function clearKind(kind) {
        if (confirming !== kind) {
            confirming = kind
            confirmTimer.restart()
            return
        }
        confirming = ""
        const ok = MainCtx.clearStorage(kind)
        message = ok ? qsTr("Cleared.") : qsTr("Stop the running stream or web player first.")
        refresh()
    }

    function clearAll() {
        if (confirming !== "all") {
            confirming = "all"
            confirmTimer.restart()
            return
        }
        confirming = ""
        let blocked = false
        for (const s of storage)
            if (s.kind !== "resume" && !MainCtx.clearStorage(s.kind))
                blocked = true
        message = blocked ? qsTr("Some items are in use by a running stream.") : qsTr("Cleared.")
        refresh()
    }

    function saveTrackers() {
        const r = MainCtx.setUserTrackers(trackerInput.text)
        trackerMessage = r.saved ? qsTr("Saved. Used by the next torrent you start.")
                                 : qsTr("Not saved, invalid line: %1").arg(r.invalid[0])
    }

    Timer {
        id: confirmTimer

        interval: 4000
        onTriggered: root.confirming = ""
    }

    Timer {
        id: closeTimer

        interval: 240
        onTriggered: root.ready = false
    }

    visible: ready
    z: 140
    opacity: shown ? 1.0 : 0.0

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Keys.onEscapePressed: root.close()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.8)

        MouseArea {
            anchors.fill: parent
            enabled: root.shown
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onClicked: root.close()
            onWheel: (wheel) => wheel.accepted = true
        }
    }

    component Btn: Rectangle {
        id: btn

        property string text
        property bool primary: false
        property bool danger: false

        signal clicked()

        width: btnLabel.implicitWidth + 2 * VLCStyle.dp(18, VLCStyle.scale)
        height: VLCStyle.dp(34, VLCStyle.scale)
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
            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            font.weight: Font.Bold
        }

        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: btnTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: btn.clicked() }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(760, VLCStyle.scale))
        height: Math.min(parent.height - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(640, VLCStyle.scale))
        radius: VLCStyle.dp(10, VLCStyle.scale)
        color: "#181818"
        clip: true

        scale: root.shown ? 1.0 : 0.94
        transform: Translate {
            y: root.shown ? 0 : VLCStyle.dp(18, VLCStyle.scale)

            Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        }

        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onWheel: (wheel) => wheel.accepted = true
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: VLCStyle.dp(28, VLCStyle.scale)
            contentWidth: width
            contentHeight: body.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: body

                width: parent.width
                spacing: VLCStyle.dp(14, VLCStyle.scale)

                Text {
                    width: parent.width
                    text: qsTr("VLCFlix storage")
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(26, VLCStyle.scale)
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: qsTr("Everything here can be downloaded again. Your own movie files are never touched.")
                    color: "#B3B3B3"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: root.storage

                    delegate: Rectangle {
                        id: row

                        required property var modelData

                        readonly property bool inUse: (modelData.kind === "torrentData" && MainCtx.torrentRunning())

                        width: body.width
                        height: VLCStyle.dp(52, VLCStyle.scale)
                        radius: VLCStyle.dp(6, VLCStyle.scale)
                        color: "#222222"

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: VLCStyle.dp(16, VLCStyle.scale)
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: row.modelData.label
                                color: "#FFFFFF"
                                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: root._size(row.modelData.bytes) + (row.modelData.files > 0 ? "  •  " + qsTr("%1 files").arg(row.modelData.files) : "")
                                      + (row.inUse ? "  •  " + qsTr("in use by the current stream") : "")
                                color: "#B3B3B3"
                                font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                            }
                        }

                        Btn {
                            anchors.right: parent.right
                            anchors.rightMargin: VLCStyle.dp(12, VLCStyle.scale)
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: row.modelData.files > 0 && !row.inUse
                            danger: root.confirming === row.modelData.kind
                            text: root.confirming === row.modelData.kind ? qsTr("Click again to clear") : qsTr("Clear")
                            onClicked: root.clearKind(row.modelData.kind)
                        }
                    }
                }

                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    Btn {
                        danger: root.confirming === "all"
                        text: root.confirming === "all" ? qsTr("Click again to clear all") : qsTr("Clear all")
                        onClicked: root.clearAll()
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.message
                        color: "#34D399"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#333333"
                }

                Text {
                    width: parent.width
                    text: qsTr("Your own torrent trackers")
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: qsTr("One address per line (udp://, http:// or https://). They are added to every torrent, before the built-in list.")
                    color: "#B3B3B3"
                    font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    width: parent.width
                    height: VLCStyle.dp(110, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: "#1F1F1F"
                    border.color: trackerInput.activeFocus ? "#FFFFFF" : "#4D4D4D"
                    clip: true

                    Flickable {
                        id: trackerFlick

                        anchors.fill: parent
                        anchors.margins: VLCStyle.dp(8, VLCStyle.scale)
                        contentWidth: width
                        contentHeight: trackerInput.paintedHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: trackerInput

                            width: trackerFlick.width
                            height: Math.max(trackerFlick.height, paintedHeight)
                            color: "#FFFFFF"
                            selectionColor: "#E50914"
                            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                            wrapMode: TextEdit.NoWrap
                            onTextChanged: root.trackerMessage = ""
                        }
                    }
                }

                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    Btn {
                        primary: true
                        text: qsTr("Save trackers")
                        onClicked: root.saveTrackers()
                    }

                    Btn {
                        text: qsTr("Remove all")
                        onClicked: {
                            trackerInput.text = ""
                            root.saveTrackers()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.trackerMessage
                        color: text.indexOf(qsTr("Not saved")) === 0 ? "#F87171" : "#34D399"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                    }
                }

                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    Btn {
                        text: qsTr("Show the torrent speed box again")
                        onClicked: MainCtx.setFlixPref("torrent/hud", "shown")
                    }

                    Btn {
                        text: qsTr("Close")
                        onClicked: root.close()
                    }
                }
            }
        }
    }
}
