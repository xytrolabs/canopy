// TEMPORARY design preview for the shared interaction components.
// Not part of the shipped shell - it drives Tooltip + MenuController on a
// timer so the tooltip and context-menu surfaces can be inspected without a
// pointer device.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "Components"

ShellRoot {
    PanelWindow {
        anchors { top: true; left: true; right: true; bottom: true }
        color: "#16161C"
        exclusionMode: ExclusionMode.Ignore

        readonly property int sw: width
        readonly property int sh: height

        Text {
            anchors.centerIn: parent
            color: "#7A7A88"
            text: "Canopy interaction preview"
            font.pixelSize: 14
        }

        Item {
            id: bottomAnchor
            x: 320
            y: parent.height - 110
            width: 44
            height: 44
            Rectangle { anchors.fill: parent; radius: 10; color: "#7C5CFC" }
        }

        Item {
            id: rightAnchor
            x: parent.width - 220
            y: 120
            width: 40
            height: 40
            Rectangle { anchors.fill: parent; radius: 8; color: "#30A46C" }
        }
    }

    InteractionOverlay { id: overlay }

    Timer {
        interval: 1500
        running: true
        onTriggered: Tooltip.show(bottomAnchor, "Firefox", "Click to launch", "bottom")
    }

    Timer {
        interval: 4500
        running: true
        onTriggered: {
            Tooltip.hide()
            MenuController.show([
                { label: "Open", icon: "application-x-executable", run: function () {} },
                { label: "Show window", icon: "view-restore-symbolic", run: function () {} },
                { label: "Minimize", icon: "window-minimize-symbolic", run: function () {} },
                { sep: true },
                { label: "Close window", icon: "window-close-symbolic", danger: true, run: function () {} },
                { sep: true },
                { label: "Pin to dock", icon: "emblem-favorite-symbolic", checked: true, run: function () {} },
                { label: "Unavailable action", enabled: false, run: function () {} }
            ], rightAnchor, "below")
        }
    }
}
