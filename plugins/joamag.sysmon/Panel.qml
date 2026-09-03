import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button showing one headline metric (CPU by default) plus a popup with
// live meters for CPU, memory, swap, GPU and disk, the sensors, and the
// busiest processes. Left click opens the popup, right click cycles the
// metric shown in the bar (persisted to shell.json), middle click refreshes.
Panel {
  id: root
  moduleName: "joamag.sysmon"
  ipcTarget: "joamag.sysmon"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can expose refresh/cycleMetric alongside open/close.
  manageIpc: false

  property var snapshot: null
  property var previous: null
  property real cpu: -1
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property string barMetric: Model.normalizeMetric(setting("barMetric", "cpu"))
  readonly property bool showLabel: setting("showLabel", true) === true
  readonly property int refreshIntervalSec: Math.max(1, Math.round(Number(setting("refreshIntervalSec", 3)) || 3))
  readonly property int processCount: Math.max(0, Math.round(Number(setting("processCount", 6)) || 0))
  readonly property string scriptPath: String(Qt.resolvedUrl("stats.sh")).replace(/^file:\/\//, "")

  readonly property bool loaded: snapshot !== null
  readonly property bool gpuAvailable: Model.hasGpu(snapshot)
  readonly property real memPercent: Model.memPercent(snapshot)
  readonly property real swapPercent: Model.swapPercent(snapshot)
  readonly property real diskPercent: Model.diskPercent(snapshot)
  readonly property real gpuPercent: Model.gpuPercent(snapshot)
  readonly property real gpuMemPercent: Model.gpuMemPercent(snapshot)
  readonly property real cpuTemp: Model.cpuTemp(snapshot)
  readonly property real gpuTemp: Model.gpuTemp(snapshot)

  readonly property string barValue: Model.barValue(barMetric, cpu, snapshot)
  readonly property real barLevel: Model.barLevel(barMetric, cpu, snapshot)
  readonly property string barIcon: Model.ICONS[barMetric]
  readonly property string barText: showLabel && !vertical ? barIcon + " " + barValue : barIcon
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // With a label next to the icon the button paints a text block wider than
  // an icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showLabel && !vertical ? button.labelWidth : 0

  // Short labels so all three fit one row at the default width; the tooltip
  // carries the full description.
  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: "Refresh now", run: function() { root.refresh() } },
    { label: "btop", icon: "󰆍", tooltip: "Open btop in a terminal", run: function() { root.openMonitor() } },
    {
      label: "Metric",
      icon: Model.ICONS[Model.nextMetric(root.barMetric, root.gpuAvailable)],
      tooltip: "Show " + Model.LABELS[Model.nextMetric(root.barMetric, root.gpuAvailable)].toLowerCase() + " in the bar",
      run: function() { root.cycleMetric() }
    }
  ]

  function refresh() {
    if (!statsProc.running) statsProc.running = true
  }

  function applySnapshot(raw) {
    var next = Model.parseSnapshot(raw)
    if (next.cpu_total === undefined) return
    var pct = Model.cpuPercent(snapshot, next)
    previous = snapshot
    snapshot = next
    if (pct >= 0) cpu = pct
  }

  // Persist the chosen metric inline on this widget's shell.json entry, like
  // the clock does with its format, so it survives a shell restart.
  function cycleMetric() {
    var next = Model.nextMetric(barMetric, gpuAvailable)
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.barMetric = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function openMonitor() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
    root.close()
  }

  function moveCursor(delta) {
    if (!cursorActive) { cursorActive = true; return }
    var n = actions.length
    cursorIndex = ((cursorIndex + delta) % n + n) % n
  }

  function activateCursor() {
    if (!cursorActive) return
    var action = actions[cursorIndex]
    if (action) action.run()
  }

  function meterColor(level) {
    if (level >= 90) return Color.urgent
    return root.foreground
  }

  IpcHandler {
    target: "joamag.sysmon"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function cycleMetric(): void { root.cycleMetric() }
    // Build stamp so `omarchy-shell joamag.sysmon version` tells which copy of
    // the code the shell is running after a reload.
    function version(): string { return "0.1.0" }
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
      cursorIndex = 0
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statsProc
    command: [root.scriptPath, String(root.opened ? root.processCount : 0)]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
  }

  // The bar label refreshes at the configured cadence; the popup speeds up to
  // once a second while open so the meters feel live.
  Timer {
    interval: (root.opened ? 1 : root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A first delta needs two samples; take the second one quickly instead of
  // waiting a full interval with "—" in the bar.
  Timer {
    interval: 600
    running: root.loaded && root.cpu < 0
    repeat: false
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    active: root.barLevel >= 90
    fontSize: Style.font.body
    horizontalMargin: root.showLabel && !root.vertical ? 8.75 : 6
    fixedWidth: root.showLabel && !root.vertical ? -1 : Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.cpu, root.snapshot)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleMetric()
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
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

        // ---------- Hero: icon · title/status · headline value ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.barIcon
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
              text: "System"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: (root.loaded
                ? "LOAD " + (root.snapshot.load1 || "—") + " · UP " + Model.formatUptime(root.snapshot.uptime_sec)
                : "COLLECTING").toUpperCase()
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
            text: root.barValue
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Meters ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          Meter {
            label: "CPU"
            detail: root.loaded ? Model.formatMhz(root.snapshot.cpu_mhz) + " · " + (root.snapshot.cpu_count || "?") + " cores" : ""
            level: root.cpu
          }
          Meter {
            label: "Memory"
            detail: root.loaded
              ? Model.formatKb(Number(root.snapshot.mem_total_kb) - Number(root.snapshot.mem_avail_kb)) + " / " + Model.formatKb(root.snapshot.mem_total_kb)
              : ""
            level: root.memPercent
          }
          Meter {
            visible: root.swapPercent >= 0 && Number(root.snapshot.swap_total_kb) > 0
            label: "Swap"
            detail: root.loaded
              ? Model.formatKb(Number(root.snapshot.swap_total_kb) - Number(root.snapshot.swap_free_kb)) + " / " + Model.formatKb(root.snapshot.swap_total_kb)
              : ""
            level: root.swapPercent
          }
          Meter {
            visible: root.gpuAvailable
            label: "GPU"
            detail: root.gpuAvailable ? String(root.snapshot.gpu_name || "") : ""
            level: root.gpuPercent
          }
          Meter {
            visible: root.gpuAvailable && root.gpuMemPercent >= 0
            label: "VRAM"
            detail: root.gpuAvailable ? Model.formatMb(root.snapshot.gpu_mem_used_mb) + " / " + Model.formatMb(root.snapshot.gpu_mem_total_mb) : ""
            level: root.gpuMemPercent
          }
          Meter {
            label: "Disk /"
            detail: root.loaded ? Model.formatKb(root.snapshot.disk_used_kb) + " / " + Model.formatKb(root.snapshot.disk_total_kb) : ""
            level: root.diskPercent
          }
        }

        // ---------- Sensors ----------
        Row {
          visible: isFinite(root.cpuTemp) || isFinite(root.gpuTemp)
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "CPU temp"; value: Model.formatTemp(root.cpuTemp) }
            InfoPair { label: "Load 5m / 15m"; value: root.loaded ? (root.snapshot.load5 || "—") + " / " + (root.snapshot.load15 || "—") : "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { visible: root.gpuAvailable; label: "GPU temp"; value: Model.formatTemp(root.gpuTemp) }
            InfoPair { label: "Uptime"; value: root.loaded ? Model.formatUptime(root.snapshot.uptime_sec) : "—" }
          }
        }

        // ---------- Processes ----------
        PanelSeparator {
          visible: root.processCount > 0
          foreground: root.foreground
        }

        Column {
          visible: root.processCount > 0
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "TOP PROCESSES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: !root.loaded || root.snapshot.procs.length === 0
            text: "Collecting…"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.loaded ? root.snapshot.procs : []

            Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: modelData.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width - cpuCol.width - memCol.width - parent.spacing * 2
              }
              Text {
                id: cpuCol
                textFormat: Text.PlainText
                text: isFinite(modelData.cpu) ? modelData.cpu.toFixed(1) + "%" : "—"
                color: root.foreground
                opacity: 0.8
                horizontalAlignment: Text.AlignRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: Style.space(52)
              }
              Text {
                id: memCol
                textFormat: Text.PlainText
                text: isFinite(modelData.mem) ? modelData.mem.toFixed(1) + "%" : "—"
                color: root.foreground
                opacity: 0.6
                horizontalAlignment: Text.AlignRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: Style.space(52)
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Item { width: parent.width - Style.space(52) * 2 - parent.spacing * 2; height: 1 }
            ColumnCaption { text: "CPU" }
            ColumnCaption { text: "MEM" }
          }
        }

        // ---------- Actions ----------
        PanelSeparator { foreground: root.foreground }

        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)

          // Every action gets the same cell and the same height, whatever its
          // icon or label measures, so the row reads as one control group.
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

  // Label + detail on the left, percentage on the right, progress bar below.
  component Meter: Column {
    property string label: ""
    property string detail: ""
    property real level: -1

    width: parent.width
    spacing: Style.space(4)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: detail
        color: root.foreground
        opacity: 0.55
        elide: Text.ElideRight
        width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.baseline: parent.children[0].baseline
      }
      Text {
        textFormat: Text.PlainText
        text: Model.formatPercent(level)
        color: root.meterColor(level)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Item {
      width: parent.width
      implicitHeight: Style.space(6)

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
        color: root.meterColor(level)
        width: level >= 0 ? Math.max(track.height, track.width * Math.min(1, level / 100)) : 0

        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 220 } }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component ColumnCaption: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.4
    horizontalAlignment: Text.AlignRight
    width: Style.space(52)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }
}
