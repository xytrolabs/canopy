import QtQuick
import "../../"

// Accent-colour swatch picker.
Item {
    id: root
    property var colors: ["#7C5CFC", "#0A84FF", "#30A46C", "#E5484D", "#FEBC2E", "#FF7AB6"]
    property color current: "#7C5CFC"
    signal picked(color value)

    implicitWidth: row.implicitWidth
    implicitHeight: 26
    width: implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: 8
        Repeater {
            model: root.colors
            delegate: Rectangle {
                width: 24; height: 24; radius: 12
                color: modelData
                border.color: String(root.current).toLowerCase() === String(modelData).toLowerCase()
                              ? Theme.textPrimary : "transparent"
                border.width: 2
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(modelData)
                }
            }
        }
    }
}
