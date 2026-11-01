import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import ".."

// Canopy Settings - Windows-like navigation, macOS-like depth.
PanelWindow {
    id: win
    property var store
    property var shell
    signal closeRequested()

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    // ---- navigation model (also drives search) ----
    readonly property var pages: [
        { name: "Appearance",    source: "pages/Appearance.qml",    keys: "theme dark light auto accent colour color transparency animations scale density" },
        { name: "Desktop",       source: "pages/Desktop.qml",       keys: "panel tray dock pinned auto-hide icon size magnification" },
        { name: "Applications",  source: "pages/Applications.qml",  keys: "apps launcher pinned install list" },
        { name: "Notifications", source: "pages/Notifications.qml", keys: "notifications dnd history toast" },
        { name: "Network",       source: "pages/Network.qml",       keys: "wifi wi-fi network wireless connect" },
        { name: "Sound",         source: "pages/Sound.qml",         keys: "volume audio sound mute pipewire output" },
        { name: "Power",         source: "pages/Power.qml",         keys: "battery power profile charge" },
        { name: "System",        source: "pages/System.qml",        keys: "about version reset restart session diagnostics license" }
    ]

    property int currentPage: shell ? shell.settingsPage : 0
    onCurrentPageChanged: if (shell) shell.settingsPage = currentPage
    property string query: ""

    readonly property var results: {
        const q = query.toLowerCase().trim()
        if (q === "") return pages.map(function (p, i) { return { idx: i, name: p.name } })
        const out = []
        for (let i = 0; i < pages.length; i++) {
            const p = pages[i]
            if (p.name.toLowerCase().indexOf(q) >= 0 || p.keys.indexOf(q) >= 0)
                out.push({ idx: i, name: p.name })
        }
        return out
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.darkMode ? "#B3000000" : "#66000000"
        MouseArea { anchors.fill: parent; onClicked: win.closeRequested() }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 900)
            height: Math.min(parent.height - 100, 620)
            radius: 18
            color: Theme.darkMode ? "#F2181820" : "#FAFFFFFF"
            border.color: Theme.darkMode ? "#33FFFFFF" : "#1A000000"
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                // ---------------- sidebar ----------------
                Column {
                    id: sidebar
                    width: 200
                    height: parent.height
                    spacing: 10

                    Text {
                        text: "Settings"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeXl
                        font.weight: Font.Bold
                        font.family: Theme.fontFamily
                    }

                    Rectangle {
                        width: parent.width
                        height: 32
                        radius: 16
                        color: Theme.darkMode ? "#1FFFFFFF" : "#0D000000"

                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: 30
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeXs
                            font.family: Theme.fontFamily
                            selectionColor: Theme.accent
                            onTextChanged: win.query = text
                            Keys.onPressed: (e) => {
                                if (e.key === Qt.Key_Escape) { win.closeRequested(); e.accepted = true }
                            }
                        }
                        CanopyIcon {
                            size: 14
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "edit-find-symbolic"
                            tint: Theme.textMuted
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 30
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search"
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeXs
                            font.family: Theme.fontFamily
                            visible: search.text === ""
                        }
                    }

                    Text {
                        visible: win.results.length === 0
                        text: "No matching settings"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                        font.family: Theme.fontFamily
                    }

                    ListView {
                        width: parent.width
                        height: parent.height - 118
                        clip: true
                        model: win.results
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: ListView.view ? ListView.view.width : 180
                            height: 34
                            radius: 9
                            color: win.currentPage === modelData.idx
                                   ? Theme.accent
                                   : (navMa.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000") : "transparent")
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: win.currentPage === modelData.idx ? "white" : Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                            }
                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { win.currentPage = modelData.idx; win.query = ""; search.text = "" }
                            }
                        }
                    }

                    Item { width: 1; height: 1 }
                }

                Rectangle { width: 1; height: parent.height; color: Theme.border }

                // ---------------- content ----------------
                Column {
                    id: contentCol
                    width: parent.width - 220
                    height: parent.height
                    spacing: 4

                    Text {
                        id: titleRow
                        text: win.pages[win.currentPage].name
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeXl
                        font.weight: Font.Bold
                        font.family: Theme.fontFamily
                    }
                    Text {
                        id: subtitle
                        text: "Canopy settings · changes apply immediately"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                        font.family: Theme.fontFamily
                        bottomPadding: 6
                    }

                    // The scroller takes exactly the space the header leaves over.
                    // It used to be sized from win.height (the whole screen), so
                    // pages spilled out of the card on anything but 720p.
                    Flickable {
                        id: pageFlick
                        width: parent.width
                        height: Math.max(120, contentCol.height - titleRow.height - subtitle.height - 14)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        Loader {
                            id: pageLoader
                            width: pageFlick.width
                            source: win.pages[win.currentPage].source
                            onLoaded: {
                                item.store = win.store
                                item.shell = win.shell
                            }
                        }
                    }
                }
            }
        }
    }

}
