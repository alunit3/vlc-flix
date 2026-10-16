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

// VLCFlix first-run welcome: what VLCFlix does, then the three things that make it useful -
// a movie folder, a TMDB token, an OpenSubtitles account. Every step can be skipped and
// everything here is also in the VLCFlix settings. Replaces VLC's own first-run wizard,
// which added the Videos and Music folders on its own.
Item {
    id: root

    signal finished()

    property int step: 0
    readonly property int lastStep: 4
    property bool shown: false

    property string tmdbStatus: ""
    property bool tmdbStatusOk: false
    property bool tmdbSaved: false
    property string osStatus: ""
    property bool osStatusOk: false
    property bool osSaved: false

    // force: opened from the settings ("Run setup again"). Otherwise this is the first
    // start, and someone who already has a library or a token is not shown anything.
    function start(force) {
        tmdbSaved = MainCtx.hasVlcOption("flix-tmdb-token")
        osSaved = MainCtx.hasVlcOption("flixsubs-api-key") && MainCtx.hasVlcOption("flixsubs-password")
        osKeyField.text = MainCtx.vlcOption("flixsubs-api-key") || ""
        osUserField.text = MainCtx.vlcOption("flixsubs-user") || ""
        langsField.text = MainCtx.vlcOption("flixsubs-languages") || ""
        step = 0
        if (force) {
            shown = true
            forceActiveFocus()
        } else {
            // the folder list fills in asynchronously
            existingCheck.restart()
        }
    }

    function finish() {
        MainCtx.setFlixPref("onboarding/done", "1")
        const langs = langsField.text.trim()
        if (langs !== (MainCtx.vlcOption("flixsubs-languages") || ""))
            MainCtx.setVlcOption("flixsubs-languages", langs)
        shown = false
        closeTimer.restart()
    }

    function next() {
        if (step < lastStep)
            step++
        else
            finish()
    }

    function back() {
        if (step > 0)
            step--
    }

    function testTmdb() {
        const typed = tmdbField.text.trim()
        if (typed === "") {
            tmdbStatus = qsTr("Paste the token first.")
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
        if (key === "" || user === "" || osPassField.text === "") {
            osStatus = qsTr("Enter the API key, username and password.")
            osStatusOk = false
            return
        }
        osStatus = qsTr("Logging in...")
        osStatusOk = true
        MainCtx.testAccount({ kind: "opensubtitles", key: key, user: user, password: osPassField.text })
    }

    Timer {
        id: existingCheck

        interval: 1200
        onTriggered: {
            if (folderList.count > 0 || MainCtx.metaEnabled()) {
                // an existing setup: nothing to welcome anyone to
                MainCtx.setFlixPref("onboarding/done", "1")
                root.finished()
                return
            }
            root.shown = true
            root.forceActiveFocus()
        }
    }

    Timer {
        id: closeTimer

        interval: 260
        onTriggered: root.finished()
    }

    Connections {
        target: MainCtx

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
                    root.osSaved = true
                    root.osStatus = text + qsTr(". Saved.")
                }
            }
        }
    }

    visible: shown || closeTimer.running
    opacity: shown ? 1.0 : 0.0

    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    Keys.onEscapePressed: root.finish()

    // ---- backdrop ----------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#0B0B0B"

        // a dim red light from the top
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2B080B" }
                GradientStop { position: 0.6; color: "#0B0B0B" }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onWheel: (wheel) => wheel.accepted = true
        }
    }

    // ---- small parts ----------------------------------------------------------------------
    component Headline: Text {
        width: parent ? parent.width : 0
        color: "#FFFFFF"
        font.pixelSize: VLCStyle.dp(30, VLCStyle.scale)
        font.weight: Font.Bold
        wrapMode: Text.WordWrap
    }

    component Body: Text {
        width: parent ? parent.width : 0
        color: "#B3B3B3"
        font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
        lineHeight: 1.25
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        linkColor: "#FFFFFF"
        onLinkActivated: (link) => Qt.openUrlExternally(link)

        HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }

    // a numbered instruction line
    component HowTo: Row {
        id: howTo

        property int number
        property string text

        width: parent ? parent.width : 0
        spacing: VLCStyle.dp(12, VLCStyle.scale)

        Rectangle {
            width: VLCStyle.dp(24, VLCStyle.scale)
            height: width
            radius: width / 2
            color: "#2A2A2A"

            Text {
                anchors.centerIn: parent
                text: howTo.number
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                font.weight: Font.Bold
            }
        }

        Text {
            width: howTo.width - VLCStyle.dp(36, VLCStyle.scale)
            topPadding: VLCStyle.dp(3, VLCStyle.scale)
            text: howTo.text
            color: "#D4D4D4"
            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            wrapMode: Text.WordWrap
            textFormat: Text.StyledText
            linkColor: "#FFFFFF"
            onLinkActivated: (link) => Qt.openUrlExternally(link)

            HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
    }

    // a feature on the first page
    component Feature: Rectangle {
        id: feature

        property string icon
        property string title
        property string text

        height: VLCStyle.dp(150, VLCStyle.scale)
        radius: VLCStyle.dp(8, VLCStyle.scale)
        color: "#1A1A1A"
        border.color: "#2A2A2A"

        Column {
            anchors.fill: parent
            anchors.margins: VLCStyle.dp(18, VLCStyle.scale)
            spacing: VLCStyle.dp(8, VLCStyle.scale)

            Text {
                text: feature.icon
                font.family: VLCIcons.fontFamily
                color: "#E50914"
                font.pixelSize: VLCStyle.dp(24, VLCStyle.scale)
            }

            Text {
                width: parent.width
                text: feature.title
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: feature.text
                color: "#999999"
                font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                wrapMode: Text.WordWrap
            }
        }
    }

    // a line of the summary
    component Done: Row {
        id: done

        property bool ok
        property string text
        property string todo

        spacing: VLCStyle.dp(12, VLCStyle.scale)

        Rectangle {
            width: VLCStyle.dp(26, VLCStyle.scale)
            height: width
            radius: width / 2
            color: done.ok ? "#1F7A4D" : "#2A2A2A"

            Text {
                anchors.centerIn: parent
                text: done.ok ? "✓" : "–"
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                font.weight: Font.Bold
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: done.ok ? done.text : done.todo
            color: done.ok ? "#FFFFFF" : "#999999"
            font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
        }
    }

    // one step of the flow
    component StepPage: Flickable {
        id: stepPage

        required property int index
        default property alias content: stepCol.data

        anchors.fill: parent
        visible: opacity > 0
        opacity: root.step === index ? 1.0 : 0.0
        enabled: root.step === index
        contentWidth: width
        contentHeight: stepCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        transform: Translate {
            x: root.step === stepPage.index ? 0
               : (root.step > stepPage.index ? -VLCStyle.dp(40, VLCStyle.scale) : VLCStyle.dp(40, VLCStyle.scale))

            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Behavior on opacity { NumberAnimation { duration: 220 } }

        Column {
            id: stepCol

            width: stepPage.width
            spacing: VLCStyle.dp(16, VLCStyle.scale)
        }
    }

    // ---- the card ---------------------------------------------------------------------------
    Item {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(820, VLCStyle.scale))
        height: Math.min(parent.height - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(780, VLCStyle.scale))

        scale: root.shown ? 1.0 : 0.96

        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        // header: wordmark, progress, skip
        Item {
            id: header

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: VLCStyle.dp(40, VLCStyle.scale)

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "VLCFLIX"
                color: "#E50914"
                font.pixelSize: VLCStyle.dp(24, VLCStyle.scale)
                font.weight: Font.Black
                font.letterSpacing: VLCStyle.dp(1, VLCStyle.scale)
            }

            Row {
                anchors.centerIn: parent
                spacing: VLCStyle.dp(8, VLCStyle.scale)

                Repeater {
                    model: root.lastStep + 1

                    delegate: Rectangle {
                        required property int index

                        width: index === root.step ? VLCStyle.dp(28, VLCStyle.scale) : VLCStyle.dp(8, VLCStyle.scale)
                        height: VLCStyle.dp(8, VLCStyle.scale)
                        radius: height / 2
                        color: index <= root.step ? "#E50914" : "#3A3A3A"

                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.step < root.lastStep
                text: qsTr("Skip setup")
                color: skipHover.hovered ? "#FFFFFF" : "#808080"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)

                HoverHandler { id: skipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.finish() }
            }
        }

        // the steps
        Item {
            id: steps

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.topMargin: VLCStyle.dp(28, VLCStyle.scale)
            anchors.bottomMargin: VLCStyle.dp(20, VLCStyle.scale)

            // 0: welcome
            StepPage {
                index: 0

                Headline {
                    text: qsTr("Welcome to VLCFlix")
                    font.pixelSize: VLCStyle.dp(38, VLCStyle.scale)
                }

                Body {
                    text: qsTr("Your own films and series, the way streaming services show them - posters, details, subtitles - all played by VLCFlix. Three quick steps get you there; each one can be skipped and changed later in the settings.")
                }

                Item { width: 1; height: VLCStyle.dp(8, VLCStyle.scale) }

                Row {
                    id: features

                    width: parent.width
                    spacing: VLCStyle.dp(14, VLCStyle.scale)

                    readonly property real tileWidth: (width - 2 * spacing) / 3

                    Feature {
                        width: features.tileWidth
                        icon: VLCIcons.medialibrary_add
                        title: qsTr("Your library")
                        text: qsTr("Point VLCFlix at the folder with your films. Nothing is scanned until you do.")
                    }

                    Feature {
                        width: features.tileWidth
                        icon: VLCIcons.info
                        title: qsTr("Posters and details")
                        text: qsTr("Artwork, synopses, cast, search and the Top 10, from TMDB.")
                    }

                    Feature {
                        width: features.tileWidth
                        icon: VLCIcons.audiosub
                        title: qsTr("Subtitles")
                        text: qsTr("Found on OpenSubtitles in your languages, automatically or on demand.")
                    }
                }
            }

            // 1: movie folder
            StepPage {
                index: 1

                Headline { text: qsTr("Where are your films?") }

                Body {
                    text: qsTr("Pick the folder (or folders) that hold your movies and series. VLCFlix finds the films inside, including in sub-folders, and keeps watching for new ones. Your files are never moved or changed.")
                }

                FlixFolderList {
                    id: folderList
                }
            }

            // 2: TMDB
            StepPage {
                index: 2

                Headline { text: qsTr("Posters and details from TMDB") }

                Body {
                    text: qsTr("TMDB (The Movie Database) is free. VLCFlix needs a personal <b>API Read Access Token</b> to fetch artwork, synopses, search results and the Top 10. Without one your library still plays, just with plain titles.")
                }

                HowTo { number: 1; text: qsTr("Create a free account at <a href=\"https://www.themoviedb.org/signup\">themoviedb.org</a>.") }
                HowTo { number: 2; text: qsTr("Open <a href=\"https://www.themoviedb.org/settings/api\">Settings › API</a> and request an API key (choose \"Personal\" use).") }
                HowTo { number: 3; text: qsTr("Copy the long <b>API Read Access Token</b> (not the short API key) and paste it below.") }

                FlixField {
                    id: tmdbField

                    secret: true
                    placeholder: root.tmdbSaved ? qsTr("A token is saved. Paste a new one to replace it.")
                                                : qsTr("Paste your API Read Access Token")
                }

                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    FlixButton { primary: true; text: qsTr("Test and save"); onClicked: root.testTmdb() }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tmdbStatus !== "" ? root.tmdbStatus : (root.tmdbSaved ? qsTr("Connected.") : "")
                        color: (root.tmdbStatus === "" || root.tmdbStatusOk) ? "#34D399" : "#F87171"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                    }
                }
            }

            // 3: OpenSubtitles
            StepPage {
                index: 3

                Headline { text: qsTr("Subtitles from OpenSubtitles") }

                Body {
                    text: qsTr("OpenSubtitles needs two things, both free:")
                }

                Rectangle {
                    width: parent.width
                    height: explain.implicitHeight + 2 * VLCStyle.dp(14, VLCStyle.scale)
                    radius: VLCStyle.dp(8, VLCStyle.scale)
                    color: "#1A1A1A"
                    border.color: "#2A2A2A"

                    Column {
                        id: explain

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: VLCStyle.dp(16, VLCStyle.scale)
                        spacing: VLCStyle.dp(8, VLCStyle.scale)

                        Body {
                            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                            text: qsTr("<b>API key</b> - identifies VLCFlix to OpenSubtitles. Enough to <i>search</i>. Get one by creating a \"consumer\" at <a href=\"https://www.opensubtitles.com/consumers\">opensubtitles.com/consumers</a>.")
                        }

                        Body {
                            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                            text: qsTr("<b>Username and password</b> - your OpenSubtitles account. Needed to <i>download</i>; your daily download allowance belongs to this account. <a href=\"https://www.opensubtitles.com/users/sign_up\">Sign up here</a>.")
                        }
                    }
                }

                FlixField { id: osKeyField; label: qsTr("API key"); placeholder: qsTr("API consumer key") }

                Row {
                    width: parent.width
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    FlixField {
                        id: osUserField

                        width: (parent.width - parent.spacing) / 2
                        label: qsTr("Username")
                        placeholder: qsTr("Username")
                    }

                    FlixField {
                        id: osPassField

                        width: (parent.width - parent.spacing) / 2
                        label: qsTr("Password")
                        secret: true
                        placeholder: root.osSaved ? qsTr("Saved. Type to replace.") : qsTr("Password")
                    }
                }

                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                    FlixButton { primary: true; text: qsTr("Log in"); onClicked: root.loginOpenSubtitles() }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.osStatus !== "" ? root.osStatus : (root.osSaved ? qsTr("Connected.") : "")
                        color: (root.osStatus === "" || root.osStatusOk) ? "#34D399" : "#F87171"
                        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                    }
                }

                FlixField {
                    id: langsField

                    label: qsTr("Subtitle languages")
                    placeholder: "en, id"
                    hint: qsTr("Two-letter codes, most wanted first. When a film starts without subtitles VLCFlix can look for them by itself; that and the rest is under Settings › Subtitles. To search by hand: right-click the video › Subtitle › Find Subtitles Online.")
                }
            }

            // 4: done
            StepPage {
                index: 4

                Headline { text: qsTr("You're all set") }

                Body {
                    text: qsTr("Everything here can be changed later: the gear at the top right opens the VLCFlix settings, where you can also run this setup again.")
                }

                Item { width: 1; height: VLCStyle.dp(6, VLCStyle.scale) }

                Done {
                    ok: folderList.count > 0
                    text: folderList.count === 1 ? qsTr("1 movie folder in your library")
                                                 : qsTr("%1 movie folders in your library").arg(folderList.count)
                    todo: qsTr("No movie folder yet - add one from Home whenever you like")
                }

                Done {
                    ok: root.tmdbSaved
                    text: qsTr("TMDB connected: posters and details on")
                    todo: qsTr("TMDB not connected: plain titles, no Top 10")
                }

                Done {
                    ok: root.osSaved
                    text: qsTr("OpenSubtitles connected")
                    todo: qsTr("OpenSubtitles not connected: no online subtitles")
                }
            }
        }

        // footer: back / next
        Item {
            id: footer

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: VLCStyle.dp(48, VLCStyle.scale)

            FlixButton {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: root.step > 0 && root.step < root.lastStep
                large: true
                text: qsTr("Back")
                onClicked: root.back()
            }

            Text {
                anchors.right: nextButton.left
                anchors.rightMargin: VLCStyle.dp(20, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                visible: (root.step === 1 && folderList.count === 0)
                         || (root.step === 2 && !root.tmdbSaved)
                         || (root.step === 3 && !root.osSaved)
                text: qsTr("Skip this step")
                color: stepSkipHover.hovered ? "#FFFFFF" : "#808080"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)

                HoverHandler { id: stepSkipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.next() }
            }

            FlixButton {
                id: nextButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                large: true
                danger: root.step === 0 || root.step === root.lastStep
                primary: !danger
                enabled: !(root.step === 1 && folderList.count === 0)
                         && !(root.step === 2 && !root.tmdbSaved)
                         && !(root.step === 3 && !root.osSaved)
                text: root.step === 0 ? qsTr("Get started")
                    : root.step === root.lastStep ? qsTr("Start watching")
                    : qsTr("Next")
                onClicked: root.next()
            }
        }
    }
}
