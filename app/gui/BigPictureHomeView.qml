// Big Picture: Computers screen.
//
// A row of large PC tiles with live status (from ComputerModel), then a row
// of actions: Settings, Return to Desktop Mode (only when Big Picture was
// entered from the desktop UI) and Exit. Selecting a PC opens its apps,
// wakes it, or pairs it, depending on its state.
import QtQuick
import QtQuick.Controls
import QtQuick.Window

import ComputerModel 1.0
import ComputerManager 1.0
import StreamingPreferences 1.0
import BigPicture 1.0

FocusScope {
    id: root
    objectName: qsTr("Big Picture")
    focus: true

    // main.qml uses this to know a Big Picture screen is showing
    readonly property bool isBigPicture: true

    BigPictureTheme { id: tvTheme }

    // Round icon button for the top bar (an inline component, so it works when
    // this screen is loaded from the Documents\MoonlightBigPicture folder).
    // Icons are drawn from plain shapes so they stay sharp at 1080p and 4K.
    component IconButton: Item {
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


    property ComputerModel computerModel: createModel()

    function createModel() {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', root, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingCompleted)
        return model
    }

    // ---- PC state -------------------------------------------------------------

    function hostState(m) {
        if (m.statusUnknown)             return "checking"
        if (!m.online)                   return m.wakeable ? "asleep" : "offline"
        if (!m.paired)                   return "unpaired"
        if (m.serverSupported === false) return "unsupported"
        return "ready"
    }

    function statusText(state) {
        switch (state) {
        case "checking":    return qsTr("Checking…")
        case "asleep":      return qsTr("Asleep")
        case "offline":     return qsTr("Offline")
        case "unpaired":    return qsTr("Not paired")
        case "unsupported": return qsTr("Needs a host update")
        default:            return qsTr("Ready")
        }
    }

    function stateHelp(state) {
        switch (state) {
        case "checking":    return qsTr("Looking for this PC on your network.")
        case "asleep":      return qsTr("This PC is asleep or turned off. Select it to send a wake signal.")
        case "offline":     return qsTr("Turn this PC on and make sure its streaming host (Sunshine) is running.")
        case "unpaired":    return qsTr("Select this PC to pair with it. You'll get a PIN to enter on the PC.")
        case "unsupported": return qsTr("Update the streaming host software on this PC.")
        default:            return qsTr("Select to see this PC's apps and games.")
        }
    }

    function confirmLabel(state) {
        switch (state) {
        case "ready":    return qsTr("Open")
        case "asleep":   return qsTr("Wake")
        case "unpaired": return qsTr("Pair")
        }
        return ""
    }

    // ---- Selection memory -------------------------------------------------------

    // Until the user moves, keep looking for the last-used PC as PCs are found
    property bool selectionSettled: false
    property string selectedUuid: ""

    function indexOfUuid(uuid) {
        for (var i = 0; i < hostList.count; i++) {
            var item = hostList.itemAtIndex(i)
            if (item && item.uuid === uuid) return i
        }
        return -1
    }

    function placeInitialSelection() {
        if (hostList.count === 0) {
            if (!topBar.activeFocus && !dialog.isOpen) topBar.forceActiveFocus()
            return
        }

        if (selectionSettled) {
            // Keep the same PC selected if the list changed under us
            var keep = indexOfUuid(selectedUuid)
            if (keep >= 0 && keep !== hostList.currentIndex) hostList.currentIndex = keep
            return
        }

        var last = indexOfUuid(BigPicture.lastHost())
        if (last >= 0) {
            hostList.currentIndex = last
            selectionSettled = true
        } else {
            // First available PC, otherwise the first one
            var pick = 0
            for (var i = 0; i < hostList.count; i++) {
                var item = hostList.itemAtIndex(i)
                if (item && item.hostStatus === "ready") { pick = i; break }
            }
            hostList.currentIndex = pick
        }

        if (!dialog.isOpen && !hostList.activeFocus && !topBar.activeFocus) {
            hostList.forceActiveFocus()
        } else if (topBar.activeFocus && !selectionSettled) {
            // PCs showed up while only the top buttons were available
            hostList.forceActiveFocus()
        }
    }

    // Stop hunting for the last-used PC after a few seconds
    Timer {
        interval: 4000
        running: true
        onTriggered: root.selectionSettled = true
    }

    Connections {
        target: root.computerModel
        function onModelReset() { Qt.callLater(root.placeInitialSelection) }
        function onRowsInserted() { Qt.callLater(root.placeInitialSelection) }
        function onRowsRemoved() { Qt.callLater(root.placeInitialSelection) }
        function onDataChanged() { if (!root.selectionSettled) Qt.callLater(root.placeInitialSelection) }
    }

    // ---- Actions ------------------------------------------------------------------

    function openHost(index, item) {
        var state = item.hostStatus
        selectionSettled = true
        if (state === "ready") {
            BigPicture.playSound("select")
            BigPicture.setLastHost(item.uuid)
            stackView.push("qrc:/gui/BigPictureAppsView.qml",
                           { "computerIndex": index, "hostName": item.name, "hostUuid": item.uuid })
        } else if (state === "asleep") {
            BigPicture.playSound("select")
            computerModel.wakeComputer(index)
            toast.show(qsTr("Wake signal sent to %1").arg(item.name))
        } else if (state === "unpaired") {
            BigPicture.playSound("select")
            startPairing(index, item)
        } else {
            BigPicture.playSound("error")
            toast.show(stateHelp(state))
        }
    }

    property int pairingIndex: -1
    property string pairingUuid: ""
    property string pairingName: ""

    function startPairing(index, item) {
        var pin = computerModel.generatePinString()
        pairingIndex = index
        pairingUuid = item.uuid
        pairingName = item.name
        computerModel.pairComputer(index, pin)
        dialog.show({
            title: qsTr("Pair with %1").arg(item.name),
            message: qsTr("On %1, enter this PIN in the host's web page or pairing prompt (for Sunshine: the PIN tab of its web UI).").arg(item.name),
            pin: pin,
            buttons: [ { label: qsTr("Cancel"), role: "cancel" } ]
        }, function(role) {
            // Pairing carries on in the background, like on the desktop page
            root.pairingIndex = -1
        })
    }

    function pairingCompleted(error) {
        var wasWaiting = pairingIndex >= 0
        var name = pairingName
        pairingIndex = -1
        if (dialog.isOpen && dialog.pin !== "") dialog.close()

        if (error !== undefined) {
            BigPicture.playSound("error")
            dialog.show({
                title: qsTr("Pairing failed"),
                message: error,
                buttons: [ { label: qsTr("OK"), role: "ok" } ],
                cancelRole: "ok"
            }, null)
        } else {
            toast.show(qsTr("Paired with %1").arg(name))
            if (wasWaiting) {
                var i = indexOfUuid(pairingUuid)
                if (i >= 0) {
                    hostList.currentIndex = i
                    var item = hostList.itemAtIndex(i)
                    if (item && item.hostStatus === "ready") openHost(i, item)
                }
            }
        }
    }

    function runAction(key) {
        BigPicture.playSound("select")
        if (key === "settings") {
            stackView.push("qrc:/gui/BigPictureSettingsView.qml")
        } else if (key === "desktop") {
            window.exitBigPicture()
        } else if (key === "exit") {
            Qt.quit()
        }
    }

    // Back on this screen: offer to leave
    function askToLeave() {
        BigPicture.playSound("back")
        var buttons = [ { label: qsTr("Exit Moonlight"), role: "exit" },
                        { label: qsTr("Switch to Desktop"), role: "desktop" } ]
        buttons.push({ label: qsTr("Cancel"), role: "cancel" })
        dialog.show({
            title: qsTr("Exit Moonlight?"),
            message: "",
            buttons: buttons,
            defaultRole: "cancel"
        }, function(role) {
            if (role === "exit") Qt.quit()
            else if (role === "desktop") window.exitBigPicture()
        })
    }

    // ---- Lifecycle ------------------------------------------------------------------

    property Item lastFocusedList: null

    StackView.onActivating: {
        toolBar.visible = false
        window.ensureBigPictureWindow()
    }
    StackView.onActivated: {
        if (lastFocusedList) lastFocusedList.forceActiveFocus()
        else placeInitialSelection()
    }
    StackView.onDeactivating: {
        lastFocusedList = topBar.activeFocus ? topBar : hostList
    }

    Component.onCompleted: Qt.callLater(placeInitialSelection)

    Keys.onEscapePressed: function(event) { event.accepted = true; askToLeave() }
    Keys.onPressed: function(event) {
        // Start / Y (Key_Hangup) opens Big Picture settings, not the desktop page
        if (event.key === Qt.Key_Hangup) {
            event.accepted = true
            runAction("settings")
        } else if (event.key === Qt.Key_Menu) {
            event.accepted = true
        }
    }

    // ---- Layout (designed at 1920x1080, scaled to fit) ------------------------------

    BigPictureBackdrop { anchors.fill: parent; theme: tvTheme }

    Item {
        id: stage
        readonly property real k: tvTheme.stageScale(root.width, root.height)
        width: root.width / k
        height: root.height / k
        scale: k
        transformOrigin: Item.TopLeft

        Item {
            id: safe
            anchors.fill: parent
            anchors.leftMargin: tvTheme.safeX(stage.width)
            anchors.rightMargin: tvTheme.safeX(stage.width)
            anchors.topMargin: tvTheme.safeY(stage.height)
            anchors.bottomMargin: tvTheme.safeY(stage.height)

            Text {
                id: brand
                text: "Moonlight"
                color: tvTheme.text
                font.pixelSize: tvTheme.fontBrand
                font.weight: Font.Light
                font.letterSpacing: 3
            }
            // Settings, Switch to Desktop, Exit: icon buttons next to the clock
            FocusScope {
                id: topBar
                anchors.right: clock.left
                anchors.rightMargin: 40
                anchors.verticalCenter: brand.verticalCenter
                width: topRow.width
                height: topRow.height

                property int currentIndex: 0
                readonly property var actions: [ { key: "settings", label: qsTr("Settings") },
                                                 { key: "desktop",  label: qsTr("Switch to Desktop") },
                                                 { key: "exit",     label: qsTr("Exit Moonlight") } ]

                function move(delta) {
                    var next = Math.max(0, Math.min(actions.length - 1, currentIndex + delta))
                    if (next !== currentIndex) {
                        currentIndex = next
                        BigPicture.playSound("move")
                    }
                }

                onActiveFocusChanged: if (activeFocus) BigPicture.playSound("move")

                Keys.onLeftPressed:   move(-1)
                Keys.onRightPressed:  move(1)
                Keys.onDownPressed:   if (hostList.count > 0) hostList.forceActiveFocus()
                Keys.onReturnPressed: root.runAction(actions[currentIndex].key)
                Keys.onEnterPressed:  root.runAction(actions[currentIndex].key)
                Keys.onSpacePressed:  root.runAction(actions[currentIndex].key)

                Row {
                    id: topRow
                    spacing: 22

                    Repeater {
                        model: topBar.actions

                        IconButton {
                            theme: tvTheme
                            icon: modelData.key
                            label: modelData.label
                            current: topBar.activeFocus && index === topBar.currentIndex
                            onHovered: { topBar.currentIndex = index; topBar.forceActiveFocus() }
                            onActivated: root.runAction(modelData.key)
                        }
                    }
                }
            }

            Text {
                id: clock
                anchors.right: parent.right
                anchors.verticalCenter: brand.verticalCenter
                property date now: new Date()
                text: Qt.formatTime(now, Qt.locale().timeFormat(Locale.ShortFormat))
                color: tvTheme.textMuted
                font.pixelSize: tvTheme.fontHeading - 8
                Timer { interval: 10000; running: true; repeat: true; onTriggered: clock.now = new Date() }
            }

            Text {
                id: pcLabel
                anchors.top: brand.bottom
                anchors.topMargin: 56
                text: qsTr("Computers")
                color: tvTheme.textMuted
                font.pixelSize: tvTheme.fontSmall + 6
            }

            // ---- PC tiles ----
            ListView {
                id: hostList
                anchors.top: pcLabel.bottom
                anchors.topMargin: 30
                anchors.left: parent.left
                anchors.right: parent.right
                height: 590
                orientation: ListView.Horizontal
                spacing: 40
                leftMargin: 14
                rightMargin: 14
                topMargin: 14
                clip: false
                cacheBuffer: 100000      // keep every tile alive so we can find PCs by ID
                keyNavigationEnabled: true
                highlightMoveDuration: 160
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: 14
                preferredHighlightEnd: width * 0.7
                model: root.computerModel

                KeyNavigation.up: topBar

                onCurrentIndexChanged: {
                    if (currentItem) root.selectedUuid = currentItem.uuid
                    if (activeFocus) BigPicture.playSound("move")
                }
                onActiveFocusChanged: if (activeFocus && currentItem) BigPicture.playSound("move")

                Keys.onPressed: function(event) {
                    // Any navigation by the user ends the hunt for the last-used PC
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) root.selectionSettled = true
                }
                Keys.onReturnPressed: if (currentItem) root.openHost(currentIndex, currentItem)
                Keys.onEnterPressed:  if (currentItem) root.openHost(currentIndex, currentItem)
                Keys.onSpacePressed:  if (currentItem) root.openHost(currentIndex, currentItem)

                delegate: Item {
                    id: tile
                    readonly property string uuid: model.uuid
                    readonly property string name: model.name
                    readonly property string hostStatus: root.hostState(model)
                    readonly property bool current: ListView.isCurrentItem && hostList.activeFocus
                    readonly property bool usable: hostStatus === "ready" || hostStatus === "asleep" || hostStatus === "unpaired"

                    width: 440
                    height: 540
                    z: current ? 2 : 1
                    scale: current ? 1.05 : 1.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    // Glow behind the focused tile
                    Rectangle {
                        anchors.fill: card
                        anchors.margins: -16
                        radius: card.radius + 16
                        color: tvTheme.moon
                        opacity: tile.current ? 0.14 : 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    Rectangle {
                        id: card
                        anchors.fill: parent
                        radius: 22
                        color: tile.current ? "#1C2648" : Qt.rgba(0.08, 0.11, 0.21, 0.78)
                        border.width: tile.current ? 4 : 1
                        border.color: tile.current ? tvTheme.moon : tvTheme.panelBorder

                        // Monitor drawing
                        Item {
                            id: monitor
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 90
                            width: 230
                            height: 190
                            opacity: tile.usable ? 1 : 0.45
                            Rectangle {
                                width: parent.width; height: 150; radius: 14
                                color: "transparent"
                                border.width: 7
                                border.color: tile.current ? tvTheme.moon : tvTheme.cool
                                Text {
                                    anchors.centerIn: parent
                                    text: tile.name.length > 0 ? tile.name.charAt(0).toUpperCase() : "?"
                                    color: tile.current ? tvTheme.moon : tvTheme.text
                                    font.pixelSize: 72
                                    font.weight: Font.Light
                                }
                            }
                            Rectangle { x: parent.width / 2 - 10; y: 150; width: 20; height: 24; color: tile.current ? tvTheme.moon : tvTheme.cool }
                            Rectangle { x: parent.width / 2 - 58; y: 172; width: 116; height: 10; radius: 5; color: tile.current ? tvTheme.moon : tvTheme.cool }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 40
                            spacing: 12

                            Text {
                                width: parent.width
                                text: tile.name
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                color: tvTheme.text
                                font.pixelSize: tvTheme.fontBody + 10
                                font.weight: Font.DemiBold
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 10
                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: tile.hostStatus === "ready" ? "#7BD88F"
                                         : tile.hostStatus === "unpaired" || tile.hostStatus === "unsupported" ? tvTheme.warn
                                         : tvTheme.textFaint
                                }
                                Text {
                                    text: root.statusText(tile.hostStatus)
                                    color: tvTheme.textMuted
                                    font.pixelSize: tvTheme.fontSmall + 4
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: function(mouse) {
                            if (BigPicture.inputMode === "keyboard" && tvTheme.pointerMoved(tile, mouse.x, mouse.y)) {
                                root.selectionSettled = true
                                hostList.currentIndex = index
                                hostList.forceActiveFocus()
                            }
                        }
                        onClicked: {
                            hostList.currentIndex = index
                            hostList.forceActiveFocus()
                            root.openHost(index, tile)
                        }
                    }
                }
            }

            // Empty state
            Column {
                anchors.verticalCenter: hostList.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 14
                width: parent.width * 0.62
                spacing: 14
                visible: hostList.count === 0
                Text {
                    text: qsTr("Looking for PCs…")
                    color: tvTheme.text
                    font.pixelSize: tvTheme.fontHeading
                    font.weight: Font.Light
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Turn on your gaming PC and start its streaming host. It shows up here automatically. To add a PC by IP address, use Switch to Desktop (top right), then the + button.")
                    color: tvTheme.textMuted
                    font.pixelSize: tvTheme.fontBody
                    lineHeight: 1.3
                }
            }

            // ---- Button prompts, bottom right ----
            BigPictureHintBar {
                id: hints
                theme: tvTheme
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                hints: {
                    var h = []
                    if (hostList.activeFocus && hostList.currentItem) {
                        var label = root.confirmLabel(hostList.currentItem.hostStatus)
                        if (label !== "") h.push({ action: "confirm", label: label })
                    } else if (topBar.activeFocus) {
                        h.push({ action: "confirm", label: topBar.actions[topBar.currentIndex].label })
                    }
                    h.push({ action: "back", label: qsTr("Exit") })
                    return h
                }
            }

            BigPictureToast {
                id: toast
                theme: tvTheme
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: hints.top
                anchors.bottomMargin: 24
            }
        }

        BigPictureDialog {
            id: dialog
            theme: tvTheme
        }
    }
}
