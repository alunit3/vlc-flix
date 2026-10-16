/*****************************************************************************
 * Copyright (C) 2021 VLC authors and VideoLAN
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


import VLC.Widgets as Widgets
import VLC.Style
import VLC.Player
import VLC.Util

Widgets.IconToolButton {
    id: root

    // Proprerties

    readonly property var _parentItem: {
        if ((typeof rootPlayer !== 'undefined') && (rootPlayer !== null))
            return rootPlayer
        else
            return g_mainDisplay
    }

    // Signals

    signal requestLockUnlockAutoHide(bool lock)
    signal menuOpened(var menu)

    // Settings

    text: VLCIcons.audiosub

    enabled: (menuLoader.status === Loader.Ready) && (popoverLoader.status === Loader.Ready)

    description: qsTr("Audio and subtitles")

    AccessibleCompat.id: "langButton"

    // Events

    // flix: the Netflix-style audio / subtitles popover; its "More options" opens the full
    // track panel (sync, video tracks, speed) that used to open here
    onClicked: {
        const popover = popoverLoader.item
        if (popover.visible) {
            popover.close()
            return
        }
        const parentItem = popover.parent
        const right = root.mapToItem(parentItem, root.width, 0).x + VLCStyle.margin_large
        popover.x = Helpers.clamp(right - popover.width, VLCStyle.margin_large,
                                  parentItem.width - popover.width - VLCStyle.margin_large)
        popover.open()
    }

    // Children

    Loader {
        id: popoverLoader

        sourceComponent: FlixTracksPopover {
            id: popover

            parent: root._parentItem

            maxHeight: Math.max(VLCStyle.dp(200, VLCStyle.scale),
                                parent.positionSliderY - VLCStyle.dp(96, VLCStyle.scale))
            y: parent.positionSliderY - height - VLCStyle.margin_normal
            z: 1

            onOpened: {
                root.requestLockUnlockAutoHide(true)
                root.menuOpened(popover)
            }

            onClosed: {
                root.requestLockUnlockAutoHide(false)
                root.forceActiveFocus()
                root.menuOpened(null)
            }

            onRequestMoreOptions: menuLoader.item.open()
        }
    }

    Loader {
        id: menuLoader

        sourceComponent: TracksMenu {
            id: menu

            parent: root._parentItem

            x: 0
            y: (parent.positionSliderY - height)
            z: 1

            focus: true

            colorContext.palette: root.colorContext.palette

            onOpened: {
                root.requestLockUnlockAutoHide(true)
                root.menuOpened(menu)
            }

            onClosed: {
                root.requestLockUnlockAutoHide(false)
                root.forceActiveFocus()
                root.menuOpened(null)
            }
        }
    }

    function forceUnlock() {
        if((menuLoader)&&(menuLoader.item))
            menuLoader.item.close()
        if (popoverLoader.item)
            popoverLoader.item.close()
    }
}
