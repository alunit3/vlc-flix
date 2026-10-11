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

// flix: full-width billboard showing the first item of `model`
// (partly watched item if any, otherwise the newest one).
Item {
    id: root

    property var model
    property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)

    // the user pressed "More Info" on a slide: {id, title, duration, thumbnail}
    signal infoRequested(var item)

    implicitHeight: VLCStyle.dp(440, VLCStyle.scale)
    visible: view.count > 0

    ListView {
        id: view

        anchors.fill: parent
        model: root.model
        orientation: ListView.Horizontal
        interactive: false
        clip: true
        highlightRangeMode: ListView.StrictlyEnforceRange
        snapMode: ListView.SnapOneItem
        currentIndex: 0

        delegate: Item {
            id: slide

            required property var model
            required property int index

            readonly property bool resuming: (model.progress ?? 0) > 0

            FlixMeta {
                id: tmdb

                name: slide.model.title ?? ""
            }

            // year / episode / resolution guessed from the file name
            readonly property var info: MainCtx.releaseInfo(model.title ?? "")

            readonly property string runtime: {
                const d = model.duration
                if (!d || !d.valid())
                    return ""
                const m = d.toMinutes()
                if (m >= 60)
                    return Math.floor(m / 60) + "h " + (m % 60) + "m"
                return m >= 1 ? (m + "m") : (d.toSeconds() + "s")
            }

            // "Movie  •  2001  •  2h 13m  •  1080p"
            readonly property string meta: {
                const parts = [info.isEpisode ? qsTr("Series") : qsTr("Movie")]
                if (info.year > 0)
                    parts.push(String(info.year))
                if (runtime !== "")
                    parts.push(runtime)
                if (info.resolution !== "")
                    parts.push(info.resolution)
                return parts.join("  •  ")
            }

            width: view.width
            height: view.height

            Rectangle {
                anchors.fill: parent
                color: "#141414"
            }

            Image {
                id: art

                anchors.fill: parent
                // TMDB backdrop when known, otherwise a frame of the video
                source: tmdb.backdrop !== "" ? tmdb.backdrop : (slide.model.thumbnail || "")
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            // left scrim: keeps the text readable
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(0.08, 0.08, 0.08, 0.95) }
                    GradientStop { position: 0.55; color: Qt.rgba(0.08, 0.08, 0.08, 0.35) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // top scrim: the black top bar melts into the picture
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: VLCStyle.dp(130, VLCStyle.scale)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.92) }
                    GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // bottom fade into the page background
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * 0.4
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#141414" }
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: root.sideMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: VLCStyle.dp(72, VLCStyle.scale)
                width: Math.min(parent.width * 0.5, VLCStyle.dp(620, VLCStyle.scale))
                spacing: VLCStyle.dp(14, VLCStyle.scale)

                Row {
                    spacing: VLCStyle.dp(8, VLCStyle.scale)

                    Rectangle {
                        width: VLCStyle.dp(4, VLCStyle.scale)
                        height: tag.implicitHeight
                        color: "#E50914"
                    }

                    Text {
                        id: tag

                        text: slide.resuming ? qsTr("CONTINUE WATCHING") : qsTr("NEW IN YOUR LIBRARY")
                        color: "#E5E5E5"
                        font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                        font.weight: Font.DemiBold
                        font.letterSpacing: VLCStyle.dp(2, VLCStyle.scale)
                    }
                }

                Text {
                    width: parent.width
                    text: MainCtx.cleanTitle(slide.model.title) || qsTr("Unknown title")
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(44, VLCStyle.scale)
                    font.weight: Font.Bold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    text: slide.meta + (tmdb.genres.length > 0 ? "  \u2022  " + tmdb.genres.slice(0, 2).join(", ") : "")
                    color: "#E5E5E5"
                    font.pixelSize: VLCStyle.dp(15, VLCStyle.scale)
                    font.weight: Font.DemiBold
                }

                Text {
                    visible: tmdb.overview !== ""
                    width: parent.width
                    text: tmdb.overview
                    color: "#E5E5E5"
                    font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                    lineHeight: 1.1
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }

                Row {
                    spacing: VLCStyle.dp(12, VLCStyle.scale)

                Rectangle {
                    id: playButton

                    width: playRow.implicitWidth + 2 * VLCStyle.dp(26, VLCStyle.scale)
                    height: VLCStyle.dp(44, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: playHover.hovered ? "#BFBFBF" : "#FFFFFF"

                    Row {
                        id: playRow

                        anchors.centerIn: parent
                        spacing: VLCStyle.dp(10, VLCStyle.scale)

                        Text {
                            text: "\u25B6"
                            color: "#141414"
                            font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: slide.resuming ? qsTr("Resume") : qsTr("Play")
                            color: "#141414"
                            font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }

                    TapHandler {
                        onTapped: {
                            if (slide.model.id !== undefined) {
                                const p = slide.model.progress ?? 0
                                const d = slide.model.duration
                                const secs = (d && d.valid()) ? d.toSeconds() : 0
                                const start = (p > 0.03 && p < 0.95 && secs > 0) ? Math.max(0, Math.round(p * secs) - 5) : 0
                                MediaLib.addAndPlay(slide.model.id, start > 0 ? ["start-time=" + start] : [])
                                MainCtx.resumeNotice = start
                                MainCtx.playerView = true
                            }
                        }
                    }
                }

                Rectangle {
                    id: infoButton

                    width: infoRow.implicitWidth + 2 * VLCStyle.dp(24, VLCStyle.scale)
                    height: VLCStyle.dp(44, VLCStyle.scale)
                    radius: VLCStyle.dp(4, VLCStyle.scale)
                    color: infoHover.hovered ? Qt.rgba(0.43, 0.43, 0.45, 0.55) : Qt.rgba(0.43, 0.43, 0.45, 0.7)

                    Row {
                        id: infoRow

                        anchors.centerIn: parent
                        spacing: VLCStyle.dp(10, VLCStyle.scale)

                        Text {
                            text: "ⓘ"
                            color: "#FFFFFF"
                            font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: qsTr("More Info")
                            color: "#FFFFFF"
                            font.pixelSize: VLCStyle.dp(18, VLCStyle.scale)
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    HoverHandler { id: infoHover; cursorShape: Qt.PointingHandCursor }

                    TapHandler {
                        onTapped: root.infoRequested({
                            id: slide.model.id,
                            title: slide.model.title,
                            duration: slide.model.duration,
                            thumbnail: slide.model.thumbnail,
                            progress: slide.model.progress ?? 0
                        })
                    }
                }
                }
            }
        }
    }
}
