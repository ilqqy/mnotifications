import QtQuick

// The banners and the Options menu, laid out in a column along one edge of
// whatever hosts it. BannerWindow hosts it in the layer surface; the
// offscreen render test hosts it in a plain window.
Item {
    id: root

    readonly property alias hitArea: hitArea
    readonly property alias menu: actionMenu

    onHeightChanged: root.scheduleRelayout()

    Connections {
        target: Theme

        function onAlignBottomChanged() {
            root.scheduleRelayout();
        }
    }

    // Stacks the banners that are not leaving, newest nearest the screen
    // edge. A banner placed for the first time jumps to its slot and starts
    // its entrance; the others glide to their new slots.
    function relayout() {
        let offset = Theme.screenMarginY;
        let top = Infinity;
        let bottom = -Infinity;
        for (let i = 0; i < stack.count; i++) {
            const banner = stack.itemAt(i);
            if (!banner || banner.leaving) continue;
            const y = Theme.alignBottom ? root.height - offset - banner.height : offset;
            banner.moveTo(y);
            top = Math.min(top, y);
            bottom = Math.max(bottom, y + banner.height);
            offset += banner.height + Theme.stackSpacing;
            if (Store.debug) {
                const p = banner.pillRect;
                Store.debugLog("layout id=" + banner.key + " card=" + [banner.cardX, y, Theme.cardWidth, banner.height].join(",")
                    + " pill=" + (banner.hasMenu ? [p.x, y + p.y, p.width, p.height].join(",") : "none"));
            }
        }
        hitArea.stackTop = top;
        hitArea.stackBottom = bottom;
    }

    function scheduleRelayout() {
        Qt.callLater(root.relayout);
    }

    // The input region: every banner in place, plus the part of the close
    // buttons that pokes out above and beside the cards.
    Item {
        id: hitArea

        property real stackTop: 0
        property real stackBottom: 0
        readonly property real reach: Theme.closeSize / 2 - Theme.closeInset

        x: (Theme.alignRight ? Theme.gutter : Theme.screenMarginX) - hitArea.reach
        y: hitArea.stackTop - hitArea.reach
        width: Theme.cardWidth + hitArea.reach
        height: hitArea.stackBottom > hitArea.stackTop ? hitArea.stackBottom - hitArea.stackTop + hitArea.reach : 0
    }

    Repeater {
        id: stack

        model: Store.shown

        delegate: Banner {
            menu: actionMenu
            onRelayoutNeeded: root.scheduleRelayout()
        }

        onItemAdded: root.scheduleRelayout()
        onItemRemoved: root.scheduleRelayout()
    }

    ActionMenu {
        id: actionMenu
        z: 1
    }
}
