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

// flix: a titled, horizontally scrolling row of FlixCard.
FocusScope {
    id: root

    property string title
    property alias model: list.model
    property alias count: list.count
    readonly property alias list: list

    property real sideMargin: VLCStyle.dp(48, VLCStyle.scale)
    property bool showSeeAll: false

    // draw the watched-progress bar under each card (continue watching)
    property bool progressBelow: false

    // show the "NEW" tag on the first few cards of this row
    property bool showNewTags: false

    // the page flickable, so the mouse wheel keeps scrolling the page while over a row
    property Flickable pageFlickable: null

    signal seeAllClicked()
    signal infoRequested(var item)
    signal moveUp()
    signal moveDown()

    readonly property real _cardHeight: Math.round(list.cardWidth * 9 / 16)
                                        + (progressBelow ? VLCStyle.dp(16, VLCStyle.scale) : 0)
    readonly property real _vpad: VLCStyle.dp(14, VLCStyle.scale)

    visible: list.count > 0
    implicitHeight: visible ? (header.height + list.height + VLCStyle.dp(10, VLCStyle.scale)) : 0
    height: implicitHeight

    function scrollBy(dx) {
        const maxX = Math.max(-list.leftMargin, list.contentWidth - list.width + list.rightMargin)
        scrollAnim.to = Math.max(-list.leftMargin, Math.min(maxX, list.contentX + dx))
        scrollAnim.restart()
    }

    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        height: titleText.implicitHeight + VLCStyle.dp(12, VLCStyle.scale)

        Text {
            id: titleText

            x: root.sideMargin
            anchors.bottom: parent.bottom
            anchors.bottomMargin: VLCStyle.dp(2, VLCStyle.scale)

            text: root.title
            color: "#E5E5E5"
            font.pixelSize: VLCStyle.dp(20, VLCStyle.scale)
            font.weight: Font.DemiBold
        }

        Text {
            visible: root.showSeeAll
            anchors.right: parent.right
            anchors.rightMargin: root.sideMargin
            anchors.verticalCenter: titleText.verticalCenter

            text: qsTr("See all") + "  \u203A"
            color: seeAllHover.hovered ? "#FFFFFF" : "#B3B3B3"
            font.pixelSize: VLCStyle.dp(13, VLCStyle.scale)

            HoverHandler { id: seeAllHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.seeAllClicked() }
        }
    }

    ListView {
        id: list

        readonly property real cardWidth: VLCStyle.dp(264, VLCStyle.scale)

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root._cardHeight + 2 * root._vpad

        orientation: ListView.Horizontal
        spacing: VLCStyle.dp(10, VLCStyle.scale)
        leftMargin: root.sideMargin
        rightMargin: root.sideMargin
        topMargin: root._vpad
        bottomMargin: root._vpad

        // scaled cards overflow the row; the page flickable clips them
        clip: false
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        focus: true
        keyNavigationEnabled: false

        cacheBuffer: width

        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        Keys.onLeftPressed: if (currentIndex > 0) currentIndex--
        Keys.onRightPressed: if (currentIndex < count - 1) currentIndex++
        Keys.onUpPressed: root.moveUp()
        Keys.onDownPressed: root.moveDown()
        Keys.onReturnPressed: if (currentItem) currentItem.activated()
        Keys.onEnterPressed: if (currentItem) currentItem.activated()

        delegate: FlixCard {
            id: card

            current: ListView.isCurrentItem && list.activeFocus
            progressBelow: root.progressBelow
            showNew: root.showNewTags && index < 4

            onActivated: {
                list.currentIndex = index
                // a click opens "More Info"; playing / resuming happens from there
                if (model.id !== undefined) {
                    root.infoRequested({
                        id: model.id,
                        title: model.title,
                        duration: model.duration,
                        thumbnail: model.thumbnail,
                        progress: model.progress ?? 0
                    })
                }
            }
        }

        NumberAnimation {
            id: scrollAnim
            target: list
            property: "contentX"
            duration: 260
            easing.type: Easing.OutCubic
        }

        // wheel: horizontal (or shift+wheel) scrolls the row, plain wheel scrolls the page
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                const dx = event.angleDelta.x !== 0 ? event.angleDelta.x
                                                    : ((event.modifiers & Qt.ShiftModifier) ? event.angleDelta.y : 0)
                if (dx !== 0) {
                    root.scrollBy(-dx * 2)
                } else if (root.pageFlickable) {
                    const f = root.pageFlickable
                    f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY - event.angleDelta.y))
                }
            }
        }
    }

    // hover arrows
    Repeater {
        model: [-1, 1]

        delegate: Item {
            id: arrow

            required property int modelData

            readonly property bool canScroll: modelData < 0 ? list.contentX > -list.leftMargin + 1
                                                            : list.contentX + list.width < list.contentWidth + list.rightMargin - 1

            width: VLCStyle.dp(44, VLCStyle.scale)
            height: list.height
            y: list.y
            x: modelData < 0 ? 0 : root.width - width
            z: 10

            visible: canScroll && rowHover.hovered
            opacity: arrowHover.hovered ? 1.0 : 0.75

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: arrow.modelData < 0 ? Qt.rgba(0.08, 0.08, 0.08, 0.9) : "transparent" }
                    GradientStop { position: 1.0; color: arrow.modelData < 0 ? "transparent" : Qt.rgba(0.08, 0.08, 0.08, 0.9) }
                }
            }

            Text {
                anchors.centerIn: parent
                text: arrow.modelData < 0 ? "\u2039" : "\u203A"
                color: "#FFFFFF"
                font.pixelSize: VLCStyle.dp(40, VLCStyle.scale)
            }

            HoverHandler { id: arrowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.scrollBy(arrow.modelData * list.width * 0.8) }
        }
    }

    HoverHandler { id: rowHover }
}
