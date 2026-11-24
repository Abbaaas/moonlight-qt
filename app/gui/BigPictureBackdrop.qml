// Animated night sky: gradient, a field of stars, a slow breathing moon glow
// and a large crescent. The glow is the only ambient motion.
import QtQuick

Item {
    id: backdrop
    property BigPictureTheme theme: BigPictureTheme {}
    clip: true

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: backdrop.theme.sky }
            GradientStop { position: 0.55; color: backdrop.theme.sky }
            GradientStop { position: 1.0; color: backdrop.theme.skyHigh }
        }
    }

    // Stars at fixed pseudo-random positions so they don't jump between launches.
    Repeater {
        model: 90
        Rectangle {
            function rnd(n) { var x = Math.sin(n * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x) }
            readonly property real s: rnd(index * 3 + 2)
            x: rnd(index * 3) * backdrop.width
            y: rnd(index * 3 + 1) * backdrop.height
            width: s > 0.9 ? 3 : 2
            height: width
            radius: width / 2
            color: backdrop.theme.text
            opacity: 0.08 + s * 0.35
        }
    }

    // Moon glow (radial), breathing slowly.
    Canvas {
        id: glow
        width: backdrop.height * 1.4
        height: width
        x: backdrop.width - width * 0.62
        y: -height * 0.42
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var r = width / 2
            var g = ctx.createRadialGradient(r, r, 0, r, r, r)
            g.addColorStop(0.0, Qt.rgba(0.95, 0.84, 0.54, 0.30))
            g.addColorStop(0.35, Qt.rgba(0.56, 0.70, 0.94, 0.10))
            g.addColorStop(1.0, Qt.rgba(0.04, 0.06, 0.13, 0.0))
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
        }
        onWidthChanged: requestPaint()

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { from: 0.75; to: 1.0; duration: 6000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.0; to: 0.75; duration: 6000; easing.type: Easing.InOutSine }
        }
    }

    // Crescent: a pale disc partly covered by a sky-colored disc.
    Item {
        width: Math.round(backdrop.height * 0.42)
        height: width
        x: backdrop.width - width * 0.95
        y: backdrop.height * 0.04
        opacity: 0.9

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#FFF3CF" }
                GradientStop { position: 1.0; color: backdrop.theme.moon }
            }
        }
        Rectangle {
            width: parent.width * 0.96
            height: width
            radius: width / 2
            x: -parent.width * 0.26
            y: -parent.height * 0.08
            color: "#141C38"
        }
    }

    // Darken the left side so the menu text always reads cleanly.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.05, 0.10, 0.70) }
            GradientStop { position: 0.45; color: Qt.rgba(0.03, 0.05, 0.10, 0.0) }
        }
    }
}
