// One line of the launcher menu: large text, a lunar bar and soft highlight when selected.
import QtQuick

import BigPicture 1.0

Item {
    id: item

    property string label: ""
    property string detail: ""
    property bool current: false
    property bool dimmed: false
    property color barColor: theme.moon
    property BigPictureTheme theme: BigPictureTheme {}

    signal activated()
    signal hovered()

    onCurrentChanged: if (current) BigPicture.playSound("move")

    width: ListView.view ? ListView.view.width : 520
    height: detail !== "" ? 104 : 80

    Rectangle {
        id: highlight
        anchors.fill: parent
        anchors.leftMargin: 20
        radius: 14
        color: item.current ? item.theme.moonA(0.09) : "transparent"
        border.width: item.current ? 1 : 0
        border.color: item.theme.moonA(0.35)
        Behavior on color { ColorAnimation { duration: 140 } }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: 6
        height: item.current ? parent.height * 0.62 : 0
        radius: 3
        color: item.barColor
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        x: item.current ? 50 : 38
        width: parent.width - x - 16
        spacing: 2
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Text {
            width: parent.width
            text: item.label
            elide: Text.ElideRight
            font.pixelSize: item.theme.fontMenu
            font.weight: item.current ? Font.DemiBold : Font.Normal
            color: item.dimmed ? item.theme.textFaint
                               : (item.current ? item.theme.text : item.theme.textMuted)
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        Text {
            width: parent.width
            visible: item.detail !== ""
            text: item.detail
            elide: Text.ElideRight
            font.pixelSize: item.theme.fontSmall
            color: item.current ? item.barColor : item.theme.textFaint
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Only a mouse that's really being used selects; a hidden cursor
        // resting over an item while the controller scrolls never does.
        onPositionChanged: function(mouse) {
            if (item.theme.pointerMoved(item, mouse.x, mouse.y) && BigPicture.inputMode === "keyboard")
                item.hovered()
        }
        onClicked: item.activated()
    }
}
