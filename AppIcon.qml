import QtQuick
import QtQuick.Effects
import Quickshell

// The icon at the left of a banner.
//
// Candidates, best first: the image hint (image-data or image-path, which
// Quickshell has already turned into a URL), the app_icon, the icon of the
// sender's desktop entry, then the theme's generic icon. A candidate that is
// missing from the icon theme is never tried; one that fails to load is
// skipped. With nothing left, a tile with the app's initial is drawn.
Item {
    id: root

    property string image: ""
    property string appIcon: ""
    property string desktopEntry: ""
    property string appName: ""
    property string label: ""

    implicitWidth: Theme.iconSize
    implicitHeight: Theme.iconSize

    // `photo` marks pictures (avatars, album art) rather than icons: those are
    // cropped to fill the square and get rounded corners.
    function resolve(value: string, photo: bool): var {
        if (!value) return null;
        if (value.startsWith("image://icon/")) {
            const name = decodeURIComponent(value.slice(13).split("?")[0]);
            // Quickshell wraps a path given as image-path the same way.
            if (name.startsWith("/")) return {"source": "file://" + name, "photo": photo};
            if (name.startsWith("file://")) return {"source": name, "photo": photo};
            return Quickshell.hasThemeIcon(name) ? {"source": value, "photo": false} : null;
        }
        if (value.startsWith("image://") || value.startsWith("file://")) return {"source": value, "photo": photo};
        if (value.startsWith("/")) return {"source": "file://" + value, "photo": photo};
        // Any other scheme (http and the like) is not fetched.
        if (value.includes("://")) return null;
        const themed = Quickshell.iconPath(value, true);
        return themed ? {"source": themed, "photo": false} : null;
    }

    readonly property var entry: {
        // Re-evaluated once the desktop entries have finished loading.
        void DesktopEntries.applications.values;
        const id = root.desktopEntry.replace(/\.desktop$/, "");
        return (id ? DesktopEntries.byId(id) : null)
            ?? (root.appName ? DesktopEntries.heuristicLookup(root.appName) : null);
    }

    readonly property var candidates: [
        root.resolve(root.image, true),
        root.resolve(root.appIcon, false),
        root.resolve(root.entry?.icon ?? "", false),
        root.resolve(Theme.fallbackIcon, false)
    ].filter(c => c !== null)

    property int attempt: 0
    onCandidatesChanged: root.attempt = 0

    readonly property var current: root.attempt < root.candidates.length ? root.candidates[root.attempt] : null
    readonly property bool photo: root.current?.photo ?? false

    Image {
        id: picture

        anchors.fill: parent
        source: root.current?.source ?? ""
        sourceSize.width: Theme.iconSize
        sourceSize.height: Theme.iconSize
        fillMode: root.photo ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        onStatusChanged: {
            if (status !== Image.Error) return;
            Store.debugLog("icon failed: " + source);
            root.attempt += 1;
        }

        // The rounding is a shader effect. Qt's software renderer draws
        // shader effects as nothing, so there the picture stays square
        // rather than vanishing.
        layer.enabled: root.photo && picture.GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: corners
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Item {
        id: corners

        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusImage
            color: "black"
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.current === null
        radius: Theme.radiusImage
        color: Theme.fallbackIconFill

        Text {
            anchors.centerIn: parent
            text: (root.label.trim()[0] ?? "?").toUpperCase()
            color: Theme.fallbackIconGlyph
            font.family: Theme.font
            font.pixelSize: Math.round(Theme.iconSize * 0.45)
            font.weight: Font.DemiBold
        }
    }
}
