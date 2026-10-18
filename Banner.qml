import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "text.js" as Format

// One notification banner: a full-width row of the window holding the card.
//
// BannerStack hands the row its slot through moveTo(); the banner owns
// everything else: its countdown, its actions, and its exit. Every exit,
// whether the user closed it, it expired, an action closed it or the app
// withdrew it, arrives as the notification's `closed` signal and runs leave().
Item {
    id: root

    required property int key
    required property int index
    property ActionMenu menu: null

    signal relayoutNeeded

    property Notification notification: Store.notificationFor(root.key)
    property real receivedAt: Store.receivedAt(root.key)

    // What the card shows. While the notification is alive this is a binding,
    // so a replacement (same id) updates the card in place; leave() freezes it
    // because the notification object is destroyed right after it closes.
    property var content: {
        const n = root.notification;
        const actions = n ? Array.from(n.actions) : [];
        return {
            "summary": n?.summary ?? "",
            "body": n?.body ?? "",
            "appName": n?.appName ?? "",
            "appIcon": n?.appIcon ?? "",
            "image": n?.image ?? "",
            "desktopEntry": n?.desktopEntry ?? "",
            "urgency": n?.urgency ?? NotificationUrgency.Normal,
            "expireTimeout": n?.expireTimeout ?? -1,
            "defaultAction": actions.find(a => a.identifier === "default") ?? null,
            "menuActions": actions.filter(a => a.identifier !== "default")
        };
    }

    readonly property bool critical: root.content.urgency === NotificationUrgency.Critical
    readonly property bool hasMenu: root.content.menuActions.length > 0
    readonly property string title: root.content.summary || root.content.appName
    readonly property string bodyMarkup: Format.sanitize(root.content.body)

    property bool placed: false
    property bool leaving: false
    // 0 = off-screen, 1 = in place. Slide and fade both follow it.
    property real presence: 0

    readonly property real cardX: card.x
    readonly property rect pillRect: Qt.rect(card.x + pill.x, pill.y, pill.width, pill.height)
    readonly property bool menuOpen: root.menu !== null && root.menu.open && root.menu.owner === root
    readonly property bool hovered: cardHover.hovered || closeButton.hovered
    readonly property bool paused: root.hovered || root.menuOpen
    // The close button and the Options pill appear together on hover, and
    // stay while this banner's menu is open.
    readonly property bool chromeShown: (root.hovered || root.menuOpen) && !root.leaving

    width: Theme.surfaceWidth
    height: card.height
    // Newest on top, so an arriving banner slides over the one it pushes
    // aside; a leaving banner drops below everything still in place.
    z: root.leaving ? -Theme.maxVisible - Store.shown.count : -root.index

    onHeightChanged: root.relayoutNeeded()
    onLeavingChanged: root.relayoutNeeded()

    opacity: root.presence
    transform: Translate {
        x: (1 - root.presence) * (Theme.cardWidth + Theme.gutter + Theme.screenMarginX) * (Theme.alignRight ? 1 : -1)
    }

    NumberAnimation {
        id: reflowAnimation
        target: root
        property: "y"
        duration: Theme.reflowDuration
        easing.type: Theme.reflowEasing
    }

    // Called by the stack with this banner's slot. The first call places it
    // and starts the entrance; later ones glide it to the new slot.
    function moveTo(slot: real) {
        if (!root.placed) {
            root.y = slot;
            root.placed = true;
            root.enter();
            return;
        }
        if (reflowAnimation.running ? reflowAnimation.to === slot : root.y === slot) return;
        reflowAnimation.stop();
        reflowAnimation.from = root.y;
        reflowAnimation.to = slot;
        reflowAnimation.start();
    }

    NumberAnimation {
        id: enterAnimation
        target: root
        property: "presence"
        to: 1
        duration: Theme.enterDuration
        easing.type: Theme.enterEasing
    }

    NumberAnimation {
        id: leaveAnimation
        target: root
        property: "presence"
        to: 0
        duration: Theme.leaveDuration
        easing.type: Theme.leaveEasing
        onFinished: Store.remove(root.key)
    }

    function enter() {
        enterAnimation.start();
        root.startCountdown(root.timeout);
    }

    function leave() {
        if (root.leaving) return;
        root.content = root.content;
        root.notification = null;
        root.leaving = true;
        // It leaves sideways from where it is; it no longer has a slot.
        reflowAnimation.stop();
        countdown.stop();
        if (root.menuOpen) root.menu.close();
        Store.release(root.key);
        enterAnimation.stop();
        leaveAnimation.start();
    }

    // ------------------------------------------------------------ actions

    function activate() {
        if (root.menu?.open) {
            root.menu.close();
            return;
        }
        if (root.content.defaultAction) root.content.defaultAction.invoke();
        else root.dismiss();
    }

    function dismiss() {
        if (root.notification) root.notification.dismiss();
        else root.leave();
    }

    function toggleMenu() {
        if (root.menuOpen) root.menu.close();
        else root.menu.openFor(root, root.content.menuActions);
    }

    // ---------------------------------------------------------- countdown

    // Milliseconds on screen; 0 keeps the banner until it is closed.
    readonly property int timeout: {
        if (root.critical) return 0;
        const requested = root.content.expireTimeout;
        if (requested === 0) return 0;
        if (requested >= Theme.appTimeoutMin && requested <= Theme.appTimeoutMax) return requested;
        return root.content.urgency === NotificationUrgency.Low ? Theme.lowTimeout : Theme.normalTimeout;
    }

    property real remaining: 0
    property real deadline: 0

    function startCountdown(ms: real) {
        countdown.stop();
        if (root.timeout <= 0 || root.leaving) return;
        root.remaining = ms;
        if (root.paused) return;
        root.deadline = Date.now() + ms;
        countdown.interval = ms;
        countdown.start();
    }

    onPausedChanged: {
        Store.debugLog("paused id=" + root.key + " " + root.paused);
        if (!root.placed || root.leaving || root.timeout <= 0) return;
        if (root.paused) {
            if (countdown.running) root.remaining = Math.max(0, root.deadline - Date.now());
            countdown.stop();
        } else {
            root.startCountdown(Math.max(root.remaining, Theme.resumeMinimum));
        }
    }

    onTimeoutChanged: if (root.placed) root.startCountdown(root.timeout)

    Timer {
        id: countdown
        onTriggered: {
            if (root.notification) root.notification.expire();
            else root.leave();
        }
    }

    // A replacement restarts the clock and the timestamp; one Notify call
    // can fire several of these, which is harmless.
    function refreshed() {
        root.receivedAt = Date.now();
        if (root.placed) root.startCountdown(root.timeout);
    }

    Connections {
        target: root.notification

        function onClosed() {
            root.leave();
        }
        function onSummaryChanged() {
            root.refreshed();
        }
        function onBodyChanged() {
            root.refreshed();
        }
        function onAppIconChanged() {
            root.refreshed();
        }
        function onImageChanged() {
            root.refreshed();
        }
        function onActionsChanged() {
            root.refreshed();
        }
        function onHintsChanged() {
            root.refreshed();
        }
    }

    // --------------------------------------------------------------- card

    FontMetrics {
        id: bodyMetrics
        font.family: Theme.font
        font.pixelSize: Theme.bodySize
    }

    Item {
        id: card

        readonly property real textX: Theme.cardPaddingX + Theme.iconSize + Theme.iconGap
        readonly property real textRight: card.width - Theme.cardPaddingX
            - (root.hasMenu ? pill.implicitWidth + Theme.pillGap : 0)
        // The first text row shares its line with the timestamp.
        readonly property real firstRowWidth: Math.min(texts.width,
            card.width - Theme.cardPaddingX - time.implicitWidth - Theme.timeGap - card.textX)

        x: Theme.alignRight ? Theme.gutter : Theme.screenMarginX
        width: Theme.cardWidth
        height: Math.max(Theme.cardMinHeight, Math.max(Theme.iconSize, texts.implicitHeight) + 2 * Theme.cardPaddingY)

        HoverHandler {
            id: cardHover
        }

        Glass {
            anchors.fill: parent
        }

        MouseArea {
            anchors.fill: parent
            enabled: !root.leaving
            onClicked: root.activate()
        }

        AppIcon {
            x: Theme.cardPaddingX
            anchors.verticalCenter: parent.verticalCenter
            image: root.content.image
            appIcon: root.content.appIcon
            desktopEntry: root.content.desktopEntry
            appName: root.content.appName
            label: root.content.appName || root.title
        }

        Column {
            id: texts

            x: card.textX
            anchors.verticalCenter: parent.verticalCenter
            width: card.textRight - card.textX
            spacing: Theme.lineGap

            Text {
                id: criticalLabel

                visible: root.critical
                width: card.firstRowWidth
                text: Theme.criticalLabel
                elide: Text.ElideRight
                color: Theme.textSecondary
                font.family: Theme.font
                font.pixelSize: Theme.labelSize
                font.weight: Theme.labelWeight
                font.letterSpacing: Theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }

            Text {
                id: titleText

                width: criticalLabel.visible ? texts.width : card.firstRowWidth
                text: root.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.textPrimary
                font.family: Theme.font
                font.pixelSize: Theme.titleSize
                font.weight: Theme.titleWeight
            }

            Text {
                id: bodyText

                visible: text !== ""
                width: texts.width
                text: root.bodyMarkup
                textFormat: Text.StyledText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: Theme.bodyMaxLines
                elide: Text.ElideRight
                color: Theme.textBody
                linkColor: Theme.link
                font.family: Theme.font
                font.pixelSize: Theme.bodySize
                onLinkActivated: link => Qt.openUrlExternally(link)

                HoverHandler {
                    cursorShape: bodyText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }

        Text {
            id: time

            readonly property Item firstRow: criticalLabel.visible ? criticalLabel : titleText

            anchors.right: parent.right
            anchors.rightMargin: Theme.cardPaddingX
            y: texts.y + time.firstRow.y + time.firstRow.baselineOffset - time.baselineOffset
            text: Format.relativeTime(root.receivedAt, Store.now)
            color: Theme.textTertiary
            font.family: Theme.font
            font.pixelSize: Theme.timeSize
        }

        OptionsPill {
            id: pill

            readonly property Item lastRow: bodyText.visible ? bodyText : titleText

            // Its column is reserved whenever the banner has actions, so the
            // text does not reflow when the pill fades in on hover.
            opacity: root.hasMenu && root.chromeShown ? 1 : 0
            visible: opacity > 0
            anchors.right: parent.right
            anchors.rightMargin: Theme.cardPaddingX
            // Centred on the last line of text, as in the reference.
            y: Math.max(Theme.cardPaddingY / 2, Math.min(card.height - height - Theme.cardPaddingY / 2,
                texts.y + pill.lastRow.y + pill.lastRow.height - bodyMetrics.height / 2 - height / 2))
            width: implicitWidth
            height: implicitHeight
            open: root.menuOpen
            enabled: !root.leaving
            onClicked: root.toggleMenu()

            Behavior on opacity {
                NumberAnimation { duration: Theme.hoverDuration }
            }
        }

        CloseButton {
            id: closeButton

            x: Theme.closeInset - width / 2
            y: Theme.closeInset - height / 2
            opacity: root.chromeShown ? 1 : 0
            visible: opacity > 0
            enabled: !root.leaving
            onClicked: root.dismiss()

            Behavior on opacity {
                NumberAnimation { duration: Theme.hoverDuration }
            }
        }
    }
}
