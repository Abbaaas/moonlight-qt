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
            "isResume": runningId === item.appId
        }))
    }

    function quitThenStart(index, name) {
        var component = Qt.createComponent("QuitSegue.qml")
        stackView.push(component.createObject(stackView, {
            "appName": runningName,
            "quitRunningAppFn": function() { appModel.quitRunningApp() },
            "nextAppName": name,
            "nextSession": appModel.createSessionForApp(index)
        }))
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
            if (role !== "quit") return
            var component = Qt.createComponent("QuitSegue.qml")
            stackView.push(component.createObject(stackView, {
                "appName": root.runningName,
                "quitRunningAppFn": function() { root.appModel.quitRunningApp() },
                "nextAppName": null,
                "nextSession": null
            }))
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
        if (event.key === Qt.Key_Menu || event.key === Qt.Key_Delete) {
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
                leftText: appGrid.currentItem ? appGrid.currentItem.name : ""
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
    }
}
