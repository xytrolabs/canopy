import QtQuick
import "../../"

// One settings line: label (+ optional hint) on the left, control on the right.
//
// IMPORTANT: the row height is a CONSTANT. Children are vertically centred
// against it, so nothing feeds position -> height -> position in a loop.
// (The previous version derived height from children that were anchored to
// parent.verticalCenter, which is a binding cycle and collapsed the row to 0.)
Item {
    id: root
    property string label: ""
    property string hint: ""
    default property alias control: holder.data

    width: parent ? parent.width : 0
    implicitHeight: 52
    height: implicitHeight

    Row {
        id: holder
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
    }

    Column {
        id: texts
        anchors.left: parent.left
        anchors.right: holder.left
        anchors.rightMargin: Theme.spacingMd
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: root.label
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeSm
            font.family: Theme.fontFamily
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.hint !== ""
            text: root.hint
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeXs
            font.family: Theme.fontFamily
            elide: Text.ElideRight
        }
    }
}
