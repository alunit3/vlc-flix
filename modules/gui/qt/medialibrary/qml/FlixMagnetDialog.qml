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

import VLC.MediaLibrary
import VLC.MainInterface
import VLC.Style

// flix: stream a magnet link (or a .torrent file) the user brings. The torrent is read first, the
// user picks the file (season packs hold many), then it is streamed like any other source.
Item {
    id: root

    property bool shown: false
    property bool ready: false              // the dialog is on screen (kept until the exit animation ends)

    signal streamStarted()

    // --- state -------------------------------------------------------------------------
    property string torrentFile: ""         // set when a .torrent file was chosen
    property bool checking: false
    property string error: ""
    property string torrentName: ""
    property var files: []
    property int selectedIdx: -1
    property var stream: null
    property bool handedOver: false
    readonly property bool streaming: stream !== null && stream.state !== "error" && stream.state !== "cancelled"

    function open() {
        closeTimer.stop()
        ready = true
        shown = true
        torrentFile = ""
        error = ""
        torrentName = ""
        files = []
        selectedIdx = -1
        stream = null
        handedOver = false
        checking = false
        input.text = MainCtx.clipboardMagnet()
        forceActiveFocus()
        input.forceActiveFocus()
    }

    // continue a torrent from "Continue Streaming": no questions, the same file as before
    function resume(entry) {
        open()
        torrentFile = entry.torrentFile ?? ""
        input.text = torrentFile !== "" ? torrentFile : (entry.magnet ?? "")
        torrentName = entry.title ?? ""
        stream = { state: "connecting" }
        const source = torrentFile !== "" ? { torrentFile: torrentFile } : { magnet: entry.magnet }
        source.fileIdx = entry.fileIdx ?? -1
        source.title = entry.title ?? ""
        source.meta = entry
        MainCtx.torrentStart(source)
    }

    function close() {
        if (!shown)
            return
        if (streaming && !handedOver)
            MainCtx.torrentCancel()
        shown = false
        closeTimer.restart()
    }

    function check() {
        error = ""
        files = []
        selectedIdx = -1
        torrentName = ""
        const text = input.text.trim()
        if (torrentFile === "" && text === "") {
            error = qsTr("Paste a magnet link or choose a .torrent file first.")
            return
        }
        checking = true
        MainCtx.torrentFiles(torrentFile !== "" ? { torrentFile: torrentFile } : { magnet: text })
    }

    function browse() {
        const path = MainCtx.pickTorrentFile(qsTr("Choose a .torrent file"))
        if (path !== "") {
            torrentFile = path
            input.text = path
            check()
        }
    }

    function startStreaming() {
        if (selectedIdx < 0)
            return
        stream = { state: "connecting" }
        const source = torrentFile !== "" ? { torrentFile: torrentFile } : { magnet: input.text.trim() }
        source.fileIdx = selectedIdx
        source.title = displayTitle
        MainCtx.torrentStart(source)
    }

    function _size(bytes) {
        if (bytes >= 1073741824)
            return (bytes / 1073741824).toFixed(2) + " GB"
        if (bytes >= 1048576)
            return Math.round(bytes / 1048576) + " MB"
        return Math.max(1, Math.round(bytes / 1024)) + " KB"
    }

    function _speed(bps) {
        return bps >= 1048576 ? (bps / 1048576).toFixed(1) + " MB/s" : Math.round(bps / 1024) + " KB/s"
    }

    readonly property string displayTitle: {
        for (const f of files)
            if (f.idx === selectedIdx)
                return MainCtx.cleanTitle(f.name.split("/").pop())
        return torrentName
    }

    Timer {
        id: closeTimer

        interval: 240
        onTriggered: root.ready = false
    }

    Connections {
        target: MainCtx

        function onTorrentFilesReady(name, list, err) {
            if (!root.checking)
                return
            root.checking = false
            root.error = err
            root.torrentName = name
            // video files first, the biggest one preselected
            const sorted = list.slice().sort((a, b) => (b.video - a.video) || (b.size - a.size))
            root.files = sorted
            root.selectedIdx = (sorted.length > 0 && sorted[0].video) ? sorted[0].idx : -1
            if (err === "" && sorted.length > 0 && !sorted[0].video)
                root.error = qsTr("This torrent has no video file.")
        }

        function onTorrentStatus(status) {
            if (!root.shown || !root.streaming)
                return
            if (status.state === "ready") {
                root.handedOver = true
                MediaLib.addAndPlay(status.url, ["meta-title=" + root.displayTitle])
                MainCtx.resumeFraction = MainCtx.torrentResume()
                MainCtx.resumeNotice = 0
                MainCtx.playerView = true
                root.stream = null
                root.close()
                root.streamStarted()
                return
            }
            root.stream = Object.assign({}, root.stream ?? {}, status)
        }
    }

    visible: ready
    z: 130
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
            onClicked: if (!root.streaming) root.close()
            onWheel: (wheel) => wheel.accepted = true
        }
    }

    // a rounded button
    component Btn: Rectangle {
        id: btn

        property string text
        property string icon: ""
        property bool primary: false
        property bool busy: false

        signal clicked()

        width: btnRow.implicitWidth + 2 * VLCStyle.dp(22, VLCStyle.scale)
        height: VLCStyle.dp(40, VLCStyle.scale)
        radius: VLCStyle.dp(4, VLCStyle.scale)
        opacity: enabled ? 1.0 : 0.4
        color: primary ? (btnHover.hovered ? "#BFBFBF" : "#FFFFFF")
                       : (btnHover.hovered ? Qt.rgba(0.43, 0.43, 0.45, 0.55) : Qt.rgba(0.43, 0.43, 0.45, 0.7))
        scale: btnTap.pressed ? 0.96 : (btnHover.hovered ? 1.03 : 1.0)

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Row {
            id: btnRow

            anchors.centerIn: parent
            spacing: VLCStyle.dp(8, VLCStyle.scale)

            Text {
                visible: btn.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: btn.icon
                font.family: VLCIcons.fontFamily
                color: btn.primary ? "#141414" : "#FFFFFF"
                font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
            }

            Text {
                id: btnLabel

                anchors.verticalCenter: parent.verticalCenter
                text: btn.text
                color: btn.primary ? "#141414" : "#FFFFFF"
                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                font.weight: Font.Bold
            }
        }

        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: btnTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: btn.clicked() }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(780, VLCStyle.scale))
        height: Math.min(parent.height - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(560, VLCStyle.scale))
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

        Column {
            id: head

            x: VLCStyle.dp(28, VLCStyle.scale)
            y: VLCStyle.dp(22, VLCStyle.scale)
            width: parent.width - 2 * VLCStyle.dp(28, VLCStyle.scale)
            spacing: VLCStyle.dp(12, VLCStyle.scale)

            Text {
                width: parent.width
                text: qsTr("Stream a magnet link")
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(26, VLCStyle.scale)
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: qsTr("Paste your own magnet link or choose a .torrent file. You pick the file before anything is streamed.")
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: VLCStyle.dp(44, VLCStyle.scale)
                radius: VLCStyle.dp(4, VLCStyle.scale)
                color: "#1F1F1F"
                border.color: input.activeFocus ? "#FFFFFF" : "#4D4D4D"

                TextInput {
                    id: input

                    anchors.fill: parent
                    anchors.leftMargin: VLCStyle.dp(14, VLCStyle.scale)
                    anchors.rightMargin: VLCStyle.dp(14, VLCStyle.scale)
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#FFFFFF"
                    selectionColor: "#E50914"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    clip: true
                    enabled: !root.streaming

                    onTextEdited: root.torrentFile = ""
                    onAccepted: root.check()

                    Text {
                        visible: input.text === "" && !input.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: "magnet:?xt=urn:btih:…"
                        color: "#808080"
                        font: input.font
                    }
                }
            }

            Row {
                spacing: VLCStyle.dp(10, VLCStyle.scale)

                Btn {
                    text: qsTr("Paste")
                    enabled: !root.streaming
                    onClicked: { input.text = MainCtx.clipboardMagnet() || input.text; input.forceActiveFocus() }
                }

                Btn {
                    text: qsTr("Browse .torrent…")
                    enabled: !root.streaming
                    onClicked: root.browse()
                }

                Btn {
                    text: qsTr("Check")
                    primary: true
                    enabled: !root.streaming && !root.checking
                    onClicked: root.check()
                }
            }

            Row {
                visible: root.checking || root.error !== ""
                spacing: VLCStyle.dp(10, VLCStyle.scale)

                Item {
                    id: spinner

                    visible: root.checking
                    width: VLCStyle.dp(18, VLCStyle.scale)
                    height: width

                    property real spin: 0

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: VLCStyle.dp(2, VLCStyle.scale)
                        border.color: "#4D4D4D"
                    }

                    Rectangle {
                        width: VLCStyle.dp(5, VLCStyle.scale)
                        height: width
                        radius: width / 2
                        color: "#E50914"
                        x: parent.width / 2 - width / 2
                        y: -height / 4

                        transform: Rotation {
                            origin.x: VLCStyle.dp(2.5, VLCStyle.scale)
                            origin.y: VLCStyle.dp(11.5, VLCStyle.scale)
                            angle: spinner.spin
                        }
                    }

                    NumberAnimation on spin { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.checking }
                }

                Text {
                    text: root.checking ? qsTr("Reading the torrent… (can take up to a minute)") : root.error
                    color: root.checking ? "#B3B3B3" : "#F87171"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: VLCStyle.dp(14, VLCStyle.scale)
            width: VLCStyle.dp(34, VLCStyle.scale)
            height: width
            radius: width / 2
            color: closeHover.hovered ? Qt.rgba(0.3, 0.3, 0.3, 0.95) : Qt.rgba(0.08, 0.08, 0.08, 0.85)

            Behavior on color { ColorAnimation { duration: 140 } }

            Text {
                anchors.centerIn: parent
                text: VLCIcons.close
                font.family: VLCIcons.fontFamily
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
            }

            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: root.close() }
        }

        // the files of the torrent
        ListView {
            id: list

            visible: root.files.length > 0
            anchors.top: head.bottom
            anchors.topMargin: VLCStyle.dp(14, VLCStyle.scale)
            anchors.bottom: footer.top
            anchors.bottomMargin: VLCStyle.dp(8, VLCStyle.scale)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: VLCStyle.dp(28, VLCStyle.scale)
            anchors.rightMargin: VLCStyle.dp(28, VLCStyle.scale)
            clip: true
            spacing: VLCStyle.dp(5, VLCStyle.scale)
            model: root.files
            boundsBehavior: Flickable.StopAtBounds

            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 } }

            delegate: Rectangle {
                id: row

                required property var modelData

                readonly property bool isSelected: root.selectedIdx === modelData.idx

                width: list.width
                height: VLCStyle.dp(42, VLCStyle.scale)
                radius: VLCStyle.dp(5, VLCStyle.scale)
                color: isSelected ? "#2E2E2E" : (rowHover.hovered ? "#262626" : "#202020")
                border.width: isSelected ? 1 : 0
                border.color: "#E50914"
                opacity: modelData.video ? 1.0 : 0.45

                Behavior on color { ColorAnimation { duration: 140 } }

                Text {
                    visible: row.modelData.video
                    anchors.left: parent.left
                    anchors.leftMargin: VLCStyle.dp(14, VLCStyle.scale)
                    anchors.verticalCenter: parent.verticalCenter
                    text: VLCIcons.play_filled
                    font.family: VLCIcons.fontFamily
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: row.modelData.video ? VLCStyle.dp(38, VLCStyle.scale) : VLCStyle.dp(14, VLCStyle.scale)
                    anchors.right: sizeText.left
                    anchors.rightMargin: VLCStyle.dp(10, VLCStyle.scale)
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    elide: Text.ElideMiddle
                }

                Text {
                    id: sizeText

                    anchors.right: parent.right
                    anchors.rightMargin: VLCStyle.dp(14, VLCStyle.scale)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._size(row.modelData.size)
                    color: "#B3B3B3"
                    font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                }

                HoverHandler { id: rowHover; cursorShape: row.modelData.video ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: if (row.modelData.video && !root.streaming) root.selectedIdx = row.modelData.idx
                }
            }
        }

        Item {
            id: footer

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: VLCStyle.dp(84, VLCStyle.scale)

            Rectangle {
                anchors.fill: parent
                color: "#121212"
            }

            Row {
                visible: !root.streaming
                anchors.left: parent.left
                anchors.leftMargin: VLCStyle.dp(28, VLCStyle.scale)
                anchors.right: parent.right
                anchors.rightMargin: VLCStyle.dp(28, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                spacing: VLCStyle.dp(16, VLCStyle.scale)

                Text {
                    width: parent.width - streamBtn.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.stream && root.stream.state === "error" ? root.stream.message
                          : root.selectedIdx >= 0 ? qsTr("Ready: %1").arg(root.torrentName)
                          : qsTr("Check the torrent to choose what to stream")
                    color: root.stream && root.stream.state === "error" ? "#F87171" : "#E5E5E5"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Btn {
                    id: streamBtn

                    anchors.verticalCenter: parent.verticalCenter
                    primary: true
                    icon: VLCIcons.play_filled
                    text: qsTr("Stream")
                    enabled: root.selectedIdx >= 0
                    onClicked: root.startStreaming()
                }
            }

            Column {
                visible: root.streaming
                anchors.left: parent.left
                anchors.leftMargin: VLCStyle.dp(28, VLCStyle.scale)
                anchors.right: cancelBtn.left
                anchors.rightMargin: VLCStyle.dp(20, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                spacing: VLCStyle.dp(8, VLCStyle.scale)

                Text {
                    width: parent.width
                    text: {
                        const s = root.stream
                        if (!s || s.state === "connecting")
                            return qsTr("Connecting to peers…")
                        if (s.state === "metadata")
                            return qsTr("Found %1 — buffering…").arg(s.name)
                        return qsTr("Buffering %1%  •  %2 peers  •  %3").arg(s.bufferPct ?? 0).arg(s.peers ?? 0)
                               .arg(root._speed(s.speedBps ?? 0))
                    }
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: VLCStyle.dp(6, VLCStyle.scale)
                    radius: height / 2
                    color: "#3A3A3A"

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: "#E50914"
                        width: parent.width * ((root.stream ? (root.stream.bufferPct ?? 0) : 0) / 100)

                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }
            }

            Btn {
                id: cancelBtn

                visible: root.streaming
                anchors.right: parent.right
                anchors.rightMargin: VLCStyle.dp(28, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Cancel")
                onClicked: MainCtx.torrentCancel()
            }
        }
    }
}
