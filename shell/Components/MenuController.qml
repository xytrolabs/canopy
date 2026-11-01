pragma Singleton
import QtQuick

// MenuController - one shared context-menu implementation for the whole shell.
//
// Menu items are plain JS objects so callers stay declarative and can build
// menus from real system state:
//
//   {
//       label:   "Pin to dock",
//       icon:    "emblem-favorite-symbolic",   // optional
//       detail:  "optional second line",       // optional
//       enabled: true,                          // optional, false = greyed out
//       danger:  false,                         // optional, red label
//       checked: true,                          // optional, shows a tick
//       sep:     false,                         // true = separator, no action
//       run:     function () { ... }            // required unless sep
//   }
//
// Anything that opens a menu calls:
//
//     MenuController.show(items, sourceItem)          // below the item
//     MenuController.show(items, sourceItem, "above")  // above the item
QtObject {
    id: ctl

    property bool open: false
    property var items: []
    property int hoverIndex: -1
    property string placement: "below"

    property real anchorX: 0
    property real anchorY: 0
    property real anchorW: 0
    property real anchorH: 0

    readonly property int gap: 6

    function show(menuItems, item, place) {
        if (!item) return
        if (!menuItems || menuItems.length === 0) return
        // Never show a menu behind a tooltip.
        Tooltip.hide()
        // Screen coordinates, not window-local ones: see Coords.qml.
        const r = Coords.rectOf(item)
        ctl.anchorX = r.x
        ctl.anchorY = r.y
        ctl.anchorW = r.width
        ctl.anchorH = r.height
        ctl.placement = place ? place : "below"
        ctl.items = menuItems
        ctl.hoverIndex = -1
        ctl.open = true
    }

    // Anchored at an explicit screen point (used by the desktop background,
    // where the menu should open exactly at the pointer).
    function showAt(menuItems, x, y, place) {
        if (!menuItems || menuItems.length === 0) return
        Tooltip.hide()
        ctl.anchorX = x
        ctl.anchorY = y
        ctl.anchorW = 0
        ctl.anchorH = 0
        ctl.placement = place ? place : "below"
        ctl.items = menuItems
        ctl.hoverIndex = -1
        ctl.open = true
    }

    function close() {
        ctl.open = false
        ctl.items = []
        ctl.hoverIndex = -1
    }

    function isValid(i) {
        const it = ctl.items[i]
        return !!(it && it.sep !== true && it.enabled !== false && typeof it.run === "function")
    }

    // Keyboard navigation: move the highlight to the next/previous selectable
    // row, wrapping around.
    function moveSelection(delta) {
        const n = ctl.items.length
        if (n === 0) return
        let i = ctl.hoverIndex
        for (let step = 0; step < n; step++) {
            i = (i + delta + n) % n
            if (isValid(i)) {
                ctl.hoverIndex = i
                return
            }
        }
    }

    function activateSelected() {
        if (ctl.hoverIndex >= 0) ctl.activate(ctl.hoverIndex)
    }

    function activate(i) {
        if (!isValid(i)) return
        const it = ctl.items[i]
        // Close first so the menu cannot linger over whatever the action opens.
        close()
        it.run()
    }
}
