// Short glass message that appears above the prompt bar.
import QtQuick

Rectangle {
    id: toast
    property BigPictureTheme theme: BigPictureTheme {}

    function show(message) {
        label.text = message
        opacity = 1
        hideTimer.restart()
    }

    width: label.implicitWidth + 72
    height: 76
    radius: 18
    color: theme.panel
    border.width: 1
    border.color: theme.moonA(0.5)
    opacity: 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    Text {
        id: label
        anchors.centerIn: parent
        color: toast.theme.text
        font.pixelSize: toast.theme.fontBody
    }

    Timer { id: hideTimer; interval: 3200; onTriggered: toast.opacity = 0 }
}
