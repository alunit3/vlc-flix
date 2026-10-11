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

// flix: details of a library title (synopsis, genres, rating, links), opened from "More Info".
Item {
    id: root

    // library item {id, title, duration, thumbnail, progress}, or an online title from
    // Top 10 / search {title, year, overview, rating, genres, imdbId, poster, backdrop}, or null
    property var item: null

    // an online title has no file to play: only the IMDb / Heartive buttons
    readonly property bool isWeb: item !== null && item.id === undefined

    function open(entry) {
        item = entry
        forceActiveFocus()
    }

    function close() {
        item = null
    }

    visible: item !== null
    z: 100

    readonly property string rawTitle: item ? (item.title ?? "") : ""
    readonly property var info: isWeb ? ({ isEpisode: false, year: item.year ?? 0, resolution: "" })
                                      : MainCtx.releaseInfo(rawTitle)

    // details fetched for an online title (movie/<key>.json); re-read when the service reports news
    property int metaTick: 0

    readonly property var extra: {
        metaTick
        return (isWeb && (item.tmdbId ?? 0) > 0)
               ? MainCtx.webDetail(item.tmdbId, item.mediaType ?? "movie") : ({})
    }

    Connections {
        target: MainCtx

        function onMetaUpdated(key) {
            if (root.isWeb && Object.keys(root.extra).length === 0)
                root.metaTick++
        }
    }

    readonly property var meta: isWeb ? Object.assign({}, item, extra.found ? extra : ({})) : tmdb.data
    readonly property string backdropUrl: isWeb ? (extra.backdrop || item.backdrop || item.poster || "") : tmdb.backdrop
    readonly property string overviewText: isWeb ? (extra.overview || item.overview || "") : tmdb.overview
    readonly property var genreList: isWeb ? ((extra.genres ?? []).length > 0 ? extra.genres : (item.genres ?? [])) : tmdb.genres
    readonly property string imdb: isWeb ? (extra.imdbId || item.imdbId || "") : tmdb.imdbId

    // Netflix-style resume: 5 s back from where the user stopped, ignore the first 3 % and the last 5 %
    readonly property real progress: (!isWeb && item) ? (item.progress ?? 0) : 0
    readonly property int totalSeconds: (!isWeb && item && item.duration && item.duration.valid())
                                        ? item.duration.toSeconds() : 0
    readonly property int resumeSeconds: (progress > 0.03 && progress < 0.95 && totalSeconds > 0)
                                         ? Math.max(0, Math.round(progress * totalSeconds) - 5) : 0

    function _clock(seconds) {
        const h = Math.floor(seconds / 3600)
        const m = Math.floor(seconds % 3600 / 60)
        const sec = seconds % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(sec).padStart(2, "0")
    }

    function play(fromStart) {
        if (isWeb || !item || item.id === undefined)
            return
        const options = (!fromStart && resumeSeconds > 0) ? ["start-time=" + resumeSeconds] : []
        MediaLib.addAndPlay(item.id, options)
        MainCtx.resumeNotice = (!fromStart && resumeSeconds > 0) ? resumeSeconds : 0
        MainCtx.playerView = true
        close()
    }

    FlixMeta {
        id: tmdb

        name: root.isWeb ? "" : root.rawTitle
    }

    readonly property string runtimeText: {
        let minutes = root.meta.runtime ?? 0
        if (minutes <= 0 && item && item.duration && item.duration.valid())
            minutes = item.duration.toMinutes()
        if (minutes <= 0)
            return ""
        return minutes >= 60 ? Math.floor(minutes / 60) + "h " + (minutes % 60) + "m" : minutes + "m"
    }

    readonly property string metaLine: {
        const parts = [info.isEpisode ? qsTr("Series") : qsTr("Movie")]
        const year = (root.meta.year ?? 0) > 0 ? root.meta.year : info.year
        if (year > 0)
            parts.push(String(year))
        if (runtimeText !== "")
            parts.push(runtimeText)
        if (info.resolution !== "")
            parts.push(info.resolution)
        if ((root.meta.rating ?? 0) > 0)
            parts.push("★ " + root.meta.rating.toFixed(1))
        return parts.join("  •  ")
    }

    Keys.onEscapePressed: root.close()

    // dim the page behind
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.72)

        TapHandler { onTapped: root.close() }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * VLCStyle.dp(32, VLCStyle.scale), VLCStyle.dp(820, VLCStyle.scale))
        height: Math.min(parent.height - 2 * VLCStyle.dp(32, VLCStyle.scale),
                         body.y + body.height + VLCStyle.dp(32, VLCStyle.scale))
        radius: VLCStyle.dp(10, VLCStyle.scale)
        color: "#181818"
        clip: true

        // swallow clicks so the dimmed backdrop does not close the card
        TapHandler {}

        Item {
            id: banner

            width: parent.width
            height: width * 9 / 16

            Image {
                anchors.fill: parent
                source: root.backdropUrl !== "" ? root.backdropUrl : (root.item ? (root.item.thumbnail || "") : "")
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.45; color: "transparent" }
                    GradientStop { position: 1.0; color: "#181818" }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: VLCStyle.dp(36, VLCStyle.scale)
                anchors.right: parent.right
                anchors.rightMargin: VLCStyle.dp(36, VLCStyle.scale)
                anchors.bottom: parent.bottom
                text: root.meta.title || MainCtx.cleanTitle(root.rawTitle)
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(38, VLCStyle.scale)
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: VLCStyle.dp(14, VLCStyle.scale)
                width: VLCStyle.dp(36, VLCStyle.scale)
                height: width
                radius: width / 2
                color: closeHover.hovered ? Qt.rgba(0.3, 0.3, 0.3, 0.95) : Qt.rgba(0.08, 0.08, 0.08, 0.85)

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                }

                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
            }
        }

        Column {
            id: body

            anchors.top: banner.bottom
            anchors.topMargin: VLCStyle.dp(8, VLCStyle.scale)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: VLCStyle.dp(36, VLCStyle.scale)
            anchors.rightMargin: VLCStyle.dp(36, VLCStyle.scale)
            spacing: VLCStyle.dp(14, VLCStyle.scale)

            // progress of a started file
            Item {
                visible: root.resumeSeconds > 0
                width: parent.width
                height: VLCStyle.dp(18, VLCStyle.scale)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - timeLeft.implicitWidth - VLCStyle.dp(12, VLCStyle.scale)
                    height: VLCStyle.dp(4, VLCStyle.scale)
                    radius: height / 2
                    color: "#4D4D4D"

                    Rectangle {
                        width: parent.width * Math.min(1, root.progress)
                        height: parent.height
                        radius: parent.radius
                        color: "#E50914"
                    }
                }

                Text {
                    id: timeLeft

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("%1 left").arg(root._clock(Math.max(0, root.totalSeconds - root.resumeSeconds)))
                    color: "#B3B3B3"
                    font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
                }
            }

            Flow {
                width: parent.width
                spacing: VLCStyle.dp(12, VLCStyle.scale)

                Repeater {
                    model: {
                        const list = []
                        if (!root.isWeb) {
                            if (root.resumeSeconds > 0) {
                                list.push({ kind: "play", primary: true,
                                            label: "▶  " + qsTr("Resume from %1").arg(root._clock(root.resumeSeconds)) })
                                list.push({ kind: "restart", primary: false, label: qsTr("Play from beginning") })
                            } else {
                                list.push({ kind: "play", primary: true, label: "▶  " + qsTr("Play") })
                            }
                        }
                        if (root.imdb !== "") {
                            list.push({ kind: "imdb", primary: root.isWeb, label: qsTr("Open IMDb") })
                            list.push({ kind: "torrents", primary: root.isWeb, label: qsTr("Open Heartive (torrents)") })
                        }
                        return list
                    }

                    delegate: Rectangle {
                        id: btn

                        required property var modelData

                        width: btnLabel.implicitWidth + 2 * VLCStyle.dp(24, VLCStyle.scale)
                        height: VLCStyle.dp(40, VLCStyle.scale)
                        radius: VLCStyle.dp(4, VLCStyle.scale)
                        color: modelData.primary ? (btnHover.hovered ? "#BFBFBF" : "#FFFFFF")
                                                 : (btnHover.hovered ? Qt.rgba(0.43, 0.43, 0.45, 0.55) : Qt.rgba(0.43, 0.43, 0.45, 0.7))

                        Text {
                            id: btnLabel

                            anchors.centerIn: parent
                            text: btn.modelData.label
                            color: btn.modelData.primary ? "#141414" : "#FFFFFF"
                            font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                            font.weight: Font.Bold
                        }

                        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                switch (btn.modelData.kind) {
                                case "play": root.play(false); break
                                case "restart": root.play(true); break
                                case "imdb": MainCtx.openExternal(MainCtx.imdbUrl(root.imdb)); break
                                case "torrents": MainCtx.openExternal(MainCtx.topTenUrl(root.imdb)); break
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: root.metaLine
                color: "#E5E5E5"
                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                font.weight: Font.DemiBold
            }

            Text {
                visible: (root.meta.tagline ?? "") !== ""
                width: parent.width
                text: root.meta.tagline ?? ""
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                font.italic: true
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: {
                    if (root.overviewText !== "")
                        return root.overviewText
                    if (root.isWeb)
                        return qsTr("No synopsis available.")
                    if (!MainCtx.metaEnabled())
                        return qsTr("Add a TMDB access token in Preferences to see the synopsis and artwork.")
                    return Object.keys(tmdb.data).length > 0 ? qsTr("No synopsis available.")
                                                              : qsTr("Looking up the synopsis…")
                }
                color: "#E5E5E5"
                font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                lineHeight: 1.15
                wrapMode: Text.WordWrap
            }

            Text {
                visible: root.genreList.length > 0
                width: parent.width
                text: qsTr("Genres: %1").arg(root.genreList.join(", "))
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                wrapMode: Text.WordWrap
            }

            Text {
                visible: !root.isWeb
                width: parent.width
                text: qsTr("File: %1").arg(root.rawTitle)
                color: "#808080"
                font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                elide: Text.ElideMiddle
            }
        }
    }
}
