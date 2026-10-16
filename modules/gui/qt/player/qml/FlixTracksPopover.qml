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
import QtQuick.Templates as T
import QtQuick.Layouts

import VLC.MainInterface
import VLC.Style
import VLC.Player
import VLC.Widgets as Widgets
import VLC.Util
import VLC.Dialogs

// flix: the audio and subtitle picker, as on Netflix: a dark panel above the subtitles
// button with an "Audio" and a "Subtitles" column, a check in front of what is selected.
// Sync, video tracks and the rest stay one click away under "More options".
T.Popup {
    id: root

    // emitted by "More options": LangButton opens the full track panel
    signal requestMoreOptions()

    readonly property real _rowHeight: VLCStyle.dp(44, VLCStyle.scale)
    readonly property real _headerHeight: VLCStyle.dp(64, VLCStyle.scale)
    readonly property real _footerHeight: VLCStyle.dp(52, VLCStyle.scale)
    readonly property int _rows: Math.max(Player.audioTracks.count, Player.subtitleTracks.count + 2, 1)

    // set by LangButton: the room there is above the seekbar
    property real maxHeight: VLCStyle.dp(480, VLCStyle.scale)

    width: VLCStyle.dp(640, VLCStyle.scale)
    height: Math.min(maxHeight, _headerHeight + _rows * _rowHeight + VLCStyle.margin_normal + _footerHeight)

    padding: 0
    focus: true
    modal: false
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: VLCStyle.duration_short }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: VLCStyle.duration_short }
    }

    readonly property ColorContext colorContext: ColorContext {
        id: theme
        colorSet: ColorContext.Window
    }

    background: Rectangle {
        color: "#262626"
        radius: VLCStyle.dp(4, VLCStyle.scale)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            TrackColumn {
                id: audioColumn

                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.fillHeight: true

                title: qsTr("Audio")
                tracksModel: Player.audioTracks
                withOff: false

                Navigation.parentItem: root.contentItem
                Navigation.rightItem: subtitleColumn
            }

            TrackColumn {
                id: subtitleColumn

                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.fillHeight: true

                title: qsTr("Subtitles")
                tracksModel: Player.subtitleTracks
                withOff: true

                // our own subtitle search (FlixSubs), at the end of the list
                actionText: qsTr("Download subtitles online…")
                actionIcon: VLCIcons.ic_fluent_arrow_download_24_regular
                onActionTriggered: {
                    root.close()
                    Player.openVLsub()
                }

                Navigation.parentItem: root.contentItem
                Navigation.leftItem: audioColumn
            }
        }

        // footer: subtitle size, add a subtitle file, the full panel
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root._footerHeight
            color: Qt.rgba(1, 1, 1, 0.04)
            radius: VLCStyle.dp(4, VLCStyle.scale)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: VLCStyle.margin_large
                anchors.rightMargin: VLCStyle.margin_large
                spacing: VLCStyle.margin_normal

                FooterText { text: qsTr("Subtitle size") }

                FooterButton {
                    text: "A−"
                    description: qsTr("Smaller subtitles")
                    enabled: Player.subtitleTextScale > 50
                    onClicked: {
                        Player.subtitleTextScale = Math.max(50, Player.subtitleTextScale - 10)
                        Player.saveSubtitleTextScale()
                    }
                }

                FooterText {
                    text: qsTr("%1%").arg(Player.subtitleTextScale)
                    color: "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    Layout.preferredWidth: VLCStyle.dp(44, VLCStyle.scale)
                }

                FooterButton {
                    text: "A+"
                    description: qsTr("Larger subtitles")
                    enabled: Player.subtitleTextScale < 300
                    onClicked: {
                        Player.subtitleTextScale = Math.min(300, Player.subtitleTextScale + 10)
                        Player.saveSubtitleTextScale()
                    }
                }

                Item { Layout.fillWidth: true }

                FooterButton {
                    text: qsTr("Add subtitle file…")
                    description: text
                    onClicked: {
                        root.close()
                        DialogsProvider.loadSubtitlesFile()
                    }
                }

                FooterButton {
                    text: qsTr("More options")
                    description: qsTr("Synchronization, video tracks and more")
                    onClicked: {
                        root.close()
                        root.requestMoreOptions()
                    }
                }
            }
        }
    }

    component FooterText: Text {
        color: "#B3B3B3"
        font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
        verticalAlignment: Text.AlignVCenter
    }

    component FooterButton: T.Button {
        id: fbtn

        property string description

        implicitWidth: flabel.implicitWidth + 2 * VLCStyle.margin_xsmall
        implicitHeight: VLCStyle.dp(32, VLCStyle.scale)

        hoverEnabled: true
        focusPolicy: Qt.TabFocus

        Accessible.name: description

        background: Rectangle {
            radius: VLCStyle.dp(4, VLCStyle.scale)
            color: fbtn.down ? Qt.rgba(1, 1, 1, 0.18)
                             : (fbtn.hovered || fbtn.visualFocus) ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
        }

        contentItem: Text {
            id: flabel
            text: fbtn.text
            color: !fbtn.enabled ? "#666666" : (fbtn.hovered || fbtn.visualFocus) ? "#FFFFFF" : "#D2D2D2"
            font.pixelSize: VLCStyle.dp(14, VLCStyle.scale)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component TrackRow: T.ItemDelegate {
        id: row

        property bool selected: false
        // an action row shows this glyph where tracks show their check
        property string glyph: ""

        implicitHeight: root._rowHeight
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus

        Accessible.role: Accessible.RadioButton
        Accessible.checkable: true
        Accessible.checked: selected

        Keys.onPressed: (event) => {
            if (KeyHelper.matchOk(event)) {
                event.accepted = true
                row.clicked()
            } else {
                Navigation.defaultKeyAction(event)
            }
        }

        background: Rectangle {
            color: (row.hovered || row.activeFocus) ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        }

        contentItem: Item {
            Text {
                id: checkMark

                x: VLCStyle.margin_large
                anchors.verticalCenter: parent.verticalCenter
                width: VLCStyle.dp(28, VLCStyle.scale)

                visible: row.selected || row.glyph !== ""
                text: (row.glyph !== "") ? row.glyph : VLCIcons.check
                font.family: VLCIcons.fontFamily
                font.pixelSize: VLCStyle.dp(22, VLCStyle.scale)
                color: (row.glyph !== "" && !(row.hovered || row.activeFocus)) ? "#B3B3B3" : "#FFFFFF"
            }

            Text {
                anchors.left: checkMark.right
                anchors.right: parent.right
                anchors.rightMargin: VLCStyle.margin_normal
                anchors.verticalCenter: parent.verticalCenter

                text: row.text
                elide: Text.ElideRight
                color: (row.selected || row.hovered || row.activeFocus) ? "#FFFFFF" : "#B3B3B3"
                font.pixelSize: VLCStyle.dp(16, VLCStyle.scale)
                font.weight: row.selected ? Font.Bold : Font.Normal
            }
        }
    }

    component TrackColumn: FocusScope {
        id: column

        required property string title
        required property var tracksModel
        property bool withOff: false

        // an optional last row that is an action rather than a track
        property string actionText: ""
        property string actionIcon: ""
        signal actionTriggered()

        // how many of the tracks are selected, kept up to date by the rows
        property int _checkedCount: 0

        function _recount() {
            let n = 0
            for (let i = 0; i < trackRepeater.count; ++i) {
                const it = trackRepeater.itemAt(i)
                if (it && it.selected)
                    ++n
            }
            _checkedCount = n
        }

        function _firstRow() {
            if (withOff)
                return offRow
            return trackRepeater.count > 0 ? trackRepeater.itemAt(0) : null
        }

        onActiveFocusChanged: {
            if (activeFocus) {
                const r = _firstRow()
                if (r)
                    r.forceActiveFocus(Qt.TabFocusReason)
            }
        }

        Text {
            id: header

            x: VLCStyle.margin_large
            height: root._headerHeight
            verticalAlignment: Text.AlignVCenter

            text: column.title
            color: "#FFFFFF"
            font.pixelSize: VLCStyle.dp(24, VLCStyle.scale)
            font.weight: Font.Bold
        }

        Flickable {
            id: flick

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: VLCStyle.margin_xsmall

            clip: true
            contentHeight: rows.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: Widgets.ScrollBarExt { }

            Column {
                id: rows

                width: flick.width

                TrackRow {
                    id: offRow

                    visible: column.withOff
                    width: parent.width
                    text: qsTr("Off")
                    selected: column._checkedCount === 0

                    Navigation.parentItem: column
                    Navigation.downAction: function() {
                        const r = trackRepeater.itemAt(0)
                        if (r)
                            r.forceActiveFocus(Qt.TabFocusReason)
                        else if (actionRow.visible)
                            actionRow.forceActiveFocus(Qt.TabFocusReason)
                    }

                    onClicked: {
                        for (let i = 0; i < trackRepeater.count; ++i) {
                            const it = trackRepeater.itemAt(i)
                            if (it && it.selected)
                                it.deselect()
                        }
                    }
                }

                Repeater {
                    id: trackRepeater

                    model: column.tracksModel

                    delegate: TrackRow {
                        id: trackRow

                        required property var model
                        required property int index

                        width: rows.width
                        text: model.display
                        selected: model.checked

                        function deselect() {
                            model.checked = false
                        }

                        onSelectedChanged: column._recount()
                        Component.onCompleted: column._recount()
                        Component.onDestruction: Qt.callLater(column._recount)

                        Navigation.parentItem: column
                        Navigation.upAction: function() {
                            if (index > 0)
                                trackRepeater.itemAt(index - 1).forceActiveFocus(Qt.BacktabFocusReason)
                            else if (column.withOff)
                                offRow.forceActiveFocus(Qt.BacktabFocusReason)
                            else
                                column.Navigation.defaultNavigationUp()
                        }
                        Navigation.downAction: function() {
                            if (index < trackRepeater.count - 1)
                                trackRepeater.itemAt(index + 1).forceActiveFocus(Qt.TabFocusReason)
                            else if (actionRow.visible)
                                actionRow.forceActiveFocus(Qt.TabFocusReason)
                            else
                                column.Navigation.defaultNavigationDown()
                        }

                        onActiveFocusChanged: {
                            if (activeFocus)
                                flick.contentY = Helpers.clamp(flick.contentY,
                                                               y + height - flick.height,
                                                               y)
                        }

                        onClicked: model.checked = true
                    }
                }

                TrackRow {
                    id: actionRow

                    visible: column.actionText !== ""
                    width: rows.width
                    text: column.actionText
                    glyph: column.actionIcon

                    Accessible.role: Accessible.Button
                    Accessible.checkable: false

                    Navigation.parentItem: column
                    Navigation.upAction: function() {
                        if (trackRepeater.count > 0)
                            trackRepeater.itemAt(trackRepeater.count - 1).forceActiveFocus(Qt.BacktabFocusReason)
                        else if (column.withOff)
                            offRow.forceActiveFocus(Qt.BacktabFocusReason)
                    }

                    onActiveFocusChanged: {
                        if (activeFocus)
                            flick.contentY = Helpers.clamp(flick.contentY,
                                                           y + height - flick.height,
                                                           y)
                    }

                    onClicked: column.actionTriggered()
                }
            }
        }
    }
}
