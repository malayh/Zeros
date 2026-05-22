import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Rectangle {
    id: root
    color: "black"
    width: 1920
    height: 1080

    property string targetUser: {
        if (userModel.lastUser && userModel.lastUser.length > 0)
            return userModel.lastUser;
        if (userModel.count > 0)
            return userModel.data(userModel.index(0, 0), Qt.UserRole + 1);
        return "";
    }
    property int failCount: 0

    Image {
        id: background
        anchors.fill: parent
        source: "backgrounds/current.png"
        fillMode: Image.PreserveAspectCrop
        cache: true
        mipmap: true
        asynchronous: true
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: background
        source: background
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        brightness: -0.18
        contrast: 0.89
        saturation: 0.17
        autoPaddingEnabled: false
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.15
    }

    Text {
        id: hourLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -300
        horizontalAlignment: Text.AlignHCenter
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 180
        font.weight: Font.Black
        color: Qt.rgba(255 / 255, 185 / 255, 0 / 255, 0.6)
        text: Qt.formatDateTime(new Date(), "HH")
    }

    Text {
        id: minuteLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -75
        horizontalAlignment: Text.AlignHCenter
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 180
        font.weight: Font.Black
        color: Qt.rgba(1, 1, 1, 0.6)
        text: Qt.formatDateTime(new Date(), "mm")
    }

    Text {
        id: dateLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 80
        horizontalAlignment: Text.AlignHCenter
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 26
        color: Qt.rgba(1, 1, 1, 0.85)
        text: Qt.formatDateTime(new Date(), "dddd, dd MMMM")
    }

    Timer {
        id: clockTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const now = new Date();
            hourLabel.text = Qt.formatDateTime(now, "HH");
            minuteLabel.text = Qt.formatDateTime(now, "mm");
            dateLabel.text = Qt.formatDateTime(now, "dddd, dd MMMM");
        }
    }

    Text {
        id: userGlyph
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 200
        horizontalAlignment: Text.AlignHCenter
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 90
        color: Qt.rgba(1, 1, 1, 0.65)
        text: ""
    }

    Rectangle {
        id: passwordBox
        width: 250
        height: 60
        radius: 8
        color: Qt.rgba(100 / 255, 114 / 255, 125 / 255, 0.5)
        border.width: 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 310

        TextField {
            id: passwordInput
            anchors.fill: parent
            anchors.margins: 4
            focus: true
            enabled: !authenticating
            echoMode: TextInput.Password
            passwordCharacter: "\u25CF"
            color: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 1)
            placeholderText: root.targetUser.length > 0 ? "Hi, " + root.targetUser : "Password"
            placeholderTextColor: Qt.rgba(1, 1, 1, 0.55)
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            background: Item {}
            onAccepted: root.attemptLogin()
        }
    }

    Text {
        id: failLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: passwordBox.bottom
        anchors.topMargin: 12
        horizontalAlignment: Text.AlignHCenter
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14
        font.italic: true
        color: Qt.rgba(1, 0.45, 0.45, 0.95)
        visible: root.failCount > 0
        text: visible ? "Login failed (" + root.failCount + ")" : ""
    }

    property bool authenticating: false

    function attemptLogin() {
        if (root.targetUser.length === 0)
            return;
        if (passwordInput.text.length === 0)
            return;
        authenticating = true;
        sddm.login(root.targetUser, passwordInput.text, 0);
    }

    Connections {
        target: sddm
        function onLoginSucceeded() {
            authenticating = false;
        }
        function onLoginFailed() {
            authenticating = false;
            root.failCount += 1;
            passwordInput.text = "";
            passwordInput.forceActiveFocus();
        }
    }

    Component.onCompleted: passwordInput.forceActiveFocus()
}
