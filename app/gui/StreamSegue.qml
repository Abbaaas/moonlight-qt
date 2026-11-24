import QtQuick
import QtQuick.Controls 2.2
import QtQuick.Window 2.2

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import SystemProperties 1.0
import BigPicture 1.0

Item {
    property Session session
    property string appName
    property string stageText : isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false

    // Set when launched from Big Picture: this screen then uses the Big
    // Picture look, and errors go to bigPictureError(title, text, helpUrl)
    // (shown in Big Picture's own dialog) instead of the desktop dialog.
    property bool bigPicture : false
    property var bigPictureError : null
    property string bigPictureStatus : isResume ? qsTr("Resuming…") : qsTr("Starting…")

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1...").arg(stage)
        bigPictureStatus = qsTr("Starting %1…").arg(stage)
    }

    function stageFailed(stage, errorCode, failingPorts)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = qsTr("Starting %1 failed: Error %2").arg(stage).arg(errorCode)

        if (failingPorts) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts)
        }
    }

    function connectionStarted()
    {
        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        stageSpinner.visible = false
        stageLabel.visible = false
        hintText.visible = false

        // Hide the window now that streaming has begun
        window.visible = false
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = text
        console.error(text)
    }

    function quitStarting()
    {
        // Avoid the push transition animation
        var component = Qt.createComponent("QuitSegue.qml")
        stackView.replace(stackView.currentItem, component.createObject(stackView, {"appName": appName}), StackView.Immediate)

        // Show the Qt window again to show quit segue
        window.visible = true
    }

    function sessionFinished(portTestResult)
    {
        if (portTestResult !== 0 && portTestResult !== -1 && streamSegueErrorDialog.text) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // Pop the StreamSegue off the stack if this is a GUI-based app launch
        if (!quitAfter) {
            stackView.pop()
        }

        if (quitAfter && !streamSegueErrorDialog.text) {
            // If this was a CLI launch without errors, exit now
            Qt.quit()
        }
        else {
            // Show the Qt window again after streaming
            window.visible = true

            // Display any launch errors. We do this after
            // the Qt UI is visible again to prevent losing
            // focus on the dialog which would impact gamepad
            // users.
            if (streamSegueErrorDialog.text && bigPicture && bigPictureError) {
                // Big Picture shows the error in its own controller dialog
                var errorText = streamSegueErrorDialog.text
                streamSegueErrorDialog.text = ""
                bigPictureError(qsTr("Couldn't stream %1").arg(appName), errorText, streamSegueErrorDialog.helpUrl)
            }
            else if (streamSegueErrorDialog.text) {
                streamSegueErrorDialog.quitAfter = quitAfter
                streamSegueErrorDialog.open()
            }
        }
    }

    function sessionReadyForDeletion()
    {
        // Garbage collect the Session object since it's pretty heavyweight
        // and keeps other libraries (like SDL_TTF) around until it is deleted.
        session = null
        gc()
    }

    StackView.onDeactivating: {
        // Show the toolbar again when popped off the stack
        toolBar.visible = true

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()
    }

    StackView.onActivated: {
        // Hide the toolbar before we start loading
        toolBar.visible = false

        // Hook up our signals
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.readyForDeletion.connect(sessionReadyForDeletion)

        // Ensure the SystemProperties async thread is finished,
        // since it may currently be using the SDL video subsystem
        SystemProperties.waitForAsyncLoad()

        // Kick off the stream
        streamLoader.active = true
    }

    Timer {
        id: startSessionTimer
        onTriggered: {
            // Garbage collect QML stuff before we start streaming,
            // since we'll probably be streaming for a while and we
            // won't be able to GC during the stream.
            gc()

            // Run the streaming session to completion
            session.start()
        }
    }

    Loader {
        id: streamLoader
        active: false
        asynchronous: true

        onLoaded: {
            // Set the hint text. We do this here rather than
            // in the hintText control itself to synchronize
            // with Session.exec() which requires no concurrent
            // gamepad usage.
            hintText.text = qsTr("Tip:") + " " + qsTr("Press %1 to disconnect your session").arg(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ?
                                                  qsTr("Start+Select+L1+R1") : qsTr("Ctrl+Alt+Shift+Q"))

            // Same tip in the Big Picture look, named for the controller in use
            if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
                bigPictureHint.text = BigPicture.glyphs === "playstation"
                        ? qsTr("To disconnect, press Options + Create + L1 + R1")
                        : BigPicture.glyphs === "xbox"
                          ? qsTr("To disconnect, press Menu + View + LB + RB")
                          : qsTr("To disconnect, press Start + Select + L1 + R1")
            } else {
                bigPictureHint.text = qsTr("To disconnect, press Ctrl + Alt + Shift + Q")
            }

            // Stop GUI gamepad usage now
            SdlGamepadKeyNavigation.disable()

            // Initialize the session and probe for host/client capabilities
            if (!session.initialize(window)) {
                sessionFinished(0);
                sessionReadyForDeletion();
                return;
            }

            // This spinner is shown only after session.initialize() has completed
            // to prevent active animations from running during decoder probing,
            // which causes re-entrant event loop livelocks with libdecor-gtk.
            stageSpinner.visible = true

            // Don't wait unless we have toasts to display
            startSessionTimer.interval = 0

            // Display the toasts together in a vertical centered arrangement
            var yOffset = 0
            for (var i = 0; i < session.launchWarnings.length; i++) {
                var text = session.launchWarnings[i]
                console.warn(text)

                // Show the tooltip for 3 seconds
                var toast = Qt.createQmlObject('import QtQuick.Controls 2.2; ToolTip {}', parent, '')
                toast.timeout = 3000
                toast.text = text
                toast.y += yOffset
                toast.visible = true

                // Offset the next toast below the previous one
                yOffset = toast.y + toast.padding + toast.height

                // Allow an extra 500 ms for the tooltip's fade-out animation to finish
                startSessionTimer.interval = toast.timeout + 500;
            }

            // Start the timer to wait for toasts (or start the session immediately)
            startSessionTimer.start()
        }

        sourceComponent: Item {}
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
            // Hidden together with the desktop label once the stream starts
            visible: stageLabel.visible

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

                // A calm ring spinner; shown at the same moment as the desktop
                // one (after session.initialize()), for the same reason.
                Item {
                    width: 40
                    height: 40
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: stageSpinner.visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 4
                        border.color: bpTheme.panelBorder
                    }
                    Canvas {
                        id: bpArc
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
                            running: bigPicture && stageSpinner.visible
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bigPictureStatus
                    color: bpTheme.textMuted
                    font.pixelSize: bpTheme.fontBody + 4
                }
            }
        }

        Text {
            id: bigPictureHint
            visible: stageLabel.visible
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 80
            color: bpTheme.textMuted
            font.pixelSize: bpTheme.fontSmall + 2
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
            visible: false
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

    Label {
        id: hintText
        opacity: bigPicture ? 0 : 1
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        font.pointSize: 18
        verticalAlignment: Text.AlignVCenter

        wrapMode: Text.Wrap
    }
}
