import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Phase 1: the server alone. Every notification, replacement and close is
// printed as one JSON line; nothing is drawn yet.
ShellRoot {
    id: root

    function describe(n: var): var {
        return {
            "id": n.id,
            "appName": n.appName,
            "appIcon": n.appIcon,
            "desktopEntry": n.desktopEntry,
            "image": n.image,
            "summary": n.summary,
            "body": n.body,
            "urgency": NotificationUrgency.toString(n.urgency),
            "expireTimeout": n.expireTimeout,
            "resident": n.resident,
            "transient": n.transient,
            "actions": n.actions.map(a => ({"id": a.identifier, "text": a.text})),
            "hints": Object.keys(n.hints)
        };
    }

    function log(event: string, payload: var) {
        console.info("mnotifications " + JSON.stringify(Object.assign({"event": event}, payload)));
    }

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

        onNotification: n => {
            n.tracked = true;
            root.log("notify", root.describe(n));
            // A Notify call with replaces_id updates this same object.
            n.summaryChanged.connect(() => root.log("replace", root.describe(n)));
            n.bodyChanged.connect(() => root.log("replace", root.describe(n)));
            n.closed.connect(reason => root.log("closed", {
                "id": n.id,
                "reason": NotificationCloseReason.toString(reason)
            }));
        }
    }
}
