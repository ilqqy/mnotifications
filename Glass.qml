import QtQuick
import QtQuick.Effects

// Frosted surface: a translucent fill for Hyprland's layer blur to show
// through, a hairline border, and a soft drop shadow.
//
// The shadow is masked out under the fill. Drawn whole, it would show through
// the translucent glass as a darker rim; cut out, the glass keeps one even
// tint and the shadow only falls outside it. Its alpha stays below the layer
// rule's ignore_alpha so the compositor does not blur behind it.
Item {
    id: root

    property real radius: Theme.radiusCard
    property color fill: Theme.cardFill
    property color border: Theme.cardBorder

    readonly property int reach: Theme.shadowBlur + Theme.shadowOffsetY

    Item {
        id: shadow

        anchors.fill: parent
        anchors.margins: -root.reach
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: cutout
        }

        RectangularShadow {
            x: root.reach
            y: root.reach + Theme.shadowOffsetY
            width: root.width
            height: root.height
            radius: root.radius
            blur: Theme.shadowBlur
            color: Theme.shadowColor
        }
    }

    Item {
        id: cutout

        anchors.fill: shadow
        visible: false
        layer.enabled: true

        Rectangle {
            x: root.reach
            y: root.reach
            width: root.width
            height: root.height
            radius: root.radius
            color: "black"
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.fill
        border.width: 1
        border.color: root.border
    }
}
