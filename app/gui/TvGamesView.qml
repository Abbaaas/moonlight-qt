// TV mode games for one PC: launcher-style game list on the left,
// box art preview on the right.
import QtQuick
import QtQuick.Controls

import AppModel 1.0
import ComputerManager 1.0

Item {
    id: root
    objectName: hostName

    property int computerIndex: -1
    property string hostName: ""

    property var appModel: null
    property int runningId: 0
    property string runningName: ""

    TvTheme { id: tvTheme }

    Component.onCompleted: {
        appModel = Qt.createQmlObject('import AppModel 1.0; AppModel {}', root, '')
        appModel.initialize(ComputerManager, computerIndex, false)   // false = hide hidden games
        gameList.model = appModel
        refreshRunning()
        gameList.forceActiveFocus()
    }

    function computerLost() {
        // Go back to the PC list if this PC disappears, like the stock game view does.
        stackView.pop()
    }

    // B goes back through main.qml's normal Escape handling.
    StackView.onActivated: {
        toolBar.visible = false
        appModel.computerLost.connect(computerLost)
        refreshRunning()
        gameList.forceActiveFocus()
    }
    StackView.onDeactivating: {
        appModel.computerLost.disconnect(computerLost)
    }

    // The host reports what's running; check regularly while this page is visible.
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
        if (runningId === 0 && quitItem.activeFocus)
            gameList.forceActiveFocus()
    }

    function launch(index, m) {
        if (runningId !== 0 && runningId !== m.appid) {
            toast.show(qsTr("Quit %1 first to start %2").arg(runningName).arg(m.name))
            quitItem.forceActiveFocus()
            return
        }
        var component = Qt.createComponent("StreamSegue.qml")
        if (component.status !== Component.Ready) {
            console.warn("TV mode: could not load StreamSegue.qml:", component.errorString())
            toast.show(qsTr("Couldn't start the stream"))
            return
        }
        var segue = component.createObject(stackView, {
            "appName": m.name,
            "session": appModel.createSessionForApp(index),
            "isResume": runningId === m.appid
        })
        stackView.push(segue)
    }

    // Uses Moonlight's own quit screen, which shows progress and any errors.
    function quitRunning() {
        if (runningId === 0) return
        var component = Qt.createComponent("QuitSegue.qml")
        stackView.push(component.createObject(stackView, {
            "appName": runningName,
            "quitRunningAppFn": function() { appModel.quitRunningApp() },
            "nextAppName": null,
            "nextSession": null
        }))
    }

    readonly property var sel: gameList.currentItem

    TvBackdrop { anchors.fill: parent; theme: tvTheme }

    Item {
        id: safe
        anchors.fill: parent
        anchors.leftMargin: tvTheme.safeX(root.width)
        anchors.rightMargin: tvTheme.safeX(root.width)
        anchors.topMargin: tvTheme.safeY(root.height)
        anchors.bottomMargin: tvTheme.safeY(root.height)

        // ---- Left column ----------------------------------------------------
        Item {
            id: left
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: hints.top
            anchors.bottomMargin: 32
            width: Math.min(parent.width * 0.4, 640)

            Text {
                id: title
                x: 38
                width: parent.width - 40
                text: root.hostName
                elide: Text.ElideRight
                color: tvTheme.text
                font.pixelSize: tvTheme.fontBrand
                font.weight: Font.Light
                font.letterSpacing: 2
            }
            Text {
                id: countLabel
                anchors.top: title.bottom
                x: 40
                text: gameList.count === 1 ? qsTr("1 game") : qsTr("%1 games").arg(gameList.count)
                color: tvTheme.textMuted
                font.pixelSize: tvTheme.fontSmall
            }

            TvMenuItem {
                id: quitItem
                theme: tvTheme
                anchors.top: countLabel.bottom
                anchors.topMargin: 36
                width: parent.width
                visible: root.runningId !== 0
                height: visible ? 104 : 0
                label: qsTr("Quit %1").arg(root.runningName)
                detail: qsTr("Ends the game on your PC")
                barColor: tvTheme.warn
                current: activeFocus
                activeFocusOnTab: true
                KeyNavigation.down: gameList
                onHovered: forceActiveFocus()
                onActivated: root.quitRunning()
                Keys.onReturnPressed: root.quitRunning()
                Keys.onEnterPressed:  root.quitRunning()
            }

            ListView {
                id: gameList
                anchors.top: quitItem.bottom
                anchors.topMargin: quitItem.visible ? 12 : 36
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                spacing: 4
                keyNavigationEnabled: true
                highlightMoveDuration: 160
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: height * 0.3
                preferredHighlightEnd: height * 0.7

                KeyNavigation.priority: KeyNavigation.AfterItem
                KeyNavigation.up: quitItem.visible ? quitItem : null

                delegate: TvMenuItem {
                    readonly property url boxart: model.boxart
                    readonly property bool running: model.running
                    theme: tvTheme
                    label: model.name
                    detail: model.running ? qsTr("Running") : ""
                    current: ListView.isCurrentItem && gameList.activeFocus
                    onHovered: { gameList.currentIndex = index; gameList.forceActiveFocus() }
                    onActivated: root.launch(index, model)
                    function activate() { root.launch(index, model) }
                }

                Keys.onReturnPressed: if (currentItem) currentItem.activate()
                Keys.onEnterPressed:  if (currentItem) currentItem.activate()
            }

            Text {
                anchors.top: countLabel.bottom
                anchors.topMargin: 48
                x: 40
                visible: gameList.count === 0
                text: qsTr("Loading games…")
                color: tvTheme.textMuted
                font.pixelSize: tvTheme.fontBody
            }
        }

        // ---- Right: box art preview -----------------------------------------
        TvPanel {
            id: previewPanel
            theme: tvTheme
            anchors.left: left.right
            anchors.leftMargin: 64
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.12
            anchors.bottom: hints.top
            anchors.bottomMargin: 32
            visible: root.sel !== null

            Image {
                id: art
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 40
                width: height * 0.71
                source: root.sel ? root.sel.boxart : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Column {
                anchors.left: art.right
                anchors.leftMargin: 48
                anchors.right: parent.right
                anchors.rightMargin: 48
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20

                Text {
                    width: parent.width
                    text: root.sel ? root.sel.label : ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: tvTheme.text
                    font.pixelSize: tvTheme.fontHeading
                    font.weight: Font.DemiBold
                }
                Row {
                    spacing: 12
                    Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.sel && root.sel.running ? tvTheme.moon : tvTheme.textFaint
                    }
                    Text {
                        text: root.sel && root.sel.running ? qsTr("Running on %1").arg(root.hostName)
                                                           : qsTr("Ready to play")
                        color: tvTheme.textMuted
                        font.pixelSize: tvTheme.fontBody
                    }
                }
            }
        }

        // ---- Bottom: prompt bar ---------------------------------------------
        TvHintBar {
            id: hints
            theme: tvTheme
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            leftText: root.hostName
            hints: quitItem.activeFocus
                   ? [ { button: "A", label: qsTr("Quit game") }, { button: "B", label: qsTr("Back") } ]
                   : [ { button: "A", label: root.sel && root.sel.running ? qsTr("Resume") : qsTr("Play") },
                       { button: "B", label: qsTr("Back") } ]
        }

        TvToast {
            id: toast
            theme: tvTheme
            anchors.horizontalCenter: previewPanel.horizontalCenter
            anchors.bottom: hints.top
            anchors.bottomMargin: 24
        }
    }
}
