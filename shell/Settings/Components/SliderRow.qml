import QtQuick
import "../../"

// Slider with an inline value readout.
Item {
    id: root
    property real from: 0
    property real to: 1
    property real value: 0
    property string suffix: ""
    signal moved(real newValue)

    implicitWidth: 210
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight

    Text {
        id: valueText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        horizontalAlignment: Text.AlignRight
        text: (root.suffix === "" ? Math.round(root.value * 100) + "%"
                                : Math.round(root.value) + root.suffix)
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeXs
        font.family: Theme.fontFamily
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: valueText.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: 3
        color: Theme.darkMode ? "#2EFFFFFF" : "#14000000"

        Rectangle {
            width: Math.max(6, parent.width * ((root.value - root.from) / (root.to - root.from)))
            height: parent.height
            radius: 3
            color: Theme.accent
        }

        Rectangle {
            width: 14; height: 14; radius: 7
            color: "white"
            border.color: Theme.accent
            border.width: 2
            y: -4
            x: Math.max(0, Math.min(parent.width - width,
                   parent.width * ((root.value - root.from) / (root.to - root.from)) - width / 2))
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            function pick(mx) {
                const t = Math.max(0, Math.min(1, mx / width))
                root.moved(root.from + t * (root.to - root.from))
            }
            onClicked: (m) => pick(m.x)
            onPositionChanged: (m) => { if (pressed) pick(m.x) }
        }
    }
}
