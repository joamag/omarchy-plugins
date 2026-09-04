import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Battery glyph of the emptiest wireless peripheral in the bar, with its
// level; the popup lists every mouse, keyboard and headset with its charge
// and the time it has left. Left click opens, middle click refreshes, right
// click opens Solaar.
Panel {
  id: root
  moduleName: "joamag.peripherals"
  ipcTarget: "joamag.peripherals"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/version to open/close/toggle.
  manageIpc: false

  property var snapshot: null
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property bool showLevel: setting("showLevel", true) !== false
  readonly property int warnPct: Math.max(5, Math.min(50, Math.round(Number(setting("warnPct", 20)) || 20)))
  readonly property bool hideWhenHealthy: setting("hideWhenHealthy", false) === true
  readonly property int refreshIntervalSec: Math.max(10, Math.round(Number(setting("refreshIntervalSec", 60)) || 60))
  readonly property string scriptPath: String(Qt.resolvedUrl("peripherals.sh")).replace(/^file:\/\//, "")

  readonly property bool loaded: snapshot !== null
  readonly property var devices: loaded ? snapshot.devices : []
  readonly property var lowest: Model.lowestDevice(snapshot)
  readonly property var low: Model.lowDevices(snapshot, warnPct)
  readonly property bool solaar: loaded && snapshot.solaar === true
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barText: Model.barText(snapshot, showLevel, vertical)
  readonly property bool barHasLabel: showLevel && !vertical && lowest !== null
  readonly property real openPanelIndicatorWidth: barHasLabel ? button.labelWidth : 0

  // Footer actions: one row of equally sized buttons, like every other panel.
  // Solaar only earns a button when it is installed.
  readonly property var actions: {
    var list = [{ label: "Refresh", icon: "󰑐", tooltip: "Refresh now", run: function() { root.refresh() } }]
    if (root.solaar) list.push({ label: "Solaar", icon: "󰍽", tooltip: "Open Solaar", run: function() { root.openSolaar() } })
    return list
  }

  function refresh() {
    if (!snapshotProc.running) snapshotProc.running = true
  }

  function applySnapshot(raw) {
    snapshot = Model.parseSnapshot(raw)
    if (cursorIndex >= actions.length) cursorIndex = Math.max(0, actions.length - 1)
  }

  function openSolaar() {
    if (!root.solaar) return
    if (root.bar) root.bar.run("omarchy-launch-or-focus solaar")
    root.close()
  }

  function isLow(device) {
    return root.low.indexOf(device) >= 0
  }

  function moveCursor(delta) {
    if (!cursorActive) { cursorActive = true; return }
    var n = actions.length
    if (n === 0) return
    cursorIndex = ((cursorIndex + delta) % n + n) % n
  }

  function activateCursor() {
    if (!cursorActive) return
    var action = actions[cursorIndex]
    if (action) action.run()
  }

  IpcHandler {
    target: "joamag.peripherals"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function version(): string { return "0.1.0" }
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
      cursorIndex = 0
    }
  }

  visible: devices.length > 0 && !(hideWhenHealthy && low.length === 0)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Process {
    id: snapshotProc
    command: [root.scriptPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
  }

  // upower announces every change as a line; a burst of them (a device
  // waking up touches several properties at once) folds into one refresh.
  // --pdeathsig takes the watcher down with the shell.
  Process {
    id: monitorProc
    command: ["setpriv", "--pdeathsig", "TERM", "upower", "--monitor"]
    running: true
    stdout: SplitParser { onRead: function(line) { changeDebounce.restart() } }
    onExited: monitorRestart.restart()
  }

  Timer {
    id: changeDebounce
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  // A watcher that dies would leave the widget on the fallback interval alone.
  Timer {
    id: monitorRestart
    interval: 5000
    repeat: false
    onTriggered: monitorProc.running = true
  }

  // Batteries drain slowly, so the timer is only there for a change the
  // watcher missed.
  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    // A device at or below the threshold turns the label urgent.
    active: root.low.length > 0
    fontSize: Style.font.body
    horizontalMargin: root.barHasLabel ? 8.75 : 6
    fixedWidth: root.barHasLabel ? -1 : Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.snapshot, root.warnPct)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openSolaar()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx !== 0 ? dx : dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "o") root.openSolaar()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: device icon · title/status · emptiest level ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.lowest ? Model.typeIcon(root.lowest) : Model.ICON
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroValue.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Peripherals"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: Model.heroStatus(root.snapshot, root.warnPct)
              color: root.low.length > 0 ? Color.urgent : Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroValue
            textFormat: Text.PlainText
            text: Model.levelLabel(root.lowest)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Devices ----------
        Column {
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "DEVICES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.devices.length === 0
            text: root.loaded ? "No wireless device is reporting a battery." : "Scanning…"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Repeater {
            model: root.devices

            DeviceRow {
              required property var modelData
              width: parent.width
              device: modelData
            }
          }
        }

        // ---------- Actions ----------
        PanelSeparator { foreground: root.foreground }

        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)

          // Same cell and same height for every action, whatever its icon or
          // label measures, so the row reads as one control group.
          readonly property real cellWidth: (width - spacing * (root.actions.length - 1)) / root.actions.length
          readonly property real cellHeight: Style.spacing.controlHeight + Style.space(6)

          Repeater {
            model: root.actions

            Button {
              required property var modelData
              required property int index
              width: actionRow.cellWidth
              height: actionRow.cellHeight
              iconText: modelData.icon
              iconSize: Style.font.title
              text: modelData.label
              tooltipText: modelData.tooltip
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              hasCursor: root.cursorActive && root.cursorIndex === index
              onClicked: modelData.run()
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.cursorIndex = index
                }
              }
            }
          }
        }
      }
    }
  }

  // One device: type glyph, name over detail line, level on the right, and a
  // charge meter underneath. Rows carry no action, so they take no cursor.
  component DeviceRow: CursorSurface {
    id: row
    required property var device

    readonly property bool urgent: root.isLow(device)
    readonly property bool charging: Model.isCharging(device)
    readonly property real charge: Model.chargePercent(device)

    hasCursor: false
    current: false
    foreground: root.foreground
    implicitHeight: inner.implicitHeight + Style.spacing.xl

    Column {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: Model.typeIcon(row.device)
          color: row.urgent ? Color.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - Style.space(22) - levelText.width - parent.spacing * 2
          spacing: Style.space(1)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            textFormat: Text.PlainText
            text: Model.deviceName(row.device)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: Model.deviceDetail(row.device)
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Text {
          id: levelText
          textFormat: Text.PlainText
          text: Model.batteryGlyph(row.charge, row.charging) + " " + Model.levelLabel(row.device)
          color: row.urgent ? Color.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: row.urgent
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Charge meter under each device.
      Item {
        width: parent.width - Style.space(30)
        x: Style.space(30)
        implicitHeight: Style.space(5)

        Rectangle {
          id: track
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        Rectangle {
          anchors.left: track.left
          anchors.verticalCenter: track.verticalCenter
          height: track.height
          radius: track.radius
          color: row.urgent ? Color.urgent : root.foreground
          width: isFinite(row.charge) ? Math.max(track.height, track.width * Math.min(1, row.charge / 100)) : 0

          Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
      }
    }
  }
}
