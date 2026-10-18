import QtQuick

// The Options dropdown. There is one per window, drawn above every banner;
// a banner opens it with its own actions. It hangs below the owning card,
// tucked slightly under it and sticking out past the card's outer edge, and
// flips above the card when there is no room below.
Item {
    id: root

    property Item owner: null
    property var entries: []
    property bool open: false

    // Labels are copied on open, so a notification closing mid-fade does not
    // blank the rows.
    function openFor(banner: Item, actions: var) {
        root.owner = banner;
        root.entries = actions.map(a => ({"label": a.text || a.identifier, "action": a}));
        root.open = true;
    }

    // The owner is kept so the fade-out happens in place.
    function close() {
        root.open = false;
    }

    function choose(entry: var) {
        root.close();
        entry.action?.invoke();
    }

    readonly property real below: root.owner ? root.owner.y + root.owner.height - Theme.menuOverlap : 0
    readonly property bool upward: root.parent && root.below + root.height > root.parent.height - Theme.screenMarginY

    x: root.owner ? root.owner.cardX + Theme.cardWidth + Theme.menuOverhang - root.width : 0
    y: !root.owner ? 0 : root.upward ? root.owner.y - root.height + Theme.menuOverlap : root.below

    width: Math.max(Theme.menuMinWidth, rows.implicitWidth + 2 * Theme.menuPadding)
    height: rows.implicitHeight + 2 * Theme.menuPadding

    visible: opacity > 0
    opacity: root.open ? 1 : 0
    scale: root.open ? 1 : Theme.menuClosedScale
    transformOrigin: root.upward ? Item.BottomRight : Item.TopRight

    Behavior on opacity {
        NumberAnimation { duration: Theme.menuDuration; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        NumberAnimation { duration: Theme.menuDuration; easing.type: Easing.OutCubic }
    }

    Glass {
        anchors.fill: parent
        radius: Theme.radiusMenu
        fill: Theme.menuFill
        border: Theme.menuBorder
    }

    // Swallows clicks on the padding, which overlaps the banners below.
    MouseArea {
        anchors.fill: parent
    }

    Column {
        id: rows

        x: Theme.menuPadding
        y: Theme.menuPadding

        Repeater {
            model: root.entries

            delegate: Item {
                id: row

                required property var modelData
                readonly property real rowWidth: root.width - 2 * Theme.menuPadding

                // Natural width only: the column's implicit width is the
                // widest label, and the menu is sized from that.
                width: label.width + 2 * Theme.menuRowPaddingX
                height: Theme.menuRowHeight

                Rectangle {
                    width: row.rowWidth
                    height: row.height
                    radius: Theme.radiusMenuRow
                    color: Theme.accent
                    visible: area.containsMouse
                }

                Text {
                    id: label

                    x: Theme.menuRowPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Theme.menuMaxWidth - 2 * (Theme.menuPadding + Theme.menuRowPaddingX))
                    text: row.modelData.label
                    elide: Text.ElideRight
                    color: area.containsMouse ? Theme.accentText : Theme.menuText
                    font.family: Theme.font
                    font.pixelSize: Theme.menuSize
                }

                MouseArea {
                    id: area

                    width: row.rowWidth
                    height: row.height
                    hoverEnabled: true
                    enabled: root.open
                    onClicked: root.choose(row.modelData)
                }
            }
        }
    }
}
