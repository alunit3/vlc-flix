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

    signal seeAllButtonClicked(string name, int reason)

    readonly property var _rows: [continueRow, recentRow, favoritesRow, allRow]

    // flix: the library folders; "Add movie folder" adds to them (the scan starts by itself)
    MLFolderModel {
        id: libraryFolders

        ctx: MainCtx
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
        contentHeight: root._visibleRows().length > 0 ? column.height + VLCStyle.dp(40, VLCStyle.scale)
                                                        : height
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

                // prefer something the user already started
                model: continueRow.count > 0 ? continueRow.model : recentRow.model

                onInfoRequested: (item) => moreInfo.open(item)
            }

            FlixRow {
                id: continueRow

                width: parent.width
                title: qsTr("Continue Watching")
                progressBelow: true
                sideMargin: root.sideMargin
                pageFlickable: flick
                showSeeAll: model.maximumCount > model.count

                model: MLRecentVideoModel {
                    ml: MediaLib
                    limit: root.rowItemCount
                }

                onSeeAllClicked: root.seeAllButtonClicked("continueWatching", Qt.MouseFocusReason)
                onInfoRequested: (item) => moreInfo.open(item)
                onMoveUp: root._step(continueRow, -1)
                onMoveDown: root._step(continueRow, 1)
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
                onAddFolder: {
                    const folder = MainCtx.pickFolder(qsTr("Choose the folder with your movies and series"))
                    if (folder.toString() !== "")
                        libraryFolders.add(folder)
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
