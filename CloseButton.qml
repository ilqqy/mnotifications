import QtQuick
import QtQuick.Shapes

// The round "x" that sits on a banner's top-left corner.
Item {
    id: root

    signal clicked

    readonly property bool hovered: area.containsMouse

    width: Theme.closeSize
    height: Theme.closeSize

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: area.containsMouse ? Theme.closeHoverFill : Theme.closeFill
        border.width: 1
        border.color: Theme.closeBorder

        Behavior on color {
            ColorAnimation { duration: Theme.hoverDuration }
        }
    }

    Shape {
        anchors.centerIn: parent
        width: Theme.closeGlyphSize
        height: Theme.closeGlyphSize
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Theme.closeGlyph
            strokeWidth: Theme.glyphStroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathMove { x: 0; y: 0 }
            PathLine { x: Theme.closeGlyphSize; y: Theme.closeGlyphSize }
            PathMove { x: Theme.closeGlyphSize; y: 0 }
            PathLine { x: 0; y: Theme.closeGlyphSize }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
