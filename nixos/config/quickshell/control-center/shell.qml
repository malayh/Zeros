import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    id: root

    property var monitors: []
    property bool loading: false
    property string discoveryError: ""

    function focusedScreen() {
        const focused = Hyprland.focusedMonitor;
        if (focused) {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === focused.name)
                    return Quickshell.screens[i];
            }
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    function refresh() {
        loading = true;
        discoveryError = "";
        discovery.exec(["custom-brightness", "list"]);
    }

    function showPanel() {
        const targetScreen = focusedScreen();
        if (targetScreen)
            panel.screen = targetScreen;
        panel.visible = true;
        refresh();
    }

    function hidePanel() {
        focusGrab.active = false;
        panel.visible = false;
    }

    function togglePanel() {
        if (panel.visible)
            hidePanel();
        else
            showPanel();
    }

    IpcHandler {
        target: "controlCenter"

        function toggle(): void { root.togglePanel(); }
        function show(): void { root.showPanel(); }
        function hide(): void { root.hidePanel(); }
    }

    Process {
        id: discovery
        stdout: StdioCollector { id: discoveryOutput }
        stderr: StdioCollector { id: discoveryErrors }

        onExited: (exitCode, exitStatus) => {
            root.loading = false;
            if (exitCode !== 0) {
                root.monitors = [];
                root.discoveryError = discoveryErrors.text.trim() || "Could not discover displays";
                return;
            }

            try {
                const parsed = JSON.parse(discoveryOutput.text);
                if (!Array.isArray(parsed))
                    throw new Error("invalid monitor list");
                root.monitors = parsed;
            } catch (error) {
                root.monitors = [];
                root.discoveryError = "Could not read display information";
            }
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [panel]
        onCleared: root.hidePanel()
    }

    FloatingWindow {
        id: panel
        visible: false
        title: "Zeros Control Center"
        color: "transparent"
        implicitWidth: 420
        implicitHeight: Math.max(180, Math.min(132 + root.monitors.length * 78,
            panel.screen ? panel.screen.height * 0.7 : 620))
        minimumSize: Qt.size(420, 180)
        maximumSize: Qt.size(420, panel.screen ? panel.screen.height * 0.7 : 620)
        onBackingWindowVisibleChanged: {
            if (backingWindowVisible && visible) {
                Hyprland.dispatch("focuswindow title:^(Zeros Control Center)$");
                Qt.callLater(() => { if (panel.visible) focusGrab.active = true; });
            }
        }

        Shortcut {
            sequence: "Escape"
            onActivated: root.hidePanel()
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "#181825"
            border.width: 1
            border.color: "#45475a"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "󰃠"
                        color: "#89b4fa"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 20
                    }

                    Text {
                        text: "Display brightness"
                        color: "#cdd6f4"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    BusyIndicator {
                        visible: root.loading
                        running: visible
                        implicitWidth: 22
                        implicitHeight: 22
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.discoveryError !== ""
                    text: root.discoveryError
                    color: "#f38ba8"
                    wrapMode: Text.Wrap
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                }

                Text {
                    Layout.fillWidth: true
                    visible: !root.loading && root.discoveryError === "" && root.monitors.length === 0
                    text: "No connected displays found"
                    color: "#a6adc8"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                }

                ListView {
                    id: monitorList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.monitors.length > 0
                    clip: true
                    spacing: 10
                    model: root.monitors

                    delegate: Rectangle {
                        id: monitorRow
                        required property var modelData
                        width: monitorList.width
                        height: modelData.available ? 68 : 58
                        radius: 8
                        color: "#1e1e2e"

                        property int confirmedRaw: modelData.current === null ? 0 : modelData.current
                        property int queuedRaw: -1
                        property string writeError: ""

                        function rawFromPercent(value) {
                            return Math.round(value * modelData.maximum / 100);
                        }

                        function queueWrite(value) {
                            if (!modelData.available)
                                return;
                            queuedRaw = rawFromPercent(value);
                            writeDebounce.restart();
                        }

                        function startWrite() {
                            if (queuedRaw < 0 || writer.running)
                                return;
                            writer.attemptedRaw = queuedRaw;
                            queuedRaw = -1;
                            writeError = "";
                            writer.exec([
                                "custom-brightness", "set", modelData.backend, modelData.target,
                                writer.attemptedRaw.toString(), modelData.maximum.toString()
                            ]);
                        }

                        Timer {
                            id: writeDebounce
                            interval: 150
                            repeat: false
                            onTriggered: monitorRow.startWrite()
                        }

                        Process {
                            id: writer
                            property int attemptedRaw: 0
                            stderr: StdioCollector { id: writerErrors }

                            onExited: (exitCode, exitStatus) => {
                                if (exitCode === 0) {
                                    monitorRow.confirmedRaw = attemptedRaw;
                                } else {
                                    monitorRow.writeError = writerErrors.text.trim() || "Could not set brightness";
                                    brightnessSlider.value = Math.round(confirmedRaw * 100 / modelData.maximum);
                                    monitorRow.queuedRaw = -1;
                                }
                                if (monitorRow.queuedRaw >= 0 && !writeDebounce.running)
                                    monitorRow.startWrite();
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: modelData.available ? "#cdd6f4" : "#6c7086"
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }

                                Text {
                                    text: modelData.available ? Math.round(brightnessSlider.value) + "%" : "Unavailable"
                                    color: modelData.available ? "#a6e3a1" : "#f9e2af"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                            }

                            Slider {
                                id: brightnessSlider
                                Layout.fillWidth: true
                                visible: modelData.available
                                from: 0
                                to: 100
                                stepSize: 1
                                value: modelData.percent === null ? 0 : modelData.percent
                                onMoved: monitorRow.queueWrite(value)

                                background: Rectangle {
                                    x: brightnessSlider.leftPadding
                                    y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                    width: brightnessSlider.availableWidth
                                    height: 4
                                    radius: 2
                                    color: "#45475a"

                                    Rectangle {
                                        width: brightnessSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color: "#89b4fa"
                                    }
                                }

                                handle: Rectangle {
                                    x: brightnessSlider.leftPadding + brightnessSlider.visualPosition
                                        * (brightnessSlider.availableWidth - width)
                                    y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    radius: 8
                                    color: brightnessSlider.pressed ? "#b4befe" : "#89b4fa"
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: monitorRow.writeError !== "" || !modelData.available
                                text: monitorRow.writeError !== "" ? monitorRow.writeError : modelData.error
                                color: monitorRow.writeError !== "" ? "#f38ba8" : "#6c7086"
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }
}
