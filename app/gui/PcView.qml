import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

Item {
    property ComputerModel computerModel : createModel()
    property int hostCellWidth: 280
    // Index of the centered tile: 0..hostCount-1 are hosts,
    // hostCount is the trailing Add Host tile.
    property int hostCount: hostRepeater.count
    property int selectedIndex: 0
    property int tileCount: hostRepeater.count + 1
    property Item focusTarget: hostRepeater.count > 0 ? hostFlick : emptyAddButton

    id: pcRoot
    focus: true
    activeFocusOnTab: true
    objectName: qsTr("Computers")

    Component.onCompleted: {
        selectedIndex = 0
        // Center without animation on first show
        centerOn(selectedIndex, false)
        focusHosts()
    }

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        // Setup signals on CM
        ComputerManager.computerAddCompleted.connect(addComplete)

        if (selectedIndex < 0 || selectedIndex >= tileCount) {
            selectedIndex = 0
        }
        centerOn(selectedIndex, false)
        focusHosts()
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
    }

    onTileCountChanged: {
        if (selectedIndex >= tileCount) {
            selectedIndex = Math.max(0, tileCount - 1)
        }
        centerOn(selectedIndex, false)
    }

    function pairingComplete(error)
    {
        // Close the PIN dialog
        pairDialog.close()

        // Display a failed dialog if we got an error
        if (error !== undefined) {
            errorDialog.text = error
            errorDialog.helpText = ""
            errorDialog.open()
        }
    }

    function addComplete(success, detectedPortBlocking)
    {
        if (!success) {
            errorDialog.text = qsTr("Unable to connect to the specified PC.")

            if (detectedPortBlocking) {
                errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
            }
            else {
                errorDialog.helpText = qsTr("Click the Help button for possible solutions.")
            }

            errorDialog.open()
        }
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', parent, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    function getHostTile(pcIndex)
    {
        if (pcIndex < 0 || pcIndex >= hostRepeater.count) {
            return null
        }
        return hostRepeater.itemAt(pcIndex)
    }

    function activatePc(pcIndex, pcName, online, paired, serverSupported)
    {
        if (online) {
            if (!serverSupported) {
                errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of Moonlight. You must update Moonlight to stream from %1.").arg(pcName)
                errorDialog.helpText = ""
                errorDialog.open()
            }
            else if (paired) {
                // go to game view
                var component = Qt.createComponent("AppView.qml")
                var appView = component.createObject(stackView, {"computerIndex": pcIndex, "objectName": pcName})
                stackView.push(appView)
            }
            else {
                var pin = computerModel.generatePinString()

                // Kick off pairing in the background
                computerModel.pairComputer(pcIndex, pin)

                // Display the pairing dialog
                pairDialog.pin = pin
                pairDialog.open()
            }
        } else {
            var item = getHostTile(pcIndex)
            if (item && item.pcContextMenu) {
                item.pcContextMenu.open()
            }
        }
    }

    function selectOrActivate(pcIndex, pcName, online, paired, serverSupported)
    {
        hostFlick.forceActiveFocus()
        if (selectedIndex !== pcIndex) {
            selectedIndex = pcIndex
            centerOn(selectedIndex, true)
        }
        else {
            activatePc(pcIndex, pcName, online, paired, serverSupported)
        }
    }

    function selectAddTile()
    {
        hostFlick.forceActiveFocus()
        if (selectedIndex !== hostRepeater.count) {
            selectedIndex = hostRepeater.count
            centerOn(selectedIndex, true)
        }
        else {
            addPcDialog.open()
        }
    }

    function focusHosts()
    {
        if (hostRepeater.count > 0) {
            hostFlick.forceActiveFocus()
        }
        else {
            emptyAddButton.forceActiveFocus()
        }
    }

    function openSelectedMenu()
    {
        var tile = getHostTile(selectedIndex)
        if (tile && tile.pcContextMenu) {
            tile.pcContextMenu.open()
        }
    }

    function deleteSelected()
    {
        if (selectedIndex >= hostRepeater.count) {
            return
        }
        var tile = getHostTile(selectedIndex)
        deletePcDialog.pcIndex = selectedIndex
        deletePcDialog.pcName = tile ? tile.pcName : ""
        deletePcDialog.open()
    }

    function moveSelection(delta)
    {
        if (tileCount <= 0) {
            return
        }
        var next = (selectedIndex + delta + tileCount) % tileCount
        selectedIndex = next
        centerOn(selectedIndex, true)
    }

    function centerOn(index, animated)
    {
        if (!hostFlick || hostFlick.width <= 0) {
            return
        }
        var target = index * hostCellWidth
        var maxX = Math.max(0, hostFlick.contentWidth - hostFlick.width)
        target = Math.max(0, Math.min(target, maxX))
        if (animated) {
            centerAnim.to = target
            centerAnim.start()
        }
        else {
            centerAnim.stop()
            hostFlick.contentX = target
        }
    }

    NumberAnimation {
        id: centerAnim
        target: hostFlick
        property: "contentX"
        duration: 280
        easing.type: Easing.OutCubic
    }

    // Main vertically-centered column: hosts carousel + settings gear
    ColumnLayout {
        id: homeColumn
        anchors.centerIn: parent
        width: parent.width
        spacing: 24

        // Hosts carousel area (fixed height, full width)
        Item {
            id: carouselArea
            Layout.fillWidth: true
            Layout.preferredHeight: 410

            // Horizontally scrollable hosts row. The current tile is
            // always animated to the center (Apple login style) and the
            // trailing tile is always Add Host.
            Flickable {
                id: hostFlick
                anchors.fill: parent
                visible: hostRepeater.count > 0
                clip: true
                contentWidth: hostRow.width
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.DragAndOvershootBounds
                focus: true
                activeFocusOnTab: false

                // Keep the selected tile centered after resizes
                onWidthChanged: centerOn(selectedIndex, false)
                onContentWidthChanged: centerOn(selectedIndex, false)

                // Snap to the nearest tile when the user drags, then select it
                onMovementEnded: {
                    var nearest = Math.round(contentX / hostCellWidth)
                    nearest = Math.max(0, Math.min(nearest, tileCount - 1))
                    selectedIndex = nearest
                    centerOn(selectedIndex, true)
                }

                Keys.onLeftPressed: moveSelection(-1)
                Keys.onRightPressed: moveSelection(1)
                Keys.onDownPressed: settingsButton.forceActiveFocus(Qt.TabFocus)
                Keys.onReturnPressed: activateSelected()
                Keys.onEnterPressed: activateSelected()
                Keys.onMenuPressed: openSelectedMenu()
                Keys.onDeletePressed: deleteSelected()

                function activateSelected()
                {
                    if (selectedIndex >= hostRepeater.count) {
                        addPcDialog.open()
                        return
                    }
                    var tile = getHostTile(selectedIndex)
                    if (tile) {
                        tile.activate()
                    }
                }

                Row {
                    id: hostRow
                    height: hostFlick.height

                    // Leading spacer so the first host can sit in the center
                    Item {
                        width: Math.max(0, (hostFlick.width - hostCellWidth) / 2)
                        height: 1
                    }

                    Repeater {
                        id: hostRepeater
                        model: computerModel

                        Item {
                            id: hostTile
                            width: hostCellWidth
                            height: 410

                            property bool isCurrent: index === selectedIndex
                            property string pcName: model.name
                            property alias pcContextMenu: pcContextMenuLoader.item

                            function activate()
                            {
                                activatePc(index, model.name, model.online, model.paired, model.serverSupported)
                            }

                            Item {
                                id: avatarContainer
                                width: 250
                                height: 330
                                anchors.top: parent.top
                                anchors.topMargin: 40
                                anchors.horizontalCenter: parent.horizontalCenter
                                scale: hostTile.isCurrent ? 1.2 : 0.80
                                opacity: {
                                    if (hostTile.isCurrent) return 1.0
                                    return model.online ? 0.65 : 0.5
                                }

                                Behavior on scale { NumberAnimation { duration: 180 } }
                                Behavior on opacity { NumberAnimation { duration: 180 } }

                                // Round login-manager style background with icon centered
                                Rectangle {
                                    id: avatarCircle
                                    width: 190
                                    height: 190
                                    radius: 95
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: {
                                        if (!model.online) return "#2b2b2b"
                                        if (!model.paired) return "#33404f"
                                        return "#2f2f2f"
                                    }
                                    border.color: {
                                        if (hostTile.isCurrent && hostFlick.activeFocus) {
                                            if (!model.online) return "#8a8a8a"
                                            if (!model.paired) return "#e0b44c"
                                            return "#7fb8ff"
                                        }
                                        return "#555555"
                                    }
                                    border.width: hostTile.isCurrent && hostFlick.activeFocus ? 3 : 2

                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Image {
                                        id: pcIcon
                                        anchors.centerIn: parent
                                        source: "qrc:/res/desktop_windows-48px.svg"
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                    }

                                    Image {
                                        id: stateIcon
                                        anchors.horizontalCenter: pcIcon.horizontalCenter
                                        anchors.verticalCenter: pcIcon.verticalCenter
                                        anchors.verticalCenterOffset: !model.online ? -18 : -16
                                        visible: !model.statusUnknown && (!model.online || !model.paired)
                                        source: !model.online ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg" : "qrc:/res/baseline-lock-24px.svg"
                                        sourceSize.width: !model.online ? 70 : 66
                                        sourceSize.height: !model.online ? 70 : 66
                                    }

                                    BusyIndicator {
                                        id: statusUnknownSpinner
                                        anchors.horizontalCenter: pcIcon.horizontalCenter
                                        anchors.verticalCenter: pcIcon.verticalCenter
                                        anchors.verticalCenterOffset: -15
                                        width: 70
                                        height: 70
                                        visible: model.statusUnknown
                                        running: visible
                                    }

                                    // Online status dot on the circle edge
                                    Rectangle {
                                        width: 22
                                        height: 22
                                        radius: 11
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 12
                                        color: !model.online ? "#e05252" : (model.paired ? "#58c472" : "#e0b44c")
                                        border.color: "#1e1e1e"
                                        border.width: 3
                                        visible: !model.statusUnknown
                                    }
                                }

                                Label {
                                    id: pcNameText
                                    text: model.name
                                    width: parent.width
                                    anchors.top: avatarCircle.bottom
                                    anchors.topMargin: 14
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    font.pointSize: hostTile.isCurrent ? 22 : 18
                                    font.bold: hostTile.isCurrent
                                    color: hostTile.isCurrent ? "white" : "#aaaaaa"
                                }
                            }

                            Loader {
                                id: pcContextMenuLoader
                                asynchronous: true
                                sourceComponent: NavigableMenu {
                                    id: pcContextMenu
                                    initiator: hostTile
                                    MenuItem {
                                        text: qsTr("PC Status: %1").arg(model.online ? qsTr("Online") : qsTr("Offline"))
                                        font.bold: true
                                        enabled: false
                                    }
                                    NavigableMenuItem {
                                        text: qsTr("View All Apps")
                                        onTriggered: {
                                            var component = Qt.createComponent("AppView.qml")
                                            var appView = component.createObject(stackView, {"computerIndex": index, "objectName": model.name, "showHiddenGames": true})
                                            stackView.push(appView)
                                        }
                                        visible: model.online && model.paired
                                    }
                                    NavigableMenuItem {
                                        text: qsTr("Wake PC")
                                        onTriggered: computerModel.wakeComputer(index)
                                        visible: !model.online && model.wakeable
                                    }
                                    NavigableMenuItem {
                                        text: qsTr("Test Network")
                                        onTriggered: {
                                            computerModel.testConnectionForComputer(index)
                                            testConnectionDialog.open()
                                        }
                                    }
                                    NavigableMenuItem {
                                        text: qsTr("Rename PC")
                                        onTriggered: {
                                            renamePcDialog.pcIndex = index
                                            renamePcDialog.originalName = model.name
                                            renamePcDialog.open()
                                        }
                                    }
                                    NavigableMenuItem {
                                        text: qsTr("Delete PC")
                                        onTriggered: {
                                            deletePcDialog.pcIndex = index
                                            deletePcDialog.pcName = model.name
                                            deletePcDialog.open()
                                        }
                                    }
                                    NavigableMenuItem {
                                        text: qsTr("View Details")
                                        onTriggered: {
                                            showPcDetailsDialog.pcDetails = model.details
                                            showPcDetailsDialog.open()
                                        }
                                    }
                                }
                            }

                            ItemDelegate {
                                id: tileButton
                                anchors.fill: parent
                                hoverEnabled: true
                                focusPolicy: Qt.NoFocus
                                activeFocusOnTab: false

                                background: Rectangle {
                                    color: "transparent"
                                }

                                // Show full name when truncated
                                ToolTip.text: model.name
                                ToolTip.delay: 1000
                                ToolTip.timeout: 5000
                                ToolTip.visible: hovered && pcNameText.truncated

                                onClicked: selectOrActivate(index, model.name, model.online, model.paired, model.serverSupported)
                                onPressAndHold: {
                                    if (pcContextMenu.popup) {
                                        pcContextMenu.popup()
                                    }
                                    else {
                                        pcContextMenu.open()
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: {
                                        tileButton.pressAndHold()
                                    }
                                }
                            }
                        }
                    }

                    // Trailing Add Host tile, always last and centerable
                    Item {
                        id: addHostTile
                        width: hostCellWidth
                        height: 410

                        property bool isCurrent: selectedIndex === hostRepeater.count

                        Item {
                            id: addAvatarContainer
                            width: 190
                            height: 230
                            anchors.top: parent.top
                            anchors.topMargin: 81
                            anchors.horizontalCenter: parent.horizontalCenter
                            opacity: addHostTile.isCurrent ? 1.0 : 0.65

                            Behavior on opacity { NumberAnimation { duration: 180 } }

                            Rectangle {
                                id: addCircle
                                width: 108
                                height: 108
                                radius: 54
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: "#2b2b2b"
                                border.color: addHostTile.isCurrent && hostFlick.activeFocus ? "#7fb8ff" : "#555555"
                                border.width: addHostTile.isCurrent && hostFlick.activeFocus ? 3 : 2

                                Behavior on color { ColorAnimation { duration: 180 } }

                                Image {
                                    anchors.centerIn: parent
                                    source: "qrc:/res/ic_add_to_queue_white_48px.svg"
                                    sourceSize.width: 52
                                    sourceSize.height: 52
                                }
                            }

                            Label {
                                text: qsTr("Add Host")
                                width: parent.width
                                anchors.top: addCircle.bottom
                                anchors.topMargin: 14
                                horizontalAlignment: Text.AlignHCenter
                                font.pointSize: addHostTile.isCurrent ? 16 : 14
                                color: addHostTile.isCurrent ? "white" : "#aaaaaa"
                            }
                        }

                        ItemDelegate {
                            anchors.fill: parent
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            activeFocusOnTab: false

                            background: Rectangle {
                                color: "transparent"
                            }

                            ToolTip.delay: 1000
                            ToolTip.timeout: 3000
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Add PC manually")

                            onClicked: selectAddTile()
                        }
                    }

                    // Trailing spacer so the Add tile can sit in the center
                    Item {
                        width: Math.max(0, (hostFlick.width - hostCellWidth) / 2)
                        height: 1
                    }
                }

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AlwaysOff
                }
            }

            // Empty state: single centered Add Host when there are no hosts
            Item {
                id: emptyState
                anchors.fill: parent
                visible: hostRepeater.count === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Item {
                        width: hostCellWidth
                        height: 270
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            id: emptyCircle
                            width: 108
                            height: 108
                            radius: 54
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: "#2b2b2b"
                            border.color: "#7fb8ff"
                            border.width: 3

                            Image {
                                anchors.centerIn: parent
                                source: "qrc:/res/ic_add_to_queue_white_48px.svg"
                                sourceSize.width: 52
                                sourceSize.height: 52
                            }
                        }

                        Label {
                            text: qsTr("Add Host")
                            width: parent.width
                            anchors.top: emptyCircle.bottom
                            anchors.topMargin: 14
                            horizontalAlignment: Text.AlignHCenter
                            font.pointSize: 18
                            color: "white"
                        }

                        ItemDelegate {
                            id: emptyAddButton
                            anchors.fill: parent
                            hoverEnabled: true

                            background: Rectangle {
                                color: "transparent"
                            }

                            ToolTip.delay: 1000
                            ToolTip.timeout: 3000
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Add PC manually")
                            onClicked: addPcDialog.open()
                            Keys.onTabPressed: powerButton.forceActiveFocus(Qt.TabFocus)
                            Keys.onBacktabPressed: settingsButton.forceActiveFocus(Qt.BacktabFocus)
                            Keys.onDownPressed: settingsButton.forceActiveFocus(Qt.TabFocus)
                            Keys.onReturnPressed: clicked()
                            Keys.onEnterPressed: clicked()
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        BusyIndicator {
                            id: searchSpinner
                            visible: StreamingPreferences.enableMdns
                            running: visible
                        }

                        Label {
                            height: searchSpinner.height
                            text: StreamingPreferences.enableMdns ? qsTr("Searching for compatible hosts on your local network...")
                                                                  : qsTr("Automatic PC discovery is disabled. Add your PC manually.")
                            font.pointSize: 16
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }

        // Power and settings buttons under the hosts list
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 28

            ToolButton {
                id: powerButton
                width: 56
                height: 56
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true

                icon.source: "qrc:/res/power.svg"
                icon.width: 32
                icon.height: 32

                background: Rectangle {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: 28
                    color: powerButton.hovered || powerButton.activeFocus ? "#a83232" : "#5c2323"
                    border.color: powerButton.activeFocus ? "#ff8a8a" : "transparent"
                    border.width: 2
                }

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Turn off this PC")

                onClicked: powerConfirmDialog.open()

                Keys.onTabPressed: settingsButton.forceActiveFocus(Qt.TabFocus)
                Keys.onBacktabPressed: settingsButton.forceActiveFocus(Qt.BacktabFocus)
                Keys.onUpPressed: {
                    if (hostFlick.visible) {
                        hostFlick.forceActiveFocus(Qt.TabFocus)
                    }
                }
                Keys.onRightPressed: settingsButton.forceActiveFocus(Qt.TabFocus)
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }

            ToolButton {
                id: settingsButton
                width: 56
                height: 56
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true

                icon.source: "qrc:/res/settings.svg"
                icon.width: 36
                icon.height: 36

                // Subtle round background for fullscreen readability
                background: Rectangle {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: 28
                    color: settingsButton.hovered || settingsButton.activeFocus ? "#3d3d3d" : "transparent"
                    border.color: settingsButton.activeFocus ? "#7fb8ff" : "transparent"
                    border.width: 2
                }

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Settings")

                Shortcut {
                    id: settingsShortcut
                    sequence: StandardKey.Preferences
                    onActivated: settingsButton.clicked()
                }

                Shortcut {
                    id: newPcShortcut
                    sequence: StandardKey.New
                    onActivated: addPcDialog.open()
                }

                onClicked: openSettings()

                Keys.onTabPressed: powerButton.forceActiveFocus(Qt.TabFocus)
                Keys.onBacktabPressed: powerButton.forceActiveFocus(Qt.BacktabFocus)
                Keys.onLeftPressed: powerButton.forceActiveFocus(Qt.TabFocus)
                Keys.onUpPressed: {
                    if (hostFlick.visible) {
                        hostFlick.forceActiveFocus(Qt.TabFocus)
                    }
                }
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
        }
    }

    NavigableMessageDialog {
        id: powerConfirmDialog
        text: qsTr("Are you sure you want to turn off this PC?")
        standardButtons: Dialog.Yes | Dialog.No

        onAccepted: {
            SystemProperties.powerOff()
        }
    }

    function openSettings()
    {
        var existing = stackView.find(function(item, index) {
            return item.objectName === qsTr("Settings")
        })
        if (existing !== null) {
            stackView.pop(existing)
        }
        else {
            stackView.push("qrc:/gui/SettingsView.qml")
        }
    }

    NavigableDialog {
        id: addPcDialog
        property string label: qsTr("Enter the IP address of your host PC:")

        standardButtons: Dialog.Ok | Dialog.Cancel

        onOpened: {
            addPcEditText.forceActiveFocus()
        }

        onClosed: {
            addPcEditText.clear()
        }

        onAccepted: {
            if (addPcEditText.text) {
                ComputerManager.addNewHostManually(addPcEditText.text.trim())
            }
        }

        ColumnLayout {
            Label {
                text: addPcDialog.label
                font.bold: true
            }

            TextField {
                id: addPcEditText
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

    ErrorMessageDialog {
        id: errorDialog

        // Using Setup-Guide here instead of Troubleshooting because it's likely that users
        // will arrive here by forgetting to enable GameStream or not forwarding ports.
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"
    }

    NavigableMessageDialog {
        id: pairDialog
        closePolicy: Popup.CloseOnEscape

        // don't allow edits to the rest of the window while open
        property string pin : "0000"
        text:qsTr("Please enter %1 on your host PC. This dialog will close when pairing is completed.").arg(pin)+"\n\n"+
             qsTr("If your host PC is running Sunshine, navigate to the Sunshine web UI to enter the PIN.")
        standardButtons: Dialog.Cancel
        onRejected: {
            // FIXME: We should interrupt pairing here
        }
    }

    NavigableMessageDialog {
        id: deletePcDialog
        // don't allow edits to the rest of the window while open
        property int pcIndex : -1
        property string pcName : ""
        text: qsTr("Are you sure you want to remove '%1'?").arg(pcName)
        standardButtons: Dialog.Yes | Dialog.No

        onAccepted: {
            computerModel.deleteComputer(pcIndex)
        }
    }

    NavigableMessageDialog {
        id: testConnectionDialog
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Ok

        onAboutToShow: {
            testConnectionDialog.text = qsTr("Moonlight is testing your network connection to determine if any required ports are blocked.") + "\n\n" + qsTr("This may take a few seconds…")
            showSpinner = true
        }

        function connectionTestComplete(result, blockedPorts)
        {
            if (result === -1) {
                text = qsTr("The network test could not be performed because none of Moonlight's connection testing servers were reachable from this PC. Check your Internet connection or try again later.")
                imageSrc = "qrc:/res/baseline-warning-24px.svg"
            }
            else if (result === 0) {
                text = qsTr("This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.") + "\n\n" + qsTr("If you are trying to stream over the Internet, install the Moonlight Internet Hosting Tool on your gaming PC and run the included Internet Streaming Tester to check your gaming PC's Internet connection.")
                imageSrc = "qrc:/res/baseline-check_circle_outline-24px.svg"
            }
            else {
                text = qsTr("Your PC's current network connection seems to be blocking Moonlight. Streaming over the Internet may not work while connected to this network.") + "\n\n" + qsTr("The following network ports were blocked:") + "\n"
                text += blockedPorts
                imageSrc = "qrc:/res/baseline-error_outline-24px.svg"
            }

            // Stop showing the spinner and show the image instead
            showSpinner = false
        }
    }

    NavigableDialog {
        id: renamePcDialog
        property string label: qsTr("Enter the new name for this PC:")
        property string originalName
        property int pcIndex : -1;

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
                computerModel.renameComputer(pcIndex, editText.text)
            }
        }

        ColumnLayout {
            Label {
                text: renamePcDialog.label
                font.bold: true
            }

            TextField {
                id: editText
                placeholderText: renamePcDialog.originalName
                Layout.fillWidth: true
                focus: true

                Keys.onReturnPressed: {
                    renamePcDialog.accept()
                }

                Keys.onEnterPressed: {
                    renamePcDialog.accept()
                }
            }
        }
    }

    NavigableMessageDialog {
        id: showPcDetailsDialog
        property string pcDetails : "";
        text: showPcDetailsDialog.pcDetails
        imageSrc: "qrc:/res/baseline-help_outline-24px.svg"
        standardButtons: Dialog.Ok
    }
}
