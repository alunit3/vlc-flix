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
import QtQuick.Controls

import VLC.MediaLibrary

import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Util
import VLC.Dialogs
import VLC.Style

// flix: streaming-style Home. Replaces HomePage (same contract as far as
// HomeDisplay is concerned: seeAllButtonClicked(), setCurrentItemFocus(), ...).
Widgets.PageExt {
    id: root

    property var pagePrefix: []

    title: qsTr("Home")

    hasGridListMode: false
    isSearchable: false

    // The billboard replaces the standard page header.
    header: Item {
        implicitHeight: 0
        visible: false
    }

    readonly property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)
    readonly property int rowItemCount: 20

    // The Home page lists what VLCFlix remembers itself (MainCtx.resumeList(): library files, files
    // opened from anywhere, torrents and online players), newest first. The library's own history
    // is read once, to bring over what was already in it, and can be cleared from here.
    MLRecentVideoModel {
        id: libraryHistory

        ml: MediaLib
        limit: 50
    }

    MLRecentMediaModel {
        id: libraryHistoryClear

        ml: MediaLib
    }

    function _importLibraryHistory() {
        if (MainCtx.flixPref("resume/imported", "0") === "1" || libraryHistory.count === 0)
            return
        const now = Math.floor(Date.now() / 1000)
        for (let i = 0; i < libraryHistory.count; ++i) {
            const m = libraryHistory.getDataAt(i)
            // newest first: keep that order
            MainCtx.importResume(String(m.mrl ?? ""), String(m.title ?? ""), m.progress ?? 0, now - i)
        }
        MainCtx.setFlixPref("resume/imported", "1")
    }

    Connections {
        target: libraryHistory

        function onCountChanged() { root._importLibraryHistory() }
        function onLoadingChanged() { if (!libraryHistory.loading) root._importLibraryHistory() }
    }

    function _clearContinueWatching() {
        MainCtx.setFlixPref("resume/imported", "1")
        MainCtx.clearResume()
        libraryHistoryClear.clearHistory()
    }

    // the same entries as the hero: newest first
    ListModel { id: heroModel }

    function _refreshHero() {
        const list = MainCtx.resumeList()
        heroModel.clear()
        if (list.length > 0) {
            const e = list[0]
            heroModel.append({ title: e.title ?? "", thumbnail: e.poster ?? "", progress: e.fraction ?? 0,
                               entryKey: e.key })
        }
    }

    Component.onCompleted: _refreshHero()

    Connections {
        target: MainCtx

        function onResumeChanged() { root._refreshHero() }
    }

    function _resume(entry) {
        if (entry.kind === "torrent") {
            magnetDialog.resume(entry)
        } else if (entry.kind === "web") {
            moreInfo.open({
                title: entry.title, poster: entry.poster, backdrop: entry.poster, year: 0,
                tmdbId: entry.tmdbId, mediaType: entry.mediaType ?? "movie", imdbId: entry.imdb ?? "",
                resumeSeason: entry.season ?? 1, resumeEpisode: entry.episode ?? 1 })
        } else {
            MediaLib.addAndPlay(entry.mrl)
            // the player continues by itself; this makes it five seconds earlier, like the rest
            MainCtx.resumeFraction = entry.fraction > 0.03 && entry.fraction < 0.95 ? entry.fraction : 0
            MainCtx.resumeNotice = 0
            MainCtx.playerView = true
        }
    }

    // flix: adding a folder used to fail silently - the model reports it through
    // operationFailed and nothing here listened, so picking a folder that the library
    // refused just did nothing and looked broken
    property string folderError: ""
    property string folderErrorUrl: ""

    // and a pick that was accepted says so too: the scan takes a while and until it
    // finishes the page looks exactly as it did before the click
    property string folderPending: ""

    function _folderFailed(op, url) {
        root.folderPending = ""
        root.folderErrorUrl = String(url)
        root.folderError = op === 0
            ? qsTr("That folder could not be added to the library.")
            : qsTr("That folder could not be removed from the library.")
        folderErrorTimer.restart()
    }

    Timer {
        id: folderErrorTimer

        // long enough to read: the message was gone after nine seconds, which is a
        // fair time to have looked away
        interval: 20000
        onTriggered: root.folderError = ""
    }

    Timer {
        id: folderPendingTimer

        // a safety net for a scan that never reports back
        interval: 60000
        onTriggered: root.folderPending = ""
    }

    // "Adding <folder>" appears as soon as the pick is accepted and goes away when the
    // library takes the folder on
    function _folderAdded() {
        if (root.folderPending === "")
            return
        folderPendingTimer.stop()
        root.folderPending = ""
    }

    Connections {
        target: libraryFolders

        function onCountChanged() {
            root._folderAdded()
        }
    }

    signal seeAllButtonClicked(string name, int reason)

    readonly property var _rows: [recentRow, favoritesRow, allRow]

    // flix: the library folders; "Add movie folder" adds to them (the scan starts by itself)
    MLFolderModel {
        id: libraryFolders

        ctx: MainCtx
        onOperationFailed: (op, url) => root._folderFailed(op, url)
    }

    FlixMagnetDialog {
        id: magnetDialog

        anchors.fill: parent
        z: 90
    }

    // flix: "More Info" details of the billboard title
    FlixMoreInfo {
        id: moreInfo

        anchors.fill: parent
    }

    function _scrollTo(y) {
        flickAnim.stop()
        flickAnim.to = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), y))
        flickAnim.start()
    }

    function positionContentAtBeginning() {
        flick.contentY = 0
    }

    function _visibleRows() {
        return _rows.filter(r => r.visible)
    }

    function _reveal(item) {
        const y = item.mapToItem(column, 0, 0).y
        const h = item.height
        if (y < flick.contentY)
            _scrollTo(y - VLCStyle.dp(60, VLCStyle.scale))
        else if (y + h > flick.contentY + flick.height)
            _scrollTo(y + h - flick.height + VLCStyle.dp(24, VLCStyle.scale))
    }

    function _focusRow(row, reason) {
        row.list.forceActiveFocus(reason)
        _reveal(row)
    }

    function _step(row, delta) {
        const rows = _visibleRows()
        const target = rows[rows.indexOf(row) + delta]
        if (target) {
            _focusRow(target, Qt.TabFocusReason)
        } else if (delta < 0) {
            _scrollTo(0)
        }
    }

    function setCurrentItemFocus(reason) {
        const rows = _visibleRows()
        if (rows.length > 0)
            _focusRow(rows[0], reason)
        else
            emptyState.forceActiveFocus(reason)
    }

    Rectangle {
        anchors.fill: parent
        color: "#141414"
        z: -1
    }

    contentItem: Flickable {
        id: flick

        clip: true
        contentWidth: width
        // flix: this used to be pinned to the viewport height whenever the library was
        // empty, which pinned contentY at 0 and cut off everything the page put below
        // the fold - including the message that says why a folder was refused. Let the
        // content be taller than the viewport in every case.
        contentHeight: Math.max(height, column.height + VLCStyle.dp(40, VLCStyle.scale))
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: Widgets.ScrollBarExt {}

        NumberAnimation {
            id: flickAnim
            target: flick
            property: "contentY"
            duration: 220
            easing.type: Easing.OutCubic
        }

        Column {
            id: column

            width: flick.width
            spacing: VLCStyle.dp(6, VLCStyle.scale)

            FlixHero {
                id: hero

                width: parent.width
                sideMargin: root.sideMargin

                // the newest thing the user started, else what is new in the library
                model: heroModel.count > 0 ? heroModel : recentRow.model

                onInfoRequested: (item) => moreInfo.open(item)
                onResumeEntry: (key) => {
                    const list = MainCtx.resumeList()
                    for (let i = 0; i < list.length; ++i)
                        if (list[i].key === key) { root._resume(list[i]); break }
                }
            }

            FlixStreamRow {
                id: streamRow

                width: parent.width
                sideMargin: root.sideMargin

                onResumeLocal: (entry) => root._resume(entry)
                onResumeTorrent: (entry) => root._resume(entry)
                onResumeWeb: (entry) => root._resume(entry)
                onClearRequested: root._clearContinueWatching()
            }

            FlixTopTen {
                id: topTen

                width: parent.width
                sideMargin: root.sideMargin

                onInfoRequested: (item) => moreInfo.open(item)
            }

            FlixLibraryPrompt {
                width: parent.width
                sideMargin: root.sideMargin
                empty: allRow.count === 0
                onStreamMagnet: magnetDialog.open()
                onAddFolder: {
                    const folder = MainCtx.pickFolder(qsTr("Choose the folder with your movies and series"))
                    if (folder.toString() !== "") {
                        root.folderError = ""
                        root.folderErrorUrl = ""
                        // say what is happening: the scan that follows takes a while and
                        // until it lands the page looks exactly as it did before
                        const picked = folder.toString().replace(/%20/g, " ")
                        root.folderPending = picked.substring(picked.lastIndexOf("/") + 1).replace(/\/$/, "")
                        folderPendingTimer.restart()
                        libraryFolders.add(folder)
                    }
                }
            }

            // a pick that was accepted: neutral, and gone as soon as the library takes it on
            Rectangle {
                visible: root.folderPending !== "" && root.folderError === ""
                width: column.width - 2 * root.sideMargin
                height: folderPendingText.implicitHeight + 2 * VLCStyle.dp(11, VLCStyle.scale)
                x: root.sideMargin
                radius: VLCStyle.dp(8, VLCStyle.scale)
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: Qt.rgba(1, 1, 1, 0.10)

                Text {
                    id: folderPendingText

                    anchors.centerIn: parent
                    width: parent.width - 2 * VLCStyle.dp(16, VLCStyle.scale)
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Adding %1…").arg(root.folderPending)
                    color: "#D4D4D4"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                }
            }

            // says why a folder was refused, which used to happen in silence
            Rectangle {
                visible: root.folderError !== ""
                width: column.width - 2 * root.sideMargin
                // the url line is a second row when it is there, so size on the column
                // rather than on the headline alone
                height: folderErrorBody.implicitHeight + 2 * VLCStyle.dp(12, VLCStyle.scale)
                x: root.sideMargin
                radius: VLCStyle.dp(8, VLCStyle.scale)
                color: Qt.rgba(0.6, 0.1, 0.12, 0.35)
                border.color: Qt.rgba(0.9, 0.25, 0.28, 0.45)

                Column {
                    id: folderErrorBody

                    anchors.centerIn: parent
                    width: parent.width - 2 * VLCStyle.dp(16, VLCStyle.scale)
                    spacing: VLCStyle.dp(3, VLCStyle.scale)

                    Text {
                        id: folderErrorText

                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        text: root.folderError
                        color: "#F2F2F2"
                        font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        visible: root.folderErrorUrl !== ""
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                        text: root.folderErrorUrl
                        color: "#C9C9C9"
                        font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                    }
                }
            }

            FlixRow {
                id: recentRow

                width: parent.width
                title: qsTr("Recently Added")
                showNewTags: true
                sideMargin: root.sideMargin
                pageFlickable: flick
                showSeeAll: model.maximumCount > model.count

                model: MLVideoModel {
                    ml: MediaLib
                    sortCriteria: "insertion"
                    sortOrder: Qt.DescendingOrder
                    limit: root.rowItemCount
                }

                onSeeAllClicked: root.seeAllButtonClicked("newVideo", Qt.MouseFocusReason)
                onInfoRequested: (item) => moreInfo.open(item)
                onMoveUp: root._step(recentRow, -1)
                onMoveDown: root._step(recentRow, 1)
            }

            FlixRow {
                id: favoritesRow

                width: parent.width
                title: qsTr("Favorites")
                sideMargin: root.sideMargin
                pageFlickable: flick
                showSeeAll: model.maximumCount > model.count

                model: MLMediaModel {
                    ml: MediaLib
                    favoriteOnly: true
                    sortCriteria: "insertion"
                    sortOrder: Qt.DescendingOrder
                    limit: root.rowItemCount
                }

                onSeeAllClicked: root.seeAllButtonClicked("favorites", Qt.MouseFocusReason)
                onInfoRequested: (item) => moreInfo.open(item)
                onMoveUp: root._step(favoritesRow, -1)
                onMoveDown: root._step(favoritesRow, 1)
            }

            FlixRow {
                id: allRow

                width: parent.width
                title: qsTr("All Videos")
                sideMargin: root.sideMargin
                pageFlickable: flick
                showSeeAll: model.maximumCount > model.count

                model: MLVideoModel {
                    ml: MediaLib
                    sortCriteria: "title"
                    sortOrder: Qt.AscendingOrder
                    limit: root.rowItemCount
                }

                onSeeAllClicked: root.seeAllButtonClicked("newVideo", Qt.MouseFocusReason)
                onInfoRequested: (item) => moreInfo.open(item)
                onMoveUp: root._step(allRow, -1)
                onMoveDown: root._step(allRow, 1)
            }
        }

        // Nothing in the library yet: offer VLC's own "add a folder" / "open" buttons.
        NoMedialibHome.ConeNButtons {
            id: emptyState

            visible: root._visibleRows().length === 0
            orientation: Qt.Vertical
            anchors.centerIn: parent

            Navigation.parentItem: root
        }
    }
}
