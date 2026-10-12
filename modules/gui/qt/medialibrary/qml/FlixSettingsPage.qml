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
import VLC.MediaLibrary
import VLC.Style

// VLCFlix settings: accounts, library, subtitles, playback, torrents, storage. These are VLCFlix's
// own settings, not VLC's native preferences. Values live in the VLC settings file (flix-* /
// flixsubs-* options, so the background services see them) or in flix-prefs.ini (UI choices).
Item {
    id: root

    property bool shown: false
    property bool ready: false              // on screen (kept until the exit animation ends)
    property string section: "accounts"

    // ---- state shown in the pages ----------------------------------------------------------
    property string tmdbStatus: ""
    property bool tmdbStatusOk: false
    property bool tmdbSaved: false
    property string osStatus: ""
    property bool osStatusOk: false
    property bool osPassSaved: false
    property string osKey: ""
    property string osUser: ""
    property string metaLang: "en-US"
    property string top10: "torrents"
    property bool subsAuto: true
    property bool subsAsk: true
    property string subsLangs: ""
    property string defaultProvider: "VidStuck"
    property var providerNames: []
    property bool showHud: true
    property string quality: "any"
    property string minSeeders: "0"
    property string sortBy: "seeders"
    property bool hideCam: true
    property string rateDown: "0"
    property string rateUp: "0"
    property bool streamOnly: true
    property string streamWindow: "33554432"
    property string networkCaching: "4000"
    property string progressWhere: "both"

    // speed caps in bytes/s, "0" being unlimited; the chips are the usual picks, the
    // fields next to them take anything else in KB/s
    readonly property var ratePresets: [
        { value: "0", text: qsTr("Unlimited") }, { value: "1048576", text: "1 MB/s" },
        { value: "5242880", text: "5 MB/s" }, { value: "10485760", text: "10 MB/s" },
        { value: "26214400", text: "25 MB/s" }, { value: "52428800", text: "50 MB/s" }
    ]

    property var storage: []
    property string confirming: ""          // storage kind waiting for a second click
    property string message: ""
    property string trackerMessage: ""

    function _bool(value) {
        return value === true || value === "true"
    }

    function load() {
        tmdbSaved = MainCtx.hasVlcOption("flix-tmdb-token")
        osKey = MainCtx.vlcOption("flixsubs-api-key") || ""
        osUser = MainCtx.vlcOption("flixsubs-user") || ""
        osPassSaved = MainCtx.hasVlcOption("flixsubs-password")
        metaLang = MainCtx.vlcOption("flix-meta-language") || "en-US"
        top10 = MainCtx.vlcOption("flix-top10-target") || "torrents"
        subsAuto = MainCtx.vlcOption("flixsubs-auto") !== false
        subsAsk = MainCtx.vlcOption("flixsubs-ask") !== false
        subsLangs = MainCtx.vlcOption("flixsubs-languages") || ""
        defaultProvider = String(MainCtx.flixPref("web/default", "VidStuck"))
        providerNames = MainCtx.webProviders().map(p => p.name)
        showHud = String(MainCtx.flixPref("torrent/hud", "shown")) !== "hidden"
        quality = String(MainCtx.flixPref("picker/quality", "any"))
        minSeeders = String(MainCtx.flixPref("picker/minSeeders", 0))
        sortBy = String(MainCtx.flixPref("picker/sortBy", "seeders"))
        hideCam = _bool(MainCtx.flixPref("picker/hideCam", true))
        rateDown = String(MainCtx.flixPref("torrent/rateDown", 0))
        rateUp = String(MainCtx.flixPref("torrent/rateUp", 0))
        rateDownField.text = _kb(rateDown)
        rateUpField.text = _kb(rateUp)
        streamOnly = String(MainCtx.flixPref("torrent/streamOnly", true)) !== "false"
        streamWindow = String(MainCtx.flixPref("torrent/streamWindow", 33554432))
        networkCaching = String(MainCtx.flixPref("torrent/networkCaching", 4000))
        progressWhere = String(MainCtx.flixPref("torrent/progressWhere", "both"))
        tmdbStatus = ""
        osStatus = ""
        message = ""
        trackerMessage = ""
        confirming = ""
        trackerInput.text = MainCtx.userTrackers()
        tmdbField.text = ""
        osKeyField.text = osKey
        osUserField.text = osUser
        osPassField.text = ""
        langsField.text = subsLangs
        refreshStorage()
    }

    function open(name) {
        closeTimer.stop()
        ready = true
        shown = true
        if (name)
            section = name
        load()
        forceActiveFocus()
    }

    function close() {
        if (!shown)
            return
        shown = false
        closeTimer.restart()
    }

    function refreshStorage() {
        storage = MainCtx.storageInfo()
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
        // A refused clear means something is genuinely playing out of these files now,
        // which is a different answer from the one this used to give in every case.
        message = ok ? qsTr("Cleared.")
                     : (kind === "torrentData" ? qsTr("A torrent is playing right now. Stop it and try again.")
                                               : qsTr("The web player is running. Close it and try again."))
        refreshStorage()
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
        refreshStorage()
    }

    function saveTrackers() {
        const r = MainCtx.setUserTrackers(trackerInput.text)
        trackerMessage = r.saved ? qsTr("Saved. Used by the next torrent you start.")
                                 : qsTr("Not saved, invalid line: %1").arg(r.invalid[0])
    }

    // a stored cap in KB/s, or "" when it is unlimited or already one of the chips
    function _kb(bytes) {
        const v = Number(bytes)
        if (!isFinite(v) || v <= 0)
            return ""
        return root.ratePresets.some(p => p.value === String(v)) ? "" : String(Math.round(v / 1024))
    }

    function saveRate(which, value) {
        const bytes = Math.max(0, Math.floor(Number(value)) || 0)
        if (which === "down") {
            root.rateDown = String(bytes)
            MainCtx.setFlixPref("torrent/rateDown", bytes)
            rateDownField.text = _kb(bytes)
        } else {
            root.rateUp = String(bytes)
            MainCtx.setFlixPref("torrent/rateUp", bytes)
            rateUpField.text = _kb(bytes)
        }
    }

    // a value typed in KB/s; empty or unreadable means unlimited
    function rateFromField(field) {
        const kb = Number(field.text)
        if (!isFinite(kb) || kb <= 0)
            return "0"
        return String(kb * 1024)
    }

    function testTmdb() {
        const typed = tmdbField.text.trim()
        if (typed === "" && !tmdbSaved) {
            tmdbStatus = qsTr("Enter the token first.")
            tmdbStatusOk = false
            return
        }
        tmdbStatus = qsTr("Checking...")
        tmdbStatusOk = true
        MainCtx.testAccount({ kind: "tmdb", token: typed })
    }

    function loginOpenSubtitles() {
        const key = osKeyField.text.trim()
        const user = osUserField.text.trim()
        if (key === "" || user === "" || (osPassField.text === "" && !osPassSaved)) {
            osStatus = qsTr("Enter the API key, username and password.")
            osStatusOk = false
            return
        }
        osStatus = qsTr("Logging in...")
        osStatusOk = true
        MainCtx.testAccount({ kind: "opensubtitles", key: key, user: user, password: osPassField.text })
    }

    Connections {
        target: MainCtx

        // a stream starting or stopping changes whether the torrent data can be cleared,
        // and the sizes change with it
        function onTorrentActiveChanged() {
            if (storage.length > 0)
                root.refreshStorage()
        }

        // the answer of the Lua service; a good account is kept right away
        function onAccountTestResult(kind, ok, text) {
            if (kind === "tmdb") {
                root.tmdbStatus = text
                root.tmdbStatusOk = ok
                if (ok && tmdbField.text.trim() !== "") {
                    MainCtx.setVlcOption("flix-tmdb-token", tmdbField.text.trim())
                    tmdbField.text = ""
                    root.tmdbSaved = true
                    root.tmdbStatus = qsTr("TMDB accepted the token. Saved.")
                }
            } else if (kind === "opensubtitles") {
                root.osStatus = text
                root.osStatusOk = ok
                if (ok) {
                    MainCtx.setVlcOption("flixsubs-api-key", osKeyField.text.trim())
                    MainCtx.setVlcOption("flixsubs-user", osUserField.text.trim())
                    if (osPassField.text !== "")
                        MainCtx.setVlcOption("flixsubs-password", osPassField.text)
                    osPassField.text = ""
                    root.osPassSaved = true
                    root.osStatus = text + qsTr(". Saved.")
                }
            }
        }
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

    // ---- small building blocks -------------------------------------------------------------
    property bool confirmClearWatching: false

    MLRecentMediaModel {
        id: recentsForClear

        ml: MediaLib
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

    // a text box with a label and a hint; secret fields show dots
    component Field: Column {
        id: field

        property string label
        property string hint
        property string placeholder
        property bool secret: false
        property alias text: input.text

        signal committed()

        width: parent ? parent.width : 0
        spacing: VLCStyle.dp(6, VLCStyle.scale)

        Text {
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
        }
    }

    // an on / off switch with a label
    component Toggle: Item {
        id: toggle

        property string label
        property string hint
        property bool checked: false

        signal toggled(bool value)

        width: parent ? parent.width : 0
        height: Math.max(VLCStyle.dp(40, VLCStyle.scale), texts.implicitHeight + VLCStyle.dp(8, VLCStyle.scale))

        Column {
            id: texts

            anchors.left: parent.left
            anchors.right: track.left
            anchors.rightMargin: VLCStyle.dp(16, VLCStyle.scale)
            anchors.verticalCenter: parent.verticalCenter
            spacing: VLCStyle.dp(2, VLCStyle.scale)

            Text {
                width: parent.width
                text: toggle.label
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                font.weight: Font.DemiBold
            }

            Text {
                visible: toggle.hint !== ""
                width: parent.width
                text: toggle.hint
                color: "#808080"
                font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            id: track

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: VLCStyle.dp(44, VLCStyle.scale)
            height: VLCStyle.dp(24, VLCStyle.scale)
            radius: height / 2
            color: toggle.checked ? "#E50914" : "#4D4D4D"

            Behavior on color { ColorAnimation { duration: 160 } }

            Rectangle {
                width: parent.height - VLCStyle.dp(6, VLCStyle.scale)
                height: width
                radius: width / 2
                y: VLCStyle.dp(3, VLCStyle.scale)
                x: toggle.checked ? parent.width - width - VLCStyle.dp(3, VLCStyle.scale) : VLCStyle.dp(3, VLCStyle.scale)
                color: "#FFFFFF"

                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: toggle.toggled(!toggle.checked) }
        }
    }

    // one value out of a few, shown as chips; options: [{value, text}]
    component Choice: Column {
        id: choice

        property string label
        property string hint
        property var options: []
        property string current

        signal picked(string value)

        width: parent ? parent.width : 0
        spacing: VLCStyle.dp(8, VLCStyle.scale)

        Text {
            text: choice.label
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            font.weight: Font.DemiBold
        }

        Flow {
            width: parent.width
            spacing: VLCStyle.dp(8, VLCStyle.scale)

            Repeater {
                model: choice.options

                delegate: Rectangle {
                    id: chip

                    required property var modelData

                    readonly property bool selected: String(modelData.value) === choice.current

                    width: chipLabel.implicitWidth + 2 * VLCStyle.dp(14, VLCStyle.scale)
                    height: VLCStyle.dp(30, VLCStyle.scale)
                    radius: height / 2
                    color: selected ? "#FFFFFF" : (chipHover.hovered ? "#3A3A3A" : "#2A2A2A")
                    scale: chipTap.pressed ? 0.95 : 1.0

                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    Text {
                        id: chipLabel

                        anchors.centerIn: parent
                        text: chip.modelData.text
                        color: chip.selected ? "#141414" : "#E5E5E5"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                        font.weight: Font.DemiBold
                    }

                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: chipTap

                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: choice.picked(String(chip.modelData.value))
                    }
                }
            }
        }

        Text {
            visible: choice.hint !== ""
            width: parent.width
            text: choice.hint
            color: "#808080"
            font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
            wrapMode: Text.WordWrap
        }
    }

    // a scrolling page of the right-hand side
    component Page: Flickable {
        id: page

        required property string name
        property bool current: false
        default property alias content: col.data

        anchors.fill: parent
        visible: opacity > 0
        opacity: current ? 1.0 : 0.0
        enabled: current
        contentWidth: width
        contentHeight: col.height + VLCStyle.dp(24, VLCStyle.scale)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Behavior on opacity { NumberAnimation { duration: 160 } }

        Column {
            id: col

            width: page.width - VLCStyle.dp(16, VLCStyle.scale)
            spacing: VLCStyle.dp(18, VLCStyle.scale)
        }
    }

    component Heading: Text {
        width: parent ? parent.width : 0
        color: "#FFFFFF"
        font.pixelSize: VLCStyle.dp(22, VLCStyle.scale)
        font.weight: Font.Bold
        wrapMode: Text.WordWrap
    }

    component Note: Text {
        width: parent ? parent.width : 0
        color: "#B3B3B3"
        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
        wrapMode: Text.WordWrap
    }

    // ---- the window ------------------------------------------------------------------------
    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(980, VLCStyle.scale))
        height: Math.min(parent.height - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(660, VLCStyle.scale))
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

        // left: sections
        Rectangle {
            id: sidebar

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: VLCStyle.dp(210, VLCStyle.scale)
            color: "#121212"

            Text {
                x: VLCStyle.dp(22, VLCStyle.scale)
                y: VLCStyle.dp(22, VLCStyle.scale)
                text: "VLCFLIX"
                color: "#E50914"
                font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
                font.weight: Font.Black
                font.letterSpacing: VLCStyle.dp(1, VLCStyle.scale)
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: VLCStyle.dp(70, VLCStyle.scale)

                Repeater {
                    model: [
                        { key: "accounts", text: qsTr("Accounts") },
                        { key: "library", text: qsTr("Library & metadata") },
                        { key: "subtitles", text: qsTr("Subtitles") },
                        { key: "playback", text: qsTr("Playback") },
                        { key: "torrents", text: qsTr("Torrents") },
                        { key: "storage", text: qsTr("Storage") },
                        { key: "about", text: qsTr("About") }
                    ]

                    delegate: Rectangle {
                        id: navItem

                        required property var modelData

                        readonly property bool selected: root.section === modelData.key

                        width: sidebar.width
                        height: VLCStyle.dp(42, VLCStyle.scale)
                        color: selected ? "#242424" : (navHover.hovered ? "#1C1C1C" : "transparent")

                        Behavior on color { ColorAnimation { duration: 140 } }

                        Rectangle {
                            width: VLCStyle.dp(3, VLCStyle.scale)
                            height: parent.height
                            color: "#E50914"
                            opacity: navItem.selected ? 1.0 : 0.0

                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: VLCStyle.dp(22, VLCStyle.scale)
                            anchors.verticalCenter: parent.verticalCenter
                            text: navItem.modelData.text
                            color: navItem.selected ? "#FFFFFF" : "#B3B3B3"
                            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                            font.weight: navItem.selected ? Font.DemiBold : Font.Normal
                        }

                        HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: {
                                root.section = navItem.modelData.key
                                if (navItem.modelData.key === "storage")
                                    root.refreshStorage()
                            }
                        }
                    }
                }
            }
        }

        // close
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: VLCStyle.dp(14, VLCStyle.scale)
            width: VLCStyle.dp(32, VLCStyle.scale)
            height: width
            radius: width / 2
            color: closeHover.hovered ? Qt.rgba(0.3, 0.3, 0.3, 0.95) : Qt.rgba(0.08, 0.08, 0.08, 0.85)
            z: 2

            Behavior on color { ColorAnimation { duration: 140 } }

            Text {
                anchors.centerIn: parent
                text: VLCIcons.close
                font.family: VLCIcons.fontFamily
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            }

            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: root.close() }
        }

        // right: pages
        Item {
            id: pages

            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: VLCStyle.dp(28, VLCStyle.scale)
            anchors.rightMargin: VLCStyle.dp(20, VLCStyle.scale)
            anchors.topMargin: VLCStyle.dp(24, VLCStyle.scale)
            anchors.bottomMargin: VLCStyle.dp(16, VLCStyle.scale)

            // ---- accounts ----
            Page {
                name: "accounts"
                current: root.section === "accounts"

                Heading { text: qsTr("Accounts") }
                Note {
                    text: qsTr("Your keys stay on this PC, in the VLC settings file. They are only sent to TMDB and OpenSubtitles.")
                }

                Field {
                    id: tmdbField

                    label: qsTr("TMDB access token")
                    secret: true
                    placeholder: root.tmdbSaved ? qsTr("A token is saved (hidden). Type a new one to replace it.") : qsTr("Paste your TMDB read access token")
                    hint: qsTr("Free at themoviedb.org/settings/api. Needed for posters, synopses, search and the Top 10.")
                }

                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    Btn { primary: true; text: qsTr("Test and save"); onClicked: root.testTmdb() }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tmdbStatus
                        color: root.tmdbStatusOk ? "#34D399" : "#F87171"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                    }
                }

                Rectangle { width: parent.width; height: 1; color: "#333333" }

                Field {
                    id: osKeyField

                    label: qsTr("OpenSubtitles API key")
                    placeholder: qsTr("API consumer key")
                    hint: qsTr("Create a consumer at opensubtitles.com/consumers.")
                }

                Field { id: osUserField; label: qsTr("OpenSubtitles username"); placeholder: qsTr("Username") }

                Field {
                    id: osPassField

                    label: qsTr("OpenSubtitles password")
                    secret: true
                    placeholder: root.osPassSaved ? qsTr("A password is saved (hidden). Leave empty to keep it.") : qsTr("Password")
                }

                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    Btn { primary: true; text: qsTr("Log in"); onClicked: root.loginOpenSubtitles() }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.osStatus
                        color: root.osStatusOk ? "#34D399" : "#F87171"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                    }
                }
            }

            // ---- library & metadata ----
            Page {
                name: "library"
                current: root.section === "library"

                Heading { text: qsTr("Library & metadata") }

                Choice {
                    label: qsTr("Synopsis and title language")
                    hint: qsTr("Language of the text TMDB sends. Applies to titles loaded from now on.")
                    current: root.metaLang
                    options: [
                        { value: "en-US", text: "English" }, { value: "id-ID", text: "Indonesian" },
                        { value: "es-ES", text: "Spanish" }, { value: "fr-FR", text: "French" },
                        { value: "de-DE", text: "German" }, { value: "pt-BR", text: "Portuguese (Brazil)" },
                        { value: "it-IT", text: "Italian" }, { value: "ja-JP", text: "Japanese" },
                        { value: "ko-KR", text: "Korean" }, { value: "zh-CN", text: "Chinese" }
                    ]
                    onPicked: (value) => { root.metaLang = value; MainCtx.setVlcOption("flix-meta-language", value) }
                }

                Choice {
                    label: qsTr("Clicking a Top 10 title opens")
                    current: root.top10
                    options: [{ value: "torrents", text: qsTr("More Info (torrents)") }, { value: "imdb", text: "IMDb" }]
                    onPicked: (value) => { root.top10 = value; MainCtx.setVlcOption("flix-top10-target", value) }
                }

                Choice {
                    label: qsTr("Default online player (Watch online)")
                    hint: qsTr("The provider that opens first. The full list is editable in:\n%1").arg(MainCtx.providersFile())
                    current: root.defaultProvider
                    options: root.providerNames.map(n => ({ value: n, text: n }))
                    onPicked: (value) => { root.defaultProvider = value; MainCtx.setFlixPref("web/default", value) }
                }

                Btn {
                    text: qsTr("Reset the provider list")
                    onClicked: { MainCtx.resetWebProviders(); root.providerNames = MainCtx.webProviders().map(p => p.name) }
                }
            }

            // ---- subtitles ----
            Page {
                name: "subtitles"
                current: root.section === "subtitles"

                Heading { text: qsTr("Subtitles") }

                Toggle {
                    label: qsTr("Look for subtitles automatically")
                    hint: qsTr("When a video starts without subtitles, search OpenSubtitles (needs the account).")
                    checked: root.subsAuto
                    onToggled: (value) => { root.subsAuto = value; MainCtx.setVlcOption("flixsubs-auto", value) }
                }

                Toggle {
                    label: qsTr("Ask before downloading")
                    hint: qsTr("Shows \"Download / Not now\" first. Off: the best match is added at once.")
                    checked: root.subsAsk
                    onToggled: (value) => { root.subsAsk = value; MainCtx.setVlcOption("flixsubs-ask", value) }
                }

                Field {
                    id: langsField

                    label: qsTr("Subtitle languages")
                    placeholder: "en,id"
                    hint: qsTr("Up to three language codes, best first. Empty: the language of Windows.")
                    onCommitted: { root.subsLangs = text; MainCtx.setVlcOption("flixsubs-languages", text) }
                }

                Note { text: qsTr("The account for downloads is in Accounts. The same login is in Subtitle > Find Subtitles Online.") }
            }

            // ---- playback ----
            Page {
                name: "playback"
                current: root.section === "playback"

                Heading { text: qsTr("Playback") }

                Toggle {
                    label: qsTr("Show the torrent speed box in the player")
                    hint: qsTr("Download and upload speed, peers and cache while a torrent plays. You can also hide it with its x.")
                    checked: root.showHud
                    onToggled: (value) => { root.showHud = value; MainCtx.setFlixPref("torrent/hud", value ? "shown" : "hidden") }
                }

                // forget what is in "Continue Watching" on Home (never touches the files themselves)
                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    Btn {
                        text: root.confirmClearWatching ? qsTr("Yes, clear it") : qsTr("Clear Continue Watching")
                        danger: root.confirmClearWatching
                        onClicked: {
                            if (!root.confirmClearWatching) {
                                root.confirmClearWatching = true
                                return
                            }
                            root.confirmClearWatching = false
                            MainCtx.setFlixPref("resume/imported", "1")
                            MainCtx.clearResume()
                            recentsForClear.clearHistory()
                        }
                    }

                    Btn {
                        visible: root.confirmClearWatching
                        text: qsTr("Cancel")
                        onClicked: root.confirmClearWatching = false
                    }
                }

                Note {
                    text: qsTr("Continue watching is automatic: VLCFlix remembers where you stopped (library files, torrents and online players) and offers \"Start over\" when it resumes.")
                }
            }

            // ---- torrents ----
            Page {
                name: "torrents"
                current: root.section === "torrents"

                Heading { text: qsTr("Torrents") }

                Choice {
                    label: qsTr("Preferred quality in the source list")
                    current: root.quality
                    options: [{ value: "any", text: qsTr("Any") }, { value: "4K", text: "4K" }, { value: "1080p", text: "1080p" },
                              { value: "720p", text: "720p" }, { value: "SD", text: "SD" }]
                    onPicked: (value) => { root.quality = value; MainCtx.setFlixPref("picker/quality", value) }
                }

                Choice {
                    label: qsTr("Minimum seeders")
                    current: root.minSeeders
                    options: [{ value: "0", text: qsTr("Any") }, { value: "5", text: "5+" }, { value: "20", text: "20+" },
                              { value: "50", text: "50+" }, { value: "100", text: "100+" }]
                    onPicked: (value) => { root.minSeeders = value; MainCtx.setFlixPref("picker/minSeeders", Number(value)) }
                }

                Choice {
                    label: qsTr("Sort sources by")
                    current: root.sortBy
                    options: [{ value: "seeders", text: qsTr("Seeders") }, { value: "size", text: qsTr("Size") }, { value: "quality", text: qsTr("Quality") }]
                    onPicked: (value) => { root.sortBy = value; MainCtx.setFlixPref("picker/sortBy", value) }
                }

                Toggle {
                    label: qsTr("Hide CAM and telesync releases")
                    checked: root.hideCam
                    onToggled: (value) => { root.hideCam = value; MainCtx.setFlixPref("picker/hideCam", value) }
                }

                Rectangle { width: parent.width; height: 1; color: "#333333" }

                Choice {
                    label: qsTr("How much to download")
                    hint: qsTr("Stream fetches only what the player is about to need and keeps nothing beyond it, so a film is never downloaded ahead of you. Download gets the whole file and keeps it on disk. Read when a stream starts.")
                    current: root.streamOnly ? "stream" : "download"
                    options: [{ value: "stream", text: qsTr("Stream (buffer only)") },
                              { value: "download", text: qsTr("Download the whole film") }]
                    onPicked: (value) => {
                        root.streamOnly = value === "stream"
                        MainCtx.setFlixPref("torrent/streamOnly", root.streamOnly)
                    }
                }

                Choice {
                    label: qsTr("How far ahead to buffer")
                    visible: root.streamOnly
                    hint: qsTr("A bigger buffer rides out a slow connection but holds more of the film on disk. Leave it alone unless playback stalls.")
                    current: root.streamWindow
                    options: [{ value: "8388608", text: "8 MB" }, { value: "33554432", text: "32 MB" },
                              { value: "134217728", text: "128 MB" }]
                    onPicked: (value) => { root.streamWindow = value; MainCtx.setFlixPref("torrent/streamWindow", Number(value)) }
                }

                Choice {
                    label: qsTr("Player buffer")
                    hint: qsTr("How much playback to hold in memory before starting. A torrent hands over its data a piece at a time, so this needs to be longer than the stock one second or the audio runs dry and crackles. Raise it if a slow swarm still stutters; 0 leaves the player default alone.")
                    current: root.networkCaching
                    options: [{ value: "0", text: qsTr("Player default") }, { value: "4000", text: "4 s" },
                              { value: "8000", text: "8 s" }, { value: "15000", text: "15 s" }]
                    onPicked: (value) => { root.networkCaching = value; MainCtx.setFlixPref("torrent/networkCaching", Number(value)) }
                }

                Choice {
                    label: qsTr("Show the download progress")
                    hint: qsTr("In the seek bar it is the lighter run ahead of the playhead, like on a video site. In the stats box it is a percentage and a bar next to the speeds.")
                    current: root.progressWhere
                    options: [{ value: "both", text: qsTr("Both") }, { value: "bar", text: qsTr("Seek bar only") },
                              { value: "hud", text: qsTr("Stats box only") }, { value: "none", text: qsTr("Nowhere") }]
                    onPicked: (value) => { root.progressWhere = value; MainCtx.setFlixPref("torrent/progressWhere", value) }
                }

                Rectangle { width: parent.width; height: 1; color: "#333333" }

                Text {
                    text: qsTr("Speed limits")
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    font.weight: Font.Bold
                }

                Note {
                    text: qsTr("How much VLCFlix takes from peers, and how much it sends back to them. Unlimited unless you set a cap here. Saving applies to the next torrent you start.")
                }

                Choice {
                    label: qsTr("Download limit")
                    hint: qsTr("A low cap keeps VLCFlix out of a busy connection; the video needs roughly 1-4 MB/s.")
                    current: root.rateDown
                    options: root.ratePresets
                    onPicked: (value) => root.saveRate("down", value)
                }

                Field {
                    id: rateDownField

                    label: qsTr("…or a custom download limit (KB/s)")
                    placeholder: qsTr("Unlimited — e.g. 750")
                    hint: qsTr("Leave empty for no limit. Press Enter or click away to save.")
                    onCommitted: root.saveRate("down", root.rateFromField(rateDownField))
                }

                Choice {
                    label: qsTr("Upload limit")
                    hint: qsTr("Sending is not needed to play the video. A cap is the polite thing to do on a shared line.")
                    current: root.rateUp
                    options: root.ratePresets
                    onPicked: (value) => root.saveRate("up", value)
                }

                Field {
                    id: rateUpField

                    label: qsTr("…or a custom upload limit (KB/s)")
                    placeholder: qsTr("Unlimited — e.g. 100")
                    hint: qsTr("Leave empty for no limit. Press Enter or click away to save.")
                    onCommitted: root.saveRate("up", root.rateFromField(rateUpField))
                }

                Rectangle { width: parent.width; height: 1; color: "#333333" }

                Text {
                    text: qsTr("Your own trackers")
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    font.weight: Font.Bold
                }

                Note {
                    text: qsTr("One address per line (udp://, http:// or https://). They are added to every torrent, before the built-in list.")
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

                    Btn { primary: true; text: qsTr("Save trackers"); onClicked: root.saveTrackers() }
                    Btn { text: qsTr("Remove all"); onClicked: { trackerInput.text = ""; root.saveTrackers() } }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.trackerMessage
                        color: text.indexOf(qsTr("Not saved")) === 0 ? "#F87171" : "#34D399"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                    }
                }
            }

            // ---- storage ----
            Page {
                name: "storage"
                current: root.section === "storage"

                Heading { text: qsTr("Storage") }
                Note { text: qsTr("Everything here can be downloaded again. Your own movie files are never touched.") }

                Repeater {
                    model: root.storage

                    delegate: Rectangle {
                        id: row

                        required property var modelData

                        // flix: this used to be a Q_INVOKABLE pull with no notify signal, so the label and the
                // disabled button were only recomputed when the page was opened. torrentActive
                // is a real property that changes when a stream starts or stops, so both follow.
                readonly property bool inUse: (modelData.kind === "torrentData" && MainCtx.torrentActive)

                        width: col0.width
                        height: VLCStyle.dp(52, VLCStyle.scale)
                        radius: VLCStyle.dp(6, VLCStyle.scale)
                        color: "#222222"

                        readonly property Item col0: parent

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
            }

            // ---- about ----
            Page {
                name: "about"
                current: root.section === "about"

                Heading { text: qsTr("About VLCFlix") }
                Note { text: qsTr("VLCFlix is a personal front end built on VLC (VideoLAN, GPL). It is not affiliated with Netflix.") }
                Note { text: qsTr("Movie information and images: this product uses the TMDB API but is not endorsed or certified by TMDB.") }
                Note { text: qsTr("Subtitles: OpenSubtitles.com. Torrent streaming: anacrolix/torrent (MPL-2.0). Online players: Microsoft Edge WebView2.") }
                Note { text: qsTr("VLCFlix does not host or index any media. You are responsible for what you stream; use of torrents shows your IP address to other peers, a VPN is advisable.") }
            }
        }
    }
}
