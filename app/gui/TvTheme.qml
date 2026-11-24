// Shared colors and sizes for TV mode.
import QtQuick

QtObject {
    // Night-sky palette: deep indigo, silver-blue text, pale lunar gold for focus.
    readonly property color sky:         "#0B1020"
    readonly property color skyHigh:     "#1B2547"
    readonly property color text:        "#E2EAF7"
    readonly property color textMuted:   "#8392B3"
    readonly property color textFaint:   "#56627F"
    readonly property color moon:        "#F2D58A"
    readonly property color cool:        "#8FB4F0"
    readonly property color warn:        "#F0A07A"

    // Glass panels
    readonly property color panel:       Qt.rgba(0.08, 0.11, 0.21, 0.70)
    readonly property color panelBorder: Qt.rgba(0.88, 0.92, 0.97, 0.12)

    function moonA(a) { return Qt.rgba(moon.r, moon.g, moon.b, a) }

    // Sized for reading from a couch.
    readonly property int fontBrand:   54
    readonly property int fontMenu:    36
    readonly property int fontHeading: 44
    readonly property int fontBody:    26
    readonly property int fontSmall:   22

    // TV safe area, about 5% of each edge.
    function safeX(w) { return Math.round(w * 0.05) }
    function safeY(h) { return Math.round(h * 0.05) }
}
