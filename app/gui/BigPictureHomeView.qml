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
            if (!actionList.activeFocus && !dialog.isOpen) actionList.forceActiveFocus()
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

        if (!dialog.isOpen && !hostList.activeFocus && !actionList.activeFocus) {
            hostList.forceActiveFocus()
        } else if (actionList.activeFocus && !selectionSettled) {
            // PCs showed up while only the actions were available
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
        var buttons = [ { label: qsTr("Exit Moonlight"), role: "exit" } ]
        if (!BigPicture.launchedDirectly) {
            buttons.push({ label: qsTr("Return to Desktop Mode"), role: "desktop" })
        }
        buttons.push({ label: qsTr("Cancel"), role: "cancel" })
        dialog.show({
            title: BigPicture.launchedDirectly ? qsTr("Exit Moonlight?") : qsTr("Leave Big Picture?"),
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
        lastFocusedList = actionList.activeFocus ? actionList : hostList
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
            Text {
                anchors.left: brand.right
                anchors.leftMargin: 20
                anchors.baseline: brand.baseline
                text: qsTr("Big Picture")
                color: tvTheme.moon
                font.pixelSize: tvTheme.fontSmall + 4
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
                anchors.topMargin: 24
                anchors.left: parent.left
                anchors.right: parent.right
                height: 400
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

                KeyNavigation.down: actionList

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

                    width: 340
                    height: 372
                    z: current ? 2 : 1
                    scale: current ? 1.06 : 1.0
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
                            y: 54
                            width: 170
                            height: 140
                            opacity: tile.usable ? 1 : 0.45
                            Rectangle {
                                width: parent.width; height: 110; radius: 12
                                color: "transparent"
                                border.width: 6
                                border.color: tile.current ? tvTheme.moon : tvTheme.cool
                                Text {
                                    anchors.centerIn: parent
                                    text: tile.name.length > 0 ? tile.name.charAt(0).toUpperCase() : "?"
                                    color: tile.current ? tvTheme.moon : tvTheme.text
                                    font.pixelSize: 52
                                    font.weight: Font.Light
                                }
                            }
                            Rectangle { x: parent.width / 2 - 8; y: 110; width: 16; height: 18; color: tile.current ? tvTheme.moon : tvTheme.cool }
                            Rectangle { x: parent.width / 2 - 44; y: 126; width: 88; height: 8; radius: 4; color: tile.current ? tvTheme.moon : tvTheme.cool }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 26
                            spacing: 8

                            Text {
                                width: parent.width
                                text: tile.name
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                color: tvTheme.text
                                font.pixelSize: tvTheme.fontBody + 4
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
                                    font.pixelSize: tvTheme.fontSmall
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
                    text: qsTr("Turn on your gaming PC and start its streaming host. It shows up here automatically. To add a PC by IP address, use Return to Desktop Mode, then the + button.")
                    color: tvTheme.textMuted
                    font.pixelSize: tvTheme.fontBody
                    lineHeight: 1.3
                }
            }

            // ---- Actions ----
            ListView {
                id: actionList
                anchors.top: hostList.bottom
                anchors.topMargin: 48
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: parent.right
                height: 84
                orientation: ListView.Horizontal
                spacing: 22
                interactive: false
                keyNavigationEnabled: true

                KeyNavigation.up: hostList.count > 0 ? hostList : null

                model: {
                    var m = [ { key: "settings", label: qsTr("Settings") } ]
                    if (!BigPicture.launchedDirectly) m.push({ key: "desktop", label: qsTr("Return to Desktop Mode") })
                    m.push({ key: "exit", label: qsTr("Exit") })
                    return m
                }

                onCurrentIndexChanged: if (activeFocus) BigPicture.playSound("move")
                onActiveFocusChanged: if (activeFocus) BigPicture.playSound("move")

                Keys.onReturnPressed: root.runAction(model[currentIndex].key)
                Keys.onEnterPressed:  root.runAction(model[currentIndex].key)
                Keys.onSpacePressed:  root.runAction(model[currentIndex].key)

                delegate: Rectangle {
                    readonly property bool current: ListView.isCurrentItem && actionList.activeFocus
                    width: actionText.implicitWidth + 80
                    height: 80
                    radius: 40
                    color: current ? tvTheme.moon : Qt.rgba(0.08, 0.11, 0.21, 0.78)
                    border.width: current ? 0 : 1
                    border.color: tvTheme.panelBorder
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.current ? tvTheme.sky : tvTheme.text
                        font.pixelSize: tvTheme.fontBody
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: function(mouse) {
                            if (BigPicture.inputMode === "keyboard" && tvTheme.pointerMoved(parent, mouse.x, mouse.y)) {
                                actionList.currentIndex = index
                                actionList.forceActiveFocus()
                            }
                        }
                        onClicked: root.runAction(modelData.key)
                    }
                }
            }

            // ---- Bottom prompt bar ----
            BigPictureHintBar {
                id: hints
                theme: tvTheme
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                leftText: {
                    var base = hostList.activeFocus && hostList.currentItem ? root.stateHelp(hostList.currentItem.hostStatus) : ""
                    if (bigPictureFilesFolder !== "")
                        base += (base ? "    " : "") + qsTr("Using Big Picture files from %1").arg(bigPictureFilesFolder)
                    return base
                }
                hints: {
                    var h = []
                    if (hostList.activeFocus && hostList.currentItem) {
                        var label = root.confirmLabel(hostList.currentItem.hostStatus)
                        if (label !== "") h.push({ action: "confirm", label: label })
                    } else if (actionList.activeFocus) {
                        h.push({ action: "confirm", label: qsTr("Select") })
                    }
                    h.push({ action: "settings", label: qsTr("Settings") })
                    h.push({ action: "back", label: BigPicture.launchedDirectly ? qsTr("Exit") : qsTr("Leave") })
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
