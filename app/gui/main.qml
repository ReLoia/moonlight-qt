import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2
import QtQuick.Controls.Material 2.2

import ComputerManager 1.0
import AutoUpdateChecker 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

ApplicationWindow {
    property bool pollingActive: false
    property bool chromeVisible: true

    // Set by SettingsView to force the back operation to pop all
    // pages except the initial view. This is required when doing
    // a retranslate() because AppView breaks for some reason.
    property bool clearOnBack: false

    id: window
    width: 1280
    height: 600

    // This function runs prior to creation of the initial StackView item
    function doEarlyInit() {
        // Override the background color to Material 2 colors for Qt 6.5+
        // in order to improve contrast between GFE's placeholder box art
        // and the background of the app grid.
        if (SystemProperties.usesMaterial3Theme) {
            Material.background = "#303030"
        }

        SdlGamepadKeyNavigation.enable()
    }

    Component.onCompleted: {
        // Show the window according to the user's preferences
        if (SystemProperties.hasDesktopEnvironment) {
            if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_MAXIMIZED) {
                window.showMaximized()
            }
            else if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_FULLSCREEN) {
                window.showFullScreen()
            }
            else {
                window.show()
            }
        } else {
            window.showFullScreen()
        }

        // Display any modal dialogs for configuration warnings
        if (runConfigChecks) {
            if (SystemProperties.isWow64) {
                wow64Dialog.open()
            }

            // Hardware acceleration and unmapped gamepads are checked asynchronously
            SystemProperties.hasHardwareAccelerationChanged.connect(hasHardwareAccelerationChanged)
            SystemProperties.unmappedGamepadsChanged.connect(hasUnmappedGamepadsChanged)
            SystemProperties.startAsyncLoad()
        }
    }

    function hasHardwareAccelerationChanged() {
        if (!SystemProperties.hasHardwareAcceleration && StreamingPreferences.videoDecoderSelection !== StreamingPreferences.VDS_FORCE_SOFTWARE) {
            if (SystemProperties.isRunningXWayland) {
                xWaylandDialog.open()
            }
            else {
                noHwDecoderDialog.open()
            }
        }
    }

    function hasUnmappedGamepadsChanged() {
        if (SystemProperties.unmappedGamepads) {
            unmappedGamepadDialog.unmappedGamepads = SystemProperties.unmappedGamepads
            unmappedGamepadDialog.open()
        }
    }

    // It would be better to use TextMetrics here, but it always lays out
    // the text slightly more compactly than real Text does in ToolTip,
    // causing unexpected line breaks to be inserted
    Text {
        id: tooltipTextLayoutHelper
        visible: false
        font: ToolTip.toolTip.font
        text: ToolTip.toolTip.text
    }

    // This configures the maximum width of the singleton attached QML ToolTip. If left unconstrained,
    // it will never insert a line break and just extend on forever.
    ToolTip.toolTip.contentWidth: Math.min(tooltipTextLayoutHelper.width, 400)

    function goBack() {
        if (clearOnBack) {
            // Pop all items except the first one
            stackView.pop(null)
            clearOnBack = false
        }
        else {
            stackView.pop()
        }
    }

    function openSettingsView()
    {
        var existingItem = stackView.find(function(item, index) {
            return item.objectName === qsTr("Settings")
        })

        if (existingItem !== null) {
            stackView.pop(existingItem)
        }
        else {
            stackView.push("qrc:/gui/SettingsView.qml")
        }
    }

    Shortcut {
        sequence: StandardKey.Preferences
        onActivated: openSettingsView()
    }

    StackView {
        id: stackView
        anchors.fill: parent
        focus: true

        Component.onCompleted: {
            // Perform our early initialization before constructing
            // the initial view and pushing it to the StackView
            doEarlyInit()
            push(initialView)
        }

        onCurrentItemChanged: {
            // Ensure focus travels to the next view when going back.
            // Views with a carousel expose it as focusTarget so that
            // keyboard/controller navigation works immediately, which
            // is critical on controller-only systems.
            if (currentItem) {
                if (currentItem.focusTarget) {
                    currentItem.focusTarget.forceActiveFocus()
                }
                else {
                    currentItem.forceActiveFocus()
                }
            }
        }

        Keys.onEscapePressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onBackPressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onMenuPressed: {
            openSettingsView()
        }

        // This is a keypress we've reserved for letting the
        // SdlGamepadKeyNavigation object tell us to show settings
        // when Menu is consumed by a focused control.
        Keys.onHangupPressed: {
            openSettingsView()
        }
    }

    // Floating navigation chrome (no top bar): back button when drilled in,
    // plus update/help/discord affordances without a full toolbar.
    ToolButton {
        id: backButton
        visible: chromeVisible && stackView.depth > 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 12
        anchors.leftMargin: 12
        width: 48
        height: 48
        z: 100
        focusPolicy: Qt.TabFocus
        hoverEnabled: true

        icon.source: "qrc:/res/arrow_left.svg"
        icon.width: 32
        icon.height: 32

        background: Rectangle {
            implicitWidth: 48
            implicitHeight: 48
            radius: 24
            color: backButton.hovered || backButton.activeFocus ? "#4a4a4a" : "#333333"
            opacity: 0.85
            border.color: backButton.activeFocus ? "#7fb8ff" : "transparent"
            border.width: 2
        }

        ToolTip.delay: 1000
        ToolTip.timeout: 3000
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Back")

        onClicked: goBack()

        function focusCurrentView(reason) {
            var item = stackView.currentItem
            if (item && item.focusTarget) {
                item.focusTarget.forceActiveFocus(reason)
            }
            else if (item && reason !== Qt.TabFocusReason && reason !== Qt.BacktabFocusReason) {
                item.forceActiveFocus(reason)
            }
        }

        Keys.onDownPressed: {
            focusCurrentView(Qt.TabFocusReason)
        }
        Keys.onTabPressed: {
            focusCurrentView(Qt.TabFocusReason)
        }
        Keys.onBacktabPressed: {
            focusCurrentView(Qt.BacktabFocusReason)
        }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
    }

    Row {
        id: floatingTopRight
        visible: chromeVisible

        ToolButton {
            id: settingsFloatingButton
            visible: stackView.depth > 1 &&
                     stackView.currentItem && stackView.currentItem.objectName !== qsTr("Settings")
            width: 48
            height: 48
            hoverEnabled: true

            icon.source: "qrc:/res/settings.svg"
            icon.width: 30
            icon.height: 30

            background: Rectangle {
                implicitWidth: 48
                implicitHeight: 48
                radius: 24
                color: settingsFloatingButton.hovered || settingsFloatingButton.activeFocus ? "#4a4a4a" : "#333333"
                opacity: 0.85
                border.color: settingsFloatingButton.activeFocus ? "#7fb8ff" : "transparent"
                border.width: 2
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 3000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Settings")

            onClicked: openSettingsView()

            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
        }
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.rightMargin: 12
        spacing: 8
        z: 100

        Label {
            id: versionLabel
            visible: stackView.currentItem && stackView.currentItem.objectName === qsTr("Settings")
            text: qsTr("Version %1").arg(SystemProperties.versionString)
            font.pointSize: 12
            horizontalAlignment: Qt.AlignRight
            verticalAlignment: Qt.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        ToolButton {
            id: updateButton
            property string browserUrl: ""

            width: 48
            height: 48
            hoverEnabled: true

            icon.source: "qrc:/res/update.svg"
            icon.width: 32
            icon.height: 32

            background: Rectangle {
                implicitWidth: 48
                implicitHeight: 48
                radius: 24
                color: updateButton.hovered || updateButton.activeFocus ? "#4a4a4a" : "#333333"
                opacity: 0.85
                border.color: updateButton.activeFocus ? "#7fb8ff" : "transparent"
                border.width: 2
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 3000
            ToolTip.visible: hovered

            // Invisible until we get a callback notifying us that
            // an update is available
            visible: false

            onClicked: {
                if (SystemProperties.hasBrowser) {
                    Qt.openUrlExternally(browserUrl);
                }
            }

            function updateAvailable(version, url)
            {
                ToolTip.text = qsTr("Update available for Moonlight: Version %1").arg(version)
                updateButton.browserUrl = url
                updateButton.visible = true
            }

            Component.onCompleted: {
                AutoUpdateChecker.onUpdateAvailable.connect(updateAvailable)
                AutoUpdateChecker.start()
            }
        }

        ToolButton {
            id: discordButton
            visible: SystemProperties.hasBrowser &&
                     stackView.currentItem && stackView.currentItem.objectName === qsTr("Settings")
            width: 48
            height: 48
            hoverEnabled: true

            icon.source: "qrc:/res/discord.svg"
            icon.width: 32
            icon.height: 32

            background: Rectangle {
                implicitWidth: 48
                implicitHeight: 48
                radius: 24
                color: discordButton.hovered || discordButton.activeFocus ? "#4a4a4a" : "#333333"
                opacity: 0.85
                border.color: discordButton.activeFocus ? "#7fb8ff" : "transparent"
                border.width: 2
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 3000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Join our community on Discord")

            onClicked: Qt.openUrlExternally("https://moonlight-stream.org/discord");
        }

    }

    // This timer keeps us polling for 5 minutes of inactivity
    // to allow the user to work with Moonlight on a second display
    // while dealing with configuration issues. This will ensure
    // machines come online even if the input focus isn't on Moonlight.
    Timer {
        id: inactivityTimer
        interval: 5 * 60000
        onTriggered: {
            if (!active && pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
    }

    onVisibleChanged: {
        // When we become invisible while streaming is going on,
        // stop polling immediately.
        if (!visible) {
            inactivityTimer.stop()

            if (pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
        else if (active) {
            // When we become visible and active again, start polling
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onActiveChanged: {
        if (active) {
            // Stop the inactivity timer
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }
        else {
            // Start the inactivity timer to stop polling
            // if focus does not return within a few minutes.
            inactivityTimer.restart()
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    function navigateTo(url, objectType)
    {
        var existingItem = stackView.find(function(item, index) {
            return item instanceof objectType
        })

        if (existingItem !== null) {
            // Pop to the existing item
            stackView.pop(existingItem)
        }
        else {
            // Create a new item
            stackView.push(url)
        }
    }

    // Top bar removed: home view is a fullscreen login-manager style
    // carousel with its own settings gear. Floating buttons above
    // provide back/update/help navigation without a toolbar.

    ErrorMessageDialog {
        id: noHwDecoderDialog
        text: qsTr("No functioning hardware accelerated video decoder was detected by Moonlight. " +
                   "Your streaming performance may be severely degraded in this configuration.")
        helpText: qsTr("Click the Help button for more information on solving this problem.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    ErrorMessageDialog {
        id: xWaylandDialog
        text: qsTr("Hardware acceleration doesn't work on XWayland. Continuing on XWayland may result in poor streaming performance. " +
                   "Try running with QT_QPA_PLATFORM=wayland or switch to X11.")
        helpText: qsTr("Click the Help button for more information.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    NavigableMessageDialog {
        id: wow64Dialog
        standardButtons: Dialog.Ok | Dialog.Cancel
        text: qsTr("This version of Moonlight isn't optimized for your PC. Please download the '%1' version of Moonlight for the best streaming performance.").arg(SystemProperties.friendlyNativeArchName)
        onAccepted: {
            Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-qt/releases");
        }
    }

    ErrorMessageDialog {
        id: unmappedGamepadDialog
        property string unmappedGamepads : ""
        text: qsTr("Moonlight detected gamepads without a mapping:") + "\n" + unmappedGamepads
        helpTextSeparator: "\n\n"
        helpText: qsTr("Click the Help button for information on how to map your gamepads.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Gamepad-Mapping"
    }

    // This dialog appears when quitting via keyboard or gamepad button
    NavigableMessageDialog {
        id: quitConfirmationDialog
        standardButtons: Dialog.Yes | Dialog.No
        text: qsTr("Are you sure you want to quit?")
        // For keyboard/gamepad navigation
        onAccepted: Qt.quit()
    }

    // HACK: This belongs in StreamSegue but keeping a dialog around after the parent
    // dies can trigger bugs in Qt 5.12 that cause the app to crash. For now, we will
    // host this dialog in a QML component that is never destroyed.
    //
    // To repro: Start a stream, cut the network connection to trigger the "Connection
    // terminated" dialog, wait until the app grid times out back to the PC grid, then
    // try to dismiss the dialog.
    ErrorMessageDialog {
        id: streamSegueErrorDialog

        property bool quitAfter: false

        onClosed: {
            if (quitAfter) {
                Qt.quit()
            }

            // StreamSegue assumes its dialog will be re-created each time we
            // start streaming, so fake it by wiping out the text each time.
            text = ""
        }
    }

    NavigableDialog {
        id: addPcDialog
        property string label: qsTr("Enter the IP address of your host PC:")

        standardButtons: Dialog.Ok | Dialog.Cancel

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            editText.forceActiveFocus()
        }

        onClosed: {
            editText.clear()
        }

        onAccepted: {
            if (editText.text) {
                ComputerManager.addNewHostManually(editText.text.trim())
            }
        }

        ColumnLayout {
            Label {
                text: addPcDialog.label
                font.bold: true
            }

            TextField {
                id: editText
                Layout.fillWidth: true
                focus: true

                Keys.onReturnPressed: {
                    addPcDialog.accept()
                }

                Keys.onEnterPressed: {
                    addPcDialog.accept()
                }
            }
        }
    }
}
