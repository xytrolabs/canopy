pragma Singleton
import QtQuick

QtObject {
    id: theme

    // ---- Appearance mode ----
    // themeMode is the persisted preference: "light" | "dark" | "auto".
    // darkMode is the live, effective state every component binds to.
    property string themeMode: "dark"
    property bool darkMode: true

    function applyThemeMode(mode, hour) {
        themeMode = mode
        if (mode === "light") darkMode = false
        else if (mode === "dark") darkMode = true
        else darkMode = !(hour >= 7 && hour < 19)
    }

    // ---- Scale / motion ----
    property real uiScale: 1.0
    property real density: 1.0
    property bool animationsEnabled: true
    property int animFast: animationsEnabled ? 140 : 0
    property int animMedium: animationsEnabled ? 220 : 0
    property int animSlow: animationsEnabled ? 320 : 0

    // ---- Colour tokens ----
    // Matched to the Canopy site: near-black violet base (#0B0A10), surfaces
    // that read as tinted glass rather than grey, one saturated accent.
    property color bgDeep: darkMode ? "#0B0A10" : "#F3F3F7"
    property color surface: darkMode ? "#16151F" : "#FFFFFF"
    property color surfaceElevated: darkMode ? "#201E2C" : "#F2F2F7"
    property color surfaceTranslucent: darkMode ? "#E616151F" : "#E6FFFFFF"
    property color acrylic: darkMode ? "#D9201E2C" : "#F2FFFFFF"
    property color border: darkMode ? "#33FFFFFF" : "#1A000000"
    property color textPrimary: darkMode ? "#F2F0F7" : "#1C1C1E"
    property color textSecondary: darkMode ? "#A9A5BB" : "#5A5A66"
    property color textMuted: darkMode ? "#7B7791" : "#8E8E99"
    property color accent: "#7C5CFC"
    property color accentHover: "#8E72FF"
    property color accentPressed: "#6A4BE0"
    property color danger: "#E5484D"
    property color success: "#30A46C"

    // ---- Materials -------------------------------------------------------
    // No blur is available on this compositor (ext-background-effect-v1 is
    // absent), so depth is built from layered translucency, hairlines and
    // soft shadow rings instead of blur passes.
    property color panelBg: darkMode ? "#E00C0B12" : "#E6F7F7FA"
    property color panelBorder: darkMode ? "#1FFFFFFF" : "#14000000"
    property color cardBg: darkMode ? "#F21A1826" : "#FAFFFFFF"
    property color cardBorder: darkMode ? "#2AFFFFFF" : "#17000000"
    property color barBg: darkMode ? "#B414131E" : "#C9FFFFFF"
    property color barBorder: darkMode ? "#38FFFFFF" : "#22000000"
    property color hoverBg: darkMode ? "#1FFFFFFF" : "#10000000"
    property color pressedBg: darkMode ? "#33FFFFFF" : "#1C000000"
    property color selectedBg: darkMode ? "#2EFFFFFF" : "#14000000"
    property color hairline: darkMode ? "#1AFFFFFF" : "#12000000"
    property color chipBg: darkMode ? "#1FFFFFFF" : "#0F000000"
    property color shadow: "#000000"
    property double shadowOpacity: darkMode ? 0.50 : 0.18
    property color scrim: darkMode ? "#8C000000" : "#33000000"

    // ---- Geometry ----
    property int radiusSmall: 8
    property int radiusMedium: 12
    property int radiusLarge: 18
    property int radiusXl: 22
    property int radiusPill: 999
    readonly property int spacingXs: Math.round(4 * density)
    readonly property int spacingSm: Math.round(8 * density)
    readonly property int spacingMd: Math.round(12 * density)
    readonly property int spacingLg: Math.round(16 * density)
    readonly property int spacingXl: Math.round(24 * density)

    // ---- Typography ------------------------------------------------------
    // Three families ship inside shell/fonts and are registered by the
    // FontLoader block at the top of shell.qml, so these names resolve even on
    // a machine with nothing installed. They are the families the Canopy site
    // uses, which is why the shell now reads like the site rather than like a
    // generic toolkit app:
    //   Space Grotesk - panel, dock, headings. Distinctive geometric grotesque.
    //   Inter         - everything you actually read (menus, settings, body).
    //   JetBrains Mono- numerals that must not jitter (clock, percentages).
    readonly property string fontDisplay: "Space Grotesk"
    readonly property string fontBody: "Inter"
    readonly property string fontMono: "JetBrains Mono"

    // Legacy name: every component already binds `font.family: Theme.fontFamily`,
    // so pointing it at the display face retypes the whole shell in one move.
    // Space Grotesk is the face the Canopy site uses for its panel, so the
    // desktop and the site now share one voice. Inter stays available as
    // Theme.fontBody for long-form copy where a neutral face reads better.
    readonly property string fontFamily: fontDisplay

    readonly property int weightRegular: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightSemibold: Font.DemiBold
    readonly property int weightBold: Font.Bold

    readonly property int fontSizeXs: Math.round(11 * uiScale)
    readonly property int fontSizeSm: Math.round(12 * uiScale)
    readonly property int fontSizeMd: Math.round(13 * uiScale)
    readonly property int fontSizeLg: Math.round(15 * uiScale)
    readonly property int fontSizeXl: Math.round(20 * uiScale)
    readonly property int fontSizeTitle: Math.round(28 * uiScale)
    readonly property real tracking: 0.15
    // Space Grotesk is drawn tight; body copy wants a touch more air.
    readonly property real trackingDisplay: -0.2
    readonly property real trackingWide: 0.4

    // ---- Transparency ----
    property double acrylicOpacity: 0.92
}
