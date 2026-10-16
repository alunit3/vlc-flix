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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
import QtQuick
import QtQuick.Window

import VLC.MainInterface
import VLC.Widgets as Widgets
import VLC.Util
import VLC.Style
import VLC.Dialogs

// flix: shown when the media library could not be opened. Upstream shows a bare cone here,
// which reads as "nothing to play"; the usual cause is a second VLC instance still running
// and holding the database lock, so that is what this page names. Opening a file still works,
// the player just cannot keep a library while it runs.
FocusScope {
    id: root

    property var pagePrefix: [] // behave like a Page

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.View
    }

    Accessible.role: Accessible.Client
    Accessible.name: qsTr("Home View")

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    Column {
        id: content

        anchors.centerIn: root
        width: Math.min(root.width - 2 * VLCStyle.applicationHorizontalMargin,
                        VLCStyle.colWidth(12))
        spacing: VLCStyle.margin_large

        Image {
            id: cone

            property real _eDPR: MainCtx.effectiveDevicePixelRatio(Window.window)

            anchors.horizontalCenter: parent.horizontalCenter

            sourceSize: Qt.size(0, VLCStyle.colWidth(1) * _eDPR)

            source: MainCtx.logoUrl(256)

            Connections {
                target: MainCtx

                function onIntfDevicePixelRatioChanged() {
                    // this one depends on the implicit size, so it has to be re-loaded
                    cone._eDPR = MainCtx.effectiveDevicePixelRatio(cone.Window.window)
                }
            }
        }

        Text {
            id: heading

            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("The media library is not available")
            color: theme.fg.primary
            font.pixelSize: VLCStyle.dp(22, VLCStyle.scale)
            font.weight: Font.Bold
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Another VLCFlix instance is most likely still running and holding the media database. Close it and start VLCFlix again. An instance that has no window can be ended from Task Manager.")
            color: theme.fg.secondary
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
            wrapMode: Text.WordWrap
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: VLCStyle.margin_large

            Widgets.ActionButtonPrimary {
                id: fileButton

                AccessibleCompat.id: "openFileButton"

                focus: true

                text: qsTr("Open File")

                // same width for the buttons, to keep the row symmetric
                width: Math.max(fileButton.implicitWidth,
                                Math.max(discButton.implicitWidth, folderButton.implicitWidth))

                Navigation.parentItem: root
                Navigation.rightItem: folderButton

                onClicked: DialogsProvider.simpleOpenDialog()
            }

            // flix: this page used to offer only a file and a disc, so a user whose
            // library had failed to open had no way to point at a folder at all - and
            // "Add movie folder" is how the library gets its first entry
            Widgets.ActionButtonPrimary {
                id: folderButton

                AccessibleCompat.id: "addFolderButton"

                text: qsTr("Add movie folder")

                width: Math.max(fileButton.implicitWidth,
                                Math.max(discButton.implicitWidth, folderButton.implicitWidth))

                Navigation.parentItem: root
                Navigation.leftItem: fileButton
                Navigation.rightItem: discButton

                onClicked: {
                    // there is no library to add it to, so say so rather than
                    // appearing to work and adding nothing
                    noFolderHint.visible = false
                    const folder = MainCtx.pickFolder(qsTr("Choose the folder with your movies and series"))
                    if (folder.toString() !== "") {
                        // flix: kept for the next start, when FlixHomePage adds it. The
                        // hint used to promise this with nothing behind it.
                        MainCtx.setFlixPref("library/pending", folder.toString())
                        noFolderHint.text = qsTr("%1 will be added to the library the next time VLCFlix starts.")
                                       .arg(folder.toString().replace(/%20/g, " "))
                        noFolderHint.visible = true
                    }
                }
            }

            Widgets.ActionButtonPrimary {
                id: discButton

                AccessibleCompat.id: "discButton"

                text: qsTr("Open Disc")

                width: Math.max(fileButton.implicitWidth,
                                Math.max(discButton.implicitWidth, folderButton.implicitWidth))

                Navigation.parentItem: root
                Navigation.leftItem: folderButton

                onClicked: DialogsProvider.openDiscDialog()
            }
        }

        Text {
            id: noFolderHint

            visible: false
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: theme.fg.secondary
            font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
        }
    }
}