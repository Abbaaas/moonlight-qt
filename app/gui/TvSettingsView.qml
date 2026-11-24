// TV mode settings: one long, sectioned list you drive with the D-pad.
// Up/Down picks a setting, Left/Right changes it, A toggles or resets it,
// B goes back. The panel on the right explains the selected setting.
import QtQuick
import QtQuick.Controls

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

Item {
    id: root
    objectName: qsTr("Settings")

    TvTheme { id: tvTheme }

    // Bumped after every change so value labels re-read the preferences.
    property int revision: 0

    // ---- Helpers -------------------------------------------------------------

    function autoBitrate() {
        if (StreamingPreferences.autoAdjustBitrate) {
            StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                        StreamingPreferences.width, StreamingPreferences.height,
                        StreamingPreferences.fps, StreamingPreferences.enableYUV444)
        }
    }

    function maxBitrate() {
        return StreamingPreferences.unlockBitrate ? 500000 : 150000
    }

    function onOff(v) { return v ? qsTr("On") : qsTr("Off") }

    // A setting that switches between a fixed list of choices.
    // options: [{ label, val }], get(): current val, set(val)
    function choice(section, label, desc, options, get, set, extra) {
        var row = { section: section, label: label, desc: desc, kind: "choice",
                    options: options, get: get, set: set }
        for (var k in extra) row[k] = extra[k]
        return row
    }

    // An on/off setting.
    function toggle(section, label, desc, get, set, extra) {
        var row = { section: section, label: label, desc: desc, kind: "toggle",
                    get: get, set: set }
        for (var k in extra) row[k] = extra[k]
        return row
    }

    function indexOfVal(row) {
        var cur = row.get()
        for (var i = 0; i < row.options.length; i++) {
            if (row.options[i].val === cur) return i
        }
        return -1
    }

    function valueText(row) {
        if (row.kind === "toggle") return onOff(row.get())
        if (row.kind === "choice") {
            var i = indexOfVal(row)
            return i >= 0 ? row.options[i].label : (row.customLabel ? row.customLabel() : "")
        }
        if (row.kind === "bitrate") {
            var mbps = StreamingPreferences.bitrateKbps / 1000
            return StreamingPreferences.autoAdjustBitrate ? qsTr("%1 Mbps (automatic)").arg(mbps)
                                                          : qsTr("%1 Mbps").arg(mbps)
        }
        return ""
    }

    function isEnabled(row) {
        return row.enabled === undefined ? true : row.enabled()
    }

    function changeValue(row, dir) {
        if (!row || !isEnabled(row)) return
        if (row.kind === "toggle") {
            row.set(!row.get())
        } else if (row.kind === "choice") {
            var i = indexOfVal(row)
            var n = row.options.length
            i = i < 0 ? (dir > 0 ? 0 : n - 1) : (i + dir + n) % n
            row.set(row.options[i].val)
        } else if (row.kind === "bitrate") {
            // 1 Mbps steps up to 20 Mbps, then 5 Mbps steps.
            var cur = StreamingPreferences.bitrateKbps
            var step = (dir > 0 ? cur >= 20000 : cur > 20000) ? 5000 : 1000
            var next = Math.max(500, Math.min(maxBitrate(), cur + dir * step))
            if (next !== cur) {
                StreamingPreferences.bitrateKbps = next
                StreamingPreferences.autoAdjustBitrate = false
            }
        } else if (row.kind === "action" && dir === 0) {
            row.run()
        }
        revision++
    }

    function activate(row) {
        if (!row || !isEnabled(row)) return
        if (row.kind === "bitrate") {
            // A puts the bitrate back on automatic.
            StreamingPreferences.autoAdjustBitrate = true
            autoBitrate()
            revision++
        } else if (row.kind === "action") {
            row.run()
        } else {
            changeValue(row, 1)
        }
    }

    // ---- The settings ------------------------------------------------------

    readonly property var rows: buildRows()

    function buildRows() {
        var video = qsTr("Video")
        var audio = qsTr("Audio")
        var host = qsTr("Host and games")
        var input = qsTr("Controllers and input")
        var app = qsTr("Moonlight")
        var r = []

        // Video
        r.push(choice(video, qsTr("Resolution"),
                      qsTr("The size of the picture your PC sends. Higher looks sharper but needs a faster PC and network."),
                      [ { label: "720p",  val: "1280x720" },
                        { label: "1080p", val: "1920x1080" },
                        { label: "1440p", val: "2560x1440" },
                        { label: "4K",    val: "3840x2160" } ],
                      function() { return StreamingPreferences.width + "x" + StreamingPreferences.height },
                      function(v) {
                          var p = v.split("x")
                          StreamingPreferences.width = parseInt(p[0])
                          StreamingPreferences.height = parseInt(p[1])
                          autoBitrate()
                      },
                      { customLabel: function() { return qsTr("Custom (%1×%2)").arg(StreamingPreferences.width).arg(StreamingPreferences.height) } }))

        r.push(choice(video, qsTr("Frame rate"),
                      qsTr("Frames per second. Match your TV's refresh rate for the smoothest picture."),
                      [ { label: qsTr("30 FPS"),  val: 30 },
                        { label: qsTr("60 FPS"),  val: 60 },
                        { label: qsTr("90 FPS"),  val: 90 },
                        { label: qsTr("120 FPS"), val: 120 },
                        { label: qsTr("144 FPS"), val: 144 },
                        { label: qsTr("165 FPS"), val: 165 },
                        { label: qsTr("240 FPS"), val: 240 } ],
                      function() { return StreamingPreferences.fps },
                      function(v) { StreamingPreferences.fps = v; autoBitrate() },
                      { customLabel: function() { return qsTr("%1 FPS").arg(StreamingPreferences.fps) } }))

        r.push({ section: video, kind: "bitrate", label: qsTr("Video bitrate"),
                 desc: qsTr("Lower it on slower connections, raise it for better image quality. Press A to go back to the automatic value for your resolution and frame rate.") })

        r.push(choice(video, qsTr("Display mode"),
                      qsTr("How the stream fills your screen. Fullscreen usually performs best."),
                      [ { label: qsTr("Fullscreen"),          val: StreamingPreferences.WM_FULLSCREEN },
                        { label: qsTr("Borderless windowed"), val: StreamingPreferences.WM_FULLSCREEN_DESKTOP },
                        { label: qsTr("Windowed"),            val: StreamingPreferences.WM_WINDOWED } ],
                      function() { return StreamingPreferences.windowMode },
                      function(v) { StreamingPreferences.windowMode = v },
                      { visible: SystemProperties.hasDesktopEnvironment,
                        enabled: function() { return !SystemProperties.rendererAlwaysFullScreen } }))

        r.push(toggle(video, qsTr("V-Sync"),
                      qsTr("Prevents tearing. Turning it off can lower latency a little but may show tearing."),
                      function() { return StreamingPreferences.enableVsync },
                      function(v) { StreamingPreferences.enableVsync = v }))

        r.push(toggle(video, qsTr("Frame pacing"),
                      qsTr("Smooths out micro-stutter by holding back frames that arrive too early. Needs V-Sync."),
                      function() { return StreamingPreferences.enableVsync && StreamingPreferences.framePacing },
                      function(v) { StreamingPreferences.framePacing = v },
                      { enabled: function() { return StreamingPreferences.enableVsync } }))

        r.push(toggle(video, qsTr("HDR"),
                      SystemProperties.supportsHdr
                          ? qsTr("Streams in HDR when the game and your PC support it.")
                          : qsTr("This display or PC doesn't support HDR streaming."),
                      function() { return SystemProperties.supportsHdr && StreamingPreferences.enableHdr },
                      function(v) { StreamingPreferences.enableHdr = v },
                      { enabled: function() { return SystemProperties.supportsHdr } }))

        r.push(toggle(video, qsTr("YUV 4:4:4"),
                      qsTr("Sharper colors and text, at the cost of a higher bitrate. Needs a supported host and GPU."),
                      function() { return StreamingPreferences.enableYUV444 },
                      function(v) { StreamingPreferences.enableYUV444 = v; autoBitrate() }))

        r.push(choice(video, qsTr("Video decoder"),
                      qsTr("Leave on Automatic unless you're fixing a problem."),
                      [ { label: qsTr("Automatic"),       val: StreamingPreferences.VDS_AUTO },
                        { label: qsTr("Force hardware"),  val: StreamingPreferences.VDS_FORCE_HARDWARE },
                        { label: qsTr("Force software"),  val: StreamingPreferences.VDS_FORCE_SOFTWARE } ],
                      function() { return StreamingPreferences.videoDecoderSelection },
                      function(v) { StreamingPreferences.videoDecoderSelection = v }))

        r.push(choice(video, qsTr("Video codec"),
                      qsTr("Leave on Automatic unless you're fixing a problem. AV1 needs Sunshine and a supported GPU."),
                      [ { label: qsTr("Automatic"),    val: StreamingPreferences.VCC_AUTO },
                        { label: "H.264",              val: StreamingPreferences.VCC_FORCE_H264 },
                        { label: "HEVC (H.265)",       val: StreamingPreferences.VCC_FORCE_HEVC },
                        { label: "AV1",                val: StreamingPreferences.VCC_FORCE_AV1 } ],
                      function() { return StreamingPreferences.videoCodecConfig },
                      function(v) { StreamingPreferences.videoCodecConfig = v }))

        r.push(toggle(video, qsTr("Unlock bitrate limit"),
                      qsTr("Allows very high bitrates. Only use this on a wired network with Sunshine."),
                      function() { return StreamingPreferences.unlockBitrate },
                      function(v) {
                          StreamingPreferences.unlockBitrate = v
                          StreamingPreferences.bitrateKbps = Math.min(StreamingPreferences.bitrateKbps, maxBitrate())
                      }))

        // Audio
        r.push(choice(audio, qsTr("Audio channels"),
                      qsTr("Match your speakers or sound system."),
                      [ { label: qsTr("Stereo"),       val: StreamingPreferences.AC_STEREO },
                        { label: qsTr("5.1 surround"), val: StreamingPreferences.AC_51_SURROUND },
                        { label: qsTr("7.1 surround"), val: StreamingPreferences.AC_71_SURROUND } ],
                      function() { return StreamingPreferences.audioConfig },
                      function(v) { StreamingPreferences.audioConfig = v }))

        r.push(toggle(audio, qsTr("Mute the host PC's speakers"),
                      qsTr("Sound plays only here, not on the gaming PC. Restart any running game for this to apply."),
                      function() { return !StreamingPreferences.playAudioOnHost },
                      function(v) { StreamingPreferences.playAudioOnHost = !v }))

        r.push(toggle(audio, qsTr("Mute when Moonlight isn't in front"),
                      qsTr("Silences the stream when you switch to another window."),
                      function() { return StreamingPreferences.muteOnFocusLoss },
                      function(v) { StreamingPreferences.muteOnFocusLoss = v },
                      { visible: SystemProperties.hasDesktopEnvironment }))

        // Host and games
        r.push(toggle(host, qsTr("Optimize game settings for streaming"),
                      qsTr("Lets the host adjust game settings to suit the stream."),
                      function() { return StreamingPreferences.gameOptimizations },
                      function(v) { StreamingPreferences.gameOptimizations = v }))

        r.push(toggle(host, qsTr("Quit the game when the stream ends"),
                      qsTr("Closes the game on your PC when you stop streaming. Unsaved progress is lost."),
                      function() { return StreamingPreferences.quitAppAfter },
                      function(v) { StreamingPreferences.quitAppAfter = v }))

        r.push(toggle(host, qsTr("Find PCs on the network automatically"),
                      qsTr("Recommended. Turn off only if you add PCs by IP address."),
                      function() { return StreamingPreferences.enableMdns },
                      function(v) {
                          if (StreamingPreferences.enableMdns === v) return
                          StreamingPreferences.enableMdns = v
                          // Restart polling so the change takes effect
                          if (window.pollingActive) {
                              ComputerManager.stopPollingAsync()
                              ComputerManager.startPolling()
                          }
                      }))

        r.push(toggle(host, qsTr("Detect blocked connections"),
                      qsTr("Recommended. Warns you when a firewall or network is blocking streaming."),
                      function() { return StreamingPreferences.detectNetworkBlocking },
                      function(v) { StreamingPreferences.detectNetworkBlocking = v }))

        // Controllers and input
        r.push(toggle(input, qsTr("Swap A/B and X/Y"),
                      qsTr("Uses a Nintendo-style button layout."),
                      function() { return StreamingPreferences.swapFaceButtons },
                      function(v) { StreamingPreferences.swapFaceButtons = v }))

        r.push(toggle(input, qsTr("Keep controller 1 always connected"),
                      qsTr("The host always sees one controller, even when none is plugged in here."),
                      function() { return !StreamingPreferences.multiController },
                      function(v) { StreamingPreferences.multiController = !v }))

        r.push(toggle(input, qsTr("Hold Start to control the mouse"),
                      qsTr("Holding Start on a controller switches it to mouse control."),
                      function() { return StreamingPreferences.gamepadMouse },
                      function(v) { StreamingPreferences.gamepadMouse = v }))

        r.push(toggle(input, qsTr("Use controllers in the background"),
                      qsTr("Controllers keep working even when Moonlight isn't the window in front."),
                      function() { return StreamingPreferences.backgroundGamepad },
                      function(v) { StreamingPreferences.backgroundGamepad = v },
                      { visible: SystemProperties.hasDesktopEnvironment }))

        r.push(toggle(input, qsTr("Mouse mode for remote desktop"),
                      qsTr("Smooth mouse control for desktop use. Doesn't work in most games."),
                      function() { return StreamingPreferences.absoluteMouseMode },
                      function(v) { StreamingPreferences.absoluteMouseMode = v }))

        r.push(toggle(input, qsTr("Swap mouse buttons"),
                      qsTr("Swaps the left and right mouse buttons."),
                      function() { return StreamingPreferences.swapMouseButtons },
                      function(v) { StreamingPreferences.swapMouseButtons = v }))

        r.push(toggle(input, qsTr("Reverse scrolling"),
                      qsTr("Flips the mouse scroll direction."),
                      function() { return StreamingPreferences.reverseScrollDirection },
                      function(v) { StreamingPreferences.reverseScrollDirection = v }))

        r.push(choice(input, qsTr("Capture system shortcuts"),
                      qsTr("Sends shortcuts like Alt+Tab to the host instead of this PC."),
                      [ { label: qsTr("Off"),           val: StreamingPreferences.CSK_OFF },
                        { label: qsTr("In fullscreen"), val: StreamingPreferences.CSK_FULLSCREEN },
                        { label: qsTr("Always"),        val: StreamingPreferences.CSK_ALWAYS } ],
                      function() { return StreamingPreferences.captureSysKeysMode },
                      function(v) { StreamingPreferences.captureSysKeysMode = v },
                      { visible: SystemProperties.hasDesktopEnvironment }))

        // Moonlight
        r.push(toggle(app, qsTr("Start in TV mode"),
                      qsTr("Opens Moonlight.exe straight into TV mode. MoonlightTvMode.exe always opens in TV mode either way."),
                      function() { return StreamingPreferences.tvMode },
                      function(v) { StreamingPreferences.tvMode = v }))

        r.push(toggle(app, qsTr("Show performance stats"),
                      qsTr("Shows frame rate, latency and other stats on top of the stream."),
                      function() { return StreamingPreferences.showPerformanceOverlay },
                      function(v) { StreamingPreferences.showPerformanceOverlay = v }))

        r.push(toggle(app, qsTr("Connection quality warnings"),
                      qsTr("Shows a warning during the stream when the network is struggling."),
                      function() { return StreamingPreferences.connectionWarnings },
                      function(v) { StreamingPreferences.connectionWarnings = v }))

        r.push(toggle(app, qsTr("Configuration warnings"),
                      qsTr("Warns at startup about problems like missing hardware decoding."),
                      function() { return StreamingPreferences.configurationWarnings },
                      function(v) { StreamingPreferences.configurationWarnings = v }))

        r.push(toggle(app, qsTr("Keep the display awake"),
                      qsTr("Stops the screensaver or display sleep while streaming."),
                      function() { return StreamingPreferences.keepAwake },
                      function(v) { StreamingPreferences.keepAwake = v }))

        r.push(toggle(app, qsTr("Discord status"),
                      qsTr("Shows the game you're streaming in your Discord status."),
                      function() { return StreamingPreferences.richPresence },
                      function(v) { StreamingPreferences.richPresence = v },
                      { visible: SystemProperties.hasDiscordIntegration }))

        r.push({ section: app, kind: "action", label: qsTr("Gamepad mapper"),
                 desc: qsTr("Map the buttons of a controller Moonlight doesn't recognize."),
                 run: function() { stackView.push("qrc:/gui/GamepadMapper.qml") } })

        r.push({ section: app, kind: "action", label: qsTr("More settings"),
                 desc: qsTr("Opens the full desktop settings page for options like language, custom resolutions and the interface window mode."),
                 run: function() { stackView.push("qrc:/gui/SettingsView.qml") } })

        return r.filter(function(row) { return row.visible === undefined || row.visible })
    }

    readonly property var current: list.currentIndex >= 0 ? rows[list.currentIndex] : null

    // ---- Lifecycle -------------------------------------------------------------

    StackView.onActivated: {
        toolBar.visible = false
        revision++
        list.forceActiveFocus()
    }

    StackView.onDeactivating: {
        toolBar.visible = true
        // Save so a stream started next picks up the changes
        StreamingPreferences.save()
    }

    Component.onDestruction: StreamingPreferences.save()

    // ---- Layout ----------------------------------------------------------------

    TvBackdrop { anchors.fill: parent; theme: tvTheme }

    Item {
        id: safe
        anchors.fill: parent
        anchors.leftMargin: tvTheme.safeX(root.width)
        anchors.rightMargin: tvTheme.safeX(root.width)
        anchors.topMargin: tvTheme.safeY(root.height)
        anchors.bottomMargin: tvTheme.safeY(root.height)

        Item {
            id: left
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: hints.top
            anchors.bottomMargin: 32
            width: Math.min(parent.width * 0.56, 900)

            Text {
                id: title
                x: 38
                text: qsTr("Settings")
                color: tvTheme.text
                font.pixelSize: tvTheme.fontBrand
                font.weight: Font.Light
                font.letterSpacing: 3
            }

            ListView {
                id: list
                anchors.top: title.bottom
                anchors.topMargin: 24
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                spacing: 4
                focus: true
                model: root.rows
                keyNavigationEnabled: true
                highlightMoveDuration: 140
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: height * 0.25
                preferredHighlightEnd: height * 0.75

                delegate: Item {
                    id: rowItem
                    readonly property var row: modelData
                    readonly property bool current: ListView.isCurrentItem && list.activeFocus
                    readonly property bool usable: { root.revision; return root.isEnabled(row) }
                    readonly property string valueText: { root.revision; return root.valueText(row) }

                    readonly property bool firstInSection:
                        index === 0 || root.rows[index - 1].section !== row.section

                    width: ListView.view.width
                    height: 80 + (firstInSection ? headerHeight : 0)
                    readonly property int headerHeight: index === 0 ? 44 : 64

                    Text {
                        visible: rowItem.firstInSection
                        x: 40
                        y: rowItem.headerHeight - height - 8
                        text: rowItem.row.section
                        color: tvTheme.textFaint
                        font.pixelSize: tvTheme.fontSmall
                    }

                    // Everything below the section header.
                    Item {
                        id: body
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 80

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        radius: 14
                        color: rowItem.current ? tvTheme.moonA(0.09) : "transparent"
                        border.width: rowItem.current ? 1 : 0
                        border.color: tvTheme.moonA(0.35)
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: rowItem.current ? parent.height * 0.6 : 0
                        radius: 3
                        color: tvTheme.moon
                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: rowItem.current ? 50 : 40
                        width: parent.width - x - valueBox.width - 48
                        text: rowItem.row.label
                        elide: Text.ElideRight
                        font.pixelSize: tvTheme.fontBody + 2
                        font.weight: rowItem.current ? Font.DemiBold : Font.Normal
                        color: !rowItem.usable ? tvTheme.textFaint
                                               : (rowItem.current ? tvTheme.text : tvTheme.textMuted)
                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    // Value: an on/off pill for toggles, ‹ value › for choices.
                    Item {
                        id: valueBox
                        anchors.right: parent.right
                        anchors.rightMargin: 24
                        anchors.verticalCenter: parent.verticalCenter
                        width: rowItem.row.kind === "toggle" ? 76
                             : rowItem.row.kind === "action" ? 40
                             : Math.max(valueLabel.implicitWidth + 64, 180)
                        height: 44

                        // Toggle pill
                        Rectangle {
                            visible: rowItem.row.kind === "toggle"
                            readonly property bool on: rowItem.valueText === root.onOff(true)
                            anchors.fill: parent
                            radius: height / 2
                            color: on && rowItem.usable ? tvTheme.moon : "transparent"
                            border.width: 2
                            border.color: on && rowItem.usable ? tvTheme.moon : tvTheme.textFaint
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                anchors.verticalCenter: parent.verticalCenter
                                x: parent.on ? parent.width - width - 6 : 6
                                color: parent.on && rowItem.usable ? tvTheme.sky : tvTheme.textMuted
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                        }

                        // Choice / bitrate value with arrows
                        Text {
                            visible: rowItem.row.kind === "choice" || rowItem.row.kind === "bitrate"
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "‹"
                            font.pixelSize: 34
                            color: rowItem.current && rowItem.usable ? tvTheme.moon : tvTheme.textFaint
                        }
                        Text {
                            id: valueLabel
                            visible: rowItem.row.kind === "choice" || rowItem.row.kind === "bitrate"
                            anchors.centerIn: parent
                            text: rowItem.valueText
                            font.pixelSize: tvTheme.fontBody
                            color: !rowItem.usable ? tvTheme.textFaint
                                                   : (rowItem.current ? tvTheme.text : tvTheme.textMuted)
                        }
                        Text {
                            visible: rowItem.row.kind === "choice" || rowItem.row.kind === "bitrate"
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            font.pixelSize: 34
                            color: rowItem.current && rowItem.usable ? tvTheme.moon : tvTheme.textFaint
                        }

                        // Action arrow
                        Text {
                            visible: rowItem.row.kind === "action"
                            anchors.centerIn: parent
                            text: "›"
                            font.pixelSize: 38
                            color: rowItem.current ? tvTheme.moon : tvTheme.textFaint
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: { list.currentIndex = index; list.forceActiveFocus() }
                        onClicked: root.activate(rowItem.row)
                    }
                    } // body
                }

                Keys.onLeftPressed:   root.changeValue(root.current, -1)
                Keys.onRightPressed:  root.changeValue(root.current, 1)
                Keys.onReturnPressed: root.activate(root.current)
                Keys.onEnterPressed:  root.activate(root.current)
                Keys.onSpacePressed:  root.activate(root.current)
            }
        }

        // ---- Right: description panel ---------------------------------------
        TvPanel {
            id: previewPanel
            theme: tvTheme
            anchors.left: left.right
            anchors.leftMargin: 64
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.12
            height: Math.min(parent.height * 0.5, 480)
            visible: root.current !== null

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 48
                spacing: 20

                Text {
                    width: parent.width
                    text: root.current ? root.current.section : ""
                    color: tvTheme.textFaint
                    font.pixelSize: tvTheme.fontSmall
                }
                Text {
                    width: parent.width
                    text: root.current ? root.current.label : ""
                    wrapMode: Text.WordWrap
                    color: tvTheme.text
                    font.pixelSize: tvTheme.fontHeading
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: { root.revision; return root.current ? root.valueText(root.current) : "" }
                    color: tvTheme.moon
                    font.pixelSize: tvTheme.fontBody + 4
                }
                Text {
                    width: parent.width
                    text: root.current ? root.current.desc : ""
                    wrapMode: Text.WordWrap
                    color: tvTheme.textMuted
                    font.pixelSize: tvTheme.fontBody
                    lineHeight: 1.35
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
            leftText: qsTr("Changes are saved automatically")
            hints: {
                var h = []
                var row = root.current
                if (row && (row.kind === "choice" || row.kind === "bitrate"))
                    h.push({ button: "◀▶", label: qsTr("Change") })
                if (row && row.kind === "toggle") h.push({ button: "A", label: qsTr("Turn on/off") })
                else if (row && row.kind === "bitrate") h.push({ button: "A", label: qsTr("Automatic") })
                else if (row && row.kind === "action") h.push({ button: "A", label: qsTr("Open") })
                h.push({ button: "B", label: qsTr("Back") })
                return h
            }
        }
    }
}
