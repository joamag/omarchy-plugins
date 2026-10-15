import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Palette icon in the bar, dimmed while every light is off; the popup lists
// what OpenRGB can light, the case's NZXT hub and the graphics card among
// them, each with a switch, a row of colours with a hex field and a
// brightness slider. Left click opens, middle click looks for devices again,
// right click turns everything off or back on. What is set is remembered on
// the widget's shell.json entry and put back when the shell starts, since the
// hardware forgets its colours on a power cycle.
Panel {
  id: root
  moduleName: "joamag.rgb"
  ipcTarget: "joamag.rgb"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/on/off to open/close.
  manageIpc: false

  property var snapshot: null
  property bool loading: false
  // A refresh asked for while a change is running is replayed once the changes
  // are through: without its server every OpenRGB call opens the devices itself,
  // and two at once on the same hidraw or i2c bus garble each other.
  property bool refreshPending: false
  // Arguments waiting for their turn, one set per device key: OpenRGB takes one
  // change at a time, and a device changed twice while it waits only needs the
  // last one.
  property var pending: ({})
  // Device key the running change is for; its row spins until OpenRGB answers.
  property string busyKey: ""
  property string lastError: ""
  // Devices whose remembered state has been put back this session.
  property var restored: ({})
  // Snapshots taken again to finish a restore at login, where the openrgb
  // service can still be detecting and list fewer devices than it has.
  property int restoreRetries: 0
  // An all on or off asked for before the first snapshot listed the devices,
  // "on", "off" or "toggle"; it is carried out once they are, after the restore.
  property string pendingAll: ""
  // Key of the device whose hex field has the keys, so typing a colour does not
  // drive the list cursor.
  property string editingKey: ""
  property string colorError: ""
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property string deviceFilter: String(setting("devices", "") || "")
  readonly property bool restoreOnStart: setting("restoreOnStart", true) !== false
  readonly property var lights: setting("lights", ({}))
  readonly property string scriptPath: String(Qt.resolvedUrl("rgb.sh")).replace(/^file:\/\//, "")

  readonly property bool loaded: snapshot !== null
  readonly property bool ok: Model.isOk(snapshot)
  readonly property var devices: Model.visibleDevices(snapshot, deviceFilter)
  readonly property bool anyOn: Model.litCount(devices, lights) > 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color onColor: Color.accent
  readonly property color dimColor: Util.alpha(foreground, 0.45)

  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: "Look for devices again", run: function() { root.refresh() } },
    { label: root.anyOn ? "All off" : "All on", icon: root.anyOn ? "󰌶" : "󰌵", tooltip: root.anyOn ? "Turn every listed light off" : "Turn every listed light back on", run: function() { root.toggleAll() } }
  ]

  // Keyboard cursor walks the device rows and then the footer actions, all on
  // one index.
  readonly property int cursorCount: devices.length + actions.length

  function refresh() {
    if (snapshotProc.running) return
    if (actionProc.running) { refreshPending = true; return }
    loading = true
    snapshotProc.running = true
  }

  function applySnapshot(raw) {
    snapshot = Model.parseSnapshot(raw)
    loading = false
    if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)
    restored = Model.pruneRestored(restored, snapshot)
    if (restoreOnStart) restore()
    var power = Model.requestedPower(pendingAll, anyOn)
    pendingAll = ""
    if (power !== null) setAll(power)
  }

  function markRestored(list) {
    var done = {}
    for (var k in root.restored) done[k] = true
    for (var i = 0; i < list.length; i++) done[list[i].key] = true
    root.restored = done
  }

  // Puts the remembered state back on every listed device that has one and has
  // not had it yet this session, as soon as a snapshot shows the device.
  function restore() {
    var list = Model.pendingRestore(root.devices, root.lights, root.restored)
    if (list.length === 0) return
    markRestored(list)
    for (var i = 0; i < list.length; i++) queue(list[i], Model.lightState(root.lights, list[i].key))
  }

  function queue(device, state) {
    var args = Model.applyArgs(device, state)
    if (args.length === 0) return
    var next = {}
    for (var k in root.pending) next[k] = root.pending[k]
    next[device.key] = args
    root.pending = next
    flush()
  }

  // One run of rgb.sh at a time, snapshot included; whatever queued up
  // meanwhile goes next, and a refresh asked for on the way goes last.
  function flush() {
    if (actionProc.running || snapshotProc.running) return
    var keys = Object.keys(root.pending)
    if (keys.length === 0) {
      if (refreshPending) {
        refreshPending = false
        refresh()
      }
      return
    }
    var key = keys[0]
    var next = {}
    for (var i = 1; i < keys.length; i++) next[keys[i]] = root.pending[keys[i]]
    actionProc.command = [root.scriptPath].concat(root.pending[key])
    root.pending = next
    root.busyKey = key
    actionProc.running = true
  }

  // Persist inline on this widget's shell.json entry, the way the clock stores
  // its format, so the colours survive a reboot and can be edited by hand.
  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Remembered first, so the popup and shell.json show the choice at once,
  // then sent to the devices behind whatever is already on its way.
  function commit(list, lights) {
    persistSetting("lights", lights)
    markRestored(list)
    for (var i = 0; i < list.length; i++) queue(list[i], Model.lightState(lights, list[i].key))
  }

  function change(device, patch) {
    if (!device || !Model.isControllable(device)) return
    lastError = ""
    commit([device], Model.setLight(root.lights, device.key, patch))
  }

  // Every listed light on or off. Before the first snapshot there is no list to
  // go by yet, so the request waits for one rather than being lost.
  function setAll(on) {
    if (!loaded) { pendingAll = on ? "on" : "off"; return }
    var list = []
    var next = root.lights
    for (var i = 0; i < devices.length; i++) {
      if (!Model.isControllable(devices[i])) continue
      list.push(devices[i])
      next = Model.setLight(next, devices[i].key, { on: on })
    }
    if (list.length === 0) return
    lastError = ""
    commit(list, next)
  }

  // All off while anything is lit, all on otherwise; which of the two is only
  // known once the devices are.
  function toggleAll() {
    if (!loaded) { pendingAll = "toggle"; return }
    setAll(!anyOn)
  }

  function toggleDevice(device) {
    if (!device) return
    change(device, { on: !Model.lightState(root.lights, device.key).on })
  }

  // h/l on a row: a lit device's brightness.
  function adjustRow(device, delta) {
    if (!device || !Model.lightState(root.lights, device.key).on) return
    change(device, { brightness: Model.lightState(root.lights, device.key).brightness + delta * Model.BRIGHTNESS_STEP })
  }

  // The device a digit or `c` acts on: the one under the cursor, or the first
  // one that can be set when the cursor is elsewhere.
  function targetIndex() {
    if (cursorActive && cursorIndex < devices.length) return cursorIndex
    for (var i = 0; i < devices.length; i++) if (Model.isControllable(devices[i])) return i
    return -1
  }

  function pickSwatch(index) {
    var target = targetIndex()
    if (target < 0 || index < 0 || index >= Model.SWATCHES.length) return
    change(devices[target], { on: true, color: Model.SWATCHES[index].color })
  }

  // [ and ]: the previous or next effect, solid colour included in the ring.
  function stepEffect(delta) {
    var target = targetIndex()
    if (target < 0) return
    var device = devices[target]
    if (Model.effectModes(device).length === 0) return
    change(device, { on: true, effect: Model.nextEffect(device, Model.lightState(root.lights, device.key), delta) })
  }

  function focusColor() {
    var target = targetIndex()
    var row = target >= 0 ? deviceRepeater.itemAt(target) : null
    if (!row || !Model.lightState(root.lights, row.device.key).on) return
    row.focusColor()
  }

  function applyCustom(device, field) {
    var color = Model.normalizeColor(field.text)
    if (color === "") {
      colorError = "Try ff8000, #ff8000 or #f80"
      return
    }
    colorError = ""
    change(device, { on: true, color: color })
    field.text = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Keep the keyboard-focused row inside the viewport when the list is taller
  // than the popup. Mirrors the first-party panels' helper.
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

  function cursorDevice() {
    return cursorActive && cursorIndex < devices.length ? devices[cursorIndex] : null
  }

  function moveCursor(delta) {
    var n = cursorCount
    if (n === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = 0
      return
    }
    cursorIndex = ((cursorIndex + delta) % n + n) % n
  }

  function activateCursor() {
    if (!cursorActive) return
    if (cursorIndex < devices.length) {
      toggleDevice(devices[cursorIndex])
      return
    }
    var action = actions[cursorIndex - devices.length]
    if (action) action.run()
  }

  IpcHandler {
    target: "joamag.rgb"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function on(): void { root.setAll(true) }
    function off(): void { root.setAll(false) }
    // Build stamp so `omarchy-shell joamag.rgb version` tells which copy of
    // the code the shell is running after a reload.
    function version(): string { return "0.1.0" }
  }

  // The first snapshot is what puts the remembered colours back at login.
  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      colorError = ""
      refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: snapshotProc
    command: [root.scriptPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
    // Changes made while the devices were being listed, and the restore the
    // snapshot itself queued, wait for it to finish.
    onExited: Qt.callLater(root.flush)
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    onExited: {
      var error = Model.actionError(actionOut.text)
      if (error !== "") {
        root.lastError = error
        // A change that did not land is put back by the next snapshot, so a
        // restore that failed is tried again rather than counted as done.
        root.restored = Model.forgetRestored(root.restored, root.busyKey)
      }
      root.busyKey = ""
      Qt.callLater(root.flush)
    }
  }

  // At login the openrgb service can still be detecting when the first snapshot
  // asks, and answers with fewer devices than it has, or none. While a
  // remembered device is still owed its state, look again a few times; then
  // give up, so a device that is gone for good is not looked for forever.
  Timer {
    interval: 10000
    repeat: true
    running: root.restoreOnStart && root.restoreRetries < 6 && Model.awaitingRestore(root.snapshot, root.deviceFilter, root.lights, root.restored)
    onTriggered: {
      root.restoreRetries++
      root.refresh()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.ICON
    dimmed: root.loaded && (!root.ok || !root.anyOn)
    fontSize: Style.font.body
    horizontalMargin: 6
    fixedWidth: Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.snapshot, root.devices, root.lights)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleAll()
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
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingKey !== ""
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) { root.moveCursor(dy); return }
        if (root.cursorActive && root.cursorIndex >= root.devices.length) root.moveCursor(dx)
        else root.adjustRow(root.cursorDevice(), dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "a") root.toggleAll()
        else if (text === "c") root.focusColor()
        else if (text === "[") root.stepEffect(-1)
        else if (text === "]") root.stepEffect(1)
        else if (/^[1-9]$/.test(text)) root.pickSwatch(Number(text) - 1)
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: palette · title/status ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: Model.ICON
              color: root.anyOn ? root.foreground : root.dimColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Behavior on color { ColorAnimation { duration: 200 } }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Lighting"
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
                  var parts = [Model.heroStatus(root.snapshot, root.devices, root.lights)]
                  if (root.loading && root.loaded) parts.push("Updating")
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
          }

          // ---------- Nothing to light: say why ----------
          Column {
            visible: root.loaded && root.devices.length === 0
            width: parent.width
            spacing: Style.space(6)

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
              text: Model.stateDetail(root.snapshot, root.deviceFilter)
              visible: text !== ""
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }

          // ---------- Devices ----------
          Column {
            visible: root.devices.length > 0
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              id: deviceRepeater
              model: root.devices

              DeviceRow {
                required property var modelData
                required property int index
                width: parent.width
                device: modelData
                rowIndex: index
              }
            }
          }

          Text {
            visible: root.colorError !== ""
            textFormat: Text.PlainText
            text: root.colorError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
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
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                hasCursor: root.cursorActive && root.cursorIndex === root.devices.length + index
                onClicked: modelData.run()
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.cursorIndex = root.devices.length + index
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // One device: its type icon in the colour it is lit, name and state, and a
  // switch; under a lit device, its effects, the colour swatches with a hex
  // field, a brightness slider and, while an effect runs, its speed.
  component DeviceRow: CursorSurface {
    id: entry
    required property var device
    required property int rowIndex

    readonly property var light: Model.lightState(root.lights, device.key)
    readonly property bool controllable: Model.isControllable(device)
    readonly property var effects: Model.effectModes(device)
    readonly property string effect: Model.activeEffect(device, light)
    readonly property bool lit: controllable && light.on
    readonly property bool busy: root.busyKey !== "" && root.busyKey === device.key
    readonly property color tone: !lit ? root.dimColor : (light.known ? "#" + light.color : root.onColor)

    function focusColor() {
      Qt.callLater(function() { colorField.forceActiveFocus() })
    }

    implicitHeight: inner.implicitHeight + Style.spacing.lg
    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(entry)
    foreground: root.foreground
    opacity: controllable ? 1.0 : 0.45

    Column {
      id: inner
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
          text: entry.busy ? "󰑐" : Model.typeIcon(entry.device)
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
          width: parent.width - Style.space(22) - toggle.width - parent.spacing * 2
          spacing: Style.space(1)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            textFormat: Text.PlainText
            text: entry.device.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: Model.deviceDetail(entry.device, entry.light)
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        ToggleSwitch {
          id: toggle
          anchors.verticalCenter: parent.verticalCenter
          checked: entry.lit
          busy: entry.busy
          interactive: entry.controllable
          foreground: root.foreground
          accent: root.onColor
          onToggled: root.toggleDevice(entry.device)
          onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = entry.rowIndex } }
        }
      }

      // Effects: one pill per animation the device offers, solid colour first,
      // the running one lit, three to a row since a hub can offer a dozen.
      Grid {
        id: effectGrid
        visible: entry.lit && entry.effects.length > 0
        x: Style.space(30)
        width: parent.width - Style.space(30)
        columns: 3
        spacing: Style.spacing.xs

        readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

        Repeater {
          model: [""].concat(entry.effects)

          Button {
            required property string modelData
            width: effectGrid.cellWidth
            height: Style.spacing.controlHeight - Style.space(4)
            text: Model.effectLabel(modelData)
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.spacing.xs
            bordered: true
            active: entry.effect === modelData
            onClicked: root.change(entry.device, { on: true, effect: modelData })
          }
        }
      }

      // Colours: one dot per swatch, the current one ringed, then a field for
      // any other. Enter applies, Esc gives the keys back.
      Row {
        id: swatchRow
        visible: entry.lit
        x: Style.space(30)
        width: parent.width - Style.space(30)
        spacing: Style.space(4)

        Repeater {
          model: Model.SWATCHES

          Swatch {
            device: entry.device
            current: entry.light.known && Model.swatchIndex(entry.light.color) === index
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        TextField {
          id: colorField
          width: Math.max(Style.space(60), swatchRow.width - (Style.space(20) + swatchRow.spacing) * Model.SWATCHES.length)
          anchors.verticalCenter: parent.verticalCenter
          placeholderText: entry.light.known && Model.swatchIndex(entry.light.color) < 0 ? "#" + entry.light.color : "#hex  (c)"
          foreground: root.foreground
          font.family: root.fontFamily
          onTextChanged: root.colorError = ""
          onActiveFocusChanged: {
            if (activeFocus) root.editingKey = entry.device.key
            else if (root.editingKey === entry.device.key) root.editingKey = ""
          }

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              colorField.text = ""
              keyCatcher.forceActiveFocus()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.applyCustom(entry.device, colorField)
              event.accepted = true
            }
          }
        }
      }

      // Brightness under a lit device, and the speed while it runs an effect:
      // drag to set, released is sent.
      SliderRow {
        visible: entry.lit
        device: entry.device
        controlKey: "brightness"
        value: entry.light.brightness
      }

      SliderRow {
        visible: entry.lit && entry.effect !== ""
        device: entry.device
        controlKey: "speed"
        value: entry.light.speed
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: entry.controllable ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Declared before the controls' own areas would be; the switch, swatches
      // and slider sit above this and take their clicks first.
      z: -1
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.cursorIndex = entry.rowIndex
      }
      onClicked: root.toggleDevice(entry.device)
    }
  }

  // One slider under a lit device, what it sets named on its left: the
  // brightness, or the speed of the effect it runs. Released is sent.
  component SliderRow: Row {
    id: sliderRow
    required property var device
    required property string controlKey
    property real value: 0

    readonly property bool speed: controlKey === "speed"

    x: Style.space(30)
    width: parent.width - Style.space(30)
    spacing: Style.space(8)

    Text {
      id: sliderCaption
      textFormat: Text.PlainText
      text: sliderRow.speed ? "Speed" : "Light"
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: Style.space(40)
      anchors.verticalCenter: parent.verticalCenter
    }

    PanelSlider {
      bar: root.bar
      width: parent.width - sliderCaption.width - parent.spacing
      implicitHeight: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      minimum: sliderRow.speed ? 0 : Model.MIN_BRIGHTNESS
      maximum: sliderRow.speed ? 100 : Model.MAX_BRIGHTNESS
      step: sliderRow.speed ? Model.SPEED_STEP : Model.BRIGHTNESS_STEP
      integer: true
      value: sliderRow.value
      fillColor: root.onColor
      knobColor: root.onColor
      onReleased: function(v) { root.change(sliderRow.device, sliderRow.speed ? { speed: v } : { brightness: v }) }
    }
  }

  // One colour of the row: a dot in that colour, ringed when it is the
  // device's colour, outlined brighter under the pointer.
  component Swatch: Rectangle {
    id: swatch
    required property var modelData
    required property int index
    property var device: null
    property bool current: false

    width: Style.space(20)
    height: width
    radius: width / 2
    color: "#" + modelData.color
    border.width: current ? 2 : 1
    border.color: current || swatchMouse.containsMouse ? root.foreground : Util.alpha(root.foreground, 0.25)

    MouseArea {
      id: swatchMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.change(swatch.device, { on: true, color: swatch.modelData.color })
    }
  }
}
