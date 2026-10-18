import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The layer surface holding the stack: a full-height column along one screen
// edge. Only the banners and the open menu take input; the rest of the
// column lets clicks through to whatever is underneath.
PanelWindow {
    id: window

    function pickScreen(): var {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === Config.output) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    screen: window.pickScreen()
    color: "transparent"

    WlrLayershell.namespace: "notif-macos"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Stay clear of bars, reserve nothing.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    anchors {
        top: true
        bottom: true
        left: !Theme.alignRight
        right: Theme.alignRight
    }
    implicitWidth: Theme.surfaceWidth

    mask: Region {
        item: stack.hitArea

        Region {
            item: stack.menu.open ? stack.menu : null
        }
    }

    BannerStack {
        id: stack
        anchors.fill: parent
    }

    // Closes the menu on a click anywhere outside this surface.
    HyprlandFocusGrab {
        windows: [window]
        active: stack.menu.open
        onCleared: stack.menu.close()
    }
}
