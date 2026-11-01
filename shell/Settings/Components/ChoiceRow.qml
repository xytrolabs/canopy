import QtQuick
import "../../"

// Segmented choice control (Light / Dark / Auto style).
Item {
    id: root
    property var options: []
    property int current: 0
    signal activated(int index)

    implicitWidth: seg.implicitWidth + 8
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: Theme.darkMode ? "#14FFFFFF" : "#0A000000"
        border.color: Theme.darkMode ? "#26FFFFFF" : "#12000000"
        border.width: 1

        Row {
            id: seg
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: root.options
                delegate: Rectangle {
                    width: Math.max(58, label.implicitWidth + 20)
                    height: 24
                    radius: 7
                    color: root.current === index ? Theme.accent
                                                  : (ma.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0F000000") : "transparent")
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: modelData
                        color: root.current === index ? "white" : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeXs
                        font.family: Theme.fontFamily
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.current = index; root.activated(index) }
                    }
                }
            }
        }
    }
}
