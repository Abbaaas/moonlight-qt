// Button prompts along the bottom right (no panel behind them), with an
// optional line of text on the left. Prompts follow the device in use
// (BigPictureGlyph).
import QtQuick

Item {
    id: bar
    property BigPictureTheme theme: BigPictureTheme {}
    property string leftText: ""
    // Each hint: { action: "confirm" | "back" | "quit" | "settings" | "change", label: "..." }
    property var hints: []

    height: 70

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - hintRow.width - 64
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
        anchors.rightMargin: 8
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
