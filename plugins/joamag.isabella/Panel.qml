import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Broom icon with the day's pending and done counts in the bar; the popup
// lists the checklist with pending work first and lets you tick, cancel or
// delay tasks, and step through days. Left click opens, middle click
// refreshes, right click opens Isabella in the browser.
Panel {
  id: root
  moduleName: "joamag.isabella"
  ipcTarget: "joamag.isabella"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/version to open/close/toggle.
  manageIpc: false

  property var result: null
  property string day: Model.todayIso()
  property bool loading: false
  // A refresh asked for while the script is still running (settings landing
  // right after the first fetch, for example) is replayed when it exits.
  property bool refreshPending: false
  // Row key ("task:3" / "sub:7") an action is running against; the row shows
  // a spinner and ignores further clicks until Isabella answers.
  property string busyKey: ""
  property bool cursorActive: false
  property int cursorIndex: 0
  // Credentials handed to isabella.sh configure through the environment for
  // the duration of that one run; cleared as soon as it exits.
  property var pendingCredentials: null

  readonly property int refreshIntervalSec: Math.max(30, Math.round(Number(setting("refreshIntervalSec", 300)) || 300))
  readonly property string barMode: String(setting("barMode", "both") || "both")
  readonly property bool hideOnRestDays: setting("hideOnRestDays", false) === true
  readonly property string credentialsFile: String(setting("credentialsFile", "") || "")
  readonly property string scriptPath: String(Qt.resolvedUrl("isabella.sh")).replace(/^file:\/\//, "")
  readonly property var scriptEnvironment: {
    var env = {}
    if (credentialsFile !== "") env.ISABELLA_ENV = credentialsFile
    if (pendingCredentials) {
      env.ISABELLA_SET_URL = pendingCredentials.url
      env.ISABELLA_SET_USERNAME = pendingCredentials.username
      env.ISABELLA_SET_PASSWORD = pendingCredentials.password
    }
    return env
  }
  readonly property bool needsCredentials: Model.needsCredentials(result)
  // Typing in the sign-in form must not drive the checklist cursor.
  readonly property bool formFocused: urlField.activeFocus || usernameField.activeFocus || passwordField.activeFocus

  readonly property bool loaded: result !== null
  readonly property bool ok: Model.isOk(result)
  readonly property bool showingDay: Model.hasDay(result)
  readonly property var dayData: showingDay ? result.day : null
  readonly property var rows: Model.visibleRows(result)
  readonly property var counts: Model.counts(result)
  readonly property bool editable: showingDay && dayData.editable === true && result.state === "ok"
  readonly property bool isToday: day === Model.todayIso()
  readonly property string url: result && result.url ? String(result.url) : ""
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barText: Model.barText(result, barMode, vertical)
  readonly property bool barHasLabel: !vertical && ok && barMode !== "none" && counts.total > 0
  readonly property real openPanelIndicatorWidth: barHasLabel ? button.labelWidth : 0

  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: "Refresh now", run: function() { root.refresh() } },
    { label: "Open", icon: "󰏌", tooltip: "Open Isabella in the browser", run: function() { root.openInBrowser() } },
    { label: root.isToday ? "Tomorrow" : "Today", icon: root.isToday ? "󱑂" : "󰃭", tooltip: root.isToday ? "Peek at tomorrow's checklist" : "Back to today", run: function() { root.isToday ? root.stepDay(1) : root.goToday() } }
  ]

  // Keyboard cursor walks the checklist rows (skipping group headers) and
  // then the footer actions, all on one index.
  readonly property int cursorCount: rows.length + actions.length

  function run(args) {
    if (proc.running) return false
    loading = true
    proc.command = [root.scriptPath].concat(args)
    proc.running = true
    return true
  }

  function refresh() {
    if (proc.running) { refreshPending = true; return }
    run(["day", day])
  }

  function applyResult(raw) {
    var next = Model.parseResult(raw)
    busyKey = ""
    if (pendingCredentials) {
      pendingCredentials = null
      if (next.state === "unauthorized") formError = "Isabella rejected that username or password"
      else if (next.state === "unreachable") formError = "Saved, but " + String(next.url || "the server") + " did not answer"
      else if (next.state === "error") formError = String(next.error || "Sign-in failed")
      else passwordField.text = ""
    }
    // A failed refresh keeps the last checklist on screen when the script
    // could not hand back a cached one itself.
    if (!Model.hasDay(next) && Model.hasDay(result) && next.state !== "unconfigured" && next.state !== "unauthorized") {
      next.day = result.day
      next.url = result.url
    }
    result = next
    if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)
  }

  function act(command, row) {
    if (!row || Model.isHeader(row) || !editable || busyKey !== "") return
    var args
    if (row.kind === "subtask") {
      if (command !== "toggle") return
      args = ["subtoggle", day, String(row.id)]
    } else {
      args = [command, day, String(row.id)]
    }
    if (run(args)) busyKey = row.key
  }

  function toggleRow(row) { act("toggle", row) }
  function cancelRow(row) { act("cancel", row) }
  function delayRow(row) {
    if (row && row.kind === "task" && dayData && dayData.delayable === true) act("delay", row)
  }

  function stepDay(delta) {
    var next = dayData && delta > 0 ? dayData.next_day : (dayData && delta < 0 ? dayData.prev_day : "")
    if (!next) {
      var d = Model.parseDay(day) || new Date()
      d.setDate(d.getDate() + delta)
      var mm = d.getMonth() + 1
      var dd = d.getDate()
      next = d.getFullYear() + "-" + (mm < 10 ? "0" : "") + mm + "-" + (dd < 10 ? "0" : "") + dd
    }
    day = next
    cursorActive = false
    cursorIndex = 0
    refresh()
  }

  function goToday() {
    if (isToday) { refresh(); return }
    day = Model.todayIso()
    cursorActive = false
    cursorIndex = 0
    refresh()
  }

  function openInBrowser() {
    if (!root.bar) return
    var target = url !== "" ? url : "https://isabella.bemisc.com"
    root.bar.run("omarchy-launch-browser '" + target.replace(/'/g, "") + "'")
    root.close()
  }

  // Sign-in form: write the credentials file through the script and land on
  // today's checklist in the same round trip.
  function submitCredentials() {
    var url = String(urlField.text || "").trim()
    var username = String(usernameField.text || "").trim()
    var password = String(passwordField.text || "")
    if (url === "" || username === "" || password === "") {
      formError = "URL, username and password are all required"
      return
    }
    if (url.indexOf("://") < 0) url = "https://" + url
    formError = ""
    pendingCredentials = { url: url, username: username, password: password }
    if (!run(["configure"])) pendingCredentials = null
  }

  property string formError: ""

  function focusForm() {
    var prefill = Model.prefill(result, "https://isabella.bemisc.com")
    if (urlField.text === "") urlField.text = prefill.url
    if (usernameField.text === "") usernameField.text = prefill.username
    Qt.callLater(function() {
      if (usernameField.text === "") usernameField.forceActiveFocus()
      else passwordField.forceActiveFocus()
    })
  }

  function editCredentials() {
    if (!root.bar) return
    var file = credentialsFile !== "" ? credentialsFile : "$HOME/.config/omarchy/isabella.env"
    root.bar.run("omarchy-launch-config-editor \"" + file + "\"")
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
      toggleRow(rows[cursorIndex])
      return
    }
    var action = actions[cursorIndex - rows.length]
    if (action) action.run()
  }

  IpcHandler {
    target: "joamag.isabella"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    // Scripting hooks: tick a task of the shown day by id, and a one-line
    // summary of what the widget currently holds.
    function toggleTask(id: string): string {
      var n = parseInt(id, 10)
      if (!isFinite(n)) return "error: task id required"
      if (!root.editable) return "read-only"
      return root.run(["toggle", root.day, String(n)]) ? "ok" : "busy"
    }
    function state(): string {
      var c = root.counts
      return (root.result ? root.result.state : "loading") + " " + root.day + " pending=" + c.pending + " done=" + c.done + " overdue=" + c.overdue + " total=" + c.total
    }
    function version(): string { return "0.1.0" }
  }

  // A changed credentials file (or a freshly filled one) is picked up on the
  // next settings push instead of waiting for the refresh timer.
  onCredentialsFileChanged: refresh()

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      // Reopening lands on today again; a browsed day is not remembered.
      if (!isToday) day = Model.todayIso()
      refresh()
      if (needsCredentials) focusForm()
    }
  }

  onNeedsCredentialsChanged: if (needsCredentials && opened) focusForm()

  visible: !(hideOnRestDays && ok && counts.total === 0)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Process {
    id: proc
    environment: root.scriptEnvironment
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyResult(text) }
    onExited: {
      root.loading = false
      root.busyKey = ""
      root.pendingCredentials = null
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  // Midnight rolls the widget over to the new day on its next refresh.
  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!root.opened && !root.isToday) root.day = Model.todayIso()
      root.refresh()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    // Overdue carryover turns the label urgent.
    active: root.ok && root.counts.overdue > 0
    dimmed: root.loaded && (!root.ok || root.counts.total === 0)
    fontSize: Style.font.body
    horizontalMargin: root.barHasLabel ? 8.75 : 6
    fixedWidth: root.barHasLabel ? -1 : Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.result)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openInBrowser()
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
      blocked: root.formFocused
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) { root.moveCursor(dy); return }
        if (root.cursorActive && root.cursorIndex >= root.rows.length) root.moveCursor(dx)
        else root.stepDay(dx)
      }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.cancelRow(root.cursorRow())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "o") root.openInBrowser()
        else if (text === "t") root.goToday()
        else if (text === "c") root.cancelRow(root.cursorRow())
        else if (text === "d") root.delayRow(root.cursorRow())
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: broom · title/status · pending count ----------
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
              text: "Isabella"
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
                var parts = [Model.heroStatus(root.result)]
                if (root.loading) parts.push("Updating")
                return parts.join(" · ").toUpperCase()
              }
              color: root.ok && root.counts.overdue > 0 ? Color.urgent : Qt.darker(root.foreground, 1.4)
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
            text: root.showingDay ? root.counts.pending + "/" + root.counts.total : "—"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Day strip: ‹ Today · Thursday 4 Sep › + budget ----------
        Row {
          visible: root.showingDay
          width: parent.width
          spacing: Style.space(6)

          PanelActionButton {
            iconText: "󰅁"
            tooltipText: "Previous day"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.stepDay(-1)
          }

          Column {
            width: parent.width - parent.spacing * 2 - parent.children[0].width - parent.children[2].width
            spacing: Style.space(1)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              textFormat: Text.PlainText
              text: Model.dayLabel(root.day)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: {
                var parts = []
                var budget = Model.budgetLine(root.result)
                if (budget) parts.push(budget)
                if (root.dayData && root.dayData.banners) for (var i = 0; i < root.dayData.banners.length; i++) parts.push(String(root.dayData.banners[i]))
                if (root.showingDay && !root.editable) parts.push("read-only")
                return parts.join(" · ")
              }
              visible: text !== ""
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              width: parent.width
            }
          }

          PanelActionButton {
            iconText: "󰅂"
            tooltipText: "Next day"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.stepDay(1)
          }
        }

        // ---------- Unavailable: explanation plus the one fix that applies ----------
        Column {
          visible: root.loaded && !root.ok
          width: parent.width
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: Model.stateTitle(root.result)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: Model.stateDetail(root.result)
            visible: text !== ""
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }

          // Sign-in form: URL, username, password. Enter in any field submits,
          // Esc closes the popup like everywhere else.
          Column {
            visible: root.needsCredentials
            width: parent.width
            spacing: Style.space(6)

            CredentialField {
              id: urlField
              placeholderText: "https://isabella.example.com"
              onAccepted: usernameField.forceActiveFocus()
            }

            CredentialField {
              id: usernameField
              placeholderText: "Username"
              onAccepted: passwordField.forceActiveFocus()
            }

            CredentialField {
              id: passwordField
              placeholderText: "Password"
              password: true
              onAccepted: root.submitCredentials()
            }

            Text {
              visible: root.formError !== ""
              textFormat: Text.PlainText
              text: root.formError
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: (parent.width - parent.spacing) / 2
                height: actionRow.cellHeight
                iconText: root.pendingCredentials ? "󰑐" : "󰍁"
                iconSpinning: root.pendingCredentials !== null
                iconSize: Style.font.title
                text: root.pendingCredentials ? "Signing in" : "Sign in"
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                enabled: root.pendingCredentials === null
                onClicked: root.submitCredentials()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                height: actionRow.cellHeight
                iconText: "󰏫"
                iconSize: Style.font.title
                text: "Edit file"
                tooltipText: "Open the credentials file in your editor"
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.editCredentials()
              }
            }
          }
        }

        // ---------- Checklist ----------
        Column {
          visible: root.showingDay
          width: parent.width
          spacing: Style.space(2)

          Text {
            visible: root.rows.length === 0
            text: root.loading ? "Loading…" : "Nothing scheduled for this day."
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            width: parent.width
          }

          Repeater {
            model: root.rows

            ChecklistRow {
              required property var modelData
              required property int index
              width: parent.width
              row: modelData
              rowIndex: index
            }
          }
        }

        // ---------- Footer ----------
        PanelSeparator { foreground: root.foreground }

        Text {
          visible: root.showingDay && root.result.state !== "ok"
          textFormat: Text.PlainText
          text: root.showingDay && root.result.state !== "ok" ? Model.stateTitle(root.result) + (root.result.error ? " · " + root.result.error : "") : ""
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
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

  // Text input of the sign-in form. Enter moves on or submits; Esc hands the
  // key back to the panel so it closes like everywhere else.
  component CredentialField: TextField {
    id: field
    width: parent.width
    foreground: root.foreground
    font.family: root.fontFamily
    enabled: root.pendingCredentials === null
    onTextChanged: root.formError = ""

    // Return is handled by TextField itself (the `accepted` signal).
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.close()
        event.accepted = true
      }
    }
  }

  // One entry of the flattened checklist: a group header ("TO DO · 9") or a
  // task / subtask row with checkbox glyph, name, detail line and minutes.
  component ChecklistRow: Item {
    id: entry
    required property var row
    required property int rowIndex

    readonly property bool header: Model.isHeader(row)
    readonly property bool subtask: !header && row.kind === "subtask"
    readonly property bool finished: !header && (row.checked === true || row.cancelled === true)
    readonly property bool busy: !header && root.busyKey !== "" && root.busyKey === row.key
    readonly property bool hasCursor: !header && root.cursorActive && root.cursorIndex === rowIndex
    readonly property color glyphColor: {
      if (header) return root.foreground
      if (row.cancelled) return Util.alpha(root.foreground, 0.4)
      if (row.checked) return Color.accent
      if (row.kind === "task" && row.from) return Color.urgent
      return root.foreground
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
      opacity: entry.finished && !entry.busy ? 0.6 : 1

      Row {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(6) + (entry.subtask ? Style.space(22) : 0)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: entry.header ? "" : (entry.busy ? "󰑐" : (entry.subtask ? Model.subtaskGlyph(entry.row, entry.row.parent) : Model.glyph(entry.row)))
          color: entry.glyphColor
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
          width: parent.width - Style.space(22) - minutesText.width - parent.spacing * 2
          spacing: Style.space(1)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            textFormat: Text.PlainText
            text: entry.header ? "" : String(entry.row.name || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: entry.subtask ? Style.font.bodySmall : Style.font.body
            font.strikeout: !entry.header && entry.row.cancelled === true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: entry.header ? "" : Model.rowDetail(entry.row)
            visible: text !== ""
            color: !entry.header && entry.row.kind === "task" && entry.row.from && !entry.finished ? Color.urgent : root.foreground
            opacity: !entry.header && entry.row.kind === "task" && entry.row.from && !entry.finished ? 0.85 : 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Text {
          id: minutesText
          textFormat: Text.PlainText
          text: entry.header || !entry.row.minutes ? "" : Model.formatMinutes(entry.row.minutes)
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          width: Style.space(40)
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.editable && !entry.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.cursorIndex = entry.rowIndex
        }
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.cancelRow(entry.row)
          else root.toggleRow(entry.row)
        }
      }
    }
  }
}
