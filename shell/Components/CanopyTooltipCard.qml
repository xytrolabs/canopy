import QtQuick
import ".."

// CanopyTooltipCard - the visual tooltip. One shared design for the entire
// shell: rounded acrylic card, hairline border, title + optional detail.
Item {
    id: root

    property string title: ""
    property string detail: ""
    property int maxTextWidth: 220

    implicitWidth: Math.min(maxTextWidth, Math.max(t1.implicitWidth, t2.implicitWidth)) + 22
    implicitHeight: col.implicitHeight + 14

    // soft depth without blur: two barely-visible rings stand in for a shadow
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: Theme.radiusSmall + 3
        color: Theme.shadow
        opacity: Theme.shadowOpacity * 0.28
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Theme.darkMode ? "#F22A2A33" : "#FAFFFFFF"
        border.color: Theme.darkMode ? "#33FFFFFF" : "#1A000000"
        border.width: 1
    }

    Column {
        id: col
        anchors.centerIn: parent
        spacing: 1

        Text {
            id: t1
            text: root.title
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeXs + 1
            font.weight: Font.Medium
            font.family: Theme.fontDisplay
            font.letterSpacing: Theme.tracking
            elide: Text.ElideRight
            width: Math.min(root.maxTextWidth, implicitWidth)
        }

        Text {
            id: t2
            visible: root.detail !== ""
            text: root.detail
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeXs - 1
            font.family: Theme.fontFamily
            elide: Text.ElideRight
            width: Math.min(root.maxTextWidth, implicitWidth)
        }
    }
}
