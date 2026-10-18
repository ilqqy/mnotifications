pragma Singleton

import QtQuick
import Quickshell

// Design tokens. Every colour, size, radius and duration the banners draw
// with lives here; components read these and nothing else. The values the
// user can set (Config.qml) are resolved here too, so a missing or invalid
// setting always lands on the default written below.
Singleton {
    id: root

    // ----------------------------------------------------------- behaviour

    readonly property bool dark: Config.mode !== "light"

    readonly property int maxVisible: Config.maxVisible >= 1 ? Math.floor(Config.maxVisible) : 4

    readonly property string position: ["top-right", "top-left", "bottom-right", "bottom-left"]
        .indexOf(Config.position) >= 0 ? Config.position : "top-right"
    readonly property bool alignRight: root.position.endsWith("right")
    readonly property bool alignBottom: root.position.startsWith("bottom")

    // Auto-dismiss delays in ms per urgency; 0 means "until closed".
    // Critical banners never expire.
    readonly property int lowTimeout: Config.lowTimeout ?? 4000
    readonly property int normalTimeout: Config.normalTimeout ?? 6000

    // An app-requested expire_timeout is honoured inside this range and
    // replaced by the urgency default outside it.
    readonly property int appTimeoutMin: 1500
    readonly property int appTimeoutMax: 120000

    // After the pointer leaves a banner its countdown resumes with whatever
    // was left, but never less than this.
    readonly property int resumeMinimum: 1500

    // Text above the title of a critical banner (drawn in capitals).
    readonly property string criticalLabel: "Critical"

    // ---------------------------------------------------------------- type

    readonly property string font: Config.font || "Inter"

    readonly property int titleSize: 13
    readonly property int titleWeight: Font.DemiBold
    readonly property int bodySize: 13
    readonly property int bodyMaxLines: 4
    readonly property int labelSize: 11
    readonly property int labelWeight: Font.DemiBold
    readonly property real labelSpacing: 0.5
    readonly property int timeSize: 12
    readonly property int pillSize: 13
    readonly property int pillWeight: Font.Medium
    readonly property int menuSize: 13

    // -------------------------------------------------------------- colour

    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(Config.accent ?? "")
        ? Config.accent
        : (root.dark ? "#0a84ff" : "#007aff")
    readonly property color accentText: "#ffffff"

    // Text is white or black at fixed alphas, as on macOS, so it keeps its
    // contrast over whatever the blur brings through.
    readonly property color ink: root.dark ? "#ffffff" : "#000000"
    readonly property color textPrimary: Qt.alpha(root.ink, root.dark ? 0.92 : 0.86)
    readonly property color textBody: Qt.alpha(root.ink, root.dark ? 0.84 : 0.78)
    readonly property color textSecondary: Qt.alpha(root.ink, root.dark ? 0.55 : 0.50)
    readonly property color textTertiary: Qt.alpha(root.ink, root.dark ? 0.40 : 0.36)
    readonly property color link: root.accent

    // The glass. Hyprland's layer blur supplies the frost; it applies only
    // where the surface alpha exceeds the layer rule's ignore_alpha (0.2, see
    // README), so every fill below stays above that and the shadow below it.
    readonly property color cardFill: root.dark ? Qt.rgba(0.13, 0.13, 0.14, 0.62) : Qt.rgba(0.97, 0.97, 0.98, 0.70)
    readonly property color cardBorder: root.dark ? Qt.alpha("#ffffff", 0.10) : Qt.alpha("#ffffff", 0.45)
    readonly property color shadowColor: Qt.rgba(0, 0, 0, root.dark ? 0.12 : 0.08)

    readonly property color closeFill: root.dark ? Qt.rgba(0.23, 0.23, 0.24, 0.92) : Qt.rgba(0.96, 0.96, 0.97, 0.92)
    readonly property color closeHoverFill: root.dark ? Qt.rgba(0.30, 0.30, 0.31, 0.95) : Qt.rgba(0.90, 0.90, 0.91, 0.95)
    readonly property color closeBorder: Qt.alpha(root.ink, root.dark ? 0.14 : 0.10)
    readonly property color closeGlyph: Qt.alpha(root.ink, root.dark ? 0.75 : 0.60)

    readonly property color pillFill: Qt.alpha(root.ink, root.dark ? 0.12 : 0.07)
    readonly property color pillHoverFill: Qt.alpha(root.ink, root.dark ? 0.19 : 0.12)
    readonly property color pillText: root.textPrimary

    readonly property color menuFill: root.dark ? Qt.rgba(0.17, 0.17, 0.18, 0.80) : Qt.rgba(0.95, 0.95, 0.96, 0.80)
    readonly property color menuBorder: root.cardBorder
    readonly property color menuText: root.textPrimary

    readonly property color fallbackIconFill: Qt.alpha(root.ink, root.dark ? 0.14 : 0.08)
    readonly property color fallbackIconGlyph: root.textSecondary

    // --------------------------------------------------------------- radii

    readonly property int radiusCard: 20
    readonly property int radiusImage: 9
    readonly property int radiusMenu: 12
    readonly property int radiusMenuRow: 6

    // ------------------------------------------------------ sizes, spacing

    readonly property int cardWidth: 360
    readonly property int cardMinHeight: 64
    readonly property int cardPaddingX: 14
    readonly property int cardPaddingY: 12
    readonly property int iconSize: 40
    readonly property int iconGap: 12
    readonly property int lineGap: 1
    readonly property int timeGap: 8

    readonly property int closeSize: 20
    // How far the close button's centre sits in from the card's corner.
    readonly property int closeInset: 5

    readonly property int pillHeight: 24
    readonly property int pillPaddingX: 10
    readonly property int pillGap: 10
    readonly property int chevronSize: 8

    readonly property int menuMinWidth: 168
    readonly property int menuPadding: 5
    readonly property int menuRowHeight: 26
    readonly property int menuRowPaddingX: 10
    // The menu tucks this far under the card and sticks out this far past
    // the card's outer edge, as in the macOS reference.
    readonly property int menuOverlap: 6
    readonly property int menuOverhang: 14

    readonly property int stackSpacing: 8
    readonly property int screenMarginX: 14
    readonly property int screenMarginY: 10

    readonly property int shadowBlur: 24
    readonly property int shadowOffsetY: 6

    // Room around the cards inside the surface, for the shadow, the close
    // button and the menu overhang.
    readonly property int gutter: 28
    readonly property int surfaceWidth: root.cardWidth + 2 * root.gutter

    // ----------------------------------------------------------- durations

    readonly property int enterDuration: 220
    readonly property int leaveDuration: 180
    readonly property int reflowDuration: 220
    readonly property int hoverDuration: 120
    readonly property int menuDuration: 120
    // Minimum gap between two banners appearing, so a burst arrives as a
    // cascade rather than one jump.
    readonly property int staggerInterval: 70
    readonly property int clockInterval: 30000

    readonly property int enterEasing: Easing.OutCubic
    readonly property int leaveEasing: Easing.InCubic
    readonly property int reflowEasing: Easing.OutCubic

    // --------------------------------------------------------------- icons

    readonly property string fallbackIcon: "dialog-information"
}
