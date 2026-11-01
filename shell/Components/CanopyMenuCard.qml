import QtQuick
import ".."

// CanopyMenuCard - the shared context-menu surface.
// Rendering only; placement and activation live in MenuController.
Item {
    id: root

    property var items: []
    property int hoverIndex: -1
    property int cardWidth: 244

    implicitWidth: cardWidth
    implicitHeight: col.implicitHeight + 12

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Theme.radiusMedium + 4
        color: Theme.shadow
        opacity: Theme.shadowOpacity * 0.35
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: Theme.darkMode ? "#FA1A1A21" : "#FCFFFFFF"
        border.color: Theme.darkMode ? "#2EFFFFFF" : "#1A000000"
        border.width: 1
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6

        Repeater {
            model: root.items

            delegate: MenuItemRow {
                id: rowDelegate
                width: col.width
                item: modelData
                hovered: root.hoverIndex === index

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) root.hoverIndex = index
                        else if (root.hoverIndex === index) root.hoverIndex = -1
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: (modelData && modelData.sep === true) || (modelData && modelData.enabled === false)
                                 ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: MenuController.activate(index)
                }
            }
        }
    }
}
