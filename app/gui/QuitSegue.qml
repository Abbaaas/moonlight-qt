import QtQuick
import QtQuick.Controls 2.2

import ComputerManager 1.0
import Session 1.0
import BigPicture 1.0

Item {
    property string appName
    property var quitRunningAppFn
    property Session nextSession : null
    property string nextAppName : ""

    // Set when started from Big Picture (see StreamSegue)
    property bool bigPicture : false
    property var bigPictureError : null

    property string stageText : qsTr("Quitting %1...").arg(appName)

    function quitAppCompleted(error)
    {
        // Display a failed dialog if we got an error
        if (error !== undefined && !(bigPicture && bigPictureError)) {
            errorDialog.text = error
            errorDialog.open()
        }
        if (error !== undefined) {
            console.error(error)
        }

        // If we're supposed to launch another game after this, do so now
        if (error === undefined && nextSession !== null) {
            var component = Qt.createComponent("StreamSegue.qml")
            var segue = component.createObject(stackView, {"appName": nextAppName, "session": nextSession,
                                                           "bigPicture": bigPicture, "bigPictureError": bigPictureError})
            stackView.replace(segue)
        }
        else {
            // Exit this view
            stackView.pop()

            // Big Picture shows the error in its own controller dialog
            if (error !== undefined && bigPicture && bigPictureError) {
                bigPictureError(qsTr("Couldn't quit %1").arg(appName), error, errorDialog.helpUrl)
            }
        }
    }

    StackView.onActivated: {
        // Hide the toolbar before we start loading
        toolBar.visible = false

        // Connect the quit completion signal
        ComputerManager.quitAppCompleted.connect(quitAppCompleted)

        // Start the quit operation if requested
        if (quitRunningAppFn) {
            quitRunningAppFn()
        }
    }

    StackView.onDeactivating: {
        // Show the toolbar again
        toolBar.visible = true

        // Disconnect the signal
        ComputerManager.quitAppCompleted.disconnect(quitAppCompleted)
    }

    // ---- Big Picture look ----
    BigPictureTheme { id: bpTheme }

    BigPictureBackdrop {
        anchors.fill: parent
        theme: bpTheme
        visible: bigPicture
    }

    Item {
        id: bpStage
        visible: bigPicture
        readonly property real k: bpTheme.stageScale(parent.width, parent.height)
        width: parent.width / k
        height: parent.height / k
        scale: k
        transformOrigin: Item.TopLeft

        Column {
            anchors.centerIn: parent
            spacing: 34

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, bpStage.width * 0.8)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: appName
                color: bpTheme.text
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
                        border.color: bpTheme.panelBorder
                    }
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.lineWidth = 4
                            ctx.lineCap = "round"
                            ctx.strokeStyle = bpTheme.moon
                            ctx.beginPath()
                            ctx.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2, Math.PI / 6)
                            ctx.stroke()
                        }
                        RotationAnimator on rotation {
                            from: 0; to: 360
                            duration: 1400
                            loops: Animation.Infinite
                            running: bigPicture
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Quitting…")
                    color: bpTheme.textMuted
                    font.pixelSize: bpTheme.fontBody + 4
                }
            }
        }
    }

    // ---- Desktop look ----
    Row {
        anchors.centerIn: parent
        spacing: 5
        opacity: bigPicture ? 0 : 1

        BusyIndicator {
            id: stageSpinner
            running: visible && !bigPicture
        }

        Label {
            id: stageLabel
            height: stageSpinner.height
            text: stageText
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.Wrap
        }
    }

    ErrorMessageDialog {
        id: errorDialog
    }
}
