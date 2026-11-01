import QtQuick
import ".."

// IconButton - the single icon-button implementation used by the panel, the
// system tray, the dock and the settings window. Handles hover, press, active
// state, tooltip and left/right click in one place so every surface behaves
// identically.
Item {
    id: root

    property string iconName: ""
    property int iconSize: 18

    // Optional artwork (SVG/PNG) rendered instead of `iconName`. Used by the
    // panel's launcher button, which carries the Canopy mark rather than a
    // generic app-grid glyph. Artwork keeps its own colours - no tinting.
    property string imageSource: ""

    // Tooltip text. `tipLabel` defaults to `label`.
    property string label: ""
    property string tipLabel: ""
    property string tipDetail: ""
    property string tipPlacement: "bottom"

    property bool active: false
    property bool background: true
    property int buttonRadius: Theme.radiusSmall
    property color tint: Theme.textPrimary
    property bool tinted: true

    // Optional colours
    property color activeColor: Theme.accent
    property bool activeFilled: false

    signal clicked()
    signal rightClicked()

    // Set false for elements that open their own popup (e.g. StatusNotifier
    // items with a real DBusMenu) so tooltips never fight with the menu.
    property bool tooltipEnabled: true

    readonly property bool hovered: ma.containsMouse

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    property int buttonSize: 32

    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: root.buttonRadius
        visible: root.background
        color: {
            if (root.activeFilled) return root.activeColor
            if (ma.containsMouse && ma.pressed) return Theme.pressedBg
            if (ma.containsMouse || root.active) return Theme.hoverBg
            return "transparent"
        }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    CanopyIcon {
        anchors.centerIn: parent
        visible: root.imageSource === ""
        size: root.iconSize
        iconName: root.iconName
        tint: !root.tinted ? "transparent"
              : (root.activeFilled ? "#FFFFFF" : (root.active ? root.activeColor : root.tint))
    }

    Image {
        anchors.centerIn: parent
        visible: root.imageSource !== ""
        source: root.imageSource
        sourceSize.width: root.iconSize * 2
        sourceSize.height: root.iconSize * 2
        width: root.iconSize
        height: root.iconSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: ma.pressed ? 0.8 : 1.0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            if (!root.tooltipEnabled) return
            const t = root.tipLabel !== "" ? root.tipLabel : root.label
            if (t === "") return
            Tooltip.show(root, t, root.tipDetail, root.tipPlacement)
        }
        onExited: Tooltip.hide()

        onClicked: (m) => {
            if (m.button === Qt.RightButton) root.rightClicked()
            else root.clicked()
        }
    }
}
