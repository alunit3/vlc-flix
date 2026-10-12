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
import VLC.Player

// flix: what is playing, in the words of a streaming service: the title, year, age rating,
// runtime and synopsis. Shared by the pause screen and the rating banner.
//
// A local file is described by its file name (parsed and looked up on TMDB). A torrent
// stream plays from http://127.0.0.1:<port>/..., so its name is useless: the title comes
// from what the source picker told the player (MainCtx.torrentSession).
Item {
    id: root

    visible: false

    readonly property bool isStream: Player.url.toString().indexOf("http://127.0.0.1:") === 0
                                     && MainCtx.torrentSession.resumeKey !== undefined
    readonly property var session: MainCtx.torrentSession
    readonly property var sessionMeta: isStream ? (session.meta ?? ({})) : ({})

    // the name TMDB is asked about
    readonly property string lookupName: {
        if (isStream) {
            const t = sessionMeta.title || session.title || ""
            if (t === "")
                return ""
            const s = Number(sessionMeta.season ?? 0)
            const e = Number(sessionMeta.episode ?? 0)
            if (s > 0 && e > 0)
                return t + " S" + String(s).padStart(2, "0") + "E" + String(e).padStart(2, "0")
            return sessionMeta.year ? t + " " + sessionMeta.year : t
        }
        return Player.title || Player.name
    }

    readonly property string display: isStream ? (sessionMeta.title || session.title || "")
                                               : MainCtx.cleanTitle(Player.title || Player.name)
    readonly property var episode: isStream
        ? (Number(sessionMeta.season ?? 0) > 0 ? [null, display, sessionMeta.season, sessionMeta.episode] : null)
        : display.match(/^(.*) - S(\d+)E(\d+)$/)

    property var meta: ({})

    function refreshMeta() {
        meta = lookupName !== "" ? MainCtx.meta(lookupName) : ({})
    }

    onLookupNameChanged: refreshMeta()
    Component.onCompleted: refreshMeta()

    Connections {
        target: MainCtx

        function onMetaUpdated(key) { root.refreshMeta() }
    }

    readonly property bool found: meta.found === true
    readonly property string title: episode ? episode[1] : (found && meta.title ? meta.title : display)
    readonly property int year: found ? (meta.year ?? 0) : (isStream ? (sessionMeta.year ?? 0) : 0)
    readonly property int runtime: found ? (meta.runtime ?? 0) : 0
    readonly property string overview: found ? (meta.overview ?? "") : ""
    readonly property string certification: found ? (meta.certification ?? "") : ""

    // "1h 58m" for 118 minutes
    readonly property string runtimeText: {
        if (runtime <= 0)
            return ""
        const h = Math.floor(runtime / 60)
        const m = runtime % 60
        return h > 0 ? qsTr("%1h %2m").arg(h).arg(m) : qsTr("%1m").arg(m)
    }

    // "16+" as streaming services print it. A number (Indonesian, German... ratings) gets a plus;
    // the US scales are mapped to the usual ages; anything else is shown as TMDB gives it
    readonly property string ageText: {
        const c = certification.trim().toUpperCase()
        if (c === "")
            return ""
        const map = { "G": "ALL", "TV-G": "ALL", "TV-Y": "ALL", "TV-Y7": "7+", "PG": "10+", "TV-PG": "10+",
                      "PG-13": "13+", "TV-14": "14+", "R": "17+", "TV-MA": "17+", "NC-17": "18+",
                      "SU": "ALL" }
        if (map[c] !== undefined)
            return map[c]
        if (/^\d+$/.test(c))
            return c + "+"
        return c
    }

    // identifies the title for "once per title" behaviours
    readonly property string key: (isStream ? "s:" : "f:") + lookupName
}
