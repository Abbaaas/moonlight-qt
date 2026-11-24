// Round icon button for Big Picture's top bar. Icons are drawn from plain
// shapes so they stay sharp at 1080p and 4K.
//
// icon: "settings" (gear), "desktop" (monitor), "exit" (door)
import QtQuick

import BigPicture 1.0

Item {
    id: button

    property BigPictureTheme theme: BigPictureTheme {}
    property string icon: "settings"
    property string label: ""
    property bool current: false

    signal activated()
    signal hovered()

    width: 76
    height: 76

    readonly property color fill: current ? theme.moon : "#151C36"
    readonly property color ink: current ? theme.sky : theme.text

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: button.fill
        border.width: button.current ? 0 : 1
        border.color: button.theme.panelBorder
        scale: button.current ? 1.08 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }

        // Gear
        Item {
            visible: button.icon === "settings"
            anchors.centerIn: parent
            width: 38; height: 38
            Repeater {
                model: 4
                Rectangle {
                    anchors.centerIn: parent
                    width: 9; height: 38; radius: 2
                    rotation: index * 45
                    color: button.ink
                }
            }
            Rectangle { anchors.centerIn: parent; width: 28; height: 28; radius: 14; color: button.ink }
            Rectangle { anchors.centerIn: parent; width: 11; height: 11; radius: 5.5; color: button.fill }
        }

        // Monitor (switch to desktop)
        Item {
            visible: button.icon === "desktop"
            anchors.centerIn: parent
            width: 38; height: 34
            Rectangle {
                width: 38; height: 26; radius: 4
                color: "transparent"
                border.width: 4
                border.color: button.ink
            }
            Rectangle { x: 16; y: 26; width: 6; height: 5; color: button.ink }
            Rectangle { x: 9; y: 30; width: 20; height: 4; radius: 2; color: button.ink }
        }

        // Door with an arrow (exit)
        Item {
            visible: button.icon === "exit"
            anchors.centerIn: parent
            width: 40; height: 36
            Rectangle {
                width: 24; height: 36; radius: 3
                color: "transparent"
                border.width: 4
                border.color: button.ink
            }
            Rectangle { x: 15; y: 16; width: 5; height: 5; radius: 2.5; color: button.ink }
            // Arrow pointing out of the door
            Rectangle { x: 22; y: 16; width: 17; height: 4; radius: 2; color: button.ink }
            Rectangle { x: 31; y: 12; width: 10; height: 4; radius: 2; rotation: 45; color: button.ink }
            Rectangle { x: 31; y: 20; width: 10; height: 4; radius: 2; rotation: -45; color: button.ink }
        }
    }

    // Name under the selected button
    Text {
        anchors.top: parent.bottom
        anchors.topMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        visible: button.current
        text: button.label
        color: button.theme.text
        font.pixelSize: button.theme.fontSmall
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
            if (BigPicture.inputMode === "keyboard" && button.theme.pointerMoved(button, mouse.x, mouse.y))
                button.hovered()
        }
        onClicked: button.activated()
    }
}
