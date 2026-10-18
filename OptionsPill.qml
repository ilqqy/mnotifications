import QtQuick
import QtQuick.Shapes

// "Options" with a chevron: opens the menu of a banner's non-default actions.
Item {
    id: root

    signal clicked

    property bool open: false
    readonly property bool hovered: area.containsMouse

    implicitWidth: content.implicitWidth + 2 * Theme.pillPaddingX
    implicitHeight: Theme.pillHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: area.containsMouse || root.open ? Theme.pillHoverFill : Theme.pillFill

        Behavior on color {
            ColorAnimation { duration: Theme.hoverDuration }
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Theme.chevronGap

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.optionsLabel
            color: Theme.pillText
            font.family: Theme.font
            font.pixelSize: Theme.pillSize
            font.weight: Theme.pillWeight
        }

        Shape {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.chevronSize
            height: Theme.chevronSize / 2 + Theme.glyphStroke
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.pillText
                strokeWidth: Theme.glyphStroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathMove { x: Theme.glyphStroke / 2; y: Theme.glyphStroke / 2 }
                PathLine { x: Theme.chevronSize / 2; y: Theme.chevronSize / 2 }
                PathLine { x: Theme.chevronSize - Theme.glyphStroke / 2; y: Theme.glyphStroke / 2 }
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
