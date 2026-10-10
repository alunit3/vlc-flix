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

    // {id, title, duration, thumbnail} of the library item, or null
    property var item: null

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
    readonly property var info: MainCtx.releaseInfo(rawTitle)

    FlixMeta {
        id: tmdb

        name: root.rawTitle
    }

    readonly property string runtimeText: {
        let minutes = tmdb.data.runtime ?? 0
        if (minutes <= 0 && item && item.duration && item.duration.valid())
            minutes = item.duration.toMinutes()
        if (minutes <= 0)
            return ""
        return minutes >= 60 ? Math.floor(minutes / 60) + "h " + (minutes % 60) + "m" : minutes + "m"
    }

    readonly property string metaLine: {
        const parts = [info.isEpisode ? qsTr("Series") : qsTr("Movie")]
        const year = (tmdb.data.year ?? 0) > 0 ? tmdb.data.year : info.year
        if (year > 0)
            parts.push(String(year))
        if (runtimeText !== "")
            parts.push(runtimeText)
        if (info.resolution !== "")
            parts.push(info.resolution)
        if ((tmdb.data.rating ?? 0) > 0)
            parts.push("★ " + tmdb.data.rating.toFixed(1))
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
                source: tmdb.backdrop !== "" ? tmdb.backdrop : (root.item ? (root.item.thumbnail || "") : "")
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
                text: tmdb.data.title || MainCtx.cleanTitle(root.rawTitle)
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

            Row {
                spacing: VLCStyle.dp(12, VLCStyle.scale)

                Rectangle {
                    width: playLabel.implicitWidth + 2 * VLCStyle.dp(26, VLCStyle.scale)
                    height: VLCStyle.dp(40, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: playHover.hovered ? "#BFBFBF" : "#FFFFFF"

                    Text {
                        id: playLabel

                        anchors.centerIn: parent
                        text: "▶  " + qsTr("Play")
                        color: "#141414"
                        font.pixelSize: VLCStyle.dp(17, VLCStyle.scale)
                        font.weight: Font.Bold
                    }

                    HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (root.item && root.item.id !== undefined) {
                                MediaLib.addAndPlay(root.item.id)
                                MainCtx.playerView = true
                                root.close()
                            }
                        }
                    }
                }

                Repeater {
                    model: tmdb.imdbId !== "" ? [
                        { label: qsTr("IMDb"), url: MainCtx.imdbUrl(tmdb.imdbId) },
                        { label: qsTr("Torrents"), url: MainCtx.topTenUrl(tmdb.imdbId) }
                    ] : []

                    delegate: Rectangle {
                        required property var modelData

                        width: linkLabel.implicitWidth + 2 * VLCStyle.dp(22, VLCStyle.scale)
                        height: VLCStyle.dp(40, VLCStyle.scale)
                        radius: VLCStyle.dp(4, VLCStyle.scale)
                        color: linkHover.hovered ? Qt.rgba(0.43, 0.43, 0.45, 0.55) : Qt.rgba(0.43, 0.43, 0.45, 0.7)

                        Text {
                            id: linkLabel

                            anchors.centerIn: parent
                            text: modelData.label
                            color: "#FFFFFF"
                            font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                            font.weight: Font.Bold
                        }

                        HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: MainCtx.openExternal(modelData.url) }
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
                visible: (tmdb.data.tagline ?? "") !== ""
                width: parent.width
                text: tmdb.data.tagline ?? ""
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                font.italic: true
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: {
                    if (tmdb.overview !== "")
                        return tmdb.overview
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
                visible: tmdb.genres.length > 0
                width: parent.width
                text: qsTr("Genres: %1").arg(tmdb.genres.join(", "))
                color: "#B3B3B3"
                font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: qsTr("File: %1").arg(root.rawTitle)
                color: "#808080"
                font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                elide: Text.ElideMiddle
            }
        }
    }
}
