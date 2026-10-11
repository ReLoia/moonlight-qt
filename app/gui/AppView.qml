import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Controls.Material 2.2
import QtQuick.Layouts 1.3

import AppModel 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0

Item {
    property int computerIndex
    property AppModel appModel : createModel()
    property bool activated
    property bool showHiddenGames
    property bool showGames

    // Carousel layout: game tile size + how far left of center
    // the selected game rests (Apple login style, shifted left)
    property int gameCellWidth: 280
    property int centerShift: 120
    property int selectedIndex: 0
    property Item focusTarget: appFlick

    id: appRoot
    focus: true
    activeFocusOnTab: true

    // No top bar: Esc/Back always returns to the main page
    Keys.onEscapePressed: stackView.pop(null)
    Keys.onBackPressed: stackView.pop(null)

    function computerLost()
    {
        // Go back to the PC view on PC loss
        stackView.pop()
    }

    Component.onCompleted: {
        selectedIndex = 0
        centerOn(selectedIndex, false)
        focusGames()
    }

    StackView.onActivated: {
        appModel.computerLost.connect(computerLost)
        activated = true

        if (selectedIndex < 0 || selectedIndex >= gameRepeater.count) {
            selectedIndex = 0
        }
        centerOn(selectedIndex, false)
        focusGames()

        if (!showGames && !showHiddenGames) {
            // Check if there's a direct launch app
            var directLaunchAppIndex = appModel.getDirectLaunchAppIndex();
            if (directLaunchAppIndex >= 0) {
                // Start the direct launch app if nothing else is running
                selectedIndex = directLaunchAppIndex
                centerOn(selectedIndex, false)
                var tile = gameRepeater.itemAt(directLaunchAppIndex)
                if (tile) {
                    tile.launchOrResumeSelectedApp(false)
                }

                // Set showGames so we will not loop when the stream ends
                showGames = true
            }
        }
    }

    StackView.onDeactivating: {
        appModel.computerLost.disconnect(computerLost)
        activated = false
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import AppModel 1.0; AppModel {}', parent, '')
        model.initialize(ComputerManager, computerIndex, showHiddenGames)
        return model
    }

    function focusGames()
    {
        appFlick.forceActiveFocus()
    }

    function getGameTile(gameIndex)
    {
        if (gameIndex < 0 || gameIndex >= gameRepeater.count) {
            return null
        }
        return gameRepeater.itemAt(gameIndex)
    }

    function openSelectedMenu()
    {
        var tile = getGameTile(selectedIndex)
        if (tile) {
            tile.openMenu()
        }
    }

    function moveSelection(delta)
    {
        if (gameRepeater.count <= 0) {
            return
        }
        var next = (selectedIndex + delta + gameRepeater.count) % gameRepeater.count
        selectedIndex = next
        centerOn(selectedIndex, true)
    }

    function centerOn(index, animated)
    {
        if (!appFlick || appFlick.width <= 0) {
            return
        }
        // Selected tile rests centerShift pixels left of center
        var target = index * gameCellWidth + centerShift
        var maxX = Math.max(0, appFlick.contentWidth - appFlick.width)
        target = Math.max(0, Math.min(target, maxX))
        if (animated) {
            centerAnim.to = target
            centerAnim.start()
        }
        else {
            centerAnim.stop()
            appFlick.contentX = target
        }
    }

    function selectOrLaunch(gameIndex)
    {
        appFlick.forceActiveFocus()
        if (selectedIndex !== gameIndex) {
            selectedIndex = gameIndex
            centerOn(selectedIndex, true)
        }
        else {
            var tile = getGameTile(gameIndex)
            if (tile) {
                tile.activate()
            }
        }
    }

    function activateSelected()
    {
        var tile = getGameTile(selectedIndex)
        if (tile) {
            tile.activate()
        }
    }

    NumberAnimation {
        id: centerAnim
        target: appFlick
        property: "contentX"
        duration: 280
        easing.type: Easing.OutCubic
    }

    // Host name, big and centered on top
    Label {
        id: hostTitleLabel
        anchors.top: parent.top
        anchors.topMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 160, implicitWidth)
        text: appRoot.objectName
        font.pointSize: 34
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    // Vertically centered games carousel
    Item {
        id: carouselArea
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 15
        width: parent.width
        height: 460

        Flickable {
            id: appFlick
            anchors.fill: parent
            visible: gameRepeater.count > 0
            clip: true
            contentWidth: gameRow.width
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.DragAndOvershootBounds
            focus: true
            activeFocusOnTab: false

            onWidthChanged: centerOn(selectedIndex, false)
            onContentWidthChanged: centerOn(selectedIndex, false)

            // Snap to the nearest game when the user drags, then select it
            onMovementEnded: {
                var nearest = Math.round((contentX - centerShift) / gameCellWidth)
                nearest = Math.max(0, Math.min(nearest, gameRepeater.count - 1))
                selectedIndex = nearest
                centerOn(selectedIndex, true)
            }

            Keys.onLeftPressed: moveSelection(-1)
            Keys.onRightPressed: moveSelection(1)
            Keys.onReturnPressed: activateSelected()
            Keys.onEnterPressed: activateSelected()
            Keys.onMenuPressed: openSelectedMenu()

            Row {
                id: gameRow
                height: appFlick.height

                // Leading spacer so the first game can rest left of center
                Item {
                    width: Math.max(0, (appFlick.width - gameCellWidth) / 2)
                    height: 1
                }

                Repeater {
                    id: gameRepeater
                    model: appModel

                    Item {
                        id: gameTile
                        width: gameCellWidth
                        height: 460

                        property bool isCurrent: index === selectedIndex
                        property alias appContextMenu: appContextMenuLoader.item

                        function activate()
                        {
                            // Running games open their menu (resume/quit);
                            // anything else launches on second press.
                            if (model.running) {
                                openMenu()
                            }
                            else {
                                launchOrResumeSelectedApp(true)
                            }
                        }

                        function openMenu()
                        {
                            if (appContextMenu) {
                                appContextMenu.open()
                            }
                        }

                        Item {
                            id: artContainer
                            width: 264
                            height: 350
                            anchors.top: parent.top
                            anchors.topMargin: 40
                            anchors.horizontalCenter: parent.horizontalCenter
                            scale: gameTile.isCurrent ? 1.2 : 0.8
                            opacity: (gameTile.isCurrent ? 1.0 : 0.6) * (model.hidden ? 0.4 : 1.0)

                            Behavior on scale { NumberAnimation { duration: 180 } }
                            Behavior on opacity { NumberAnimation { duration: 180 } }

                            Rectangle {
                                id: artRing
                                width: 254
                                height: 334
                                radius: 16
                                color: "transparent"
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: gameTile.isCurrent
                                border.color: gameTile.isCurrent && appFlick.activeFocus ? "#7fb8ff" : "#555555"
                                border.width: 3
                            }

                            Item {
                                id: artFrame
                                width: 242
                                height: 322
                                anchors.top: parent.top
                                anchors.topMargin: 6
                                anchors.horizontalCenter: parent.horizontalCenter

                                // Slightly rounded box art (radius in pixels)
                                Canvas {
                                    id: artCanvas
                                    anchors.fill: parent
                                    property string artUrl: model.boxart
                                    property int cornerRadius: 11

                                    onArtUrlChanged: {
                                        if (artUrl !== "") {
                                            loadImage(artUrl)
                                        }
                                        requestPaint()
                                    }
                                    Component.onCompleted: {
                                        if (artUrl !== "") {
                                            loadImage(artUrl)
                                        }
                                    }
                                    onImageLoaded: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        var w = width
                                        var h = height
                                        var r = cornerRadius
                                        ctx.clearRect(0, 0, w, h)
                                        ctx.save()
                                        ctx.beginPath()
                                        ctx.moveTo(r, 0)
                                        ctx.lineTo(w - r, 0)
                                        ctx.arcTo(w, 0, w, r, r)
                                        ctx.lineTo(w, h - r)
                                        ctx.arcTo(w, h, w - r, h, r)
                                        ctx.lineTo(r, h)
                                        ctx.arcTo(0, h, 0, h - r, r)
                                        ctx.lineTo(0, r)
                                        ctx.arcTo(0, 0, r, 0, r)
                                        ctx.closePath()
                                        ctx.clip()
                                        if (artUrl !== "" && isImageLoaded(artUrl)) {
                                            ctx.drawImage(artUrl, 0, 0, w, h)
                                        }
                                        ctx.restore()
                                    }
                                }

                                // Hidden image: feeds placeholder detection
                                // and the shared image cache for the canvas
                                Image {
                                    id: appIcon
                                    property bool isPlaceholder: false

                                    visible: false
                                    source: model.boxart

                                    onSourceSizeChanged: {
                                        // Nearly all of Nvidia's official box art does not match the dimensions of placeholder
                                        // images, however the one known exception is Overcooked. Therefore, we only execute
                                        // the image size checks if this is not an app collector game. We know the officially
                                        // supported games all have box art, so this check is not required.
                                        if (!model.isAppCollectorGame &&
                                            ((sourceSize.width === 130 && sourceSize.height === 180) || // GFE 2.0 placeholder image
                                             (sourceSize.width === 628 && sourceSize.height === 888) || // GFE 3.0 placeholder image
                                             (sourceSize.width === 200 && sourceSize.height === 266)))  // Our no_app_image.png
                                        {
                                            isPlaceholder = true
                                        }
                                        else
                                        {
                                            isPlaceholder = false
                                        }
                                    }
                                }

                                Loader {
                                    active: model.running
                                    asynchronous: true
                                    anchors.fill: artFrame

                                    sourceComponent: Item {
                                        RoundButton {
                                            // Don't steal focus from the toolbar buttons
                                            focusPolicy: Qt.NoFocus

                                            anchors.horizontalCenterOffset: appIcon.isPlaceholder ? -47 : 0
                                            anchors.verticalCenterOffset: appIcon.isPlaceholder ? -75 : -60
                                            anchors.centerIn: parent
                                            implicitWidth: 85
                                            implicitHeight: 85

                                            icon.source: "qrc:/res/play_arrow_FILL1_wght700_GRAD200_opsz48.svg"
                                            icon.width: 75
                                            icon.height: 75

                                            onClicked: {
                                                launchOrResumeSelectedApp(true)
                                            }

                                            ToolTip.text: qsTr("Resume Game")
                                            ToolTip.delay: 1000
                                            ToolTip.timeout: 3000
                                            ToolTip.visible: hovered

                                            Material.background: "#D0808080"
                                        }

                                        RoundButton {
                                            // Don't steal focus from the toolbar buttons
                                            focusPolicy: Qt.NoFocus

                                            anchors.horizontalCenterOffset: appIcon.isPlaceholder ? 47 : 0
                                            anchors.verticalCenterOffset: appIcon.isPlaceholder ? -75 : 60
                                            anchors.centerIn: parent
                                            implicitWidth: 85
                                            implicitHeight: 85

                                            icon.source: "qrc:/res/stop_FILL1_wght700_GRAD200_opsz48.svg"
                                            icon.width: 75
                                            icon.height: 75

                                            onClicked: {
                                                doQuitGame()
                                            }

                                            ToolTip.text: qsTr("Quit Game")
                                            ToolTip.delay: 1000
                                            ToolTip.timeout: 3000
                                            ToolTip.visible: hovered

                                            Material.background: "#D0808080"
                                        }
                                    }
                                }

                                Loader {
                                    id: appNameTextLoader
                                    active: appIcon.isPlaceholder

                                    // This loader is not asynchronous to avoid noticeable differences
                                    // in the time in which the text loads for each game.

                                    width: artFrame.width
                                    height: model.running ? 175 : artFrame.height

                                    anchors.left: artFrame.left
                                    anchors.right: artFrame.right
                                    anchors.bottom: artFrame.bottom

                                    sourceComponent: Label {
                                        id: appNameText
                                        text: model.name
                                        font.pointSize: 22
                                        leftPadding: 20
                                        rightPadding: 20
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        function launchOrResumeSelectedApp(quitExistingApp)
                        {
                            var runningId = appModel.getRunningAppId()
                            if (runningId !== 0 && runningId !== model.appid) {
                                if (quitExistingApp) {
                                    quitAppDialog.appName = appModel.getRunningAppName()
                                    quitAppDialog.segueToStream = true
                                    quitAppDialog.nextAppName = model.name
                                    quitAppDialog.nextAppIndex = index
                                    quitAppDialog.open()
                                }

                                return
                            }

                            var component = Qt.createComponent("StreamSegue.qml")
                            var segue = component.createObject(stackView, {
                                                                   "appName": model.name,
                                                                   "session": appModel.createSessionForApp(index),
                                                                   "isResume": runningId === model.appid
                                                               })
                            stackView.push(segue)
                        }

                        function doQuitGame() {
                            quitAppDialog.appName = appModel.getRunningAppName()
                            quitAppDialog.segueToStream = false
                            quitAppDialog.open()
                        }

                        Loader {
                            id: appContextMenuLoader
                            asynchronous: true
                            sourceComponent: NavigableMenu {
                                id: appContextMenu
                                initiator: gameTile
                                NavigableMenuItem {
                                    text: model.running ? qsTr("Resume Game") : qsTr("Launch Game")
                                    onTriggered: launchOrResumeSelectedApp(true)
                                }
                                NavigableMenuItem {
                                    text: qsTr("Quit Game")
                                    onTriggered: doQuitGame()
                                    visible: model.running
                                }
                                NavigableMenuItem {
                                    checkable: true
                                    checked: model.directLaunch
                                    text: qsTr("Direct Launch")
                                    onTriggered: appModel.setAppDirectLaunch(model.index, !model.directLaunch)
                                    enabled: !model.hidden

                                    ToolTip.text: qsTr("Launch this app immediately when the host is selected, bypassing the app selection grid.")
                                    ToolTip.delay: 1000
                                    ToolTip.timeout: 3000
                                    ToolTip.visible: hovered
                                }
                                NavigableMenuItem {
                                    checkable: true
                                    checked: model.hidden
                                    text: qsTr("Hide Game")
                                    onTriggered: appModel.setAppHidden(model.index, !model.hidden)
                                    enabled: model.hidden || (!model.running && !model.directLaunch)

                                    ToolTip.text: qsTr("Hide this game from the app grid. To access hidden games, right-click on the host and choose %1.").arg(qsTr("View All Apps"))
                                    ToolTip.delay: 1000
                                    ToolTip.timeout: 5000
                                    ToolTip.visible: hovered
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

                            // Display a tooltip with the full name if it's truncated
                            ToolTip.text: model.name
                            ToolTip.delay: 1000
                            ToolTip.timeout: 5000
                            ToolTip.visible: hovered && appNameTextLoader.item && appNameTextLoader.item.truncated

                            onClicked: selectOrLaunch(index)

                            onPressAndHold: {
                                // popup() ensures the menu appears under the mouse cursor
                                if (appContextMenu.popup) {
                                    appContextMenu.popup()
                                }
                                else {
                                    // Qt 5.9 doesn't have popup()
                                    appContextMenu.open()
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton;
                                onClicked: {
                                    tileButton.pressAndHold()
                                }
                            }
                        }
                    }
                }

                // Trailing spacer so the last game can rest left of center
                Item {
                    width: Math.max(0, (appFlick.width - gameCellWidth) / 2 + centerShift)
                    height: 1
                }
            }

            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AlwaysOff
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 5
            visible: gameRepeater.count === 0

            Label {
                text: qsTr("This computer doesn't seem to have any applications or some applications are hidden")
                font.pointSize: 20
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
            }
        }
    }

    NavigableMessageDialog {
        id: quitAppDialog
        property string appName : ""
        property bool segueToStream : false
        property string nextAppName: ""
        property int nextAppIndex: 0
        text:qsTr("Are you sure you want to quit %1? Any unsaved progress will be lost.").arg(appName)
        standardButtons: Dialog.Yes | Dialog.No

        function quitApp() {
            var component = Qt.createComponent("QuitSegue.qml")
            var params = {"appName": appName, "quitRunningAppFn": function() { appModel.quitRunningApp() }}
            if (segueToStream) {
                // Store the session and app name if we're going to stream after
                // successfully quitting the old app.
                params.nextAppName = nextAppName
                params.nextSession = appModel.createSessionForApp(nextAppIndex)
            }
            else {
                params.nextAppName = null
                params.nextSession = null
            }

            stackView.push(component.createObject(stackView, params))
        }

        onAccepted: quitApp()
    }
}
