import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// InteractionOverlay - a single Overlay-layer surface that renders every
// tooltip and every context menu in Canopy.
//
// * Tooltips never take input (its input region stays 0x0, so clicks pass
//   straight through to whatever is underneath).
// * While a context menu is open the input region becomes the whole screen so
//   that a click anywhere dismisses the menu, exactly like a native popup.
PanelWindow {
    id: overlay

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "canopy-overlay"
    WlrLayershell.keyboardFocus: MenuController.open ? WlrKeyboardFocus.Exclusive
                                                     : WlrKeyboardFocus.None
    visible: Tooltip.shown || MenuController.open

    readonly property int edge: 8

    // ---------- positioning ----------
    function tooltipPoint(w, h) {
        let x = Tooltip.anchorX + Tooltip.anchorW / 2 - w / 2
        let y = Tooltip.anchorY + Tooltip.anchorH + Tooltip.gap
        if (Tooltip.placement === "top") {
            y = Tooltip.anchorY - h - Tooltip.gap
        } else if (Tooltip.placement === "right") {
            x = Tooltip.anchorX + Tooltip.anchorW + Tooltip.gap
            y = Tooltip.anchorY + Tooltip.anchorH / 2 - h / 2
        } else if (Tooltip.placement === "left") {
            x = Tooltip.anchorX - w - Tooltip.gap
            y = Tooltip.anchorY + Tooltip.anchorH / 2 - h / 2
        }
        // keep it on screen: flip first, then clamp
        if (y + h > height - edge) y = Tooltip.anchorY - h - Tooltip.gap
        if (y < edge) y = Tooltip.anchorY + Tooltip.anchorH + Tooltip.gap
        y = Math.max(edge, Math.min(y, height - h - edge))
        x = Math.max(edge, Math.min(x, width - w - edge))
        return Qt.point(x, y)
    }

    function menuPoint(w, h) {
        let x = MenuController.anchorX
        let y = MenuController.anchorY + MenuController.anchorH + MenuController.gap
        if (MenuController.placement === "above")
            y = MenuController.anchorY - h - MenuController.gap
        if (y + h > height - edge)
            y = Math.max(edge, MenuController.anchorY - h - MenuController.gap)
        if (y < edge) y = edge
        if (x + w > width - edge) x = width - w - edge
        x = Math.max(edge, x)
        return Qt.point(x, y)
    }

    // ---------- input ----------
    // Full-screen click catcher, but only while a menu is open.
    mask: Region { item: blocker }

    Item {
        id: blocker
        x: 0
        y: 0
        width: MenuController.open ? overlay.width : 0
        height: MenuController.open ? overlay.height : 0

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: MenuController.close()
            onWheel: MenuController.close()
        }
    }

    // ---------- keyboard ----------
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: MenuController.open
        Keys.onEscapePressed: MenuController.close()
        Keys.onDownPressed: MenuController.moveSelection(1)
        Keys.onUpPressed: MenuController.moveSelection(-1)
        Keys.onReturnPressed: MenuController.activateSelected()
        Keys.onEnterPressed: MenuController.activateSelected()
    }

    // ---------- tooltip ----------
    CanopyTooltipCard {
        id: tip
        visible: Tooltip.shown
        title: Tooltip.title
        detail: Tooltip.detail

        readonly property var pt: overlay.tooltipPoint(implicitWidth, implicitHeight)
        x: pt.x
        y: pt.y
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    // ---------- context menu ----------
    CanopyMenuCard {
        id: menu
        visible: MenuController.open && MenuController.items.length > 0
        items: MenuController.items
        hoverIndex: MenuController.hoverIndex

        readonly property var pt: overlay.menuPoint(implicitWidth, implicitHeight)
        x: pt.x
        y: pt.y
    }
}
