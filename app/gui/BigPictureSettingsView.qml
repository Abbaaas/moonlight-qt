// Big Picture settings, laid out like Moonlight's standard settings page:
// two columns of groups in the same order (Basic, Audio, Host, UI on the
// left; Input, Gamepad, Advanced on the right), in the Big Picture style.
// Every setting reads and writes StreamingPreferences directly; opening this
// screen or Big Picture itself never changes a stream setting.
//
// Controller: Up/Down moves through the settings in reading order (down the
// left column, then down the right one), Left/Right changes the value,
// A turns a setting on/off or opens it, B goes back.
import QtQuick
import QtQuick.Controls

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import BigPicture 1.0

FocusScope {
    id: root
    objectName: qsTr("Settings")
    focus: true

    readonly property bool isBigPicture: true

    BigPictureTheme { id: tvTheme }

    // Bumped after every change so value labels re-read the preferences.
    property int revision: 0
    property int currentIndex: 0

    // columns: [ [ group, ... ], [ group, ... ] ]; group: { title, rows }
    property var columns: []
    // Every row in reading order; row.gi is its index here.
    property var flatRows: []
    // gi -> row item on screen, for scrolling
    property var rowItems: ({})

    readonly property var current: flatRows.length > 0 ? flatRows[currentIndex] : null

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

    function choice(label, desc, options, get, set, extra) {
        var row = { label: label, desc: desc, kind: "choice", options: options, get: get, set: set }
        for (var k in extra) row[k] = extra[k]
        return row
    }

    function toggle(label, desc, get, set, extra) {
        var row = { label: label, desc: desc, kind: "toggle", get: get, set: set }
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
        if (!row) return ""
        if (row.kind === "toggle") return onOff(row.get())
        if (row.kind === "choice") {
            var i = indexOfVal(row)
            return i >= 0 ? row.options[i].label : (row.customLabel ? row.customLabel() : "")
        }
        if (row.kind === "bitrate") {
            var mbps = StreamingPreferences.bitrateKbps / 1000
            return StreamingPreferences.autoAdjustBitrate ? qsTr("%1 Mbps (auto)").arg(mbps)
                                                          : qsTr("%1 Mbps").arg(mbps)
        }
        return ""
    }

    function isEnabled(row) {
        return row && (row.enabled === undefined ? true : row.enabled())
    }

    // dir: -1 (Left) or +1 (Right)
    function changeValue(row, dir) {
        if (!row) return
        if (!isEnabled(row)) { BigPicture.playSound("error"); return }

        if (row.kind === "toggle") {
            var want = dir > 0
            if (row.get() === want) return
            row.set(want)
        } else if (row.kind === "choice") {
            var i = indexOfVal(row)
            var n = row.options.length
            var next = i < 0 ? (dir > 0 ? 0 : n - 1) : Math.max(0, Math.min(n - 1, i + dir))
            if (next === i) return
            row.set(row.options[next].val)
        } else if (row.kind === "bitrate") {
            // 1 Mbps steps up to 20 Mbps, then 5 Mbps steps.
            var cur = StreamingPreferences.bitrateKbps
            var step = (dir > 0 ? cur >= 20000 : cur > 20000) ? 5000 : 1000
            var nb = Math.max(500, Math.min(maxBitrate(), cur + dir * step))
            if (nb === cur) return
            StreamingPreferences.bitrateKbps = nb
            StreamingPreferences.autoAdjustBitrate = false
        } else {
            return
        }
        BigPicture.playSound("toggle")
        revision++
    }

    function activate(row) {
        if (!row) return
        if (!isEnabled(row)) { BigPicture.playSound("error"); return }

        if (row.kind === "toggle") {
            row.set(!row.get())
            BigPicture.playSound("toggle")
        } else if (row.kind === "choice") {
            // A steps forward through the choices, wrapping around.
            var i = indexOfVal(row)
            row.set(row.options[(i + 1) % row.options.length].val)
            BigPicture.playSound("toggle")
        } else if (row.kind === "bitrate") {
            StreamingPreferences.autoAdjustBitrate = true
            autoBitrate()
            BigPicture.playSound("toggle")
        } else if (row.kind === "action") {
            BigPicture.playSound("select")
            row.run()
        }
        revision++
    }

    // Last selected setting in each column, so jumping back lands where you were
    property int lastLeftIndex: 0
    property int lastRightIndex: -1

    onCurrentIndexChanged: {
        if (currentIndex < columnSplit) lastLeftIndex = currentIndex
        else lastRightIndex = currentIndex
    }

    // LB / L1 (Page Up) and RB / R1 (Page Down): jump between the two columns
    function jumpToColumn(right) {
        if (right) {
            if (currentIndex >= columnSplit || columnSplit >= flatRows.length) return
            select(lastRightIndex >= columnSplit ? lastRightIndex : columnSplit)
        } else {
            if (currentIndex < columnSplit) return
            select(lastLeftIndex < columnSplit ? lastLeftIndex : 0)
        }
    }

    function select(gi) {
        if (gi < 0 || gi >= flatRows.length || gi === currentIndex) return
        currentIndex = gi
        BigPicture.playSound("move")
        ensureVisible(gi)
    }

    function ensureVisible(gi) {
        var item = rowItems[gi]
        var flick = gi < columnSplit ? leftFlick : rightFlick
        if (!item || !flick) return
        var y = item.mapToItem(flick.contentItem, 0, 0).y
        var margin = 90
        var target = flick.contentY
        if (y - margin < flick.contentY) {
            target = y - margin
        } else if (y + item.height + margin > flick.contentY + flick.height) {
            target = y + item.height + margin - flick.height
        }
        target = Math.max(0, Math.min(target, flick.contentHeight - flick.height))
        if (target !== flick.contentY) flick.contentY = target
    }

    // First index of the right column
    property int columnSplit: 0

    // ---- Resolution and frame rate choices (like the standard page) -----------

    function resolutionOptions() {
        var list = [ { label: "720p",  w: 1280, h: 720 },
                     { label: "1080p", w: 1920, h: 1080 },
                     { label: "1440p", w: 2560, h: 1440 },
                     { label: "4K",    w: 3840, h: 2160 } ]

        function add(prefix, rect) {
            if (!rect || rect.width === 0) return
            for (var j = 0; j < list.length; j++) {
                if (list[j].w === rect.width && list[j].h === rect.height) return
            }
            list.push({ label: prefix + " (" + rect.width + "×" + rect.height + ")", w: rect.width, h: rect.height })
        }

        SystemProperties.refreshDisplays()
        for (var d = 0; d < 8; d++) {
            var screen = SystemProperties.getNativeResolution(d)
            if (screen.width === 0) break
            add(qsTr("Native"), screen)
            add(qsTr("Native (Excluding Notch)"), SystemProperties.getSafeAreaResolution(d))
        }

        var maxPixels = SystemProperties.maximumResolution.width * SystemProperties.maximumResolution.height
        list = list.filter(function(r) { return maxPixels <= 0 || r.w * r.h <= maxPixels })
        list.sort(function(a, b) { return a.w * a.h - b.w * b.h })
        return list.map(function(r) { return { label: r.label, val: r.w + "x" + r.h } })
    }

    function fpsOptions() {
        var rates = [30, 60]
        for (var d = 0; d < 8; d++) {
            var rate = SystemProperties.getRefreshRate(d)
            if (rate === 0) break
            if (rates.indexOf(rate) < 0) rates.push(rate)
        }
        rates.sort(function(a, b) { return a - b })
        return rates.map(function(r) { return { label: qsTr("%1 FPS").arg(r), val: r } })
    }

    // ---- The settings, in the standard page's order ------------------------

    function buildColumns() {
        var basic = { title: qsTr("Basic Settings"), rows: [
            choice(qsTr("Resolution"),
                   qsTr("Setting values too high for your PC or network connection may cause lag, stuttering, or errors."),
                   resolutionOptions(),
                   function() { return StreamingPreferences.width + "x" + StreamingPreferences.height },
                   function(v) {
                       var p = v.split("x")
                       StreamingPreferences.width = parseInt(p[0])
                       StreamingPreferences.height = parseInt(p[1])
                       autoBitrate()
                   },
                   { customLabel: function() { return qsTr("Custom (%1×%2)").arg(StreamingPreferences.width).arg(StreamingPreferences.height) } }),
            choice(qsTr("Frame rate"),
                   qsTr("Match your display's refresh rate for the smoothest picture."),
                   fpsOptions(),
                   function() { return StreamingPreferences.fps },
                   function(v) { StreamingPreferences.fps = v; autoBitrate() },
                   { customLabel: function() { return qsTr("Custom (%1 FPS)").arg(StreamingPreferences.fps) } }),
            { kind: "bitrate", label: qsTr("Video bitrate"),
              desc: qsTr("Lower the bitrate on slower connections. Raise the bitrate to increase image quality. Press A to use the default.") },
            choice(qsTr("Display mode"),
                   qsTr("Fullscreen generally provides the best performance, but borderless windowed may work better with features like Alt+Tab, screenshot tools and on-screen overlays."),
                   [ { label: qsTr("Fullscreen"),          val: StreamingPreferences.WM_FULLSCREEN },
                     { label: qsTr("Borderless windowed"), val: StreamingPreferences.WM_FULLSCREEN_DESKTOP },
                     { label: qsTr("Windowed"),            val: StreamingPreferences.WM_WINDOWED } ],
                   function() { return StreamingPreferences.windowMode },
                   function(v) { StreamingPreferences.windowMode = v },
                   { visible: SystemProperties.hasDesktopEnvironment,
                     enabled: function() { return !SystemProperties.rendererAlwaysFullScreen } }),
            toggle(qsTr("V-Sync"),
                   qsTr("Disabling V-Sync allows sub-frame rendering latency, but it can display visible tearing."),
                   function() { return StreamingPreferences.enableVsync },
                   function(v) { StreamingPreferences.enableVsync = v }),
            toggle(qsTr("Frame pacing"),
                   qsTr("Frame pacing reduces micro-stutter by delaying frames that come in too early. Needs V-Sync."),
                   function() { return StreamingPreferences.enableVsync && StreamingPreferences.framePacing },
                   function(v) { StreamingPreferences.framePacing = v },
                   { enabled: function() { return StreamingPreferences.enableVsync } }),
            toggle(qsTr("Enable HDR"),
                   SystemProperties.supportsHdr ? qsTr("The stream will be HDR when the game and the host PC's GPU support it.")
                                                : qsTr("HDR streaming isn't supported on this PC or display."),
                   function() { return SystemProperties.supportsHdr && StreamingPreferences.enableHdr },
                   function(v) { StreamingPreferences.enableHdr = v },
                   { enabled: function() { return SystemProperties.supportsHdr } })
        ]}

        var audio = { title: qsTr("Audio Settings"), rows: [
            choice(qsTr("Audio configuration"),
                   qsTr("Match your speakers or sound system."),
                   [ { label: qsTr("Stereo"),             val: StreamingPreferences.AC_STEREO },
                     { label: qsTr("5.1 surround sound"), val: StreamingPreferences.AC_51_SURROUND },
                     { label: qsTr("7.1 surround sound"), val: StreamingPreferences.AC_71_SURROUND } ],
                   function() { return StreamingPreferences.audioConfig },
                   function(v) { StreamingPreferences.audioConfig = v }),
            toggle(qsTr("Mute host PC speakers while streaming"),
                   qsTr("You must restart any game currently in progress for this setting to take effect."),
                   function() { return !StreamingPreferences.playAudioOnHost },
                   function(v) { StreamingPreferences.playAudioOnHost = !v }),
            toggle(qsTr("Mute audio stream when Moonlight is not the active window"),
                   qsTr("Mutes Moonlight's audio when you Alt+Tab out of the stream or click on a different window."),
                   function() { return StreamingPreferences.muteOnFocusLoss },
                   function(v) { StreamingPreferences.muteOnFocusLoss = v },
                   { visible: SystemProperties.hasDesktopEnvironment })
        ]}

        var host = { title: qsTr("Host Settings"), rows: [
            toggle(qsTr("Optimize game settings for streaming"),
                   qsTr("Lets the host adjust game settings to suit the stream."),
                   function() { return StreamingPreferences.gameOptimizations },
                   function(v) { StreamingPreferences.gameOptimizations = v }),
            toggle(qsTr("Quit app on host PC after ending stream"),
                   qsTr("This will close the app or game you are streaming when you end your stream. You will lose any unsaved progress!"),
                   function() { return StreamingPreferences.quitAppAfter },
                   function(v) { StreamingPreferences.quitAppAfter = v })
        ]}

        var ui = { title: qsTr("UI Settings"), rows: [
            choice(qsTr("Language"),
                   qsTr("The language Moonlight uses."),
                   [ { label: qsTr("Automatic"), val: StreamingPreferences.LANG_AUTO },
                     { label: "Deutsch", val: StreamingPreferences.LANG_DE },
                     { label: "English", val: StreamingPreferences.LANG_EN },
                     { label: "Français", val: StreamingPreferences.LANG_FR },
                     { label: "简体中文", val: StreamingPreferences.LANG_ZH_CN },
                     { label: "Norwegian Bokmål", val: StreamingPreferences.LANG_NB_NO },
                     { label: "русский", val: StreamingPreferences.LANG_RU },
                     { label: "Español", val: StreamingPreferences.LANG_ES },
                     { label: "日本語", val: StreamingPreferences.LANG_JA },
                     { label: "Tiếng Việt", val: StreamingPreferences.LANG_VI },
                     { label: "ภาษาไทย", val: StreamingPreferences.LANG_TH },
                     { label: "한국어", val: StreamingPreferences.LANG_KO },
                     { label: "Magyar", val: StreamingPreferences.LANG_HU },
                     { label: "Nederlands", val: StreamingPreferences.LANG_NL },
                     { label: "Svenska", val: StreamingPreferences.LANG_SV },
                     { label: "Türkçe", val: StreamingPreferences.LANG_TR },
                     { label: "Українська", val: StreamingPreferences.LANG_UK },
                     { label: "繁體中文", val: StreamingPreferences.LANG_ZH_TW },
                     { label: "Português", val: StreamingPreferences.LANG_PT },
                     { label: "Português do Brasil", val: StreamingPreferences.LANG_PT_BR },
                     { label: "Ελληνικά", val: StreamingPreferences.LANG_EL },
                     { label: "Italiano", val: StreamingPreferences.LANG_IT },
                     { label: "हिन्दी", val: StreamingPreferences.LANG_HI },
                     { label: "Język polski", val: StreamingPreferences.LANG_PL },
                     { label: "Čeština", val: StreamingPreferences.LANG_CS },
                     { label: "עִבְרִית", val: StreamingPreferences.LANG_HE },
                     { label: "کرمانجیی خواروو", val: StreamingPreferences.LANG_CKB },
                     { label: "Lietuvių kalba", val: StreamingPreferences.LANG_LT },
                     { label: "Eesti", val: StreamingPreferences.LANG_ET },
                     { label: "Български", val: StreamingPreferences.LANG_BG },
                     { label: "Esperanto", val: StreamingPreferences.LANG_EO },
                     { label: "தமிழ்", val: StreamingPreferences.LANG_TA } ],
                   function() { return StreamingPreferences.language },
                   function(v) {
                       if (StreamingPreferences.language === v) return
                       StreamingPreferences.language = v
                       if (!StreamingPreferences.retranslate()) {
                           restartNote.visible = true
                       } else {
                           // Same as the standard page: pop everything on back
                           window.clearOnBack = true
                           rebuildTimer.restart()
                       }
                   }),
            choice(qsTr("GUI display mode"),
                   qsTr("How Moonlight's window opens outside Big Picture. Big Picture is always full screen."),
                   [ { label: qsTr("Windowed"),   val: StreamingPreferences.UI_WINDOWED },
                     { label: qsTr("Maximized"),  val: StreamingPreferences.UI_MAXIMIZED },
                     { label: qsTr("Fullscreen"), val: StreamingPreferences.UI_FULLSCREEN } ],
                   function() { return StreamingPreferences.uiDisplayMode },
                   function(v) { StreamingPreferences.uiDisplayMode = v },
                   { visible: SystemProperties.hasDesktopEnvironment }),
            toggle(qsTr("Show connection quality warnings"),
                   qsTr("Shows a warning during the stream when the network is struggling."),
                   function() { return StreamingPreferences.connectionWarnings },
                   function(v) { StreamingPreferences.connectionWarnings = v }),
            toggle(qsTr("Show configuration warnings"),
                   qsTr("Warns at startup about problems like missing hardware decoding."),
                   function() { return StreamingPreferences.configurationWarnings },
                   function(v) { StreamingPreferences.configurationWarnings = v }),
            toggle(qsTr("Discord Rich Presence integration"),
                   qsTr("Updates your Discord status to display the name of the game you're streaming."),
                   function() { return StreamingPreferences.richPresence },
                   function(v) { StreamingPreferences.richPresence = v },
                   { visible: SystemProperties.hasDiscordIntegration }),
            toggle(qsTr("Keep the display awake while streaming"),
                   qsTr("Prevents the screensaver from starting or the display from going to sleep while streaming."),
                   function() { return StreamingPreferences.keepAwake },
                   function(v) { StreamingPreferences.keepAwake = v }),
            toggle(qsTr("Open Moonlight.exe in Big Picture"),
                   qsTr("Makes Moonlight.exe start in Big Picture too. Moonlight.BigPicture.exe always starts in Big Picture either way."),
                   function() { return StreamingPreferences.tvMode },
                   function(v) { StreamingPreferences.tvMode = v }),
            toggle(qsTr("Big Picture navigation sounds"),
                   qsTr("Plays a soft sound when you move, select and go back in Big Picture."),
                   function() { return StreamingPreferences.tvSounds },
                   function(v) { StreamingPreferences.tvSounds = v })
        ]}

        var input = { title: qsTr("Input Settings"), rows: [
            toggle(qsTr("Optimize mouse for remote desktop instead of games"),
                   qsTr("Seamless mouse control without capturing the cursor. Ideal for remote desktop, but won't work in most games."),
                   function() { return StreamingPreferences.absoluteMouseMode },
                   function(v) { StreamingPreferences.absoluteMouseMode = v }),
            choice(qsTr("Capture system keyboard shortcuts"),
                   qsTr("Sends shortcuts like Alt+Tab to the host instead of this PC."),
                   [ { label: qsTr("Off"),           val: StreamingPreferences.CSK_OFF },
                     { label: qsTr("in fullscreen"), val: StreamingPreferences.CSK_FULLSCREEN },
                     { label: qsTr("always"),        val: StreamingPreferences.CSK_ALWAYS } ],
                   function() { return StreamingPreferences.captureSysKeysMode },
                   function(v) { StreamingPreferences.captureSysKeysMode = v },
                   { visible: SystemProperties.hasDesktopEnvironment }),
            toggle(qsTr("Use touchscreen as a virtual trackpad"),
                   qsTr("When on, the touchscreen acts like a trackpad. When off, it directly controls the mouse pointer."),
                   function() { return !StreamingPreferences.absoluteTouchMode },
                   function(v) { StreamingPreferences.absoluteTouchMode = !v }),
            toggle(qsTr("Swap left and right mouse buttons"),
                   qsTr("Swaps the left and right mouse buttons."),
                   function() { return StreamingPreferences.swapMouseButtons },
                   function(v) { StreamingPreferences.swapMouseButtons = v }),
            toggle(qsTr("Reverse mouse scrolling direction"),
                   qsTr("Flips the mouse scroll direction."),
                   function() { return StreamingPreferences.reverseScrollDirection },
                   function(v) { StreamingPreferences.reverseScrollDirection = v })
        ]}

        var gamepad = { title: qsTr("Gamepad Settings"), rows: [
            toggle(qsTr("Swap A/B and X/Y gamepad buttons"),
                   qsTr("This switches gamepads into a Nintendo-style button layout."),
                   function() { return StreamingPreferences.swapFaceButtons },
                   function(v) { StreamingPreferences.swapFaceButtons = v }),
            toggle(qsTr("Force gamepad #1 always connected"),
                   qsTr("Forces a single gamepad to always stay connected to the host, even if no gamepads are connected to this PC."),
                   function() { return !StreamingPreferences.multiController },
                   function(v) { StreamingPreferences.multiController = !v }),
            toggle(qsTr("Enable mouse control with gamepads by holding the 'Start' button"),
                   qsTr("Holding Start on a controller switches it to mouse control."),
                   function() { return StreamingPreferences.gamepadMouse },
                   function(v) { StreamingPreferences.gamepadMouse = v }),
            toggle(qsTr("Process gamepad input when Moonlight is in the background"),
                   qsTr("Allows Moonlight to capture gamepad inputs even if it's not the current window in focus."),
                   function() { return StreamingPreferences.backgroundGamepad },
                   function(v) { StreamingPreferences.backgroundGamepad = v },
                   { visible: SystemProperties.hasDesktopEnvironment }),
            { kind: "action", label: qsTr("Gamepad Mapper"),
              desc: qsTr("Map the buttons of a controller Moonlight doesn't recognize."),
              run: function() { stackView.push("qrc:/gui/GamepadMapper.qml") } }
        ]}

        var advanced = { title: qsTr("Advanced Settings"), rows: [
            choice(qsTr("Video decoder"),
                   qsTr("Leave on Automatic unless you're fixing a problem."),
                   [ { label: qsTr("Automatic (Recommended)"),  val: StreamingPreferences.VDS_AUTO },
                     { label: qsTr("Force software decoding"),  val: StreamingPreferences.VDS_FORCE_SOFTWARE },
                     { label: qsTr("Force hardware decoding"),  val: StreamingPreferences.VDS_FORCE_HARDWARE } ],
                   function() { return StreamingPreferences.videoDecoderSelection },
                   function(v) { StreamingPreferences.videoDecoderSelection = v }),
            choice(qsTr("Video codec"),
                   qsTr("Leave on Automatic unless you're fixing a problem."),
                   [ { label: qsTr("Automatic (Recommended)"), val: StreamingPreferences.VCC_AUTO },
                     { label: qsTr("H.264"),                   val: StreamingPreferences.VCC_FORCE_H264 },
                     { label: qsTr("HEVC (H.265)"),            val: StreamingPreferences.VCC_FORCE_HEVC },
                     { label: qsTr("AV1"),                     val: StreamingPreferences.VCC_FORCE_AV1 } ],
                   function() { return StreamingPreferences.videoCodecConfig },
                   function(v) { StreamingPreferences.videoCodecConfig = v }),
            toggle(qsTr("Enable YUV 4:4:4"),
                   qsTr("Sharper colors and text, at the cost of a higher bitrate. Needs a supported host and GPU."),
                   function() { return StreamingPreferences.enableYUV444 },
                   function(v) { StreamingPreferences.enableYUV444 = v; autoBitrate() }),
            toggle(qsTr("Unlock bitrate limit (Experimental)"),
                   qsTr("Unlocks extremely high video bitrates for Sunshine hosts. Only use it over a wired network."),
                   function() { return StreamingPreferences.unlockBitrate },
                   function(v) {
                       StreamingPreferences.unlockBitrate = v
                       StreamingPreferences.bitrateKbps = Math.min(StreamingPreferences.bitrateKbps, maxBitrate())
                   }),
            toggle(qsTr("Automatically find PCs on the local network (Recommended)"),
                   qsTr("Turn off only if you add PCs by IP address."),
                   function() { return StreamingPreferences.enableMdns },
                   function(v) {
                       if (StreamingPreferences.enableMdns === v) return
                       StreamingPreferences.enableMdns = v
                       // Restart polling so the change takes effect
                       if (window.pollingActive) {
                           ComputerManager.stopPollingAsync()
                           ComputerManager.startPolling()
                       }
                   }),
            toggle(qsTr("Automatically detect blocked connections (Recommended)"),
                   qsTr("Warns you when a firewall or network is blocking streaming."),
                   function() { return StreamingPreferences.detectNetworkBlocking },
                   function(v) { StreamingPreferences.detectNetworkBlocking = v }),
            toggle(qsTr("Show performance stats while streaming"),
                   qsTr("Display real-time stream performance information while streaming. Toggle it any time with Select+L1+R1+X."),
                   function() { return StreamingPreferences.showPerformanceOverlay },
                   function(v) { StreamingPreferences.showPerformanceOverlay = v }),
            { kind: "action", label: qsTr("Custom resolution and frame rate"),
              desc: qsTr("Opens the standard settings page, where you can type a custom resolution or frame rate."),
              run: function() { stackView.push("qrc:/gui/SettingsView.qml") } }
        ]}

        function clean(group) {
            group.rows = group.rows.filter(function(r) { return r.visible === undefined || r.visible })
            return group
        }
        return [ [ basic, audio, host, ui ].map(clean),
                 [ input, gamepad, advanced ].map(clean) ]
    }

    function rebuild() {
        var cols = buildColumns()
        var flat = []
        for (var c = 0; c < cols.length; c++) {
            if (c === 1) columnSplit = flat.length
            for (var g = 0; g < cols[c].length; g++) {
                for (var r = 0; r < cols[c][g].rows.length; r++) {
                    var row = cols[c][g].rows[r]
                    row.gi = flat.length
                    row.section = cols[c][g].title
                    flat.push(row)
                }
            }
        }
        rowItems = ({})
        flatRows = flat
        columns = cols
        currentIndex = Math.min(currentIndex, flat.length - 1)
    }

    // Rebuilding right after retranslate() would happen mid-change
    Timer {
        id: rebuildTimer
        interval: 0
        onTriggered: root.rebuild()
    }

    Component.onCompleted: rebuild()

    // ---- Lifecycle -------------------------------------------------------------

    StackView.onActivating: {
        toolBar.visible = false
        window.ensureBigPictureWindow()
    }

    StackView.onActivated: {
        revision++
        root.forceActiveFocus()
        ensureVisible(currentIndex)
    }

    StackView.onDeactivating: {
        // Save so a stream started next picks up the changes
        StreamingPreferences.save()
    }

    StackView.onRemoved: BigPicture.playSound("back")

    Component.onDestruction: StreamingPreferences.save()

    // LB / RB (Page Up / Page Down) jump between the two columns.
    // Start / Y and X / Square do nothing here (and must not open the desktop page).
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_PageUp) { event.accepted = true; jumpToColumn(false) }
        else if (event.key === Qt.Key_PageDown) { event.accepted = true; jumpToColumn(true) }
        else if (event.key === Qt.Key_Hangup || event.key === Qt.Key_Menu) event.accepted = true
    }

    Keys.onUpPressed:     select(currentIndex - 1)
    Keys.onDownPressed:   select(currentIndex + 1)
    Keys.onLeftPressed:   changeValue(current, -1)
    Keys.onRightPressed:  changeValue(current, 1)
    Keys.onReturnPressed: activate(current)
    Keys.onEnterPressed:  activate(current)
    Keys.onSpacePressed:  activate(current)

    // ---- Layout ----------------------------------------------------------------

    BigPictureBackdrop { anchors.fill: parent; theme: tvTheme }

    // Designed at 1920x1080 and scaled to fit (1080p and 4K look the same)
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
            x: 8
            text: qsTr("Settings")
            color: tvTheme.text
            font.pixelSize: tvTheme.fontBrand
            font.weight: Font.Light
            font.letterSpacing: 3
        }

        Text {
            id: restartNote
            visible: false
            anchors.left: title.right
            anchors.leftMargin: 32
            anchors.verticalCenter: title.verticalCenter
            text: qsTr("Restart Moonlight to change the language")
            color: tvTheme.moon
            font.pixelSize: tvTheme.fontSmall
        }

        Row {
            id: columnsRow
            anchors.top: title.bottom
            anchors.topMargin: 20
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: hints.top
            anchors.bottomMargin: 20
            spacing: 32

            Repeater {
                model: root.columns.length

                Flickable {
                    id: flick
                    readonly property var groups: root.columns[index]
                    width: (columnsRow.width - columnsRow.spacing) / 2
                    height: columnsRow.height
                    contentHeight: groupColumn.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Behavior on contentY { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    Component.onCompleted: {
                        if (index === 0) root.leftFlickRef = flick
                        else root.rightFlickRef = flick
                    }

                    Column {
                        id: groupColumn
                        width: flick.width
                        spacing: 20

                        Repeater {
                            model: flick.groups

                            // One group, like the standard page's group boxes
                            BigPicturePanel {
                                id: panel
                                readonly property var group: modelData
                                theme: tvTheme
                                width: groupColumn.width
                                height: panelColumn.height + 28

                                Column {
                                    id: panelColumn
                                    x: 0
                                    y: 18
                                    width: parent.width

                                    Text {
                                        x: 32
                                        height: 46
                                        verticalAlignment: Text.AlignVCenter
                                        text: panel.group.title
                                        color: tvTheme.cool
                                        font.pixelSize: tvTheme.fontSmall + 2
                                        font.weight: Font.DemiBold
                                    }

                                    Repeater {
                                        model: panel.group.rows

                                        Item {
                                            id: rowItem
                                            readonly property var row: modelData
                                            readonly property bool current: row.gi === root.currentIndex
                                            readonly property bool usable: { root.revision; return root.isEnabled(row) }
                                            readonly property string valueText: { root.revision; return root.valueText(row) }

                                            width: panelColumn.width
                                            height: Math.max(70, label.implicitHeight + 26)

                                            Component.onCompleted: root.rowItems[row.gi] = rowItem

                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                radius: 12
                                                color: rowItem.current ? tvTheme.moonA(0.10) : "transparent"
                                                border.width: rowItem.current ? 1 : 0
                                                border.color: tvTheme.moonA(0.4)
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }

                                            Rectangle {
                                                x: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 5
                                                height: rowItem.current ? parent.height * 0.55 : 0
                                                radius: 3
                                                color: tvTheme.moon
                                                Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                            }

                                            Text {
                                                id: label
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: 34
                                                width: parent.width - x - valueBox.width - 52
                                                text: rowItem.row.label
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                                font.pixelSize: tvTheme.fontBody
                                                font.weight: rowItem.current ? Font.DemiBold : Font.Normal
                                                color: !rowItem.usable ? tvTheme.textFaint
                                                                       : (rowItem.current ? tvTheme.text : tvTheme.textMuted)
                                            }

                                            // On/off pill, ‹ value ›, or an arrow for pages
                                            Item {
                                                id: valueBox
                                                anchors.right: parent.right
                                                anchors.rightMargin: 30
                                                anchors.verticalCenter: parent.verticalCenter
                                                readonly property bool isChoice: rowItem.row.kind === "choice" || rowItem.row.kind === "bitrate"
                                                width: rowItem.row.kind === "toggle" ? 72
                                                     : rowItem.row.kind === "action" ? 30
                                                     : Math.min(Math.max(valueLabel.implicitWidth + 60, 160), panelColumn.width * 0.45)
                                                height: 40

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
                                                        width: 28; height: 28; radius: 14
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: parent.on ? parent.width - width - 6 : 6
                                                        color: parent.on && rowItem.usable ? tvTheme.sky : tvTheme.textMuted
                                                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    }
                                                }

                                                Text {
                                                    visible: valueBox.isChoice
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "‹"
                                                    font.pixelSize: 32
                                                    color: rowItem.current && rowItem.usable ? tvTheme.moon : tvTheme.textFaint
                                                }
                                                Text {
                                                    id: valueLabel
                                                    visible: valueBox.isChoice
                                                    anchors.centerIn: parent
                                                    width: Math.min(implicitWidth, parent.width - 56)
                                                    elide: Text.ElideRight
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: rowItem.valueText
                                                    font.pixelSize: tvTheme.fontSmall + 2
                                                    color: !rowItem.usable ? tvTheme.textFaint
                                                                           : (rowItem.current ? tvTheme.text : tvTheme.textMuted)
                                                }
                                                Text {
                                                    visible: valueBox.isChoice
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "›"
                                                    font.pixelSize: 32
                                                    color: rowItem.current && rowItem.usable ? tvTheme.moon : tvTheme.textFaint
                                                }
                                                Text {
                                                    visible: rowItem.row.kind === "action"
                                                    anchors.centerIn: parent
                                                    text: "›"
                                                    font.pixelSize: 36
                                                    color: rowItem.current ? tvTheme.moon : tvTheme.textFaint
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onPositionChanged: function(mouse) {
                                                    if (BigPicture.inputMode === "keyboard" && tvTheme.pointerMoved(rowItem, mouse.x, mouse.y))
                                                        root.select(rowItem.row.gi)
                                                }
                                                onClicked: {
                                                    root.select(rowItem.row.gi)
                                                    root.activate(rowItem.row)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Bottom: what the selected setting does, plus button prompts ----
        BigPictureHintBar {
            id: hints
            theme: tvTheme
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            leftText: root.current ? root.current.desc : ""
            hints: {
                var h = []
                var row = root.current
                if (row && (row.kind === "choice" || row.kind === "bitrate" || row.kind === "toggle"))
                    h.push({ action: "change", label: qsTr("Change") })
                if (row && row.kind === "toggle") h.push({ action: "confirm", label: qsTr("On/off") })
                else if (row && row.kind === "bitrate") h.push({ action: "confirm", label: qsTr("Default") })
                else if (row && row.kind === "choice") h.push({ action: "confirm", label: qsTr("Next") })
                else if (row && row.kind === "action") h.push({ action: "confirm", label: qsTr("Open") })
                h.push({ action: "back", label: qsTr("Back") })
                return h
            }
        }
    }

    } // stage

    // Set by the two column Flickables
    property var leftFlickRef: null
    property var rightFlickRef: null
    readonly property var leftFlick: leftFlickRef
    readonly property var rightFlick: rightFlickRef
}
