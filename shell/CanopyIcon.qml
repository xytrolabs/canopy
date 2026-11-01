import QtQuick
import Qt5Compat.GraphicalEffects
import "icon-map.js" as IconMap

// CanopyIcon - renders an icon from the generated system icon index.
// The index (icon-map.js) is produced by scripts/gen-icon-map.py and maps
// icon names to real files on disk, so we never rely on Qt's theme lookup
// (which fails for most names and paints the missing-image checkerboard).
Item {
    id: root

    property string iconName: ""
    property int size: 18
    // Fallback letter follows the theme so it never washes out in light mode.
    property color fallbackColor: Theme.textSecondary
    // When set (alpha > 0) the glyph is recoloured - use this for monochrome
    // symbolic icons so they stay visible on light or dark surfaces.
    property color tint: "transparent"
    readonly property bool tinted: tint.a > 0

    implicitWidth: size
    implicitHeight: size

    readonly property string resolvedPath: {
        if (!iconName) return ""
        // Quickshell hands StatusNotifierItem icons over as an image provider
        // URL: "image://icon/<theme name>". Rendering that URL directly
        // produced magenta/garbage pixmaps under this Qt build, so the name is
        // unwrapped and resolved through our own index instead. We only use it as
        // a last resort, and only for names that look like real icon names.
        const iconProvider = "image://icon/"
        if (iconName.indexOf(iconProvider) === 0) {
            const n = iconName.substring(iconProvider.length)
            let ip = IconMap.map[n]
            if (!ip) ip = IconMap.map[n + "-symbolic"]
            return ip ? ip : ""
        }
        // Absolute paths and raw provider URLs (e.g. image://qspixmap/... which
        // carries the application's own pixmap) are used verbatim.
        if (iconName.charAt(0) === "/") return iconName
        if (iconName.indexOf("file://") === 0) return iconName.substring(7)
        if (iconName.indexOf("image://") === 0 || iconName.indexOf("qrc:/") === 0) return iconName
        let p = IconMap.map[iconName]
        if (!p) p = IconMap.map[iconName + "-symbolic"]
        if (p) return p
        // Themes usually ship a non-symbolic and a -symbolic variant under the
        // same base name; our index is generated from whatever was installed on
        // the machine that ran gen-icon-map.py, so a thin set can miss one of
        // them. Try the common aliases before giving up.
        const base = iconName.endsWith("-symbolic") ? iconName.slice(0, -9) : iconName
        if (IconMap.map[base]) return IconMap.map[base]
        if (IconMap.map[base + "-symbolic"]) return IconMap.map[base + "-symbolic"]
        if (IconMap.map[base + "-plain"]) return IconMap.map[base + "-plain"]
        return ""
    }
    readonly property string source: {
        const r = resolvedPath
        if (r === "") {
            // Qt's own icon provider knows every base name the theme declares,
            // including ones our map never saw. Fall back to it so a missing
            // entry (or a stale map) does not become a letter glyph - the
            // reported symptom of "a lot of apps are still missing icons".
            const n = iconName.indexOf("image://icon/") === 0 ? iconName.substring(13)
                                                                     : iconName
            if (n !== "" && n.indexOf("/") < 0 && n.indexOf("://") < 0) return "image://icon/" + n
            return ""
        }
        if (r.indexOf("://") >= 0) return r
        return "file://" + r
    }
    readonly property bool resolved: img.status === Image.Ready

    Image {
        id: img
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        source: root.source
        sourceSize.width: Math.max(16, root.size * 2)
        sourceSize.height: Math.max(16, root.size * 2)
        visible: status === Image.Ready && !root.tinted
    }

    ColorOverlay {
        anchors.fill: img
        source: img
        color: root.tint
        cached: true
        visible: img.status === Image.Ready && root.tinted
    }

    Text {
        anchors.centerIn: parent
        visible: !root.resolved
        text: root.iconName.length > 0 ? root.iconName.charAt(0).toUpperCase() : "?"
        color: root.fallbackColor
        font.pixelSize: Math.max(8, Math.round(root.size * 0.6))
        font.bold: true
    }
}
