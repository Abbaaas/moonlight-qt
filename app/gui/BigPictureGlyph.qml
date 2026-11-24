// A button prompt that follows the input device in use (BigPicture.glyphs):
// Xbox letters, PlayStation shapes, a neutral face-button diamond for other
// controllers, or keyboard keys. The face button shown always matches what
// SdlGamepadKeyNavigation actually maps to the action, including when
// "Swap A/B and X/Y gamepad buttons" is on.
//
// action: "confirm" (Enter), "back" (Esc), "quit" (Menu / X), "settings"
// (Start or Y), "change" (Left/Right)
import QtQuick

import BigPicture 1.0
import StreamingPreferences 1.0

Item {
    id: glyph

    property string action: "confirm"
    property BigPictureTheme theme: BigPictureTheme {}
    property int size: 44

    readonly property string family: BigPicture.glyphs
    readonly property bool keyboard: family === "keyboard"
    readonly property bool swapped: StreamingPreferences.swapFaceButtons

    // Physical face button for this action: "south", "east", "west", "north",
    // "start" or "dpad"
    readonly property string button: {
        switch (action) {
        case "confirm":  return swapped ? "east" : "south"
        case "back":     return swapped ? "south" : "east"
        case "quit":     return swapped ? "north" : "west"
        case "settings": return "start"
        case "change":   return "dpad"
        }
        return "south"
    }

    // Keyboard key for this action ("" = no keyboard shortcut)
    readonly property string keyLabel: {
        switch (action) {
        case "confirm": return qsTr("Enter")
        case "back":    return qsTr("Esc")
        case "quit":    return qsTr("Del")
        case "change":  return "←  →"
        }
        return ""
    }

    // False when the action has no prompt for this device
    readonly property bool available: !keyboard || keyLabel !== ""

    visible: available
    implicitHeight: size
    implicitWidth: keyboard ? keyCap.width
                 : (button === "start" || button === "dpad") ? pill.width
                 : size
    width: implicitWidth
    height: implicitHeight

    readonly property var xboxLetter: ({ south: "A", east: "B", west: "X", north: "Y" })
    readonly property var xboxColor: ({ south: "#5DB83A", east: "#E0503F", west: "#3E8FE8", north: "#F0C02E" })
    readonly property var psShape: ({ south: "✕", east: "○", west: "□", north: "△" })
    readonly property var psColor: ({ south: "#8FB8F2", east: "#F0808A", west: "#E39AD8", north: "#55CCAA" })

    // Keyboard key cap
    Rectangle {
        id: keyCap
        visible: glyph.keyboard
        height: glyph.size
        width: Math.max(glyph.size, keyText.implicitWidth + 24)
        radius: 8
        color: "transparent"
        border.width: 2
        border.color: glyph.theme.text
        Text {
            id: keyText
            anchors.centerIn: parent
            text: glyph.keyLabel
            color: glyph.theme.text
            font.pixelSize: Math.round(glyph.size * 0.42)
            font.weight: Font.DemiBold
        }
    }

    // Start / Options button, or the D-pad
    Rectangle {
        id: pill
        visible: !glyph.keyboard && (glyph.button === "start" || glyph.button === "dpad")
        height: glyph.size
        width: pillText.implicitWidth + 26
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: glyph.theme.text
        Text {
            id: pillText
            anchors.centerIn: parent
            text: glyph.button === "dpad" ? "◀ ▶"
                : glyph.family === "playstation" ? qsTr("Options") : "☰"
            color: glyph.theme.text
            font.pixelSize: Math.round(glyph.size * (glyph.button === "dpad" ? 0.36 : 0.42))
            font.weight: Font.DemiBold
        }
    }

    // Xbox: colored letter in a dark circle
    Rectangle {
        visible: glyph.family === "xbox" && glyph.xboxLetter[glyph.button] !== undefined
        anchors.fill: parent
        radius: width / 2
        color: "#1B1F27"
        border.width: 2
        border.color: glyph.xboxColor[glyph.button] || glyph.theme.text
        Text {
            anchors.centerIn: parent
            text: glyph.xboxLetter[glyph.button] || ""
            color: glyph.xboxColor[glyph.button] || glyph.theme.text
            font.pixelSize: Math.round(glyph.size * 0.5)
            font.weight: Font.Bold
        }
    }

    // PlayStation: colored shape in a dark circle
    Rectangle {
        visible: glyph.family === "playstation" && glyph.psShape[glyph.button] !== undefined
        anchors.fill: parent
        radius: width / 2
        color: "#1B1F27"
        border.width: 2
        border.color: glyph.theme.textMuted
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: glyph.button === "north" ? -1 : 0
            text: glyph.psShape[glyph.button] || ""
            color: glyph.psColor[glyph.button] || glyph.theme.text
            font.pixelSize: Math.round(glyph.size * (glyph.button === "south" ? 0.52 : 0.58))
            font.weight: Font.Bold
        }
    }

    // Unrecognized controller: a diamond of four face buttons with the one to
    // press filled in, so it's right whatever the labels say
    Item {
        visible: glyph.family === "generic" && ["south", "east", "west", "north"].indexOf(glyph.button) >= 0
        anchors.fill: parent

        Repeater {
            model: [ { pos: "north", x: 0.5, y: 0.2 }, { pos: "west", x: 0.2, y: 0.5 },
                     { pos: "east", x: 0.8, y: 0.5 }, { pos: "south", x: 0.5, y: 0.8 } ]
            Rectangle {
                readonly property bool on: modelData.pos === glyph.button
                width: glyph.size * 0.3
                height: width
                radius: width / 2
                x: glyph.size * modelData.x - width / 2
                y: glyph.size * modelData.y - height / 2
                color: on ? glyph.theme.moon : "transparent"
                border.width: 2
                border.color: on ? glyph.theme.moon : glyph.theme.textMuted
            }
        }
    }
}
