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

// flix: TMDB information (synopsis, artwork, ...) for the title `name`, refreshed when the
// Lua service has written it. `data` is empty until the title is known.
QtObject {
    id: root

    property string name

    property var data: ({})

    readonly property bool found: !!data.found
    readonly property string overview: data.overview ?? ""
    readonly property string backdrop: data.backdrop ?? ""
    readonly property string poster: data.poster ?? ""
    readonly property string imdbId: data.imdbId ?? ""
    readonly property var genres: data.genres ?? []

    function refresh() {
        data = name !== "" ? MainCtx.meta(name) : ({})
    }

    onNameChanged: refresh()
    Component.onCompleted: refresh()

    property Connections _updates: Connections {
        target: MainCtx

        function onMetaUpdated(key) {
            if (root.name !== "" && !root.found)
                root.refresh()
        }
    }
}
