// Controller-friendly dialog for Big Picture. Left/Right (or Up/Down) picks
// a button, confirm chooses it, back cancels. Focus goes back to whatever
// had it before the dialog opened, so the selection underneath is kept.
//
//   dialog.show({ title, message, pin, buttons: [ { label, role } ],
//                 defaultRole, cancelRole }, function(role) { ... })
//
// cancelRole is what back (B / Circle / Esc) chooses; "" means back does
// nothing (used while pairing, which can't be cancelled from here).
import QtQuick
import QtQuick.Window

import BigPicture 1.0

FocusScope {
    id: dialog

    property BigPictureTheme theme: BigPictureTheme {}

    property string title: ""
    property string message: ""
    property string pin: ""
    property var buttons: []
    property string cancelRole: "cancel"
    property int currentButton: 0
    property var callback: null
    property Item returnFocus: null
    readonly property bool isOpen: visible

    anchors.fill: parent
    visible: false
    z: 1000

    function show(options, onChosen) {
        title = options.title || ""
        message = options.message || ""
        pin = options.pin || ""
        buttons = options.buttons || [ { label: qsTr("OK"), role: "ok" } ]
        cancelRole = options.cancelRole !== undefined ? options.cancelRole : "cancel"
        callback = onChosen || null

        currentButton = 0
        if (options.defaultRole) {
            for (var i = 0; i < buttons.length; i++) {
                if (buttons[i].role === options.defaultRole) currentButton = i
            }
        }

        // Remember focus only when opening fresh, not when replacing an open dialog
        if (!visible) {
            returnFocus = dialog.Window.activeFocusItem
        }
        visible = true
        forceActiveFocus()
    }

    function close() {
        if (!visible) return
        visible = false
        if (returnFocus) returnFocus.forceActiveFocus()
        returnFocus = null
    }

    function choose(role) {
        var cb = callback
        callback = null
        close()
        if (cb) cb(role)
    }

    function move(delta) {
        var next = Math.max(0, Math.min(buttons.length - 1, currentButton + delta))
        if (next !== currentButton) {
            currentButton = next
            BigPicture.playSound("move")
        }
    }

    Keys.onLeftPressed:   move(-1)
    Keys.onUpPressed:     move(-1)
    Keys.onRightPressed:  move(1)
    Keys.onDownPressed:   move(1)
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed:  activate()
    Keys.onSpacePressed:  activate()
    Keys.onEscapePressed: function(event) {
        event.accepted = true
        if (cancelRole !== "") {
            BigPicture.playSound("back")
            choose(cancelRole)
        }
    }
    // Keep Start/Y/X from reaching the screens underneath
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Menu || event.key === Qt.Key_Hangup || event.key === Qt.Key_Delete) {
            event.accepted = true
        }
    }

    function activate() {
        if (buttons.length === 0) return
        BigPicture.playSound("select")
        choose(buttons[currentButton].role)
    }

    // Dim and block everything underneath
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.03, 0.07, 0.72)
        MouseArea { anchors.fill: parent; hoverEnabled: true }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.6, 980)
        height: content.height + 96
        radius: 24
        color: "#141B33"
        border.width: 1
        border.color: dialog.theme.panelBorder

        Column {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 48
            spacing: 26

            Text {
                width: parent.width
                visible: text !== ""
                text: dialog.title
                wrapMode: Text.WordWrap
                color: dialog.theme.text
                font.pixelSize: dialog.theme.fontHeading
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: dialog.message
                wrapMode: Text.WordWrap
                color: dialog.theme.textMuted
                font.pixelSize: dialog.theme.fontBody
                lineHeight: 1.3
            }

            Text {
                visible: dialog.pin !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                text: dialog.pin.split("").join(" ")
                color: dialog.theme.moon
                font.pixelSize: 96
                font.weight: Font.Light
                font.letterSpacing: 8
            }

            Row {
                anchors.right: parent.right
                spacing: 20
                visible: dialog.buttons.length > 0

                Repeater {
                    model: dialog.buttons

                    Rectangle {
                        readonly property bool current: index === dialog.currentButton
                        width: label.implicitWidth + 72
                        height: 76
                        radius: 38
                        color: current ? dialog.theme.moon : "transparent"
                        border.width: 2
                        border.color: current ? dialog.theme.moon : dialog.theme.textFaint
                        Behavior on color { ColorAnimation { duration: 110 } }

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.current ? dialog.theme.sky : dialog.theme.text
                            font.pixelSize: dialog.theme.fontBody
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: function(mouse) {
                                if (BigPicture.inputMode === "keyboard" && dialog.theme.pointerMoved(parent, mouse.x, mouse.y))
                                    dialog.currentButton = index
                            }
                            onClicked: {
                                dialog.currentButton = index
                                dialog.activate()
                            }
                        }
                    }
                }
            }
        }
    }
}
