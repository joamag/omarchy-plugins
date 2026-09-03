import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Disk icon with the root filesystem's usage in the bar; the popup lists
// every mount with a usage meter, lets removable media be mounted, unmounted
// or ejected, and empties the trash or the package cache. Left click opens,
// middle click refreshes, right click opens the file manager.
Panel {
  id: root
  moduleName: "joamag.disks"
  ipcTarget: "joamag.disks"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/version to open/close/toggle.
  manageIpc: false

  property var snapshot: null
  property bool loading: false
  property string lastError: ""
  // Row key an action is running against; its row shows a spinner and
  // ignores further clicks until the script returns.
  property string busyKey: ""
  // Destructive cleanups ask twice: the first activation arms the row for a
  // few seconds, the second one runs it.
  property string armedKey: ""
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property string barMode: String(setting("barMode", "percent") || "percent")
  readonly property int warnPct: Math.max(50, Math.min(99, Math.round(Number(setting("warnPct", 90)) || 90)))
  readonly property int refreshIntervalSec: Math.max(5, Math.round(Number(setting("refreshIntervalSec", 30)) || 30))
  readonly property string scriptPath: String(Qt.resolvedUrl("disks.sh")).replace(/^file:\/\//, "")

  readonly property bool loaded: Model.isLoaded(snapshot)
  readonly property var rootMount: Model.rootMount(snapshot)
  readonly property var rows: Model.visibleRows(snapshot)
  readonly property var hotMounts: Model.overThreshold(snapshot, warnPct)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barText: Model.barText(snapshot, barMode, vertical)
  readonly property bool barHasLabel: !vertical && rootMount !== null && barMode !== "none"
  readonly property real openPanelIndicatorWidth: barHasLabel ? button.labelWidth : 0

  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: "Refresh now", run: function() { root.refresh() } },
    { label: "Files", icon: "󰉋", tooltip: "Open the file manager", run: function() { root.openFiles("") } },
    { label: "Speed test", icon: "󰓅", tooltip: "Measure the system disk", run: function() { root.speedTest() } }
  ]

  // Keyboard cursor walks the list rows (skipping group headers) and then
  // the footer actions, all on one index.
  readonly property int cursorCount: rows.length + actions.length

  function refresh() {
    if (snapshotProc.running) return
    loading = true
    snapshotProc.running = true
  }

  function applySnapshot(raw) {
    var next = Model.parseSnapshot(raw)
    // A refresh that came back empty keeps the last list rather than
    // flashing an empty popup.
    if (next.mounts.length === 0 && loaded && snapshot.mounts.length > 0) return
    snapshot = next
    if (armedKey !== "" && !rows.some(function(r) { return r.key === armedKey })) armedKey = ""
    if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)
  }

  function act(args, key) {
    if (actionProc.running) return false
    busyKey = key
    lastError = ""
    actionProc.command = [root.scriptPath].concat(args)
    actionProc.running = true
    return true
  }

  function applyAction(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts[0] === "error") lastError = parts.slice(1).join("\t")
    }
  }

  function openFiles(path) {
    if (!root.bar) return
    var target = String(path || "").replace(/'/g, "")
    root.bar.run(target !== "" ? "xdg-open '" + target + "'" : "omarchy-launch-nautilus")
    root.close()
  }

  function speedTest() {
    if (root.bar) root.bar.run("omarchy-shell shell summon omarchy.disk-speedtest '{}'")
    root.close()
  }

  function unmount(mount) {
    if (mount && mount.removable) act(["unmount", mount.target], mount.key)
  }

  function eject(mount) {
    if (mount && mount.removable && mount.disk) act(["eject", mount.disk], mount.key)
  }

  function mountVolume(volume) {
    if (volume && volume.path) act(["mount", volume.path], volume.key)
  }

  function emptyTrash() {
    act(["empty-trash"], "trash")
  }

  // paccache needs root, so it runs in a floating terminal where sudo can
  // ask; the popup refreshes on its next tick.
  function cleanCache() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation 'sudo paccache -rk1'")
    root.close()
  }

  // Cleanup rows arm on the first activation and run on the second.
  function activateCleanup(row) {
    if (!row) return
    if (armedKey !== row.key) {
      armedKey = row.key
      disarmTimer.restart()
      return
    }
    armedKey = ""
    disarmTimer.stop()
    if (row.kind === "trash") emptyTrash()
    else if (row.kind === "cache") cleanCache()
  }

  function activateRow(row) {
    if (!row || Model.isHeader(row)) return
    if (row.kind === "mount") openFiles(row.target)
    else if (row.kind === "volume") mountVolume(row)
    else activateCleanup(row)
  }

  // `u`: unmount a removable mount, or mount an unmounted volume.
  function toggleMount(row) {
    if (!row) return
    if (row.kind === "mount") unmount(row)
    else if (row.kind === "volume") mountVolume(row)
  }

  function cursorRow() {
    return cursorActive && cursorIndex < rows.length ? rows[cursorIndex] : null
  }

  function moveCursor(delta) {
    var n = cursorCount
    if (n === 0) return
    if (!cursorActive) {
      cursorActive = true
      var first = Model.firstRowIndex(rows)
      cursorIndex = first >= 0 ? first : rows.length
      return
    }
    var idx = cursorIndex
    for (var step = 0; step < n; step++) {
      idx = ((idx + delta) % n + n) % n
      if (idx >= rows.length || !Model.isHeader(rows[idx])) break
    }
    cursorIndex = idx
  }

  function activateCursor() {
    if (!cursorActive) return
    if (cursorIndex < rows.length) {
      activateRow(rows[cursorIndex])
      return
    }
    var action = actions[cursorIndex - rows.length]
    if (action) action.run()
  }

  IpcHandler {
    target: "joamag.disks"

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
      cursorActive = false
      cursorIndex = 0
      armedKey = ""
      refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: snapshotProc
    command: [root.scriptPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
    onExited: root.loading = false
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyAction(text) }
    onExited: {
      root.busyKey = ""
      root.refresh()
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: disarmTimer
    interval: 4000
    onTriggered: root.armedKey = ""
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    // A mount over the threshold turns the label urgent.
    active: root.hotMounts.length > 0
    dimmed: root.loading && !root.loaded
    fontSize: Style.font.body
    horizontalMargin: root.barHasLabel ? 8.75 : 6
    fixedWidth: root.barHasLabel ? -1 : Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.snapshot, root.warnPct)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openFiles("")
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
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
        else if (text === "u") root.toggleMount(root.cursorRow())
        else if (text === "e") root.eject(root.cursorRow())
        else if (text === "o") root.openFiles("")
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: icon · title/status · root usage ----------
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
              text: "Disks"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: {
                var parts = [Model.heroStatus(root.snapshot, root.warnPct)]
                if (root.loading) parts.push("Updating")
                return parts.join(" · ").toUpperCase()
              }
              color: root.hotMounts.length > 0 ? Color.urgent : Qt.darker(root.foreground, 1.4)
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
            text: root.rootMount ? Model.formatKb(root.rootMount.availKb) : "—"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          visible: root.rootMount !== null
          textFormat: Text.PlainText
          text: root.rootMount ? "free on the root filesystem · " + Model.formatKb(root.rootMount.usedKb) + " of " + Model.formatKb(root.rootMount.sizeKb) + " used" : ""
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
          width: parent.width
        }

        // ---------- Mounts, volumes and cleanup ----------
        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            visible: !root.loaded
            text: "Loading…"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            width: parent.width
          }

          Repeater {
            model: root.rows

            DiskRow {
              required property var modelData
              required property int index
              width: parent.width
              row: modelData
              rowIndex: index
            }
          }
        }

        // ---------- Footer: status line + actions ----------
        PanelSeparator { foreground: root.foreground }

        Text {
          visible: root.lastError !== ""
          textFormat: Text.PlainText
          text: root.lastError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          width: parent.width
        }

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
              hasCursor: root.cursorActive && root.cursorIndex === root.rows.length + index
              onClicked: modelData.run()
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.cursorIndex = root.rows.length + index
                }
              }
            }
          }
        }
      }
    }
  }

  // One entry of the flattened list: a group header, a mount with its usage
  // meter, an unmounted volume, or a cleanup row. Actions sit at the right
  // edge and show while the row holds the cursor.
  component DiskRow: Item {
    id: entry
    required property var row
    required property int rowIndex

    readonly property bool header: Model.isHeader(row)
    readonly property string kind: header ? "" : String(row.kind)
    readonly property bool busy: !header && root.busyKey !== "" && root.busyKey === row.key
    readonly property bool armed: !header && root.armedKey !== "" && root.armedKey === row.key
    readonly property bool hasCursor: !header && root.cursorActive && root.cursorIndex === rowIndex
    readonly property bool hot: kind === "mount" && isFinite(row.pct) && row.pct >= root.warnPct && row.fstype !== "iso9660"
    readonly property string title: {
      if (header) return ""
      if (kind === "mount") return Model.mountName(row)
      if (kind === "volume") return Model.volumeName(row)
      if (kind === "trash") return "Trash"
      return "Package cache"
    }
    readonly property string detail: {
      if (header) return ""
      if (kind === "mount") return Model.mountDetail(row)
      if (kind === "volume") return Model.volumeDetail(row)
      if (kind === "trash") return Model.trashDetail(root.snapshot)
      return Model.cacheDetail(root.snapshot)
    }
    readonly property string glyph: {
      if (header) return ""
      if (entry.busy) return "󰑐"
      if (kind === "mount") return row.removable ? "󱊞" : (row.target === "/" ? "󰋊" : "󰉋")
      if (kind === "volume") return "󱊟"
      if (kind === "trash") return "󰩹"
      return "󰏗"
    }
    // What Enter or a click does, spelled out at the right edge.
    readonly property string actionLabel: {
      if (header) return ""
      if (kind === "mount") return row.removable ? "open · u unmount · e eject" : "open"
      if (kind === "volume") return "mount"
      if (entry.armed) return "press again to confirm"
      if (kind === "trash") return root.snapshot && root.snapshot.trashItems > 0 ? "empty" : ""
      return "clean (sudo)"
    }

    implicitHeight: header ? headerItem.implicitHeight : surface.implicitHeight

    Item {
      id: headerItem
      visible: entry.header
      width: parent.width
      implicitHeight: headerText.implicitHeight + Style.space(entry.rowIndex === 0 ? 4 : 12)

      PanelSectionHeader {
        id: headerText
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(2)
        text: entry.header ? entry.row.title + " · " + entry.row.count : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }

    CursorSurface {
      id: surface
      visible: !entry.header
      width: parent.width
      implicitHeight: inner.implicitHeight + Style.spacing.lg
      hasCursor: entry.hasCursor
      foreground: root.foreground

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
            text: entry.glyph
            color: entry.hot ? Color.urgent : root.foreground
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
              running: entry.busy
              onRunningChanged: if (!running) rotation = 0
            }
          }

          Column {
            width: parent.width - Style.space(22) - trailing.width - parent.spacing * 2
            spacing: Style.space(1)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              textFormat: Text.PlainText
              text: entry.title
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: entry.kind === "mount"
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: entry.detail
              visible: text !== ""
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: trailing
            textFormat: Text.PlainText
            text: entry.header ? "" : (entry.kind === "mount" && isFinite(entry.row.pct) ? Model.formatPercent(entry.row.pct) : "")
            color: entry.hot ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: entry.hot
            horizontalAlignment: Text.AlignRight
            width: text !== "" ? Style.space(40) : 0
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Usage meter under each mount.
        Item {
          visible: entry.kind === "mount"
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
            color: entry.hot ? Color.urgent : root.foreground
            width: entry.kind === "mount" && isFinite(entry.row.pct) ? Math.max(track.height, track.width * Math.min(1, entry.row.pct / 100)) : 0

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
          }
        }

        // The available action, visible while the row holds the cursor.
        Text {
          visible: !entry.header && entry.hasCursor && entry.actionLabel !== ""
          textFormat: Text.PlainText
          text: entry.actionLabel
          color: entry.armed ? Color.urgent : root.foreground
          opacity: entry.armed ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          width: parent.width
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: entry.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.cursorIndex = entry.rowIndex
        }
        onClicked: function(mouse) {
          if (entry.busy) return
          if (mouse.button === Qt.RightButton) root.toggleMount(entry.row)
          else root.activateRow(entry.row)
        }
      }
    }
  }
}
