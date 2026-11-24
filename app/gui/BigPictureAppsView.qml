// Big Picture: Apps screen for one PC.
//
// A grid of the host's apps with their artwork (AppModel). Confirm starts or
// resumes an app through Moonlight's normal StreamSegue/Session flow. Leaving
// a stream (disconnecting) brings you back here with the same tile selected.
// Quitting the app on the host is a separate action (X / Square, or Del)
// with its own confirmation, so disconnecting never closes the game.
import QtQuick
import QtQuick.Controls
import QtQuick.Window

import AppModel 1.0
import ComputerManager 1.0
import BigPicture 1.0

FocusScope {
    id: root
    objectName: hostName
    focus: true

    readonly property bool isBigPicture: true

    property int computerIndex: -1
    property string hostName: ""
    property string hostUuid: ""

    property var appModel: null
    property int runningId: 0
    property string runningName: ""

    // App ID of the selected tile, kept across list refreshes and streams
    property int selectedAppId: 0
    property bool restoredInitialSelection: false

    BigPictureTheme { id: tvTheme }

    Component.onCompleted: {
        appModel = Qt.createQmlObject('import AppModel 1.0; AppModel {}', root, '')
        appModel.initialize(ComputerManager, computerIndex, false)   // false = hide hidden apps
        appGrid.model = appModel
        refreshRunning()
        Qt.callLater(restoreSelection)
    }

    // ---- Selection memory -------------------------------------------------------

    function indexOfApp(appId) {
        for (var i = 0; i < appGrid.count; i++) {
            var item = appGrid.itemAtIndex(i)
            if (item && item.appId === appId) return i
        }
        return -1
    }

    function restoreSelection() {
        if (appGrid.count === 0) return

        var want = selectedAppId
        if (!restoredInitialSelection) {
            // Last app used on this PC, otherwise whatever is running
            want = BigPicture.lastApp(hostUuid)
            if (indexOfApp(want) < 0) want = runningId
            restoredInitialSelection = true
        }

        var i = indexOfApp(want)
        if (i >= 0 && i !== appGrid.currentIndex) appGrid.currentIndex = i
        if (appGrid.currentItem) selectedAppId = appGrid.currentItem.appId
    }

    Connections {
        target: root.appModel
        function onModelReset() { Qt.callLater(root.restoreSelection) }
        function onRowsInserted() { Qt.callLater(root.restoreSelection) }
        function onRowsRemoved() { Qt.callLater(root.restoreSelection) }
    }

    // ---- Running app -----------------------------------------------------------------

    Timer {
        interval: 1500
        repeat: true
        running: root.StackView.status === StackView.Active
        onTriggered: root.refreshRunning()
    }

    function refreshRunning() {
        if (!appModel) return
        runningId = appModel.getRunningAppId()
        runningName = runningId !== 0 ? appModel.getRunningAppName() : ""
    }

    function computerLost() {
        // Back to the PC list if this PC goes away, like the desktop app view
        dialog.close()
        stackView.pop()
    }

    // ---- Actions ----------------------------------------------------------------------

    function launch(index, item) {
        selectedAppId = item.appId
        BigPicture.setLastApp(hostUuid, item.appId)

        if (runningId !== 0 && runningId !== item.appId) {
            BigPicture.playSound("select")
            dialog.show({
                title: qsTr("%1 is running").arg(runningName),
                message: qsTr("Quit %1 on %2 to start %3? Unsaved progress in %1 will be lost.")
                            .arg(runningName).arg(hostName).arg(item.name),
                buttons: [ { label: qsTr("Quit and start %1").arg(item.name), role: "switch" },
                           { label: qsTr("Cancel"), role: "cancel" } ],
                defaultRole: "cancel"
            }, function(role) {
                if (role === "switch") root.quitThenStart(index, item.name)
            })
            return
        }

        var component = Qt.createComponent("StreamSegue.qml")
        if (component.status !== Component.Ready) {
            console.warn("Big Picture: could not load StreamSegue.qml:", component.errorString())
            BigPicture.playSound("error")
            toast.show(qsTr("Couldn't start the stream"))
            return
        }
        BigPicture.playSound("select")
        stackView.push(component.createObject(stackView, {
            "appName": item.name,
            "session": appModel.createSessionForApp(index),
            "isResume": runningId === item.appId,
            "bigPicture": true,
            "bigPictureError": root.showError
        }))
    }

    function quitThenStart(index, name) {
        quitApp({ index: index, name: name })
    }

    // ---- Quitting the app on the host -------------------------------------------------
    // Done on this screen (with its own "Quitting…" overlay) rather than through
    // the shared QuitSegue screen, so the desktop UI's quit screen is untouched.

    property bool quitting: false
    property string quittingName: ""
    property var startAfterQuit: null

    function quitApp(next) {
        if (quitting || runningId === 0) return
        quittingName = runningName
        startAfterQuit = next || null
        quitting = true
        quitOverlay.forceActiveFocus()
        ComputerManager.quitAppCompleted.connect(quitDone)
        appModel.quitRunningApp()
    }

    function quitDone(error) {
        ComputerManager.quitAppCompleted.disconnect(quitDone)
        quitting = false
        refreshRunning()
        appGrid.forceActiveFocus()

        if (error !== undefined) {
            console.error(error)
            showError(qsTr("Couldn't quit %1").arg(quittingName), error,
                      "https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting")
            return
        }

        var next = startAfterQuit
        startAfterQuit = null
        if (next) {
            var item = appGrid.itemAtIndex(next.index)
            if (item) launch(next.index, item)
        }
    }

    // Stream and quit errors, in Big Picture's own controller dialog
    function showError(title, text, helpUrl) {
        BigPicture.playSound("error")
        dialog.show({
            title: title,
            message: text,
            buttons: [ { label: qsTr("OK"), role: "ok" },
                       { label: qsTr("Help"), role: "help" } ],
            cancelRole: "ok"
        }, function(role) {
            if (role === "help" && helpUrl) Qt.openUrlExternally(helpUrl)
        })
    }

    function askToQuit() {
        if (runningId === 0) {
            BigPicture.playSound("error")
            toast.show(qsTr("Nothing is running on %1").arg(hostName))
            return
        }
        BigPicture.playSound("select")
        dialog.show({
            title: qsTr("Quit %1?").arg(runningName),
            message: qsTr("This closes %1 on %2. Unsaved progress will be lost. (To leave a stream without closing the game, just disconnect.)")
                        .arg(runningName).arg(hostName),
            buttons: [ { label: qsTr("Quit app on host"), role: "quit" },
                       { label: qsTr("Cancel"), role: "cancel" } ],
            defaultRole: "cancel"
        }, function(role) {
            if (role === "quit") root.quitApp(null)
        })
    }

    // ---- Lifecycle ----------------------------------------------------------------------

    StackView.onActivating: {
        toolBar.visible = false
        window.ensureBigPictureWindow()
    }
    StackView.onActivated: {
        appModel.computerLost.connect(computerLost)
        refreshRunning()
        restoreSelection()
        if (!dialog.isOpen) appGrid.forceActiveFocus()
    }
    StackView.onDeactivating: {
        appModel.computerLost.disconnect(computerLost)
    }
    StackView.onRemoved: BigPicture.playSound("back")

    // B goes back through main.qml's normal Escape handling (stackView.pop)
    Keys.onPressed: function(event) {
        if (root.quitting) {
            event.accepted = true
        } else if (event.key === Qt.Key_Menu || event.key === Qt.Key_Delete) {
            // X / Square (or Del): quit the running app on the host
            event.accepted = true
            askToQuit()
        } else if (event.key === Qt.Key_Hangup) {
            // Start / Y: Big Picture settings, not the desktop page
            event.accepted = true
            BigPicture.playSound("select")
            stackView.push("qrc:/gui/BigPictureSettingsView.qml")
        }
    }

    // ---- Layout (designed at 1920x1080, scaled to fit) ------------------------------------

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
                id: title
                width: parent.width * 0.6
                text: root.hostName
                elide: Text.ElideRight
                color: tvTheme.text
                font.pixelSize: tvTheme.fontBrand
                font.weight: Font.Light
                font.letterSpacing: 2
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: title.verticalCenter
                text: root.runningId !== 0 ? qsTr("Running: %1").arg(root.runningName)
                                           : (appGrid.count === 1 ? qsTr("1 app") : qsTr("%1 apps").arg(appGrid.count))
                color: root.runningId !== 0 ? tvTheme.moon : tvTheme.textMuted
                font.pixelSize: tvTheme.fontBody
            }

            GridView {
                id: appGrid
                readonly property int columns: Math.max(1, Math.floor(parent.width / cellWidth))

                anchors.top: title.bottom
                anchors.topMargin: 28
                anchors.bottom: hints.top
                anchors.bottomMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                width: columns * cellWidth

                cellWidth: 292
                cellHeight: 430
                topMargin: 18
                bottomMargin: 18
                clip: true
                cacheBuffer: 100000      // keep every tile alive so we can find apps by ID
                keyNavigationEnabled: true
                highlightMoveDuration: 150
                highlightRangeMode: GridView.ApplyRange
                preferredHighlightBegin: 18
                preferredHighlightEnd: height - cellHeight - 18

                onCurrentIndexChanged: {
                    if (currentItem) root.selectedAppId = currentItem.appId
                    if (activeFocus) BigPicture.playSound("move")
                }

                Keys.onReturnPressed: if (currentItem) root.launch(currentIndex, currentItem)
                Keys.onEnterPressed:  if (currentItem) root.launch(currentIndex, currentItem)
                Keys.onSpacePressed:  if (currentItem) root.launch(currentIndex, currentItem)

                delegate: Item {
                    id: tile
                    readonly property int appId: model.appid
                    readonly property string name: model.name
                    readonly property bool running: model.running
                    readonly property bool current: GridView.isCurrentItem && appGrid.activeFocus

                    width: appGrid.cellWidth
                    height: appGrid.cellHeight
                    z: current ? 2 : 1

                    Item {
                        id: body
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10
                        width: 252
                        height: 400
                        scale: tile.current ? 1.07 : 1.0
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: art
                            anchors.margins: -14
                            radius: 26
                            color: tvTheme.moon
                            opacity: tile.current ? 0.16 : 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }

                        Rectangle {
                            id: art
                            width: parent.width
                            height: 336
                            radius: 14
                            color: "#1A2240"
                            clip: true

                            Image {
                                id: artImage
                                anchors.fill: parent
                                source: model.boxart
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 504
                            }

                            // Name on the tile when there's no artwork
                            Text {
                                visible: artImage.status !== Image.Ready
                                anchors.fill: parent
                                anchors.margins: 18
                                text: tile.name
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: tvTheme.text
                                font.pixelSize: tvTheme.fontBody + 2
                            }

                            Rectangle {
                                visible: tile.running
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 12
                                width: runningText.implicitWidth + 28
                                height: 38
                                radius: 19
                                color: tvTheme.moon
                                Text {
                                    id: runningText
                                    anchors.centerIn: parent
                                    text: qsTr("Running")
                                    color: tvTheme.sky
                                    font.pixelSize: tvTheme.fontSmall - 2
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        // Focus outline
                        Rectangle {
                            anchors.fill: art
                            anchors.margins: -6
                            radius: 18
                            color: "transparent"
                            border.width: tile.current ? 5 : 0
                            border.color: tvTheme.moon
                        }

                        Text {
                            anchors.top: art.bottom
                            anchors.topMargin: 16
                            width: parent.width
                            text: tile.name
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            color: tile.current ? tvTheme.text : tvTheme.textMuted
                            font.pixelSize: tvTheme.fontBody - 2
                            font.weight: tile.current ? Font.DemiBold : Font.Normal
                        }
                    }

                    MouseArea {
                        anchors.fill: body
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: function(mouse) {
                            if (BigPicture.inputMode === "keyboard" && tvTheme.pointerMoved(tile, mouse.x, mouse.y)) {
                                appGrid.currentIndex = index
                                appGrid.forceActiveFocus()
                            }
                        }
                        onClicked: {
                            appGrid.currentIndex = index
                            appGrid.forceActiveFocus()
                            root.launch(index, tile)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: appGrid
                visible: appGrid.count === 0
                text: qsTr("Loading apps…")
                color: tvTheme.textMuted
                font.pixelSize: tvTheme.fontHeading
                font.weight: Font.Light
            }

            BigPictureHintBar {
                id: hints
                theme: tvTheme
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                hints: {
                    var h = []
                    if (appGrid.currentItem) {
                        h.push({ action: "confirm",
                                 label: appGrid.currentItem.running ? qsTr("Resume") : qsTr("Play") })
                    }
                    if (root.runningId !== 0) h.push({ action: "quit", label: qsTr("Quit app on host") })
                    h.push({ action: "settings", label: qsTr("Settings") })
                    h.push({ action: "back", label: qsTr("Back") })
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

        // "Quitting…" overlay while the host closes the app; swallows input
        FocusScope {
            id: quitOverlay
            anchors.fill: parent
            visible: root.quitting
            z: 900

            Keys.onPressed: function(event) { event.accepted = true }

            BigPictureBackdrop { anchors.fill: parent; theme: tvTheme }
            MouseArea { anchors.fill: parent; hoverEnabled: true }

            Column {
                anchors.centerIn: parent
                spacing: 34

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.quittingName
                    color: tvTheme.text
                    font.pixelSize: 64
                    font.weight: Font.Light
                    font.letterSpacing: 2
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20

                    Item {
                        width: 40
                        height: 40
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 4
                            border.color: tvTheme.panelBorder
                        }
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.lineWidth = 4
                                ctx.lineCap = "round"
                                ctx.strokeStyle = tvTheme.moon
                                ctx.beginPath()
                                ctx.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2, Math.PI / 6)
                                ctx.stroke()
                            }
                            RotationAnimator on rotation {
                                from: 0; to: 360
                                duration: 1400
                                loops: Animation.Infinite
                                running: root.quitting
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Quitting…")
                        color: tvTheme.textMuted
                        font.pixelSize: tvTheme.fontBody + 4
                    }
                }
            }
        }
    }
}
