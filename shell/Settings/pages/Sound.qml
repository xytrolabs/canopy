import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../Components"
import "../../"

Column {
    id: page
    property var store
    property var shell
    width: parent ? parent.width : 0
    spacing: Theme.spacingLg

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool available: sink !== null && sink.audio !== undefined
    readonly property bool micAvailable: source !== null && source.audio !== undefined

    function label(node) {
        if (!node) return "Unknown device"
        return node.description && node.description !== ""
               ? node.description : (node.nickname || node.name || "Audio device")
    }

    function sinks() {
        const all = Pipewire.nodes ? (Pipewire.nodes.values || []) : []
        return all.filter(function (n) { return n && n.isSink === true && n.audio })
    }

    function sources() {
        const all = Pipewire.nodes ? (Pipewire.nodes.values || []) : []
        return all.filter(function (n) {
            return n && n.isSink === false && n.isStream === false && n.audio
        })
    }

    SectionCard {
        width: parent.width
        title: "Output"
        description: available ? "Controlled through PipeWire."
                              : "No PipeWire output device was reported."

        SettingRow {
            label: "Volume"
            hint: "Master output volume"
            SliderRow {
                from: 0; to: 1
                value: available ? sink.audio.volume : 0
                onMoved: (v) => { if (available) sink.audio.volume = v }
            }
        }

        SettingRow {
            label: "Mute"
            hint: available && sink.audio.muted ? "Output is muted" : "Output is audible"
            ToggleSwitch {
                value: available ? sink.audio.muted : false
                onToggled: (v) => { if (available) sink.audio.muted = v }
            }
        }
    }

    // ---- choose the active output device ----
    SectionCard {
        width: parent.width
        title: "Output device"
        description: "Pick which speakers or headphones PipeWire sends audio to."

        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: page.sinks()

                delegate: Rectangle {
                    width: parent.width
                    height: 40
                    radius: 9
                    color: (devMa.containsMouse || Pipewire.defaultAudioSink === modelData)
                           ? Theme.hoverBg : "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        CanopyIcon {
                            size: 16
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "audio-speakers-symbolic"
                            tint: Pipewire.defaultAudioSink === modelData ? Theme.accent : Theme.textPrimary
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 74
                            spacing: 1

                            Text {
                                width: parent.width
                                text: page.label(modelData)
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: Pipewire.defaultAudioSink === modelData ? "Default output"
                                                                            : (modelData.name || "")
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                            }
                        }

                        CanopyIcon {
                            visible: Pipewire.defaultAudioSink === modelData
                            size: 14
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "emblem-ok-symbolic"
                            tint: Theme.accent
                        }
                    }

                    MouseArea {
                        id: devMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            try { Pipewire.preferredDefaultAudioSink = modelData } catch (e) { }
                        }
                    }
                }
            }

            Text {
                visible: page.sinks().length === 0
                text: "No audio outputs detected"
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
                font.family: Theme.fontFamily
            }
        }
    }

    // ---- microphone ----
    SectionCard {
        width: parent.width
        title: "Input"
        description: micAvailable ? "Microphone level."
                                  : "No microphone was reported."

        SettingRow {
            label: "Volume"
            hint: "Microphone input volume"
            SliderRow {
                from: 0; to: 1
                value: page.micAvailable ? page.source.audio.volume : 0
                onMoved: (v) => { if (page.micAvailable) page.source.audio.volume = v }
            }
        }

        SettingRow {
            label: "Mute"
            hint: page.micAvailable && page.source.audio.muted ? "Microphone is muted"
                                                              : "Microphone is live"
            ToggleSwitch {
                value: page.micAvailable ? page.source.audio.muted : false
                onToggled: (v) => { if (page.micAvailable) page.source.audio.muted = v }
            }
        }
    }
}
