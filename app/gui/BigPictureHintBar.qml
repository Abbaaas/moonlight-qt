// Glass prompt bar along the bottom: a description on the left and button
// prompts on the right. Prompts follow the device in use (BigPictureGlyph).
import QtQuick

Rectangle {
    id: bar
    property BigPictureTheme theme: BigPictureTheme {}
    property string leftText: ""
    // Each hint: { action: "confirm" | "back" | "quit" | "settings" | "change", label: "..." }
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
        width: parent.width - hintRow.width - 96
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: bar.leftText
        color: bar.theme.textMuted
        font.pixelSize: bar.theme.fontSmall
    }

    Row {
        id: hintRow
        anchors.right: parent.right
        anchors.rightMargin: 32
        anchors.verticalCenter: parent.verticalCenter
        spacing: 36

        Repeater {
            model: bar.hints
            Row {
                spacing: 12
                visible: glyph.available
                BigPictureGlyph {
                    id: glyph
                    theme: bar.theme
                    action: modelData.action
                    anchors.verticalCenter: parent.verticalCenter
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
