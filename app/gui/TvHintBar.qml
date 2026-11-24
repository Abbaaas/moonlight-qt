// Glass prompt bar along the bottom with controller button hints.
import QtQuick

Rectangle {
    id: bar
    property TvTheme theme: TvTheme {}
    property string leftText: ""
    // Each hint: { button: "A", label: "Select" }
    property var hints: []

    height: 84
    radius: 18
    color: theme.panel
    border.width: 1
    border.color: theme.panelBorder

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.verticalCenter: parent.verticalCenter
        text: bar.leftText
        color: bar.theme.textFaint
        font.pixelSize: bar.theme.fontSmall
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 32
        anchors.verticalCenter: parent.verticalCenter
        spacing: 40

        Repeater {
            model: bar.hints
            Row {
                spacing: 14
                Rectangle {
                    width: Math.max(46, buttonText.implicitWidth + 24); height: 46; radius: 23
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.button === "A" ? bar.theme.moon : "transparent"
                    border.width: 2
                    border.color: modelData.button === "A" ? bar.theme.moon : bar.theme.text
                    Text {
                        id: buttonText
                        anchors.centerIn: parent
                        text: modelData.button
                        color: modelData.button === "A" ? bar.theme.sky : bar.theme.text
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: bar.theme.text
                    font.pixelSize: bar.theme.fontSmall
                }
            }
        }
    }
}
