pragma Singleton
import QtQuick
import Quickshell

// Coords - converts item positions into SCREEN coordinates.
//
// Every Canopy surface lives in its own wlr-layer-shell window (panel, tray,
// dock, overlay...). Item.mapToGlobal() is unusable here: Qt has no position for
// a layer surface, so it answers with window-local pixels. Quickshell's
// itemRect() is not uniform either - measured on 0.3.2 it returned a
// screen-space X but a window-local Y, which is exactly why dock tooltips (a
// bottom-anchored window) appeared up near the panel.
//
// This computes the window origin from the surface's own layer-shell geometry -
// its anchors, margins and the screen size - then adds the item's position
// inside that window. Correct for any edge, alignment, resolution and scale
// factor, with no magic offsets.
QtObject {
    id: coords

    function _window(item) {
        try {
            const w = item.QsWindow.window
            if (w) return w
        } catch (e) { }
        try {
            const w2 = item.Window.window
            if (w2) return w2
        } catch (e) { }
        return null
    }

    // Screen-space origin of a layer-shell window.
    function windowOrigin(win) {
        if (!win) return Qt.point(0, 0)
        const sc = win.screen
        const sw = sc ? sc.width : 0
        const sh = sc ? sc.height : 0

        let a = null
        let m = null
        try { a = win.anchors } catch (e) { a = null }
        try { m = win.margins } catch (e) { m = null }

        let x = 0
        let y = 0
        if (a) {
            const left = a.left === true
            const right = a.right === true
            const top = a.top === true
            const bottom = a.bottom === true

            // anchored to the right edge only -> subtract our width; else left
            if (right && !left) x = sw - win.width - (m ? m.right : 0)
            else x = m ? m.left : 0

            if (bottom && !top) y = sh - win.height - (m ? m.bottom : 0)
            else y = m ? m.top : 0
        }
        return Qt.point(x, y)
    }

    // {x, y, width, height} of `item` in screen coordinates.
    function rectOf(item) {
        if (!item) return Qt.rect(0, 0, 0, 0)
        const win = _window(item)
        // where the item sits inside its own window (scene coordinates)
        const p = item.mapToItem(null, 0, 0)
        const o = windowOrigin(win)
        return Qt.rect(o.x + p.x, o.y + p.y, item.width, item.height)
    }

    function centerOf(item) {
        const r = rectOf(item)
        return Qt.point(r.x + r.width / 2, r.y + r.height / 2)
    }
}
