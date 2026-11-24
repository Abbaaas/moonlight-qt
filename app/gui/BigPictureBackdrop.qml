// Plain dark background for Big Picture screens (no artwork).
import QtQuick

Rectangle {
    id: backdrop
    property BigPictureTheme theme: BigPictureTheme {}

    gradient: Gradient {
        GradientStop { position: 0.0; color: backdrop.theme.sky }
        GradientStop { position: 1.0; color: "#111830" }
    }
}
