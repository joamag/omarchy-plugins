import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Checkbox icon with the number of tasks left in the bar; the popup lists a
// plain todo.txt file with what is left first and the latest ticks after,
// and lets you tick, add, prioritise, delete and archive from there. Left
// click opens, middle click refreshes, right click opens the file.
Panel {
  id: root
  moduleName: "joamag.todo"
  ipcTarget: "joamag.todo"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/add/version to open/close/toggle.
  manageIpc: false

  property var snapshot: null
  property bool loading: false
  // A refresh asked for while the script is still running is replayed when
  // it exits.
  property bool refreshPending: false
  // Row key an edit is running against; its row shows a spinner and ignores
  // further clicks until the script returns.
  property string busyKey: ""
  // Destructive things ask twice: the first activation arms the row (or the
  // archive button) for a few seconds, the second one runs it.
  property string armedKey: ""
  property string lastError: ""
  property bool cursorActive: false
  property int cursorIndex: 0
  // The add field is open at the bottom of the list.
  property bool adding: false

  readonly property string file: String(setting("file", "") || "")
  readonly property string barMode: String(setting("barMode", "pending") || "pending")
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true
  readonly property int doneLimit: Math.max(0, Math.round(Number(setting("doneLimit", 5)) || 0))
  readonly property int refreshIntervalSec: Math.max(10, Math.round(Number(setting("refreshIntervalSec", 60)) || 60))
  readonly property string scriptPath: String(Qt.resolvedUrl("todo.sh")).replace(/^file:\/\//, "")
  readonly property string filePath: file !== "" ? file : Quickshell.env("HOME") + "/.local/share/omarchy/todo.txt"
  readonly property var scriptEnvironment: file !== "" ? ({ TODO_FILE: file }) : ({})

  readonly property bool loaded: Model.isLoaded(snapshot)
  readonly property var rows: Model.visibleRows(snapshot, doneLimit)
  readonly property var counts: Model.counts(snapshot)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barText: Model.barText(snapshot, barMode, vertical)
  readonly property bool barHasLabel: !vertical && loaded && barMode !== "none" && counts.pending > 0
  readonly property real openPanelIndicatorWidth: barHasLabel ? button.labelWidth : 0

  readonly property var actions: [
    { label: "Add", icon: "󰐕", tooltip: "Add a task", run: function() { root.startAdding() } },
    { label: root.armedKey === "archive" ? "Sure?" : "Archive", icon: "󰆼", tooltip: "Move the done tasks to done.txt", run: function() { root.archive() } },
    { label: "Edit file", icon: "󰏫", tooltip: "Open todo.txt in your editor", run: function() { root.editFile() } }
  ]

  // Keyboard cursor walks the task rows (skipping group headers) and then
  // the footer actions, all on one index.
  readonly property int cursorCount: rows.length + actions.length

  function toneColor(tone) {
    switch (tone) {
    case "urgent": return Color.urgent
    case "accent": return Color.accent
    default: return foreground
    }
  }

  function run(args) {
    if (proc.running) return false
    loading = true
    proc.command = [root.scriptPath].concat(args)
    proc.running = true
    return true
  }

  function refresh() {
    if (proc.running) { refreshPending = true; return }
    run(["list"])
  }

  function applySnapshot(raw) {
    var next = Model.parseSnapshot(raw)
    busyKey = ""
    if (next.error !== "") {
      // A refused edit keeps the last list on screen and says why; the
      // script's own listing follows in the same output when there is one.
      lastError = next.error
      if (next.tasks.length === 0 && loaded) return
    } else {
      lastError = ""
    }
    snapshot = next
    if (armedKey !== "" && armedKey !== "archive" && !rows.some(function(r) { return r.key === armedKey })) armedKey = ""
    if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)
  }

  function act(args, key) {
    if (busyKey !== "") return
    if (run(args)) busyKey = key
  }

  function toggleTask(row) {
    if (!row || Model.isHeader(row)) return
    act(["toggle", String(row.line), row.text], row.key)
  }

  // Delete arms on the first press and runs on the second within four seconds.
  function removeTask(row) {
    if (!row || Model.isHeader(row)) return
    if (armedKey !== row.key) {
      armedKey = row.key
      disarmTimer.restart()
      return
    }
    armedKey = ""
    disarmTimer.stop()
    act(["remove", String(row.line), row.text], row.key)
  }

  function cyclePriority(row) {
    if (!row || Model.isHeader(row)) return
    var next = Model.nextPriority(row.priority)
    act(["priority", String(row.line), row.text, next === "" ? "-" : next], row.key)
  }

  function archive() {
    if (counts.done === 0) return
    if (armedKey !== "archive") {
      armedKey = "archive"
      disarmTimer.restart()
      return
    }
    armedKey = ""
    disarmTimer.stop()
    act(["archive"], "archive")
  }

  function startAdding() {
    adding = true
    addField.text = ""
    Qt.callLater(function() { addField.forceActiveFocus() })
  }

  function cancelAdding() {
    adding = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Enter in the add field: append and stay in the field, so several tasks
  // can be typed in a row; an empty Enter leaves it.
  function commitAdd() {
    var text = String(addField.text || "").trim()
    if (text === "") { cancelAdding(); return }
    if (run(["add", text])) addField.text = ""
  }

  function editFile() {
    if (!root.bar) return
    root.bar.run("omarchy-launch-config-editor \"" + filePath.replace(/"/g, "") + "\"")
    root.close()
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
      toggleTask(rows[cursorIndex])
      return
    }
    var action = actions[cursorIndex - rows.length]
    if (action) action.run()
  }

  IpcHandler {
    target: "joamag.todo"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    // Scripting hook: `omarchy-shell joamag.todo add "Buy milk +groceries"`.
    function add(text: string): string {
      var trimmed = String(text || "").trim()
      if (trimmed === "") return "error: text required"
      return root.run(["add", trimmed]) ? "ok" : "busy"
    }
    function version(): string { return "0.1.0" }
  }

  onFileChanged: refresh()

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      armedKey = ""
      refresh()
    } else if (adding) {
      cancelAdding()
    }
  }

  visible: !(hideWhenEmpty && loaded && counts.pending === 0)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Process {
    id: proc
    environment: root.scriptEnvironment
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
    onExited: {
      root.loading = false
      root.busyKey = ""
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  // The file is the source of truth and may be edited by hand or by another
  // todo.txt tool; a change on disk refreshes the popup within a beat.
  FileView {
    path: root.filePath
    watchChanges: true
    printErrors: false
    onFileChanged: changeDebounce.restart()
  }

  Timer {
    id: changeDebounce
    interval: 300
    repeat: false
    onTriggered: root.refresh()
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
    // A priority A task turns the label urgent.
    active: root.counts.urgent > 0
    dimmed: root.loaded && root.counts.pending === 0
    fontSize: Style.font.body
    horizontalMargin: root.barHasLabel ? 8.75 : 6
    fixedWidth: root.barHasLabel ? -1 : Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.snapshot)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.editFile()
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.adding
      onMoveRequested: function(dx, dy) { root.moveCursor(dx !== 0 ? dx : dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.removeTask(root.cursorRow())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "a") root.startAdding()
        else if (text === "x") root.removeTask(root.cursorRow())
        else if (text === "p") root.cyclePriority(root.cursorRow())
        else if (text === "r") root.refresh()
        else if (text === "e") root.editFile()
        else if (text === "A") root.archive()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: column.implicitHeight > scrollArea.height
        }

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          // ---------- Hero: icon · title/status · tasks left ----------
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
                text: "To do"
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
                  var parts = [Model.heroStatus(root.snapshot)]
                  if (root.loading) parts.push("Updating")
                  return parts.join(" · ").toUpperCase()
                }
                color: root.counts.urgent > 0 ? Color.urgent : Qt.darker(root.foreground, 1.4)
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
              text: root.loaded ? String(root.counts.pending) : "—"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // ---------- Tasks ----------
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              visible: root.rows.length === 0 && !root.adding
              text: root.loaded ? "Nothing to do. Press a to add a task." : "Loading…"
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Repeater {
              model: root.rows

              TaskRow {
                required property var modelData
                required property int index
                width: parent.width
                row: modelData
                rowIndex: index
              }
            }
          }

          // Add field, opened from the footer or with `a`. Enter appends and
          // stays for the next one; Esc leaves. "(A) text" sets a priority,
          // +project and @context go straight into the file.
          Row {
            visible: root.adding
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: addField
              width: parent.width - addHint.width - parent.spacing
              placeholderText: "New task, e.g. (A) Call the bank @phone +admin"
              foreground: root.foreground
              font.family: root.fontFamily

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelAdding()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitAdd()
                  event.accepted = true
                }
              }
            }

            Text {
              id: addHint
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Enter adds · Esc done"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: !root.adding && root.rows.length > 0
            textFormat: Text.PlainText
            text: "a add · x delete · p priority · Enter tick · A archive done"
            color: root.foreground
            opacity: 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
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
                foreground: index === 1 && root.armedKey === "archive" ? Color.urgent : root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                opacity: index === 1 && root.counts.done === 0 ? 0.45 : 1
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
  }

  // One entry of the flattened list: a group header ("TO DO · 4") or a task
  // with its checkbox glyph, title, detail line and priority letter.
  component TaskRow: Item {
    id: entry
    required property var row
    required property int rowIndex

    readonly property bool header: Model.isHeader(row)
    readonly property bool busy: !header && root.busyKey !== "" && root.busyKey === row.key
    readonly property bool armed: !header && root.armedKey !== "" && root.armedKey === row.key
    readonly property bool hasCursor: !header && root.cursorActive && root.cursorIndex === rowIndex
    readonly property color tone: header ? root.foreground : root.toneColor(Model.priorityTone(row))

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
        text: entry.header
          ? entry.row.title + (entry.row.shown !== undefined && entry.row.shown < entry.row.count ? " · " + entry.row.shown + " OF " + entry.row.count : " · " + entry.row.count)
          : ""
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
      opacity: !entry.header && entry.row.done && !entry.busy ? 0.6 : 1

      Row {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: entry.header ? "" : (entry.busy ? "󰑐" : Model.glyph(entry.row))
          color: !entry.header && entry.row.done ? Color.accent : entry.tone
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
          width: parent.width - Style.space(22) - priorityText.width - parent.spacing * 2
          spacing: Style.space(1)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            textFormat: Text.PlainText
            text: entry.header ? "" : String(entry.row.title || entry.row.text || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.strikeout: !entry.header && entry.row.done === true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: entry.header ? "" : (entry.armed ? "press again to delete" : Model.taskDetail(entry.row))
            visible: text !== ""
            color: entry.armed ? Color.urgent : root.foreground
            opacity: entry.armed ? 1 : 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        // The priority letter, in its tone, or nothing.
        Text {
          id: priorityText
          textFormat: Text.PlainText
          text: entry.header ? "" : String(entry.row.priority || "")
          color: entry.tone
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          horizontalAlignment: Text.AlignRight
          width: text !== "" ? Style.space(18) : 0
          anchors.verticalCenter: parent.verticalCenter
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
          if (mouse.button === Qt.RightButton) root.removeTask(entry.row)
          else root.toggleTask(entry.row)
        }
      }
    }
  }
}
