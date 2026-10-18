pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Owns the notification server and decides what is on screen.
//
// Every incoming notification is queued; pump() moves queued ones into
// `shown` (newest first) while fewer than Theme.maxVisible banners hold a
// slot, at most one per Theme.staggerInterval. A banner gives its slot back
// with release() the moment it starts leaving and disappears from `shown`
// with remove() once its slide-out has finished.
//
// The log lines carry ids, app names and state changes only, never the
// summary or body.
Singleton {
    id: root

    readonly property ListModel shown: ListModel {}

    // id -> { notification, receivedAt, state: "queued" | "shown" }
    property var entries: ({})
    // Queued ids in display order: critical first, then oldest first.
    property var queue: []
    property int occupied: 0
    property real lastShownAt: 0

    // Wall clock for the relative timestamps, ticking while anything shows.
    property real now: Date.now()

    function notificationFor(id: int): var {
        return root.entries[id]?.notification ?? null;
    }

    function receivedAt(id: int): real {
        return root.entries[id]?.receivedAt ?? Date.now();
    }

    function log(message: string) {
        console.info("mnotifications: " + message);
    }

    // MNOTIFICATIONS_DEBUG=1 adds layout geometry to the log, which the
    // isolated test uses to aim its clicks.
    readonly property bool debug: Quickshell.env("MNOTIFICATIONS_DEBUG") === "1"

    function debugLog(message: string) {
        if (root.debug) root.log(message);
    }

    function add(n: var) {
        n.tracked = true;
        const id = n.id;
        root.entries[id] = {"notification": n, "receivedAt": Date.now(), "state": "queued"};

        const critical = n.urgency === NotificationUrgency.Critical;
        let at = root.queue.length;
        if (critical) {
            at = root.queue.findIndex(q => root.entries[q].notification.urgency !== NotificationUrgency.Critical);
            if (at < 0) at = root.queue.length;
        }
        root.queue.splice(at, 0, id);

        root.log("notify id=" + id + " app=" + JSON.stringify(n.appName)
            + " urgency=" + NotificationUrgency.toString(n.urgency)
            + " expireTimeout=" + n.expireTimeout + " actions=" + n.actions.length
            + (n.lastGeneration ? " (from before reload)" : ""));

        const replaced = () => root.replaced(id);
        n.summaryChanged.connect(replaced);
        n.bodyChanged.connect(replaced);
        n.closed.connect(reason => root.closed(id, reason));

        root.pump();
    }

    // A Notify call carrying this id as replaces_id updated the object in
    // place. Several property signals fire for one call; they collapse here.
    property var replacedIds: ({})

    function replaced(id: int) {
        const entry = root.entries[id];
        if (!entry) return;
        entry.receivedAt = Date.now();
        root.replacedIds[id] = true;
        Qt.callLater(root.logReplaced);
    }

    function logReplaced() {
        for (const id of Object.keys(root.replacedIds)) {
            root.log("replace id=" + id + " state=" + (root.entries[id]?.state ?? "gone"));
        }
        root.replacedIds = ({});
    }

    function closed(id: int, reason: int) {
        root.log("closed id=" + id + " reason=" + NotificationCloseReason.toString(reason));
        const entry = root.entries[id];
        if (entry?.state === "queued") {
            root.queue = root.queue.filter(q => q !== id);
            delete root.entries[id];
        }
        // A shown banner sees the same signal and starts its own slide-out.
    }

    function pump() {
        while (root.queue.length > 0 && root.occupied < Theme.maxVisible) {
            const wait = root.lastShownAt + Theme.staggerInterval - Date.now();
            if (wait > 0) {
                stagger.interval = wait;
                stagger.restart();
                return;
            }
            const id = root.queue.shift();
            root.entries[id].state = "shown";
            root.occupied += 1;
            root.lastShownAt = Date.now();
            root.shown.insert(0, {"key": id});
            root.log("shown id=" + id + " queued=" + root.queue.length);
        }
    }

    function release(id: int) {
        root.occupied = Math.max(0, root.occupied - 1);
        root.pump();
    }

    function remove(id: int) {
        for (let i = 0; i < root.shown.count; i++) {
            if (root.shown.get(i).key === id) {
                root.shown.remove(i);
                break;
            }
        }
        delete root.entries[id];
    }

    Timer {
        id: stagger
        onTriggered: root.pump()
    }

    Timer {
        interval: Theme.clockInterval
        repeat: true
        running: root.shown.count > 0
        onRunningChanged: root.now = Date.now()
        onTriggered: root.now = Date.now()
    }

    // Which icon theme the wrapper picked for the configured mode.
    Component.onCompleted: root.log("started, icon theme " + (Quickshell.env("QS_ICON_THEME") || "(Qt default)"))

    NotificationServer {
        keepOnReload: true
        persistenceSupported: false
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false

        onNotification: n => root.add(n)
    }
}
