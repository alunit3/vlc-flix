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
import VLC.MediaLibrary
import VLC.Style

// The folders VLCFlix builds its library from: add, rescan, remove. Removing a folder only
// takes its films out of the library; nothing is deleted from the disk.
Column {
    id: root

    readonly property alias count: folders.count
    property bool allowRemove: true

    property string status: ""
    property bool statusOk: true
    property string confirming: ""          // url of the folder waiting for a second click
    property string pending: ""             // name of a folder being added

    function addFolder() {
        const folder = MainCtx.pickFolder(qsTr("Choose the folder with your movies and series"))
        if (folder.toString() === "")
            return
        const picked = decodeURIComponent(folder.toString())
        root.pending = picked.replace(/\/$/, "").substring(picked.replace(/\/$/, "").lastIndexOf("/") + 1)
        root.status = ""
        pendingTimer.restart()
        folders.add(folder)
    }

    function _name(url) {
        const s = decodeURIComponent(String(url)).replace(/^file:\/\/\//, "").replace(/\/$/, "")
        return s.substring(s.lastIndexOf("/") + 1)
    }

    function _path(url) {
        return decodeURIComponent(String(url)).replace(/^file:\/\/\//, "").replace(/\/$/, "").replace(/\//g, "\\")
    }

    width: parent ? parent.width : 0
    spacing: VLCStyle.dp(8, VLCStyle.scale)

    MLFolderModel {
        id: folders

        ctx: MainCtx

        onCountChanged: {
            if (root.pending !== "") {
                root.status = qsTr("Added %1. Its films appear as they are scanned.").arg(root.pending)
                root.statusOk = true
                root.pending = ""
                pendingTimer.stop()
            }
        }

        onOperationFailed: (op, url) => {
            root.pending = ""
            root.statusOk = false
            root.status = op === 0 ? qsTr("%1 could not be added to the library.").arg(root._name(url))
                                   : qsTr("%1 could not be removed from the library.").arg(root._name(url))
        }
    }

    Timer {
        id: pendingTimer

        interval: 60000
        onTriggered: root.pending = ""
    }

    Timer {
        id: confirmTimer

        interval: 4000
        onTriggered: root.confirming = ""
    }

    Repeater {
        model: folders

        delegate: Rectangle {
            id: row

            required property int index
            required property var url
            required property string display_url

            readonly property bool asking: root.confirming === String(url)

            width: root.width
            height: VLCStyle.dp(58, VLCStyle.scale)
            radius: VLCStyle.dp(6, VLCStyle.scale)
            color: "#222222"

            // a folder, drawn: tab and body
            Item {
                id: folderIcon

                anchors.left: parent.left
                anchors.leftMargin: VLCStyle.dp(16, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                width: VLCStyle.dp(22, VLCStyle.scale)
                height: VLCStyle.dp(17, VLCStyle.scale)

                Rectangle {
                    width: parent.width * 0.45
                    height: parent.height * 0.3
                    radius: VLCStyle.dp(2, VLCStyle.scale)
                    color: "#8C8C8C"
                }

                Rectangle {
                    y: parent.height * 0.18
                    width: parent.width
                    height: parent.height * 0.82
                    radius: VLCStyle.dp(2, VLCStyle.scale)
                    color: "#B3B3B3"
                }
            }

            Column {
                anchors.left: folderIcon.right
                anchors.leftMargin: VLCStyle.dp(14, VLCStyle.scale)
                anchors.right: buttons.left
                anchors.rightMargin: VLCStyle.dp(12, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                spacing: VLCStyle.dp(2, VLCStyle.scale)

                Text {
                    width: parent.width
                    text: root._name(row.url)
                    elide: Text.ElideRight
                    color: "#FFFFFF"
                    font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: row.asking ? qsTr("Removes its films from the library. The files stay on your disk.")
                                     : root._path(row.url)
                    elide: Text.ElideMiddle
                    color: row.asking ? "#F87171" : "#808080"
                    font.pixelSize: VLCStyle.dp(12, VLCStyle.scale)
                }
            }

            Row {
                id: buttons

                anchors.right: parent.right
                anchors.rightMargin: VLCStyle.dp(12, VLCStyle.scale)
                anchors.verticalCenter: parent.verticalCenter
                spacing: VLCStyle.dp(8, VLCStyle.scale)

                FlixButton {
                    visible: !row.asking
                    text: qsTr("Rescan")
                    onClicked: {
                        folders.reload(row.index)
                        root.status = qsTr("Looking for new and removed files in %1.").arg(root._name(row.url))
                        root.statusOk = true
                    }
                }

                FlixButton {
                    visible: root.allowRemove
                    danger: row.asking
                    text: row.asking ? qsTr("Click again to remove") : qsTr("Remove")
                    onClicked: {
                        if (!row.asking) {
                            root.confirming = String(row.url)
                            confirmTimer.restart()
                            return
                        }
                        root.confirming = ""
                        root.status = qsTr("Removed %1 from the library.").arg(root._name(row.url))
                        root.statusOk = true
                        folders.removeAt(row.index)
                    }
                }
            }
        }
    }

    Text {
        visible: folders.count === 0 && root.pending === ""
        width: root.width
        text: qsTr("No folders yet. Nothing is scanned until you add one.")
        color: "#808080"
        font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
        wrapMode: Text.WordWrap
    }

    Row {
        spacing: VLCStyle.dp(12, VLCStyle.scale)
        topPadding: VLCStyle.dp(4, VLCStyle.scale)

        FlixButton {
            primary: true
            text: folders.count === 0 ? qsTr("+  Add movie folder") : qsTr("+  Add another folder")
            onClicked: root.addFolder()
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.width * 0.6
            visible: text !== ""
            text: root.pending !== "" ? qsTr("Adding %1…").arg(root.pending) : root.status
            color: root.pending !== "" ? "#D4D4D4" : (root.statusOk ? "#34D399" : "#F87171")
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)
            wrapMode: Text.WordWrap
        }
    }
}
