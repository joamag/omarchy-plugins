import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Whale icon plus running-container count in the bar; the popup lists every
// container and toggles it with a click. Left click opens, middle click
// refreshes, right click opens lazydocker.
Panel {
  id: root
  moduleName: "joamag.docker"
  ipcTarget: "joamag.docker"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/version to open/close/toggle.
  manageIpc: false

  property var snapshot: null
  property bool cursorActive: false
  property int cursorIndex: 0
  // Container id an action is running against; its row shows a spinner-ish
  // icon and ignores further clicks until docker returns.
  property string busyId: ""

  readonly property bool showCount: setting("showCount", true) === true
  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true
  readonly property int refreshIntervalSec: Math.max(2, Math.round(Number(setting("refreshIntervalSec", 10)) || 10))
  readonly property string scriptPath: String(Qt.resolvedUrl("docker.sh")).replace(/^file:\/\//, "")

  readonly property bool loaded: snapshot !== null
  readonly property bool ok: Model.isOk(snapshot)
  readonly property bool missing: loaded && snapshot.state === "missing"
  readonly property var containers: ok ? snapshot.containers : []
  readonly property int runningCount: Model.runningCount(snapshot)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barText: Model.barText(snapshot, showCount, vertical)
  readonly property real openPanelIndicatorWidth: showCount && ok && !vertical ? button.labelWidth : 0

  // Footer actions: one row of equally sized buttons, like every other panel.
  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: "Refresh the container list", run: function() { root.refresh() } },
    { label: "lazydocker", icon: "󰆍", tooltip: "Open lazydocker in a terminal", run: function() { root.openTui() } }
  ]

  // Keyboard cursor walks the container rows first, then the footer actions.
  readonly property int cursorCount: containers.length + actions.length

  function refresh() {
    if (!statsProc.running) statsProc.running = true
  }

  function applySnapshot(raw) {
    var next = Model.parseSnapshot(raw)
    snapshot = next
    if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)
  }

  function act(command, containerId) {
    if (!containerId || actionProc.running) return
    busyId = containerId
    actionProc.command = ["docker", command, containerId]
    actionProc.running = true
  }

  function toggleContainer(container) {
    if (!container || root.busyId !== "") return
    act(Model.toggleCommand(container), container.id)
  }

  function restartContainer(container) {
    if (!container || root.busyId !== "") return
    act("restart", container.id)
  }

  function openTui() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui omarchy-launch-docker-tui")
    root.close()
  }

  function startDaemon() {
    // systemd asks polkit, so the shell's own agent shows the prompt.
    if (root.bar) root.bar.run("systemctl start docker.socket docker.service")
    daemonRetry.restart()
  }

  function enableSudoless() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-sudoless-docker")
    root.close()
  }

  function moveCursor(delta) {
    if (!cursorActive) { cursorActive = true; return }
    var n = cursorCount
    if (n === 0) return
    cursorIndex = ((cursorIndex + delta) % n + n) % n
  }

  function activateCursor() {
    if (!cursorActive) return
    if (cursorIndex < containers.length) {
      toggleContainer(containers[cursorIndex])
      return
    }
    var action = actions[cursorIndex - containers.length]
    if (action) action.run()
  }

  IpcHandler {
    target: "joamag.docker"

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

  visible: !missing && !(hideWhenIdle && ok && runningCount === 0)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Process {
    id: statsProc
    command: [root.scriptPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
  }

  Process {
    id: actionProc
    onExited: {
      root.busyId = ""
      root.refresh()
    }
  }

  // The bar count refreshes at the configured cadence; the popup speeds up
  // while open so a start/stop is reflected promptly.
  Timer {
    interval: (root.opened ? 3 : root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Poll a few times after asking systemd to start the daemon, so the popup
  // flips to the container list as soon as the socket appears.
  Timer {
    id: daemonRetry
    interval: 1500
    repeat: true
    property int attempts: 0
    onTriggered: {
      root.refresh()
      if (++attempts >= 6 || root.ok) { attempts = 0; stop() }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    dimmed: root.loaded && !root.ok
    fontSize: Style.font.body
    horizontalMargin: root.showCount && root.ok && !root.vertical ? 8.75 : 6
    fixedWidth: root.showCount && root.ok && !root.vertical ? -1 : Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.snapshot)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openTui()
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

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: whale · title/status · running count ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: Model.ICON
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
              text: "Docker"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: Model.heroStatus(root.snapshot)
              color: Qt.darker(root.foreground, 1.4)
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
            text: root.ok ? String(root.runningCount) : "—"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Unavailable: explanation plus the one fix that applies ----------
        Column {
          visible: root.loaded && !root.ok
          width: parent.width
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: Model.stateTitle(root.snapshot)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: Model.stateDetail(root.snapshot)
            visible: text !== ""
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Button {
            visible: root.loaded && root.snapshot.state === "stopped"
            width: parent.width
            height: actionRow.cellHeight
            iconText: "󰐊"
            iconSize: Style.font.title
            text: "Start daemon"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.startDaemon()
          }

          Button {
            visible: root.loaded && root.snapshot.state === "denied"
            width: parent.width
            height: actionRow.cellHeight
            iconText: "󰟵"
            iconSize: Style.font.title
            text: "Enable sudoless Docker"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.enableSudoless()
          }
        }

        // ---------- Containers ----------
        Column {
          visible: root.ok
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "CONTAINERS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.containers.length === 0
            text: "No containers. Run one and it shows up here."
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Repeater {
            model: root.containers

            ContainerRow {
              required property var modelData
              required property int index
              width: parent.width
              container: modelData
              rowIndex: index
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
              hasCursor: root.cursorActive && root.cursorIndex === root.containers.length + index
              onClicked: modelData.run()
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.cursorIndex = root.containers.length + index
                }
              }
            }
          }
        }
      }
    }
  }

  // One container: state glyph, name over image, status on the right. Click
  // toggles start/stop, right click restarts.
  component ContainerRow: CursorSurface {
    id: row
    required property var container
    required property int rowIndex

    readonly property bool running: Model.isRunning(container)
    readonly property bool busy: root.busyId !== "" && root.busyId === container.id

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: false
    foreground: root.foreground
    implicitHeight: inner.implicitHeight + Style.spacing.xl
    opacity: running || busy ? 1.0 : 0.6

    Row {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: row.busy ? "󰑐" : Model.stateIcon(row.container)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter

        RotationAnimation on rotation {
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
          running: row.busy
          onRunningChanged: if (!running) rotation = 0
        }
      }

      Column {
        width: parent.width - Style.space(22) - statusText.width - parent.spacing * 2
        spacing: Style.space(1)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: row.container.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: Model.shortImage(row.container.image)
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Text {
        id: statusText
        textFormat: Text.PlainText
        text: row.busy ? "working" : row.container.status
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        width: Math.min(implicitWidth, Style.space(120))
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: row.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.cursorIndex = row.rowIndex
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.restartContainer(row.container)
        else root.toggleContainer(row.container)
      }
    }
  }
}
