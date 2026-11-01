import QtQuick
import "../../"

// Canopy settings toggle. `value` is the live state; `toggled` fires on user action.
Item {
    id: root
    property bool value: false
    signal toggled(bool newValue)

    implicitWidth: 46
    implicitHeight: 26
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.value ? Theme.accent : (Theme.darkMode ? "#33FFFFFF" : "#22000000")
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Rectangle {
            width: 20; height: 20; radius: 10
            y: 3
            x: root.value ? parent.width - 23 : 3
            color: "white"
            Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.value)
    }
}
