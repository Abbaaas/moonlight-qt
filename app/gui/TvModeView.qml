// TV mode home: a launcher-style menu of PCs and actions on the left,
// a glass preview panel on the right, and a prompt bar along the bottom.
import QtQuick
import QtQuick.Controls
import QtQuick.Window

import ComputerModel 1.0
import ComputerManager 1.0
import StreamingPreferences 1.0
import SdlGamepadKeyNavigation 1.0

Item {
    id: root
    objectName: qsTr("TV mode")

    TvTheme { id: tvTheme }

    property ComputerModel computerModel: createModel()

    function createModel() {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', root, '')
        model.initialize(ComputerManager)
        return model
    }

    // ---- Host state helpers -------------------------------------------------

    function hostState(m) {
        if (m.statusUnknown)             return "checking"
        if (!m.online)                   return m.wakeable ? "asleep" : "offline"
        if (!m.paired)                   return "unpaired"
        if (m.serverSupported === false) return "unsupported"
        return "ready"
    }

    function statusText(state) {
        switch (state) {
        case "checking":    return qsTr("Checking")
        case "asleep":      return qsTr("Asleep")
        case "offline":     return qsTr("Offline")
        case "unpaired":    return qsTr("Not paired")
        case "unsupported": return qsTr("Needs a host update")
        default:            return qsTr("Ready")
        }
    }

    function bodyText(state) {
        switch (state) {
        case "checking":    return qsTr("Looking for this PC on your network.")
        case "asleep":      return qsTr("This PC is asleep or turned off. Select it to send a wake signal.")
        case "offline":     return qsTr("Turn this PC on and make sure its streaming host is running.")
        case "unpaired":    return qsTr("Pair this PC in desktop mode, then come back to stream.")
        case "unsupported": return qsTr("Update the streaming host software on this PC.")
        default:            return qsTr("Choose a game to stream from this PC.")
        }
    }

    function actionVerb(state) {
        if (state === "ready")  return qsTr("Open games")
        if (state === "asleep") return qsTr("Wake PC")
        return ""
    }

    function openHost(index, m) {
        var state = hostState(m)
        if (state === "ready") {
            stackView.push("qrc:/gui/TvGamesView.qml",
                           { "computerIndex": index, "hostName": m.name })
        } else if (state === "asleep") {
            computerModel.wakeComputer(index)
            toast.show(qsTr("Wake signal sent to %1").arg(m.name))
        } else {
            toast.show(bodyText(state))
        }
    }

    function runAction(key) {
        if (key === "settings") {
            settingsButton.clicked()
        } else if (key === "desktop") {
            StreamingPreferences.tvMode = false
            StreamingPreferences.save()
            if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_MAXIMIZED)
                window.showMaximized()
            else if (StreamingPreferences.uiDisplayMode != StreamingPreferences.UI_FULLSCREEN)
                window.showNormal()
            stackView.replace(null, "qrc:/gui/PcView.qml")
        } else if (key === "exit") {
            quitConfirmationDialog.open()
        }
    }

    function takeFocus() {
        if (hostList.count > 0) hostList.forceActiveFocus()
        else actionList.forceActiveFocus()
    }

    // What the preview panel shows for the current selection.
    readonly property var preview: {
        if (actionList.activeFocus && actionList.currentItem) {
            var a = actionList.currentItem
            return { title: a.label, status: "", state: "action", body: a.desc, verb: a.verb, glyph: a.glyph }
        }
        if (hostList.currentItem) {
            var h = hostList.currentItem
            return { title: h.label, status: h.detail, state: h.hostStatus, body: root.bodyText(h.hostStatus),
                     verb: root.actionVerb(h.hostStatus), glyph: h.label.charAt(0).toUpperCase() }
        }
        return { title: qsTr("No PCs yet"), status: "", state: "empty", glyph: "",
                 body: qsTr("Turn on your gaming PC and start its streaming host. It will appear here automatically. To add a PC by IP address, use desktop mode."),
                 verb: "" }
    }

    // The stock toolbar is hidden on TV screens and shown again for Settings.
    // B on this screen asks whether to quit Moonlight (handled by main.qml).
    StackView.onActivated: {
        toolBar.visible = false
        takeFocus()
    }
    StackView.onDeactivating: toolBar.visible = true

    TvBackdrop { anchors.fill: parent; theme: tvTheme }

    Item {
        id: safe
        anchors.fill: parent
        anchors.leftMargin: tvTheme.safeX(root.width)
        anchors.rightMargin: tvTheme.safeX(root.width)
        anchors.topMargin: tvTheme.safeY(root.height)
        anchors.bottomMargin: tvTheme.safeY(root.height)

        // ---- Left column: brand and menu -----------------------------------
        Item {
            id: left
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: hints.top
            anchors.bottomMargin: 32
            width: Math.min(parent.width * 0.4, 640)

            Text {
                id: brand
                text: "Moonlight"
                color: tvTheme.text
                font.pixelSize: tvTheme.fontBrand
                font.weight: Font.Light
                font.letterSpacing: 3
                x: 38
            }
            Text {
                id: tagline
                anchors.top: brand.bottom
                x: 40
                text: qsTr("Stream games from your PC")
                color: tvTheme.textMuted
                font.pixelSize: tvTheme.fontSmall
            }

            Text {
                id: pcLabel
                anchors.top: tagline.bottom
                anchors.topMargin: 52
                x: 40
                text: qsTr("Your PCs")
                color: tvTheme.textFaint
                font.pixelSize: tvTheme.fontSmall
            }

            ListView {
                id: hostList
                anchors.top: pcLabel.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: divider.top
                anchors.bottomMargin: 20
                clip: true
                spacing: 6
                keyNavigationEnabled: true
                highlightMoveDuration: 160
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: height * 0.2
                preferredHighlightEnd: height * 0.8
                model: root.computerModel

                KeyNavigation.priority: KeyNavigation.AfterItem
                KeyNavigation.down: actionList

                delegate: TvMenuItem {
                    readonly property string hostStatus: root.hostState(model)
                    theme: tvTheme
                    label: model.name
                    detail: root.statusText(hostStatus)
                    dimmed: hostStatus === "offline" || hostStatus === "asleep"
                    barColor: hostStatus === "ready" ? tvTheme.moon : tvTheme.cool
                    current: ListView.isCurrentItem && hostList.activeFocus
                    onHovered: { hostList.currentIndex = index; hostList.forceActiveFocus() }
                    onActivated: root.openHost(index, model)
                    function activate() { root.openHost(index, model) }
                }

                Keys.onReturnPressed: if (currentItem) currentItem.activate()
                Keys.onEnterPressed:  if (currentItem) currentItem.activate()
            }

            Text {
                anchors.top: pcLabel.bottom
                anchors.topMargin: 24
                x: 40
                visible: hostList.count === 0
                text: qsTr("Searching your network…")
                color: tvTheme.textMuted
                font.pixelSize: tvTheme.fontBody
            }

            Rectangle {
                id: divider
                anchors.bottom: actionList.top
                anchors.bottomMargin: 16
                x: 40
                width: parent.width - 60
                height: 1
                color: tvTheme.panelBorder
            }

            ListView {
                id: actionList
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: count * 80 + (count - 1) * spacing
                spacing: 4
                interactive: false
                keyNavigationEnabled: true

                KeyNavigation.priority: KeyNavigation.AfterItem
                KeyNavigation.up: hostList.count > 0 ? hostList : null

                model: ListModel {
                    ListElement { key: "settings"; name: qsTr("Settings");       glyph: "S"
                                  desc: qsTr("Change video quality, frame rate, audio and controller options."); verb: qsTr("Open settings") }
                    ListElement { key: "desktop";  name: qsTr("Desktop mode");   glyph: "D"
                                  desc: qsTr("Go back to the standard windowed interface. TV mode turns off."); verb: qsTr("Switch") }
                    ListElement { key: "exit";     name: qsTr("Exit Moonlight"); glyph: "X"
                                  desc: qsTr("Close Moonlight."); verb: qsTr("Exit") }
                }

                delegate: TvMenuItem {
                    readonly property string desc: model.desc
                    readonly property string verb: model.verb
                    readonly property string glyph: model.glyph
                    theme: tvTheme
                    label: model.name
                    current: ListView.isCurrentItem && actionList.activeFocus
                    onHovered: { actionList.currentIndex = index; actionList.forceActiveFocus() }
                    onActivated: root.runAction(model.key)
                    function activate() { root.runAction(model.key) }
                }

                Keys.onReturnPressed: if (currentItem) currentItem.activate()
                Keys.onEnterPressed:  if (currentItem) currentItem.activate()
            }
        }

        // ---- Right: preview panel --------------------------------------------
        TvPanel {
            id: previewPanel
            theme: tvTheme
            anchors.left: left.right
            anchors.leftMargin: 64
            anchors.right: parent.right
            anchors.bottom: hints.top
            anchors.bottomMargin: 32
            height: Math.min(parent.height * 0.56, 560)

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 56
                anchors.rightMargin: 56
                spacing: 22

                // Glyph in a lunar ring.
                Rectangle {
                    width: 120; height: 120; radius: 60
                    visible: root.preview.glyph !== ""
                    color: "transparent"
                    border.width: 3
                    border.color: root.preview.state === "ready" || root.preview.state === "action"
                                  ? tvTheme.moon : tvTheme.textFaint
                    Text {
                        anchors.centerIn: parent
                        text: root.preview.glyph
                        color: parent.border.color
                        font.pixelSize: 56
                        font.weight: Font.Light
                    }
                }

                Text {
                    width: parent.width
                    text: root.preview.title
                    elide: Text.ElideRight
                    color: tvTheme.text
                    font.pixelSize: tvTheme.fontHeading
                    font.weight: Font.DemiBold
                }

                Row {
                    visible: root.preview.status !== ""
                    spacing: 12
                    Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.preview.state === "ready" ? tvTheme.moon
                             : root.preview.state === "unpaired" || root.preview.state === "unsupported" ? tvTheme.warn
                             : tvTheme.textFaint
                    }
                    Text {
                        text: root.preview.status
                        color: tvTheme.textMuted
                        font.pixelSize: tvTheme.fontBody
                    }
                }

                Text {
                    width: Math.min(parent.width, 760)
                    text: root.preview.body
                    wrapMode: Text.WordWrap
                    color: tvTheme.textMuted
                    font.pixelSize: tvTheme.fontBody
                    lineHeight: 1.35
                }
            }
        }

        // ---- Bottom: prompt bar ----------------------------------------------
        TvHintBar {
            id: hints
            theme: tvTheme
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            leftText: Qt.formatTime(clockTick.now, Qt.locale().timeFormat(Locale.ShortFormat))
            hints: root.preview.verb !== "" ? [ { button: "A", label: root.preview.verb } ] : []
        }

        Timer {
            id: clockTick
            property date now: new Date()
            interval: 10000; running: true; repeat: true
            onTriggered: now = new Date()
        }

        TvToast {
            id: toast
            theme: tvTheme
            anchors.horizontalCenter: previewPanel.horizontalCenter
            anchors.bottom: previewPanel.top
            anchors.bottomMargin: 24
        }
    }
}
