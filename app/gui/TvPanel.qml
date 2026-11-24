// Glass panel used for the right-hand preview area.
import QtQuick

Rectangle {
    property TvTheme theme: TvTheme {}
    radius: 22
    color: theme.panel
    border.width: 1
    border.color: theme.panelBorder
}
