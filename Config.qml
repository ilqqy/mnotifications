pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// User settings, merged key by key, lowest precedence first:
//   1. Theme.qml defaults (a key missing here falls through to them)
//   2. /etc/xdg/mnotifications/config.json            (nixosModules.default)
//   3. $XDG_CONFIG_HOME/mnotifications/config.json   (homeManagerModules.default)
//      or the file named by $MNOTIFICATIONS_CONFIG
// Both files are watched; editing one restyles running banners.
Singleton {
    id: root

    readonly property string systemPath: "/etc/xdg/mnotifications/config.json"
    readonly property string userPath: Quickshell.env("MNOTIFICATIONS_CONFIG")
        || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
            + "/mnotifications/config.json")

    property var system: ({})
    property var user: ({})

    // Resolved values; null or undefined means "use the theme default".
    readonly property var font: root.pick("font", "string")
    readonly property var maxVisible: root.pick("maxVisible", "number")
    readonly property var position: root.pick("position", "string")
    readonly property var output: root.pick("output", "string")
    readonly property var mode: root.pick("mode", "string")
    readonly property var accent: root.pick("accent", "string")
    readonly property var lowTimeout: root.pickTimeout("low")
    readonly property var normalTimeout: root.pickTimeout("normal")

    function pick(key: string, type: string): var {
        if (typeof root.user[key] === type) return root.user[key];
        if (typeof root.system[key] === type) return root.system[key];
        return null;
    }

    function pickTimeout(key: string): var {
        for (const layer of [root.user, root.system]) {
            const t = layer.timeouts;
            if (t && typeof t[key] === "number" && t[key] >= 0) return t[key];
        }
        return null;
    }

    function parse(view: var): var {
        try {
            const parsed = JSON.parse(view.text());
            return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }

    FileView {
        id: systemFile
        path: root.systemPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.system = root.parse(systemFile)
        onLoadFailed: root.system = ({})
    }

    FileView {
        id: userFile
        path: root.userPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.user = root.parse(userFile)
        onLoadFailed: root.user = ({})
    }
}
