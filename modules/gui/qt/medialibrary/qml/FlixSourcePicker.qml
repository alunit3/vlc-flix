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

// flix: "Choose a source": the torrents found for a title, best seeded first, with quality and
// seeder filters. Nothing is downloaded until the user picks one and presses Stream.
Item {
    id: root

    // {title, year, imdbId, isTv}
    property var info: null
    property bool shown: false

    signal streamStarted()

    // --- state -------------------------------------------------------------------------
    property var sources: []
    property bool loading: false
    property string error: ""
    property string selectedId: ""

    property string quality: "any"          // any | 4K | 1080p | 720p | SD
    property int minSeeders: 0
    property string sortBy: "seeders"       // seeders | size | quality
    property bool hideCam: true
    property int season: 1
    property int episode: 1

    // streaming
    property var stream: null               // last status of the helper, null when idle
    // the stream is now playing: closing this window must not stop the helper
    property bool handedOver: false
    readonly property bool streaming: stream !== null && stream.state !== "error" && stream.state !== "cancelled"

    readonly property string displayTitle: info ? (info.title + (info.year > 0 ? " (" + info.year + ")" : "")) : ""

    readonly property var qualityRank: ({ "4K": 4, "1080p": 3, "720p": 2, "480p": 1, "SD": 1, "CAM": 0 })

    function _matchesQuality(q) {
        if (quality === "any")
            return true
        if (quality === "SD")
            return q === "480p" || q === "SD" || q === "CAM"
        return q === quality
    }

    readonly property var filtered: {
        const list = sources.filter(s => _matchesQuality(s.quality)
                                         && (!hideCam || s.quality !== "CAM")
                                         && (s.seeders < 0 ? minSeeders === 0 : s.seeders >= minSeeders))
        const key = sortBy
        list.sort((a, b) => {
            if (key === "size")
                return (b.sizeBytes || 0) - (a.sizeBytes || 0)
            if (key === "quality") {
                const d = (qualityRank[b.quality] ?? 0) - (qualityRank[a.quality] ?? 0)
                return d !== 0 ? d : b.seeders - a.seeders
            }
            return b.seeders - a.seeders
        })
        return list
    }

    // the best seeded 1080p is the suggested pick (fast and good), else simply the best seeded
    readonly property string bestId: {
        let best = null
        for (const s of filtered)
            if (s.quality === "1080p" && (best === null || s.seeders > best.seeders))
                best = s
        if (best === null && filtered.length > 0)
            best = filtered.reduce((a, b) => b.seeders > a.seeders ? b : a)
        return best ? best.id : ""
    }

    readonly property var selected: {
        for (const s of sources)
            if (s.id === selectedId)
                return s
        return null
    }

    function open(entry) {
        closeTimer.stop()
        info = entry
        sources = []
        error = ""
        selectedId = ""
        stream = null
        handedOver = false
        quality = MainCtx.flixPref("picker/quality", "any")
        minSeeders = Number(MainCtx.flixPref("picker/minSeeders", 0))
        sortBy = MainCtx.flixPref("picker/sortBy", "seeders")
        hideCam = MainCtx.flixPref("picker/hideCam", true) === true || MainCtx.flixPref("picker/hideCam", true) === "true"
        shown = true
        forceActiveFocus()
        if (!info.isTv)
            load()
    }

    function close() {
        if (!shown)
            return
        if (streaming && !handedOver)
            MainCtx.torrentCancel()
        shown = false
        closeTimer.restart()
    }

    function load() {
        if (!MainCtx.torrentAvailable()) {
            error = qsTr("The torrent helper is not installed. Build it with flix/build-torrent.ps1.")
            return
        }
        loading = true
        error = ""
        sources = []
        MainCtx.torrentSources(info.imdbId, info.isTv ? season : 0, info.isTv ? episode : 0)
    }

    function startStreaming() {
        if (!selected)
            return
        stream = { state: "connecting" }
        const source = Object.assign({}, selected)
        // what the player needs for subtitles and "continue watching"
        source.title = displayTitle
        source.meta = { title: info.title, year: info.year ?? 0, imdb: info.imdbId ?? "",
                        tmdbId: info.tmdbId ?? 0, poster: info.poster ?? "",
                        mediaType: info.isTv ? "tv" : "movie",
                        season: info.isTv ? season : 0, episode: info.isTv ? episode : 0 }
        MainCtx.torrentStart(source)
    }

    function _speed(bps) {
        return bps >= 1048576 ? (bps / 1048576).toFixed(1) + " MB/s" : Math.round(bps / 1024) + " KB/s"
    }

    onQualityChanged: if (shown) MainCtx.setFlixPref("picker/quality", quality)
    onMinSeedersChanged: if (shown) MainCtx.setFlixPref("picker/minSeeders", minSeeders)
    onSortByChanged: if (shown) MainCtx.setFlixPref("picker/sortBy", sortBy)
    onHideCamChanged: if (shown) MainCtx.setFlixPref("picker/hideCam", hideCam)

    Timer {
        id: closeTimer

        interval: 240
        onTriggered: root.info = null
    }

    Connections {
        target: MainCtx

        function onTorrentSourcesReady(items, err) {
            root.loading = false
            root.error = err
            root.sources = items
            if (items.length > 0 && root.selectedId === "")
                root.selectedId = root.bestId
        }

        function onTorrentStatus(status) {
            if (!root.shown)
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
            if (status.state === "progress" || status.state === "connecting" || status.state === "metadata"
                    || status.state === "error" || status.state === "cancelled")
                root.stream = Object.assign({}, root.stream ?? {}, status)
        }
    }

    visible: info !== null
    z: 120
    opacity: shown ? 1.0 : 0.0

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Keys.onEscapePressed: root.close()

    // dim; eats every mouse event so nothing below can be reached
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

    // a small filter chip
    component Chip: Rectangle {
        id: chip

        property string text
        property bool selected: false

        signal clicked()

        width: chipLabel.implicitWidth + 2 * VLCStyle.dp(14, VLCStyle.scale)
        height: VLCStyle.dp(28, VLCStyle.scale)
        radius: height / 2
        color: selected ? "#FFFFFF" : (chipHover.hovered ? "#3A3A3A" : "#2A2A2A")
        scale: chipTap.pressed ? 0.95 : 1.0

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

        Text {
            id: chipLabel

            anchors.centerIn: parent
            text: chip.text
            color: chip.selected ? "#141414" : "#E5E5E5"
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
            font.weight: Font.DemiBold
        }

        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: chipTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: chip.clicked() }
    }

    component FilterRow: Row {
        property string label

        spacing: VLCStyle.dp(8, VLCStyle.scale)

        Text {
            width: VLCStyle.dp(100, VLCStyle.scale)
            height: VLCStyle.dp(28, VLCStyle.scale)
            verticalAlignment: Text.AlignVCenter
            text: parent.label
            color: "#808080"
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(980, VLCStyle.scale))
        height: Math.min(parent.height - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(720, VLCStyle.scale))
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
            spacing: VLCStyle.dp(10, VLCStyle.scale)

            Text {
                width: parent.width
                text: qsTr("Choose a source")
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(26, VLCStyle.scale)
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: root.displayTitle + "  •  " + qsTr("sorted by seeders: more seeders start faster")
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                elide: Text.ElideRight
            }

            // series: which episode
            FilterRow {
                visible: root.info !== null && root.info.isTv
                label: qsTr("Episode")

                Repeater {
                    model: [{ key: "season", label: qsTr("Season") }, { key: "episode", label: qsTr("Episode") }]

                    delegate: Row {
                        id: numberRow

                        required property var modelData

                        spacing: VLCStyle.dp(6, VLCStyle.scale)

                        Text {
                            height: VLCStyle.dp(28, VLCStyle.scale)
                            verticalAlignment: Text.AlignVCenter
                            text: numberRow.modelData.label
                            color: "#B3B3B3"
                            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                        }

                        Rectangle {
                            width: VLCStyle.dp(56, VLCStyle.scale)
                            height: VLCStyle.dp(28, VLCStyle.scale)
                            radius: height / 2
                            color: "#2A2A2A"

                            TextInput {
                                anchors.fill: parent
                                anchors.leftMargin: VLCStyle.dp(12, VLCStyle.scale)
                                anchors.rightMargin: VLCStyle.dp(12, VLCStyle.scale)
                                verticalAlignment: TextInput.AlignVCenter
                                color: "#FFFFFF"
                                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                                validator: IntValidator { bottom: 1; top: 999 }
                                text: String(numberRow.modelData.key === "season" ? root.season : root.episode)
                                onEditingFinished: {
                                    const v = Math.max(1, Number(text) || 1)
                                    if (numberRow.modelData.key === "season")
                                        root.season = v
                                    else
                                        root.episode = v
                                }
                            }
                        }
                    }
                }

                Chip { text: qsTr("Find sources"); selected: true; onClicked: root.load() }
            }

            FilterRow {
                label: qsTr("Quality")

                Repeater {
                    model: ["any", "4K", "1080p", "720p", "SD"]

                    delegate: Chip {
                        required property string modelData

                        text: modelData === "any" ? qsTr("Any") : modelData
                        selected: root.quality === modelData
                        onClicked: root.quality = modelData
                    }
                }
            }

            FilterRow {
                label: qsTr("Min seeders")

                Repeater {
                    model: [0, 5, 20, 50, 100]

                    delegate: Chip {
                        required property int modelData

                        text: modelData === 0 ? qsTr("Any") : modelData + "+"
                        selected: root.minSeeders === modelData
                        onClicked: root.minSeeders = modelData
                    }
                }
            }

            FilterRow {
                label: qsTr("Sort by")

                Repeater {
                    model: [{ id: "seeders", label: qsTr("Seeders") },
                            { id: "size", label: qsTr("Size") },
                            { id: "quality", label: qsTr("Quality") }]

                    delegate: Chip {
                        required property var modelData

                        text: modelData.label
                        selected: root.sortBy === modelData.id
                        onClicked: root.sortBy = modelData.id
                    }
                }

                Chip { text: qsTr("Hide CAM / TS"); selected: root.hideCam; onClicked: root.hideCam = !root.hideCam }
            }
        }

        // close
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

        // the list
        ListView {
            id: list

            anchors.top: head.bottom
            anchors.topMargin: VLCStyle.dp(14, VLCStyle.scale)
            anchors.bottom: footer.top
            anchors.bottomMargin: VLCStyle.dp(8, VLCStyle.scale)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: VLCStyle.dp(28, VLCStyle.scale)
            anchors.rightMargin: VLCStyle.dp(28, VLCStyle.scale)
            clip: true
            spacing: VLCStyle.dp(6, VLCStyle.scale)
            model: root.filtered
            boundsBehavior: Flickable.StopAtBounds

            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 } }
            displaced: Transition { NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic } }

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                readonly property bool isSelected: root.selectedId === modelData.id
                readonly property bool isBest: root.bestId === modelData.id

                width: list.width
                height: VLCStyle.dp(62, VLCStyle.scale)
                radius: VLCStyle.dp(6, VLCStyle.scale)
                color: isSelected ? "#2E2E2E" : (rowHover.hovered ? "#262626" : "#202020")
                border.width: isSelected ? 1 : 0
                border.color: "#E50914"

                Behavior on color { ColorAnimation { duration: 140 } }

                // quality badge
                Rectangle {
                    id: badge

                    x: VLCStyle.dp(12, VLCStyle.scale)
                    anchors.verticalCenter: parent.verticalCenter
                    width: VLCStyle.dp(58, VLCStyle.scale)
                    height: VLCStyle.dp(26, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: row.modelData.quality === "4K" ? "#7C3AED"
                         : row.modelData.quality === "1080p" ? "#2563EB"
                         : row.modelData.quality === "720p" ? "#0F766E"
                         : row.modelData.quality === "CAM" ? "#7F1D1D" : "#4B5563"

                    Text {
                        anchors.centerIn: parent
                        text: row.modelData.quality
                        color: "#FFFFFF"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                        font.weight: Font.Bold
                    }
                }

                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: VLCStyle.dp(14, VLCStyle.scale)
                    anchors.right: seeds.left
                    anchors.rightMargin: VLCStyle.dp(10, VLCStyle.scale)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: VLCStyle.dp(3, VLCStyle.scale)

                    Row {
                        spacing: VLCStyle.dp(8, VLCStyle.scale)
                        width: parent.width

                        Rectangle {
                            visible: row.isBest
                            anchors.verticalCenter: parent.verticalCenter
                            width: bestLabel.implicitWidth + VLCStyle.dp(12, VLCStyle.scale)
                            height: VLCStyle.dp(18, VLCStyle.scale)
                            radius: VLCStyle.dp(3, VLCStyle.scale)
                            color: "#E50914"

                            Text {
                                id: bestLabel

                                anchors.centerIn: parent
                                text: qsTr("BEST PICK")
                                color: "#FFFFFF"
                                font.pixelSize: VLCStyle.dp(10, VLCStyle.scale)
                                font.weight: Font.Bold
                            }
                        }

                        Text {
                            width: parent.width - (row.isBest ? VLCStyle.dp(80, VLCStyle.scale) : 0)
                            text: row.modelData.name
                            color: "#FFFFFF"
                            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                        }
                    }

                    Text {
                        width: parent.width
                        text: [row.modelData.sizeText, row.modelData.source, row.modelData.languages]
                              .filter(t => t && t !== "").join("   •   ")
                        color: "#808080"
                        font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                        elide: Text.ElideRight
                    }
                }

                // seeders, coloured: green = fast start
                Text {
                    id: seeds

                    anchors.right: parent.right
                    anchors.rightMargin: VLCStyle.dp(16, VLCStyle.scale)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "👤 " + (row.modelData.seeders >= 0 ? row.modelData.seeders : "?")
                    color: row.modelData.seeders >= 50 ? "#34D399" : row.modelData.seeders >= 10 ? "#FBBF24" : "#F87171"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    font.weight: Font.Bold
                }

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: if (!root.streaming) root.selectedId = row.modelData.id
                    onDoubleTapped: if (!root.streaming) { root.selectedId = row.modelData.id; root.startStreaming() }
                }
            }
        }

        // empty / loading / error
        Row {
            anchors.centerIn: list
            spacing: VLCStyle.dp(12, VLCStyle.scale)
            visible: root.loading || (root.filtered.length === 0 && !(root.info && root.info.isTv && root.sources.length === 0 && root.error === ""))

            Item {
                id: spinner

                visible: root.loading
                width: VLCStyle.dp(22, VLCStyle.scale)
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
                    width: VLCStyle.dp(6, VLCStyle.scale)
                    height: width
                    radius: width / 2
                    color: "#E50914"
                    x: parent.width / 2 - width / 2
                    y: -height / 4

                    transform: Rotation {
                        origin.x: VLCStyle.dp(3, VLCStyle.scale)
                        origin.y: VLCStyle.dp(14, VLCStyle.scale)
                        angle: spinner.spin
                    }
                }

                NumberAnimation on spin { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.loading }
            }

            Text {
                text: root.loading ? qsTr("Looking for sources…")
                    : root.error !== "" ? root.error
                    : root.sources.length > 0 ? qsTr("Nothing matches these filters. Try a lower quality or fewer seeders.")
                    : qsTr("No sources found for this title.")
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
            }
        }

        // footer: selection / buffering
        Item {
            id: footer

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: VLCStyle.dp(86, VLCStyle.scale)

            Rectangle {
                anchors.fill: parent
                color: "#121212"
            }

            // idle: what is selected + Stream
            Row {
                visible: !root.streaming
                anchors.left: parent.left
                anchors.leftMargin: VLCStyle.dp(28, VLCStyle.scale)
                anchors.right: parent.right
                anchors.rightMargin: VLCStyle.dp(28, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                spacing: VLCStyle.dp(16, VLCStyle.scale)

                Text {
                    width: parent.width - streamButton.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.stream && root.stream.state === "error"
                          ? root.stream.message
                          : root.selected ? qsTr("Selected: %1 • %2 • %3 seeders")
                                              .arg(root.selected.quality).arg(root.selected.sizeText || "?")
                                              .arg(root.selected.seeders >= 0 ? root.selected.seeders : "?")
                                          : qsTr("Pick a source from the list")
                    color: root.stream && root.stream.state === "error" ? "#F87171" : "#E5E5E5"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: streamButton

                    anchors.verticalCenter: parent.verticalCenter
                    enabled: root.selected !== null
                    opacity: enabled ? 1.0 : 0.4
                    width: streamLabel.implicitWidth + streamIcon.implicitWidth + VLCStyle.dp(8, VLCStyle.scale)
                           + 2 * VLCStyle.dp(26, VLCStyle.scale)
                    height: VLCStyle.dp(42, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: streamHover.hovered ? "#BFBFBF" : "#FFFFFF"
                    scale: streamTap.pressed ? 0.96 : (streamHover.hovered ? 1.03 : 1.0)

                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    Text {
                        id: streamIcon

                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: streamLabel.left
                        anchors.rightMargin: VLCStyle.dp(8, VLCStyle.scale)
                        text: VLCIcons.play_filled
                        font.family: VLCIcons.fontFamily
                        color: "#141414"
                        font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    }

                    Text {
                        id: streamLabel

                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: (streamIcon.implicitWidth + VLCStyle.dp(8, VLCStyle.scale)) / 2
                        text: qsTr("Stream this source")
                        color: "#141414"
                        font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                        font.weight: Font.Bold
                    }

                    HoverHandler { id: streamHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: streamTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: root.startStreaming() }
                }
            }

            // buffering
            Column {
                visible: root.streaming
                anchors.left: parent.left
                anchors.leftMargin: VLCStyle.dp(28, VLCStyle.scale)
                anchors.right: cancelButton.left
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

            Rectangle {
                id: cancelButton

                visible: root.streaming
                anchors.right: parent.right
                anchors.rightMargin: VLCStyle.dp(28, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                width: cancelLabel.implicitWidth + 2 * VLCStyle.dp(24, VLCStyle.scale)
                height: VLCStyle.dp(42, VLCStyle.scale)
                radius: VLCStyle.dp(4, VLCStyle.scale)
                color: cancelHover.hovered ? Qt.rgba(0.43, 0.43, 0.45, 0.55) : Qt.rgba(0.43, 0.43, 0.45, 0.7)

                Behavior on color { ColorAnimation { duration: 160 } }

                Text {
                    id: cancelLabel

                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    font.weight: Font.Bold
                }

                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: MainCtx.torrentCancel()
                }
            }
        }
    }
}
