import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// House icon with the lights lit and the thermostat's target in the bar; the
// popup lists what Home Assistant controls, grouped, with switches on the
// rows, brightness under the lights that dim, and a target and mode row on
// each thermostat. Left click opens, middle click refreshes, right click
// opens Home Assistant in the browser.
Panel {
  id: root
  moduleName: "joamag.home"
  ipcTarget: "joamag.home"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/version to open/close/toggle.
  manageIpc: false

  property var result: null
  property bool loading: false
  // A refresh asked for while the script is still running is replayed when
  // it exits.
  property bool refreshPending: false
  // Entity id an action is running against; its row shows a spinner and
  // ignores further clicks until Home Assistant answers.
  property string busyKey: ""
  property string lastError: ""
  property bool cursorActive: false
  property int cursorIndex: 0
  // Credentials handed to home.sh configure through the environment for the
  // duration of that one run; cleared as soon as it exits.
  property var pendingCredentials: null
  property string formError: ""

  // Which tab is open and what is typed in the filter. The tab is remembered
  // inline on the widget's shell.json entry, like the clock keeps its format.
  property string tab: Model.normalizeTab(result, String(setting("tab", "all") || "all"))
  property string query: ""

  readonly property string entitySetting: String(setting("entities", "") || "")
  readonly property string barMode: String(setting("barMode", "both") || "both")
  readonly property int refreshIntervalSec: Math.max(10, Math.round(Number(setting("refreshIntervalSec", 30)) || 30))
  readonly property string credentialsFile: String(setting("credentialsFile", "") || "")
  readonly property string scriptPath: String(Qt.resolvedUrl("home.sh")).replace(/^file:\/\//, "")
  readonly property var scriptEnvironment: {
    var env = { HOME_ENTITIES: entitySetting }
    if (credentialsFile !== "") env.HOME_ASSISTANT_ENV = credentialsFile
    if (pendingCredentials) {
      env.HOME_ASSISTANT_SET_URL = pendingCredentials.url
      env.HOME_ASSISTANT_SET_USERNAME = pendingCredentials.username
      env.HOME_ASSISTANT_SET_PASSWORD = pendingCredentials.password
    }
    return env
  }
  readonly property bool needsCredentials: Model.needsCredentials(result)
  // Typing in the sign-in form must not drive the list cursor.
  readonly property bool formFocused: urlField.activeFocus || usernameField.activeFocus || passwordField.activeFocus || filterField.activeFocus

  readonly property bool loaded: result !== null
  readonly property bool ok: Model.isOk(result)
  readonly property bool showingEntities: Model.hasEntities(result) && Model.entities(result).length > 0
  readonly property var tabList: Model.tabs(result)
  readonly property var rows: Model.visibleRows(result, tab, query)
  readonly property var climate: Model.activeClimate(result)
  readonly property string url: result && result.url ? String(result.url) : ""
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color onColor: Color.accent
  readonly property color heatColor: Color.urgent
  readonly property color dimColor: Util.alpha(foreground, 0.45)

  readonly property string barText: Model.barText(result, barMode, vertical)
  readonly property bool barHasLabel: !vertical && barText !== Model.ICON
  readonly property real openPanelIndicatorWidth: barHasLabel ? button.labelWidth : 0

  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: "Refresh now", run: function() { root.refresh() } },
    { label: "Open", icon: "󰏌", tooltip: "Open Home Assistant in the browser", run: function() { root.openInBrowser() } },
    { label: "Lights off", icon: "󰌶", tooltip: "Turn every listed light off", run: function() { root.allLightsOff() } }
  ]

  // Keyboard cursor walks the entity rows (skipping group headers) and then
  // the footer actions, all on one index.
  readonly property int cursorCount: rows.length + actions.length

  // The colour a row's icon takes: warm for heating, accent for anything
  // else that is on, dim when off.
  function stateColor(entity) {
    if (!Model.isOn(entity)) return dimColor
    if (Model.isClimate(entity) && String(entity.state) === "heat") return heatColor
    return onColor
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
    run(["snapshot", entitySetting])
  }

  function applyResult(raw) {
    var next = Model.parseResult(raw)
    busyKey = ""
    if (pendingCredentials) {
      pendingCredentials = null
      if (next.state === "unauthorized") formError = String(next.error || "Home Assistant rejected that sign-in")
      else if (next.state === "unreachable") formError = "No answer from " + String(next.url || "that address")
      else if (next.state === "error") formError = String(next.error || "Sign-in failed")
      else passwordField.text = ""
    }
    // A failed refresh keeps the last list on screen when the script could
    // not hand back a cached one itself.
    if (!Model.hasEntities(next) && Model.hasEntities(result) && next.state !== "unconfigured" && next.state !== "unauthorized") {
      next.entities = result.entities
      next.url = result.url
    }
    lastError = next.state === "error" ? String(next.error || "") : ""
    result = next
    if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)
  }

  function act(args, entity) {
    if (!entity || busyKey !== "") return
    if (run(args)) busyKey = String(entity.id)
  }

  function toggleRow(row) {
    if (!row || Model.isHeader(row)) return
    switch (Model.rowAction(row)) {
    case "climate": setMode(row, Model.nextMode(row, 1)); break
    case "activate": act(["activate", row.id], row); break
    default: act(["toggle", row.id], row)
    }
  }

  function setMode(entity, mode) {
    if (!Model.isClimate(entity) || !mode) return
    act(["climate", entity.id, "mode", String(mode)], entity)
  }

  function stepTarget(entity, delta) {
    if (!Model.isClimate(entity)) return
    var target = Model.clampTemperature(entity, Number(entity.temperature) + delta * Model.climateUiStep(entity))
    if (!isFinite(target)) return
    act(["climate", entity.id, "temperature", String(target)], entity)
  }

  function setBrightness(entity, percent) {
    if (!entity || entity.domain !== "light") return
    var pct = Math.max(0, Math.min(100, Math.round(Number(percent) || 0)))
    act(["brightness", entity.id, String(pct)], entity)
  }

  // h/l on a row: the thermostat's target, or a light's brightness.
  function adjustRow(row, delta) {
    if (!row || Model.isHeader(row)) return
    if (Model.isClimate(row)) stepTarget(row, delta)
    else if (Model.canDim(row)) setBrightness(row, Model.brightnessPct(row) + delta * 10)
  }

  function allLightsOff() {
    var list = Model.entities(result)
    for (var i = 0; i < list.length; i++) {
      if (list[i].domain === "light" && Model.isOn(list[i])) { act(["turn_off", list[i].id], list[i]); return }
    }
  }

  function openInBrowser() {
    if (!root.bar || url === "") return
    root.bar.run("omarchy-launch-browser '" + url.replace(/'/g, "") + "'")
    root.close()
  }

  // Sign-in form: run the login flow through the script and land on the
  // entities in the same round trip.
  function submitCredentials() {
    var address = String(urlField.text || "").trim()
    var username = String(usernameField.text || "").trim()
    var password = String(passwordField.text || "")
    if (address === "" || username === "" || password === "") {
      formError = "Address, username and password are all required"
      return
    }
    if (address.indexOf("://") < 0) address = "http://" + address
    formError = ""
    pendingCredentials = { url: address, username: username, password: password }
    if (!run(["configure"])) pendingCredentials = null
  }

  function focusForm() {
    var prefill = Model.prefill(result, "")
    if (urlField.text === "") urlField.text = prefill.url
    if (usernameField.text === "") usernameField.text = prefill.username
    Qt.callLater(function() {
      if (urlField.text === "") urlField.forceActiveFocus()
      else if (usernameField.text === "") usernameField.forceActiveFocus()
      else passwordField.forceActiveFocus()
    })
  }

  function editCredentials() {
    if (!root.bar) return
    var file = credentialsFile !== "" ? credentialsFile : "$HOME/.config/omarchy/home.env"
    root.bar.run("omarchy-launch-config-editor \"" + file + "\"")
    root.close()
  }

  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function selectTab(key) {
    var next = Model.normalizeTab(result, key)
    if (next === tab) return
    tab = next
    persistSetting("tab", next)
    cursorActive = false
    cursorIndex = 0
    scrollArea.contentItem.contentY = 0
  }

  function stepTab(delta) {
    selectTab(Model.nextTab(result, tab, delta))
  }

  function focusFilter() {
    Qt.callLater(function() { filterField.forceActiveFocus() })
  }

  function clearFilter() {
    filterField.text = ""
    query = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Keep the keyboard-focused row inside the viewport when the list is
  // taller than the popup. Mirrors the first-party panels' helper.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin) flick.contentY = bottom + margin - flick.height
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
      if (idx >= rows.length || !Model.isPassive(rows[idx])) break
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
    target: "joamag.home"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function version(): string { return "0.1.0" }
  }

  // A changed credentials file is picked up on the next settings push
  // instead of waiting for the refresh timer.
  onCredentialsFileChanged: refresh()
  onEntitySettingChanged: refresh()

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      if (!root.ok || !result.fetchedAt || Date.now() / 1000 - Number(result.fetchedAt) > 10) refresh()
      if (needsCredentials) focusForm()
    }
  }

  onNeedsCredentialsChanged: if (needsCredentials && opened) focusForm()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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
    dimmed: root.loaded && !root.ok && !root.showingEntities
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
    contentWidth: panel.fittedContentWidth(Style.space(470))
    // The natural height is the fixed top block, the whole list and the
    // footer; capped, the list is what gives, scrolling inside its slot.
    contentHeight: panel.fittedContentHeight(
      topBlock.implicitHeight + footer.implicitHeight + Style.space(24)
        + (root.showingEntities ? listColumn.implicitHeight + Style.space(4) : 0),
      Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.formFocused
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) { root.moveCursor(dy); return }
        if (root.cursorActive && root.cursorIndex >= root.rows.length) root.moveCursor(dx)
        else root.adjustRow(root.cursorRow(), dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "o") root.openInBrowser()
        else if (text === "a") root.allLightsOff()
        else if (text === "[") root.stepTab(-1)
        else if (text === "]") root.stepTab(1)
        else if (text === "/") root.focusFilter()
        else if (/^[1-9]$/.test(text) && root.tabList.length >= Number(text)) root.selectTab(root.tabList[Number(text) - 1].key)
      }

      Item {
        id: content
        anchors.fill: parent

      Column {
        id: topBlock
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: house · title/status · room temperature ----------
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
              text: "Home"
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
            text: Model.heroValue(root.result)
            color: root.climate && Model.isOn(root.climate) ? root.stateColor(root.climate) : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Unavailable: explanation plus the sign-in form ----------
        Column {
          visible: root.loaded && !root.ok && !root.showingEntities
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

          Column {
            visible: root.needsCredentials
            width: parent.width
            spacing: Style.space(6)

            CredentialField {
              id: urlField
              placeholderText: "https://home.example.com or 192.168.1.10:8123"
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
                text: "Use a token"
                tooltipText: "Open the credentials file, for a long-lived access token"
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.editCredentials()
              }
            }
          }
        }

        // ---------- Tabs and filter ----------
        Column {
          visible: root.showingEntities
          width: parent.width
          spacing: Style.space(8)

          // One pill per group that exists, "All" in front. Digits jump to
          // them, [ and ] step through them.
          ButtonGroup {
            visible: root.tabList.length > 1
            width: parent.width
            options: root.tabList.map(function(t) { return { value: t.key, label: t.title + " " + t.count } })
            value: root.tab
            foreground: root.foreground
            background: Color.popups.background
            accent: root.onColor
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            focusable: false
            onChanged: function(v) { root.selectTab(v) }
          }

          // Type to narrow the list across every group; / focuses it, Esc
          // clears it and hands the keys back to the list.
          Item {
            width: parent.width
            implicitHeight: filterField.implicitHeight

            TextField {
              id: filterField
              anchors.left: parent.left
              anchors.right: filterHint.left
              anchors.rightMargin: Style.space(8)
              placeholderText: "Filter by name…  (/)"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: {
                root.query = String(text || "")
                root.cursorActive = false
                root.cursorIndex = 0
              }
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.clearFilter()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Down) {
                  // Enter or Down lands on the first match so it can be acted on.
                  root.cursorActive = true
                  root.cursorIndex = Math.max(0, Model.firstRowIndex(root.rows))
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            Text {
              id: filterHint
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                var n = 0
                for (var i = 0; i < root.rows.length; i++) if (!Model.isPassive(root.rows[i])) n++
                return n + (n === 1 ? " item" : " items")
              }
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

      }

        // ---------- Entities, scrolling in whatever is left between the
        // top block and the footer ----------
        ScrollView {
          id: scrollArea
          visible: root.showingEntities
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: topBlock.bottom
          anchors.topMargin: Style.space(12)
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.space(12)
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          ScrollBar.vertical.policy: listColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          Binding {
            target: scrollArea.contentItem
            property: "interactive"
            value: listColumn.implicitHeight > scrollArea.height
          }

          Column {
            id: listColumn
            width: scrollArea.availableWidth
            spacing: Style.space(2)

            Text {
              visible: root.rows.length === 0
              text: root.query !== "" ? "Nothing matches \"" + root.query + "\"." : "Nothing on this tab."
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width
            }

            Repeater {
              model: root.rows

              HomeRow {
                required property var modelData
                required property int index
                width: parent.width
                row: modelData
                rowIndex: index
              }
            }
          }
        }

      Column {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(12)

        // ---------- Footer: status line + actions ----------
        PanelSeparator { foreground: root.foreground }

        Text {
          visible: root.lastError !== "" || (root.showingEntities && root.result.state === "unreachable")
          textFormat: Text.PlainText
          text: root.lastError !== "" ? root.lastError : (root.showingEntities && root.result.state === "unreachable" ? Model.stateTitle(root.result) + " · " + String(root.result.error || "") : "")
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

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.close()
        event.accepted = true
      }
    }
  }

  // One entry of the flattened list: a group header ("LIGHTS · 4"), a
  // thermostat card with its target and mode row, or a plain entity row with
  // a switch on the right and, under a light that dims, a brightness slider.
  component HomeRow: Item {
    id: entry
    required property var row
    required property int rowIndex

    readonly property bool header: Model.isHeader(row)
    readonly property bool more: Model.isMore(row)
    readonly property bool climate: !header && !more && Model.isClimate(row)
    readonly property bool busy: !header && !more && root.busyKey !== "" && root.busyKey === String(row.id)
    readonly property bool hasCursor: !header && !more && root.cursorActive && root.cursorIndex === rowIndex
    readonly property bool on: !header && !more && Model.isOn(row)
    readonly property bool dimmable: !header && !more && Model.canDim(row)
    readonly property color tone: header || more ? root.foreground : root.stateColor(row)

    implicitHeight: header ? headerItem.implicitHeight : (more ? moreItem.implicitHeight : (climate ? climateCard.implicitHeight : surface.implicitHeight))
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(entry)

    // The list stopped short: say how much is behind the cut and how to reach it.
    Item {
      id: moreItem
      visible: entry.more
      width: parent.width
      implicitHeight: moreText.implicitHeight + Style.space(12)

      Text {
        id: moreText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: entry.more ? "… " + entry.row.hidden + " more · type to filter" : ""
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: headerItem
      visible: entry.header
      width: parent.width
      implicitHeight: headerText.implicitHeight + Style.space(entry.rowIndex === 0 ? 0 : 12)

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

    // ---- Thermostat card ----
    CursorSurface {
      id: climateCard
      visible: entry.climate
      width: parent.width
      implicitHeight: climateInner.implicitHeight + Style.spacing.lg
      hasCursor: entry.hasCursor
      foreground: root.foreground

      Column {
        id: climateInner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(6)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: entry.busy ? "󰑐" : Model.typeIcon(entry.row)
            color: entry.tone
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
            RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: entry.busy; onRunningChanged: if (!running) rotation = 0 }
          }

          Column {
            width: parent.width - Style.space(22) - targetBlock.width - parent.spacing * 2
            spacing: Style.space(1)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              textFormat: Text.PlainText
              text: entry.climate ? Model.entityName(entry.row) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: entry.climate ? Model.climateDetail(entry.row) : ""
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          // Target with a step either side, big enough to read across a room.
          Row {
            id: targetBlock
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter

            PanelActionButton {
              iconText: "󰍴"
              tooltipText: "Lower the target"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: if (entry.climate) root.stepTarget(entry.row, -1)
            }

            Text {
              textFormat: Text.PlainText
              text: entry.climate ? Model.formatTemp(entry.row.temperature) : ""
              color: entry.on ? entry.tone : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(58)
              anchors.verticalCenter: parent.verticalCenter

              Behavior on color { ColorAnimation { duration: 200 } }
            }

            PanelActionButton {
              iconText: "󰐕"
              tooltipText: "Raise the target"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: if (entry.climate) root.stepTarget(entry.row, 1)
            }
          }
        }

        // Mode row: one pill per mode the device offers, the current one lit,
        // indented to sit under the name.
        Row {
          id: modeRow
          x: Style.space(30)
          width: parent.width - Style.space(30)
          spacing: Style.space(4)

          readonly property var modes: entry.climate ? Model.climateModes(entry.row) : []

          Repeater {
            model: modeRow.modes

            Button {
              required property string modelData
              height: Style.spacing.controlHeight - Style.space(4)
              iconText: Model.modeIcon(modelData)
              iconSize: Style.font.bodySmall
              text: Model.modeLabel(modelData)
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.xs
              bordered: true
              active: entry.climate && String(entry.row.state) === modelData
              onClicked: if (entry.climate) root.setMode(entry.row, modelData)
            }
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.cursorIndex = entry.rowIndex
        }
      }
    }

    // ---- Light, switch, fan, cover, scene ----
    CursorSurface {
      id: surface
      visible: !entry.header && !entry.more && !entry.climate
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
            text: entry.header || entry.more ? "" : (entry.busy ? "󰑐" : Model.typeIcon(entry.row))
            color: entry.tone
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
            RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: entry.busy; onRunningChanged: if (!running) rotation = 0 }
          }

          Column {
            width: parent.width - Style.space(22) - control.width - parent.spacing * 2
            spacing: Style.space(1)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              textFormat: Text.PlainText
              text: entry.header || entry.more ? "" : Model.entityName(entry.row)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: entry.header || entry.more ? "" : Model.entityDetail(entry.row)
              visible: text !== ""
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          // A switch for things that toggle, a run button for scenes.
          Item {
            id: control
            width: entry.header || entry.more ? 0 : (Model.rowAction(entry.row) === "activate" ? runButton.width : toggle.width)
            height: Math.max(toggle.height, runButton.height)
            anchors.verticalCenter: parent.verticalCenter

            ToggleSwitch {
              id: toggle
              visible: !entry.header && !entry.more && Model.rowAction(entry.row) === "toggle"
              anchors.verticalCenter: parent.verticalCenter
              checked: entry.on
              busy: entry.busy
              interactive: !entry.busy && Model.isAvailable(entry.row)
              foreground: root.foreground
              accent: root.onColor
              onToggled: root.toggleRow(entry.row)
              onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = entry.rowIndex } }
            }

            PanelActionButton {
              id: runButton
              visible: !entry.header && !entry.more && Model.rowAction(entry.row) === "activate"
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰐊"
              tooltipText: "Run"
              foreground: root.foreground
              hoverColor: root.onColor
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.toggleRow(entry.row)
            }
          }
        }

        // Brightness under a light that dims: drag to set, follows the light.
        PanelSlider {
          visible: entry.dimmable && entry.on
          bar: root.bar
          width: parent.width - Style.space(30)
          x: Style.space(30)
          implicitHeight: Style.space(18)
          minimum: 1
          maximum: 100
          step: 5
          integer: true
          value: entry.dimmable ? Model.brightnessPct(entry.row) : 0
          fillColor: root.onColor
          knobColor: root.onColor
          onReleased: function(v) { root.setBrightness(entry.row, v) }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: entry.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
        // Declared before the controls' own areas would be; the switch and
        // slider sit above this and take their clicks first.
        z: -1
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.cursorIndex = entry.rowIndex
        }
        onClicked: root.toggleRow(entry.row)
      }
    }
  }
}
