pragma Singleton
import QtQuick

// Tooltip - global tooltip controller for the whole shell.
//
// One instance of this singleton exists per shell runtime. Any element that
// wants a tooltip calls:
//
//     Tooltip.show(item, "Settings", "Open Canopy settings", "right")
//
// and calls Tooltip.hide() when the pointer leaves. The single overlay
// surface (InteractionOverlay) renders the card, so every tooltip in Canopy
// shares the same look, delay and edge handling.
QtObject {
    id: ctl

    // ---- Public state read by InteractionOverlay ----
    property bool shown: false
    property string title: ""
    property string detail: ""
    // bottom | top | right | left
    property string placement: "bottom"
    // Anchor rectangle in global (screen) coordinates
    property real anchorX: 0
    property real anchorY: 0
    property real anchorW: 0
    property real anchorH: 0

    // Short hover delay, as requested ("show after a short hover delay").
    readonly property int delayMs: 400
    readonly property int gap: 8

    property var _source: null

    // QtObject has no default property, so the timer must be a property.
    property Timer delayTimer: Timer {
        interval: ctl.delayMs
        repeat: false
        onTriggered: ctl._present()
    }

    function show(item, title, detail, place) {
        if (!item) return
        if (!title || title === "") return
        _source = item
        ctl.title = title
        ctl.detail = detail ? detail : ""
        ctl.placement = place ? place : "bottom"
        shown = false
        delayTimer.restart()
    }

    // Update the text of an already-visible tooltip without re-anchoring
    function update(title, detail) {
        if (!shown) return
        ctl.title = title ? title : ""
        ctl.detail = detail ? detail : ""
    }

    function _present() {
        const it = _source
        if (!it || title === "") return
        if (it.width <= 0 || it.height <= 0) return
        // Screen coordinates, not window-local ones: see Coords.qml.
        const r = Coords.rectOf(it)
        ctl.anchorX = r.x
        ctl.anchorY = r.y
        ctl.anchorW = r.width
        ctl.anchorH = r.height
        shown = true
    }

    function hide() {
        delayTimer.stop()
        shown = false
        _source = null
    }
}
