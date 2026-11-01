import QtQuick
import QtQuick.Dialogs
import "../Components"
import "../../"

Column {
    id: page
    property var store
    property var shell
    width: parent ? parent.width : 0
    spacing: Theme.spacingLg

    SectionCard {
        width: parent.width
        title: "Theme"
        description: "Choose how Canopy looks. Automatic switches with daylight hours."

        SettingRow {
            label: "Appearance"
            hint: "Light, dark, or follow the time of day"
            ChoiceRow {
                options: ["Light", "Dark", "Auto"]
                current: store.themeMode === "light" ? 0 : (store.themeMode === "dark" ? 1 : 2)
                onActivated: (i) => shell.setThemeMode(["light", "dark", "auto"][i])
            }
        }

        SettingRow {
            label: "Accent colour"
            hint: "Used for highlights, toggles and focus rings"
            ColorRow {
                current: Theme.accent
                onPicked: (c) => shell.setAccent(c)
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Wallpaper"
        description: shell.includePictures
                     ? "Images from ~/Pictures, ~/.local/share/wallpapers and /usr/share/backgrounds."
                     : "Images from ~/.local/share/wallpapers and /usr/share/backgrounds."

        SettingRow {
            label: "Include my Pictures folder"
            hint: "Off by default - Canopy only reads wallpaper folders. Turning this on adds ~/Pictures to the picker above."
            ToggleSwitch {
                value: shell.includePictures
                onToggled: (v) => { shell.includePictures = v }
            }
        }

        SettingRow {
            label: "Scaling"
            hint: "How the image fills the screen"
            ChoiceRow {
                options: ["Crop", "Fit", "Stretch", "Tile", "Centre"]
                current: Math.max(0, ["crop","fit","stretch","tile","center"].indexOf(store.wallpaperMode))
                onActivated: (i) => shell.setWallpaperMode(["crop","fit","stretch","tile","center"][i])
            }
        }

        GridView {
            width: parent.width
            height: 168
            cellWidth: Math.floor(width / 4)
            cellHeight: 84
            clip: true
            model: shell.wallpaperList
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                width: GridView.view.cellWidth
                height: 84
                radius: 8
                color: String(shell.wallpaper) === String(model.path) ? Theme.accent
                     : (wm.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000") : "transparent")
                border.color: Theme.darkMode ? "#22FFFFFF" : "#12000000"
                border.width: 1

                Image {
                    anchors.fill: parent
                    anchors.margins: 4
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectCrop
                    source: "file://" + model.path
                    // decode at thumbnail size instead of full resolution
                    sourceSize.width: 200
                    sourceSize.height: 120
                }

                MouseArea {
                    id: wm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shell.setWallpaper(model.path)
                }
            }
        }

        Row {
            spacing: 10

            Rectangle {
                width: 150; height: 30; radius: 9
                color: pickMa.containsMouse ? Theme.accent : (Theme.darkMode ? "#1FFFFFFF" : "#0D000000")
                Text {
                    anchors.centerIn: parent
                    text: "Choose file\u2026"
                    color: pickMa.containsMouse ? "white" : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: pickMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wallpaperDialog.open()
                }
            }

            Rectangle {
                width: 150; height: 30; radius: 9
                color: clrMa.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000") : "transparent"
                border.color: Theme.darkMode ? "#33FFFFFF" : "#1A000000"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "Clear wallpaper"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: clrMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shell.clearWallpaper()
                }
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Effects"
        description: "Transparency and motion. Turning motion off disables every transition."

        SettingRow {
            label: "Transparency"
            hint: "Opacity of the panel, tray and dock surfaces"
            SliderRow {
                from: 0.5; to: 1.0
                value: Theme.acrylicOpacity
                onMoved: (v) => shell.setTransparency(v)
            }
        }

        SettingRow {
            label: "Interface animations"
            hint: "Smooth transitions and hover effects"
            ToggleSwitch {
                value: Theme.animationsEnabled
                onToggled: (v) => shell.setAnimations(v)
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Scale"
        description: "Text size and spacing density."

        SettingRow {
            label: "Interface scale"
            hint: "Scales all Canopy text"
            SliderRow {
                from: 0.85; to: 1.3
                value: Theme.uiScale
                onMoved: (v) => shell.setUiScale(v)
            }
        }

        SettingRow {
            label: "Density"
            hint: "Spacing between elements"
            ChoiceRow {
                options: ["Compact", "Normal", "Comfortable"]
                current: Theme.density < 0.95 ? 0 : (Theme.density > 1.05 ? 2 : 1)
                onActivated: (i) => shell.setDensity([0.85, 1.0, 1.2][i])
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Reset"
        Rectangle {
            width: 170; height: 34; radius: 9
            color: resetMa.containsMouse ? Theme.danger : (Theme.darkMode ? "#1FFFFFFF" : "#0D000000")
            border.color: Theme.danger
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "Restore defaults"
                color: resetMa.containsMouse ? "white" : Theme.danger
                font.pixelSize: Theme.fontSizeSm
                font.family: Theme.fontFamily
            }
            MouseArea {
                id: resetMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shell.resetAppearance()
            }
        }
    }

    FileDialog {
        id: wallpaperDialog
        title: "Choose a wallpaper"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.svg)", "All files (*)"]
        onAccepted: {
            let f = String(selectedFile)
            if (f.indexOf("file://") === 0) f = f.substring(7)
            shell.setWallpaper(decodeURIComponent(f))
        }
    }
}
