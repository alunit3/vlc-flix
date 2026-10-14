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
import VLC.Style

// flix: search page. "Online" browses TMDB (popular movies / series, with sort, genre, year and
// rating filters; a click opens More Info with the IMDb / Heartive buttons). "My library" searches
// the local files (a click opens More Info with Play / Resume).
Widgets.PageLoader {
    id: root

    pageModel: [{
        name: "base",
        component: searchComponent,
        default: true
    }]

    Accessible.role: Accessible.Client
    Accessible.name: qsTr("Search")

    Component {
        id: searchComponent

        Widgets.PageExt {
            id: page

            title: qsTr("Search")

            hasGridListMode: false
            isSearchable: false

            header: Item {
                implicitHeight: 0
                visible: false
            }

            readonly property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)

            // --- state -------------------------------------------------------------------
            property bool online: MainCtx.metaEnabled()
            property string kind: "movie"           // "movie" | "tv"
            property string onlineSort: "popularity.desc"
            property string query: ""
            property var genreIds: []
            property int yearFrom: 0
            property int yearTo: 0
            property real minRating: 0

            // online results
            property var results: []
            property int loadedPage: 0
            property int totalPages: 1
            property bool waiting: false
            property bool failed: false
            property var genreList: []

            readonly property var onlineSorts: [
                { id: "popularity.desc", label: qsTr("Popularity") },
                { id: "rating.desc", label: qsTr("Rating") },
                { id: "date.desc", label: qsTr("Newest") },
                { id: "date.asc", label: qsTr("Oldest") },
                { id: "title.asc", label: qsTr("A–Z") },
                { id: "revenue.desc", label: qsTr("Box office") }
            ]
            readonly property var librarySorts: [
                { id: "insertion", label: qsTr("Recently added") },
                { id: "title", label: qsTr("Title") },
                { id: "last_played", label: qsTr("Last played") },
                { id: "duration", label: qsTr("Duration") }
            ]
            property string librarySort: "insertion"

            // a function, not a binding: it must see the new values inside the on...Changed handlers
            function requestParams() {
                return {
                    type: kind, query: query, sort: onlineSort,
                    genres: genreIds.join(","),
                    year_from: yearFrom, year_to: yearTo, min_rating: minRating
                }
            }

            function reloadGenres() {
                genreList = MainCtx.genres(kind)
            }

            function restart() {
                results = []
                loadedPage = 0
                totalPages = 1
                fetch(1)
            }

            function fetch(pageNumber) {
                if (!online)
                    return
                const answer = MainCtx.discover(Object.assign({ page: pageNumber }, requestParams()))
                if (answer.ready) {
                    waiting = false
                    failed = false
                    giveUp.stop()
                    if (pageNumber <= loadedPage)
                        return
                    results = pageNumber === 1 ? answer.items : results.concat(answer.items)
                    loadedPage = pageNumber
                    totalPages = answer.totalPages
                } else {
                    waiting = true
                    failed = false
                    pendingPage = pageNumber
                    giveUp.restart()
                }
            }

            property int pendingPage: 1

            // no answer from TMDB (no network, wrong token): say so instead of waiting forever
            Timer {
                id: giveUp

                interval: 25000
                onTriggered: {
                    if (page.waiting) {
                        page.waiting = false
                        page.failed = true
                    }
                }
            }

            function toggleGenre(id) {
                const list = genreIds.slice()
                const at = list.indexOf(id)
                if (at >= 0)
                    list.splice(at, 1)
                else
                    list.push(id)
                genreIds = list
                restart()
            }

            onKindChanged: { genreIds = []; reloadGenres(); restart() }
            onOnlineSortChanged: restart()
            onQueryChanged: restart()
            onYearFromChanged: restart()
            onYearToChanged: restart()
            onMinRatingChanged: restart()

            Component.onCompleted: { reloadGenres(); restart() }

            Connections {
                target: MainCtx

                function onMetaUpdated(key) {
                    if (key === "genres")
                        page.reloadGenres()
                    if (page.waiting)
                        page.fetch(page.pendingPage)
                }
            }

            function setCurrentItemFocus(reason) {
                searchField.forceActiveFocus(reason)
            }

            function positionContentAtBeginning() {
                flick.contentY = 0
            }

            FlixMoreInfo {
                id: moreInfo

                anchors.fill: parent
            }

            FlixMagnetDialog {
                id: magnetDialog

                anchors.fill: parent
            }

            Rectangle {
                anchors.fill: parent
                color: "#141414"
                z: -1
            }

            // a small filter chip
            component Chip: Rectangle {
                id: chip

                property string text
                property string icon: ""
                property bool selected: false

                signal clicked()

                width: chipRow.implicitWidth + 2 * VLCStyle.dp(14, VLCStyle.scale)
                height: VLCStyle.dp(30, VLCStyle.scale)
                radius: height / 2
                color: selected ? "#FFFFFF" : (chipHover.hovered ? "#3A3A3A" : "#2A2A2A")
                scale: chipTap.pressed ? 0.95 : 1.0

                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                Row {
                    id: chipRow

                    anchors.centerIn: parent
                    spacing: VLCStyle.dp(6, VLCStyle.scale)

                    Text {
                        visible: chip.icon !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.icon
                        font.family: VLCIcons.fontFamily
                        color: chip.selected ? "#141414" : "#E5E5E5"
                        font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    }

                    Text {
                        id: chipLabel

                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.text
                        color: chip.selected ? "#141414" : "#E5E5E5"
                        font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                        font.weight: Font.DemiBold
                    }
                }

                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: chipTap; onTapped: chip.clicked() }
            }

            // a labelled row of controls
            component FilterRow: Row {
                property string label

                spacing: VLCStyle.dp(8, VLCStyle.scale)

                Text {
                    width: VLCStyle.dp(86, VLCStyle.scale)
                    height: VLCStyle.dp(30, VLCStyle.scale)
                    verticalAlignment: Text.AlignVCenter
                    text: parent.label
                    color: "#808080"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                }
            }

            contentItem: Flickable {
                id: flick

                clip: true
                contentWidth: width
                contentHeight: column.height + VLCStyle.dp(60, VLCStyle.scale)
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: Widgets.ScrollBarExt {}

                Column {
                    id: column

                    x: page.sideMargin
                    y: VLCStyle.dp(24, VLCStyle.scale)
                    width: flick.width - 2 * page.sideMargin
                    spacing: VLCStyle.dp(14, VLCStyle.scale)

                    // search box
                    Rectangle {
                        width: parent.width
                        height: VLCStyle.dp(46, VLCStyle.scale)
                        radius: VLCStyle.dp(4, VLCStyle.scale)
                        color: "#1F1F1F"
                        border.color: searchField.activeFocus ? "#FFFFFF" : "#4D4D4D"

                        TextInput {
                            id: searchField

                            anchors.fill: parent
                            anchors.leftMargin: VLCStyle.dp(16, VLCStyle.scale)
                            anchors.rightMargin: VLCStyle.dp(16, VLCStyle.scale)
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#FFFFFF"
                            selectionColor: "#E50914"
                            font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
                            clip: true

                            onTextChanged: debounce.restart()

                            Text {
                                visible: searchField.text === "" && !searchField.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Search titles, people, ideas…")
                                color: "#808080"
                                font: searchField.font
                            }

                            Timer {
                                id: debounce

                                interval: 500
                                onTriggered: {
                                    page.query = searchField.text.trim()
                                    libraryModel.searchPattern = page.query
                                }
                            }
                        }
                    }

                    FilterRow {
                        label: qsTr("Search in")

                        Chip {
                            text: qsTr("Online (TMDB)")
                            selected: page.online
                            visible: MainCtx.metaEnabled()
                            onClicked: { page.online = true; page.restart() }
                        }
                        Chip {
                            text: qsTr("My library")
                            selected: !page.online
                            onClicked: page.online = false
                        }
                        Chip {
                            icon: VLCIcons.add
                            text: qsTr("Magnet link")
                            onClicked: magnetDialog.open()
                        }
                    }

                    FilterRow {
                        visible: page.online
                        label: qsTr("Type")

                        Chip { text: qsTr("Movies"); selected: page.kind === "movie"; onClicked: page.kind = "movie" }
                        Chip { text: qsTr("Series"); selected: page.kind === "tv"; onClicked: page.kind = "tv" }
                    }

                    FilterRow {
                        label: qsTr("Sort by")

                        Repeater {
                            model: page.online ? page.onlineSorts : page.librarySorts

                            delegate: Chip {
                                required property var modelData

                                text: modelData.label
                                selected: page.online ? page.onlineSort === modelData.id
                                                      : page.librarySort === modelData.id
                                onClicked: {
                                    if (page.online)
                                        page.onlineSort = modelData.id
                                    else
                                        page.librarySort = modelData.id
                                }
                            }
                        }
                    }

                    // genres
                    Row {
                        visible: page.online && page.genreList.length > 0
                        spacing: VLCStyle.dp(8, VLCStyle.scale)
                        width: parent.width

                        Text {
                            width: VLCStyle.dp(86, VLCStyle.scale)
                            height: VLCStyle.dp(30, VLCStyle.scale)
                            verticalAlignment: Text.AlignVCenter
                            text: qsTr("Genre")
                            color: "#808080"
                            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                        }

                        Flow {
                            width: parent.width - VLCStyle.dp(94, VLCStyle.scale)
                            spacing: VLCStyle.dp(8, VLCStyle.scale)

                            Repeater {
                                model: page.genreList

                                delegate: Chip {
                                    required property var modelData

                                    text: modelData.name
                                    selected: page.genreIds.indexOf(modelData.id) >= 0
                                    onClicked: page.toggleGenre(modelData.id)
                                }
                            }
                        }
                    }

                    // year range and rating
                    FilterRow {
                        visible: page.online
                        label: qsTr("Year")

                        Repeater {
                            model: [
                                { label: qsTr("Any"), from: 0, to: 0 },
                                { label: qsTr("2020s"), from: 2020, to: 2029 },
                                { label: qsTr("2010s"), from: 2010, to: 2019 },
                                { label: qsTr("2000s"), from: 2000, to: 2009 },
                                { label: qsTr("90s"), from: 1990, to: 1999 },
                                { label: qsTr("80s"), from: 1980, to: 1989 },
                                { label: qsTr("Older"), from: 1900, to: 1979 }
                            ]

                            delegate: Chip {
                                required property var modelData

                                text: modelData.label
                                selected: page.yearFrom === modelData.from && page.yearTo === modelData.to
                                onClicked: { page.yearFrom = modelData.from; page.yearTo = modelData.to }
                            }
                        }

                        // an exact range
                        Rectangle {
                            width: VLCStyle.dp(150, VLCStyle.scale)
                            height: VLCStyle.dp(30, VLCStyle.scale)
                            radius: height / 2
                            color: "#2A2A2A"

                            TextInput {
                                id: rangeField

                                anchors.fill: parent
                                anchors.leftMargin: VLCStyle.dp(14, VLCStyle.scale)
                                anchors.rightMargin: VLCStyle.dp(14, VLCStyle.scale)
                                verticalAlignment: TextInput.AlignVCenter
                                color: "#FFFFFF"
                                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                clip: true

                                // "1999" or "1995-2005"
                                onEditingFinished: {
                                    const m = text.trim().match(/^(\d{4})(?:\s*[-–]\s*(\d{4}))?$/)
                                    if (m) {
                                        page.yearFrom = Number(m[1])
                                        page.yearTo = Number(m[2] ?? m[1])
                                    }
                                }

                                Text {
                                    visible: rangeField.text === ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("1995-2005")
                                    color: "#808080"
                                    font: rangeField.font
                                }
                            }
                        }
                    }

                    FilterRow {
                        visible: page.online
                        label: qsTr("Rating")

                        Repeater {
                            model: [
                                { label: qsTr("Any"), value: 0 },
                                { label: "★ 6+", value: 6 },
                                { label: "★ 7+", value: 7 },
                                { label: "★ 8+", value: 8 }
                            ]

                            delegate: Chip {
                                required property var modelData

                                text: modelData.label
                                selected: page.minRating === modelData.value
                                onClicked: page.minRating = modelData.value
                            }
                        }
                    }

                    // --- online results ---------------------------------------------------
                    Row {
                        visible: page.online && (page.waiting || page.failed || page.results.length === 0)
                        spacing: VLCStyle.dp(10, VLCStyle.scale)

                        // spinner
                        Item {
                            id: spinner

                            visible: page.waiting
                            width: VLCStyle.dp(18, VLCStyle.scale)
                            height: width

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

                            property real spin: 0

                            NumberAnimation on spin {
                                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                                running: page.waiting
                            }
                        }

                        Text {
                            text: page.waiting ? qsTr("Searching…")
                                : page.failed ? qsTr("Could not reach TMDB. Check your connection, and the token in <a href=\"flix:accounts\">VLCFlix settings › Accounts</a>.")
                                : qsTr("No results.")
                            color: "#B3B3B3"
                            font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                            textFormat: Text.StyledText
                            linkColor: "#FFFFFF"
                            onLinkActivated: MainCtx.openFlixSettings("accounts")

                            HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        }
                    }

                    Flow {
                        visible: page.online
                        width: parent.width
                        spacing: VLCStyle.dp(14, VLCStyle.scale)

                        Repeater {
                            model: page.online ? page.results : []

                            delegate: Item {
                                id: tile

                                required property var modelData
                                required property int index

                                width: VLCStyle.dp(170, VLCStyle.scale)
                                height: VLCStyle.dp(255 + 44, VLCStyle.scale)

                                // fade + rise in, row by row
                                opacity: 0
                                transform: Translate { id: tileRise; y: VLCStyle.dp(16, VLCStyle.scale) }

                                ParallelAnimation {
                                    id: tileAppear

                                    PauseAnimation { duration: (tile.index % 9) * 35 }
                                    ParallelAnimation {
                                        NumberAnimation { target: tile; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: tileRise; property: "y"; to: 0; duration: 360; easing.type: Easing.OutCubic }
                                    }
                                }

                                Component.onCompleted: tileAppear.start()

                                Rectangle {
                                    id: poster

                                    width: parent.width
                                    height: VLCStyle.dp(255, VLCStyle.scale)
                                    radius: VLCStyle.dp(6, VLCStyle.scale)
                                    color: "#2A2A2A"
                                    scale: tileHover.hovered ? 1.04 : 1.0

                                    Behavior on scale { NumberAnimation { duration: 120 } }

                                    Image {
                                        anchors.fill: parent
                                        source: tile.modelData.poster
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: 400
                                    }

                                    Rectangle {
                                        visible: tile.modelData.rating > 0
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: VLCStyle.dp(6, VLCStyle.scale)
                                        width: ratingText.implicitWidth + VLCStyle.dp(12, VLCStyle.scale)
                                        height: VLCStyle.dp(22, VLCStyle.scale)
                                        radius: VLCStyle.dp(4, VLCStyle.scale)
                                        color: Qt.rgba(0, 0, 0, 0.75)

                                        Text {
                                            id: ratingText

                                            anchors.centerIn: parent
                                            text: "★ " + tile.modelData.rating.toFixed(1)
                                            color: "#FFFFFF"
                                            font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                Text {
                                    anchors.top: poster.bottom
                                    anchors.topMargin: VLCStyle.dp(6, VLCStyle.scale)
                                    width: parent.width
                                    text: tile.modelData.title + (tile.modelData.year > 0 ? "  (" + tile.modelData.year + ")" : "")
                                    color: "#E5E5E5"
                                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: moreInfo.open(tile.modelData) }
                            }
                        }
                    }

                    Rectangle {
                        visible: page.online && page.loadedPage > 0 && page.loadedPage < page.totalPages
                        width: moreLabel.implicitWidth + 2 * VLCStyle.dp(26, VLCStyle.scale)
                        height: VLCStyle.dp(40, VLCStyle.scale)
                        radius: VLCStyle.dp(4, VLCStyle.scale)
                        color: moreHover.hovered ? Qt.rgba(0.43, 0.43, 0.45, 0.55) : Qt.rgba(0.43, 0.43, 0.45, 0.7)

                        Text {
                            id: moreLabel

                            anchors.centerIn: parent
                            text: qsTr("Show more")
                            color: "#FFFFFF"
                            font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                            font.weight: Font.Bold
                        }

                        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: page.fetch(page.loadedPage + 1) }
                    }

                    // --- library results --------------------------------------------------
                    Text {
                        visible: !page.online
                        text: libraryModel.count === 0 ? qsTr("Nothing in your library matches.") : ""
                        color: "#B3B3B3"
                        font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    }

                    Flow {
                        visible: !page.online
                        width: parent.width
                        spacing: VLCStyle.dp(14, VLCStyle.scale)

                        Repeater {
                            model: MLVideoModel {
                                id: libraryModel

                                ml: MediaLib
                                sortCriteria: page.librarySort
                                sortOrder: page.librarySort === "title" ? Qt.AscendingOrder : Qt.DescendingOrder
                                limit: 120
                            }

                            delegate: FlixCard {
                                progressBelow: false
                                cardWidth: VLCStyle.dp(264, VLCStyle.scale)
                                width: cardWidth
                                height: pictureHeight + VLCStyle.dp(8, VLCStyle.scale)

                                onActivated: {
                                    if (model.id !== undefined)
                                        moreInfo.open({
                                            id: model.id,
                                            title: model.title,
                                            duration: model.duration,
                                            thumbnail: model.thumbnail,
                                            progress: model.progress ?? 0
                                        })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
