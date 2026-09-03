import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// GitHub icon plus the number of things that need you in the bar; the popup
// lists review requests, your pull requests with CI and review state,
// assigned issues and unread notifications. Left click opens, middle click
// refreshes, right click opens the notifications inbox.
Panel {
  id: root
  moduleName: "joamag.github"
  ipcTarget: "joamag.github"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/markRead/version to open/close/toggle.
  manageIpc: false

  property var snapshot: null
  property bool loading: false
  property bool marking: false
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property int refreshIntervalSec: Math.max(60, Math.round(Number(setting("refreshIntervalSec", 180)) || 180))
  readonly property int maxRows: Math.max(1, Math.min(15, Math.round(Number(setting("maxRows", 5)) || 5)))
  readonly property bool hideWhenQuiet: setting("hideWhenQuiet", false) === true
  readonly property var sectionSettings: ({
    showReviews: setting("showReviews", true) !== false,
    showPulls: setting("showPulls", true) !== false,
    showIssues: setting("showIssues", true) !== false,
    showNotifications: setting("showNotifications", true) !== false
  })
  readonly property string scriptPath: String(Qt.resolvedUrl("radar.sh")).replace(/^file:\/\//, "")

  readonly property bool loaded: snapshot !== null
  readonly property bool ok: Model.isOk(snapshot)
  readonly property bool missing: loaded && snapshot.state === "missing"
  readonly property string login: ok ? String(snapshot.login || "") : ""
  readonly property var rows: Model.visibleRows(snapshot, sectionSettings)
  readonly property int attention: Model.attentionCount(snapshot, sectionSettings)
  readonly property int unread: Model.section(snapshot, "notifications").total
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barText: Model.barText(snapshot, sectionSettings, vertical)
  readonly property real openPanelIndicatorWidth: !vertical && ok && attention > 0 ? button.labelWidth : 0

  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: "Refresh now", run: function() { root.refresh() } },
    { label: "Inbox", icon: "󰂚", tooltip: "Open github.com/notifications", run: function() { root.openInbox() } },
    { label: "Mark read", icon: "󰄬", tooltip: root.unread > 0 ? "Mark all " + root.unread + " notifications as read" : "No unread notifications", run: function() { root.markRead() } }
  ]

  // Keyboard cursor walks the list rows (skipping section headers) and then
  // the footer actions, all on one index.
  readonly property int cursorCount: rows.length + actions.length

  function toneColor(tone) {
    switch (tone) {
    case "urgent": return Color.urgent
    case "accent": return Color.accent
    case "muted": return Util.alpha(foreground, 0.5)
    default: return foreground
    }
  }

  function refresh() {
    if (radarProc.running) return
    loading = true
    radarProc.command = [root.scriptPath, String(root.maxRows)]
    radarProc.running = true
  }

  function applySnapshot(raw) {
    var next = Model.parseSnapshot(raw)
    // A transient failure keeps the last good lists on screen and only
    // surfaces its message in the status line.
    if (next.state === "error" && root.ok) {
      var kept = {}
      for (var key in snapshot) kept[key] = snapshot[key]
      kept.lastError = next.error
      snapshot = kept
      return
    }
    snapshot = next
    if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)
  }

  function openUrl(url) {
    if (!root.bar || !url) return
    root.bar.run("omarchy-launch-browser '" + String(url).replace(/'/g, "") + "'")
    root.close()
  }

  function openRow(row) {
    if (row && !Model.isHeader(row)) openUrl(row.url)
  }

  function copyRow(row) {
    if (!root.bar || !row || Model.isHeader(row) || !row.url) return
    root.bar.run("wl-copy '" + String(row.url).replace(/'/g, "") + "'")
  }

  function openInbox() {
    openUrl("https://github.com/notifications")
  }

  function signIn() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation 'gh auth login'")
    root.close()
  }

  function markRead() {
    if (marking || !root.ok || root.unread === 0) return
    marking = true
    markProc.command = [root.scriptPath, "mark-read"]
    markProc.running = true
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
      openRow(rows[cursorIndex])
      return
    }
    var action = actions[cursorIndex - rows.length]
    if (action) action.run()
  }

  IpcHandler {
    target: "joamag.github"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function markRead(): void { root.markRead() }
    function version(): string { return "0.1.0" }
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      // Data older than half a minute is refreshed on open; fresher data is
      // shown as is, so the popup never flashes a spinner needlessly.
      if (!root.ok || !snapshot.fetchedAt || Date.now() / 1000 - Number(snapshot.fetchedAt) > 30) refresh()
    }
  }

  visible: !missing && !(hideWhenQuiet && ok && attention === 0)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Process {
    id: radarProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
    onExited: root.loading = false
  }

  Process {
    id: markProc
    onExited: {
      root.marking = false
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    // Red checks or requested changes on my own PRs turn the label urgent.
    active: root.ok && Model.hasFailures(root.snapshot)
    dimmed: root.loaded && !root.ok
    fontSize: Style.font.body
    horizontalMargin: root.ok && root.attention > 0 && !root.vertical ? 8.75 : 6
    fixedWidth: root.ok && root.attention > 0 && !root.vertical ? -1 : Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.snapshot, root.sectionSettings)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openInbox()
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
    contentWidth: panel.fittedContentWidth(Style.space(460))
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
        else if (text === "m") root.markRead()
        else if (text === "o") root.openInbox()
        else if (text === "y") root.copyRow(root.cursorRow())
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: icon · title/status · attention count ----------
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
              text: "GitHub"
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
                var parts = []
                if (root.login) parts.push("@" + root.login)
                parts.push(Model.heroStatus(root.snapshot, root.sectionSettings))
                if (root.loading) parts.push("Updating")
                else if (root.ok) parts.push(Model.formatFetched(root.snapshot.fetchedAt))
                return parts.join(" · ").toUpperCase()
              }
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
            text: root.ok ? String(root.attention) : "—"
            color: root.ok && Model.hasFailures(root.snapshot) ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
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
            visible: root.loaded && root.snapshot.state === "unauthenticated"
            width: parent.width
            height: actionRow.cellHeight
            iconText: Model.ICON
            iconSize: Style.font.title
            text: "Sign in with gh auth login"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.signIn()
          }
        }

        // ---------- Sections and rows ----------
        Column {
          visible: root.ok
          width: parent.width
          spacing: Style.space(2)

          Text {
            visible: root.rows.length === 0
            text: root.loading ? "Loading…" : "Nothing needs you right now."
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            width: parent.width
          }

          Repeater {
            model: root.rows

            RadarRow {
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
          visible: root.ok && !!root.snapshot.lastError
          textFormat: Text.PlainText
          text: root.ok && root.snapshot.lastError ? "Last refresh failed: " + root.snapshot.lastError : ""
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
              iconSpinning: index === 2 && root.marking
              text: modelData.label
              tooltipText: modelData.tooltip
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              opacity: index === 2 && root.unread === 0 ? 0.45 : 1
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

  // One entry of the flattened list: either a section header ("MY PULL
  // REQUESTS · 3 OF 32") or an item with glyph, title, detail line and age.
  component RadarRow: Item {
    id: entry
    required property var row
    required property int rowIndex

    readonly property bool header: Model.isHeader(row)
    readonly property bool hasCursor: !header && root.cursorActive && root.cursorIndex === rowIndex
    readonly property color glyphColor: root.toneColor(Model.rowTone(row))

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
          ? entry.row.title + (entry.row.total > entry.row.shown ? " · " + entry.row.shown + " OF " + entry.row.total : " · " + entry.row.total)
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
          text: entry.header ? "" : Model.rowGlyph(entry.row)
          color: entry.glyphColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - Style.space(22) - ageText.width - parent.spacing * 2
          spacing: Style.space(1)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            textFormat: Text.PlainText
            text: entry.header ? "" : String(entry.row.title || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: {
              if (entry.header) return ""
              var parts = [Model.rowTitle(entry.row, root.login)]
              var status = Model.rowStatus(entry.row)
              if (status) parts.push(status)
              if (entry.row.kind !== "notification" && entry.row.author && entry.row.author !== root.login) parts.push("by " + entry.row.author)
              return parts.join(" · ")
            }
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Text {
          id: ageText
          textFormat: Text.PlainText
          text: entry.header ? "" : Model.formatAge(entry.row.updatedAt)
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          width: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.cursorIndex = entry.rowIndex
        }
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.copyRow(entry.row)
          else root.openRow(entry.row)
        }
      }
    }
  }
}
