import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Display controls in the bar: brightness, contrast, gamma and colour
// temperature, then the text size, scale and monitor list. Forked from
// Omarchy's first-party omarchy.monitor panel, which owns everything below the
// sliders; the contrast, gamma and temperature rows and the single-snapshot
// data path are the additions.
//
// Brightness and contrast are the monitor's own DDC/CI features, so they
// survive a reboot and apply to that panel alone. No monitor exposes a gamma
// VCP, so gamma and temperature are the compositor's gamma ramp, driven
// through wl-gammarelay-rs: a true exponent with 1.00 neutral, the same
// quantity the NVIDIA control panel calls gamma, covering every display.
Panel {
  id: root
  moduleName: "joamag.display"
  ipcTarget: "joamag.display"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/brightness/contrast/gamma to open/close.
  manageIpc: false

  property var snapshot: null
  property real brightnessPercent: NaN
  property real contrastPercent: NaN
  // A true gamma exponent, 1.00 neutral, the same quantity and range the
  // NVIDIA control panel calls gamma.
  property real gammaExponent: NaN
  property real temperatureKelvin: NaN
  property string monitorName: ""
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0

  // The control the pointer or keyboard is currently changing. Its value is
  // ours, not the monitor's, until the write lands: a refresh landing mid-drag
  // would otherwise yank the knob back to the last value read over i2c.
  property string activeControl: ""
  property string queuedControl: ""
  property real queuedValue: NaN
  // Live value while a knob is being dragged, for the hero line.
  property string dragControl: ""
  property real dragValue: NaN
  property string lastError: ""

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // Whether the ramp daemon was on the bus at the last snapshot. Brightness and
  // contrast live in the monitor's own memory and come back by themselves, but
  // the ramp is session state: a daemon that has just started is at 1.00 and
  // 6500K whatever the user last chose, so the remembered values are replayed
  // onto it the moment it appears.
  property bool rampPresent: false
  property int rampFailures: 0
  readonly property real savedGamma: Number(setting("gamma", 1))
  readonly property real savedTemperature: Number(setting("temperature", 6500))

  readonly property bool showContrast: setting("showContrast", true) !== false
  readonly property bool showGamma: setting("showGamma", true) !== false
  readonly property bool showTemperature: setting("showTemperature", true) !== false
  readonly property int wheelStep: Math.max(1, Math.min(25, Math.round(Number(setting("wheelStep", 5)) || 5)))
  readonly property int refreshIntervalSec: Math.max(2, Math.min(60, Math.round(Number(setting("refreshIntervalSec", 5)) || 5)))
  readonly property string scriptPath: String(Qt.resolvedUrl("display.sh")).replace(/^file:\/\//, "")

  readonly property bool loaded: snapshot !== null

  // The sliders this machine can actually drive, minus the ones switched off
  // in settings.
  readonly property var visibleControls: {
    var out = []
    var all = Model.visibleControls(snapshot)
    for (var i = 0; i < all.length; i++) {
      if (all[i] === "contrast" && !showContrast) continue
      if (all[i] === "gamma" && !showGamma) continue
      if (all[i] === "temperature" && !showTemperature) continue
      out.push(all[i])
    }
    return out
  }

  // Cursor model shared by keyboard and mouse, inherited from the first-party
  // panel. Slider sections use selectedIndex -1 as their sentinel; "scale" is
  // a horizontal row of presets; "monitors" is a vertical list.
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property var scaleValues: {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.availableScales(scalePresets, display.width, display.height)
    }
    return scalePresets
  }
  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel, which slides rows under a
  // stationary pointer and fires synthetic hover. While true, hover is not
  // allowed to hijack the keyboard focus section.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: {
    var list = []
    for (var i = 0; i < visibleControls.length; i++) list.push(visibleControls[i])
    list.push("textsize")
    list.push("scale")
    if (displays.length > 1) list.push("monitors")
    return list
  }

  function isControlSection(section) {
    return Model.controlByKey(section) !== null
  }

  function sectionCount(section) {
    if (isControlSection(section)) return 0  // only the slider sentinel at -1
    if (section === "textsize") return 0
    if (section === "scale") return scaleValues.length
    if (section === "monitors") return displays.length
    return 0
  }

  function sectionIsSingleRow(section) {
    // Sliders are lone rows; scale presets sit horizontally.
    return isControlSection(section) || section === "textsize" || section === "scale"
  }

  function sectionFirstIndex(section) {
    if (isControlSection(section) || section === "textsize") return -1
    return 0
  }

  // ---- Control values ----------------------------------------------------

  function controlValue(key) {
    if (key === "brightness") return brightnessPercent
    if (key === "contrast") return contrastPercent
    if (key === "gamma") return gammaExponent
    if (key === "temperature") return temperatureKelvin
    return NaN
  }

  function setControlValue(key, value) {
    if (key === "brightness") brightnessPercent = value
    else if (key === "contrast") contrastPercent = value
    else if (key === "gamma") gammaExponent = value
    else if (key === "temperature") temperatureKelvin = value
  }

  // Shown while dragging: the knob's own value, so the number and the hero
  // track the pointer rather than the last completed write.
  function displayValue(key) {
    return dragControl === key && isFinite(dragValue) ? dragValue : controlValue(key)
  }

  function refresh() {
    if (!snapshotProc.running) snapshotProc.running = true
  }

  function applySnapshot(raw) {
    var next = Model.parseSnapshot(raw)
    snapshot = next
    root.monitorName = next.monitor
    root.monitorScale = next.scale
    root.displays = next.displays
    root.enabledDisplayCount = next.enabledDisplayCount
    // Whatever the user is changing right now stays theirs.
    var keys = ["brightness", "contrast", "gamma", "temperature"]
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (activeControl === key || queuedControl === key) continue
      setControlValue(key, next[key])
    }
    clampCursor()
    applyRamp(next)
  }

  // One place decides what the ramp's state means, whether it came from a full
  // snapshot or from the cheap probe.
  function applyRamp(reading) {
    var present = isFinite(reading.gamma) || isFinite(reading.temperature)
    // Absent, or freshly back at its own defaults: either way the remembered
    // values have to be put on it again.
    if (!present || !rampPresent) restoreRamp()
    else {
      var keys = ["gamma", "temperature"]
      for (var i = 0; i < keys.length; i++) {
        if (activeControl === keys[i] || queuedControl === keys[i]) continue
        setControlValue(keys[i], reading[keys[i]])
      }
    }
    rampPresent = present
  }

  function restoreRamp() {
    if (restoreProc.running) return
    restoreProc.command = [root.scriptPath, "restore", String(savedGamma), String(savedTemperature)]
    restoreProc.running = true
  }

  // Optimistic: the knob and the number move now, the write follows after the
  // debounce so a drag does not put one i2c exchange on the bus per pixel.
  function previewControl(key, value) {
    var next = Model.clampControl(key, value)
    setControlValue(key, next)
    dragControl = key
    dragValue = next
    commitDebounce.controlKey = key
    commitDebounce.restart()
  }

  // Persist inline on this widget's shell.json entry, the way the clock stores
  // its format, so a choice survives a reboot and can be edited by hand.
  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function commitControl(key, value) {
    var next = Model.clampControl(key, value)
    setControlValue(key, next)
    // Brightness and contrast are remembered by the monitor itself; only the
    // session-wide ramp needs writing down.
    if (Model.controlScope(key) === "session") persistSetting(key, next)
    if (actionProc.running) {
      queuedControl = key
      queuedValue = next
      return
    }
    activeControl = key
    queuedControl = ""
    queuedValue = NaN
    lastError = ""
    // The ramp controls belong to the session, so they take no monitor name.
    actionProc.command = Model.controlScope(key) === "session"
      ? [root.scriptPath, key, String(next)]
      : [root.scriptPath, key, root.monitorName, String(next)]
    actionProc.running = true
  }

  // One keyboard press moves the knob a fixed distance along the track, so it
  // means the same amount of change wherever the control currently sits.
  function adjustControl(key, steps) {
    if (!isFinite(controlValue(key))) return
    commitDebounce.stop()
    dragControl = ""
    var position = Model.sliderFromValue(key, controlValue(key)) + steps * Model.controlKeyStep(key)
    commitControl(key, Model.valueFromSlider(key, position))
  }

  function applyAction(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts[0] === "error") lastError = parts.slice(1).join("\t")
    }
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  // ---- Cursor ------------------------------------------------------------

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l: walks the scale presets, steps the text size, and moves a slider;
  // every slider section adjusts its own control.
  function moveCursorH(delta) {
    if (focusSection === "scale") {
      var next = selectedIndex + delta
      if (next < 0) next = 0
      if (next > scaleValues.length - 1) next = scaleValues.length - 1
      selectedIndex = next
      return
    }
    if (focusSection === "textsize") { adjustTextSize(delta); return }
    if (isControlSection(focusSection)) adjustControl(focusSection, delta)
  }

  function activateCursor() {
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
      return
    }
    if (focusSection === "monitors" && selectedIndex >= 0 && selectedIndex < displays.length) {
      var d = displays[selectedIndex]
      if (d) toggleDisplay(d.name, d.enabled)
    }
    // sliders: no separate action; the value is the action.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      if (isControlSection(focusSection) || focusSection === "textsize") selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height.
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
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  // ---- Scale, text size, monitors (as the first-party panel does them) ----

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.matchingScaleIndex(scaleValues, monitorScale, display.width, display.height)
    }
    return -1
  }

  function effectiveScale(scale) {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.cleanScale(scale, display.width, display.height)
    }
    return normalizeScale(scale)
  }

  function toggleDisplay(name, enabled) {
    if (!name) return
    if (enabled && root.enabledDisplayCount <= 1) return

    hyprProc.command = ["hyprctl", "keyword", "monitor", name + (enabled ? ",disable" : ",preferred,auto,auto")]
    if (!hyprProc.running) hyprProc.running = true
  }

  function setScale(scale) {
    hyprProc.command = ["bash", "-c", "omarchy-hyprland-monitor-scaling " + scale]
    if (!hyprProc.running) hyprProc.running = true
  }

  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  IpcHandler {
    target: "joamag.display"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function brightness(percent: string): string { return root.setFromIpc("brightness", percent) }
    function contrast(percent: string): string { return root.setFromIpc("contrast", percent) }
    function gamma(exponent: string): string { return root.setFromIpc("gamma", exponent) }
    function temperature(kelvin: string): string { return root.setFromIpc("temperature", kelvin) }
    function state(): string {
      return JSON.stringify({
        monitor: root.monitorName,
        brightness: isFinite(root.brightnessPercent) ? root.brightnessPercent : null,
        contrast: isFinite(root.contrastPercent) ? root.contrastPercent : null,
        gamma: isFinite(root.gammaExponent) ? root.gammaExponent : null,
        temperature: isFinite(root.temperatureKelvin) ? root.temperatureKelvin : null,
        controls: root.visibleControls,
        scale: root.monitorScale
      })
    }
    // Build stamp so `omarchy-shell joamag.display version` tells which copy
    // of the code the shell is running after a reload.
    function version(): string { return "0.2.0" }
  }

  function setFromIpc(key, percent) {
    if (!isFinite(controlValue(key))) return "unavailable"
    commitDebounce.stop()
    dragControl = ""
    commitControl(key, Number(percent))
    return String(Model.clampControl(key, percent))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      var sections = visibleSections
      focusSection = sections.length > 0 ? sections[0] : "scale"
      selectedIndex = sectionFirstIndex(focusSection)
      cursorActive = false
    }
  }

  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Only poll while the panel is open: every refresh is an i2c exchange with
  // the monitor, and the bar glyph only tracks the monitor count.
  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // The ramp is session state, so somebody has to watch it even while the
  // popup is shut: at login the shell starts before the daemon does, and a
  // daemon that dies takes the remembered gamma with it. This probe is one
  // D-Bus round trip and never touches i2c, so it can run on its own timer;
  // it backs off once the daemon is up, and gives up after a few failed
  // revivals so a machine without the daemon is not nagged forever.
  Timer {
    id: rampCheck
    interval: root.rampPresent ? 15000 : 3000
    repeat: true
    running: root.rampFailures < 3
    triggeredOnStart: true
    onTriggered: if (!rampProc.running && !restoreProc.running) rampProc.running = true
  }

  Process {
    id: snapshotProc
    command: [root.scriptPath, "snapshot"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
  }

  Timer {
    id: commitDebounce
    property string controlKey: ""
    interval: 180
    repeat: false
    onTriggered: {
      if (controlKey === "") return
      root.dragControl = ""
      root.commitControl(controlKey, root.controlValue(controlKey))
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyAction(text) }
    // Deliberately no refresh() here: the value just written is authoritative,
    // and re-reading it over i2c straight away races the monitor's own update,
    // which reads back as the knob jumping. The open-panel timer picks up
    // changes made from the monitor's buttons.
    onRunningChanged: {
      if (running) return
      root.activeControl = ""
      if (root.queuedControl !== "") {
        var key = root.queuedControl
        var value = root.queuedValue
        root.queuedControl = ""
        root.queuedValue = NaN
        root.commitControl(key, value)
      }
    }
  }

  Process {
    id: hyprProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  // The cheap probe: the ramp values alone, no i2c traffic.
  Process {
    id: rampProc
    command: [root.scriptPath, "ramp"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyRamp(Model.parseSnapshot(text)) }
  }

  // Replays the remembered ramp values onto a daemon that has just started.
  // Kept off actionProc so it can never be dropped by that queue.
  Process {
    id: restoreProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.applyAction(text)
        // A restore that could not bring the daemon up counts against the
        // budget; one that worked clears the slate.
        if (String(text || "").indexOf("error\t") === 0) root.rampFailures++
        else {
          root.rampFailures = 0
          root.setControlValue("gamma", root.savedGamma)
          root.setControlValue("temperature", root.savedTemperature)
          root.rampPresent = true
        }
      }
    }
  }

  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displays.length > 1 ? Model.ICON_MULTI : Model.ICON
    tooltipText: root.opened ? "" : Model.tooltip(root.snapshot)
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!isFinite(root.brightnessPercent)) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      commitDebounce.stop()
      root.dragControl = ""
      root.commitControl("brightness", root.brightnessPercent + wheel.steps * root.wheelStep)
      root.showBrightnessOsd(root.brightnessPercent)
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
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r") root.refresh()
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

          // ---------- Hero: display icon · title/status ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.displays.length > 1 ? Model.ICON_MULTI : Model.ICON
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Display"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: Model.heroStatus(root.snapshot, root.displayValue("brightness"))
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Brightness, contrast, gamma ----------
          Repeater {
            model: root.visibleControls

            ControlSlider {
              required property string modelData
              width: panelColumn.width
              controlKey: modelData
            }
          }

          // Nothing to drive: say why, since an empty panel looks broken.
          Column {
            visible: root.loaded && root.visibleControls.length === 0
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.bar.foreground }

            Text {
              textFormat: Text.PlainText
              text: Model.unavailableDetail(root.snapshot) + (Model.rampDetail(root.snapshot) !== "" ? " " + Model.rampDetail(root.snapshot) : "")
              visible: text.trim() !== ""
              color: root.bar.foreground
              opacity: 0.7
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }

          // ---------- Text size ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                textFormat: Text.PlainText
                text: (textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "textsize"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Scale ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(scaleHeader.implicitHeight, scaleMonitor.implicitHeight)

              PanelSectionHeader {
                id: scaleHeader
                text: "SCALE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Name the monitor SCALE targets, since it only applies to the
              // focused one.
              Text {
                id: scaleMonitor
                textFormat: Text.PlainText
                text: root.monitorName
                visible: root.monitorName !== "" && root.enabledDisplayCount > 1
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Grid {
              id: scaleRow
              width: parent.width
              columns: root.scaleValues.length
              spacing: Style.spacing.xs

              readonly property real cellWidth: root.scaleValues.length > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.scaleValues

                ScalePill {
                  required property string modelData
                  required property int index

                  scaleValue: modelData
                  scaleIndex: index
                  width: scaleRow.cellWidth
                }
              }
            }
          }

          // ---------- Monitors ----------
          PanelSeparator {
            visible: root.displays.length > 1
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.displays.length > 1

            PanelSectionHeader {
              text: "DISPLAYS"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.displays

              MonitorRow {
                required property var modelData
                required property int index

                width: panelColumn.width
                display: modelData
                rowIndex: index
              }
            }
          }

          // ---------- Failure line ----------
          Text {
            visible: root.lastError !== ""
            textFormat: Text.PlainText
            text: root.lastError
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  // One slider row: section header with the live percentage on the right, and
  // a slider underneath that writes through display.sh.
  component ControlSlider: Column {
    id: control
    required property string controlKey

    readonly property real currentValue: root.displayValue(controlKey)
    readonly property bool focused: root.cursorActive && root.focusSection === controlKey && root.selectedIndex === -1

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(controlHeader.implicitHeight, controlPercent.implicitHeight)

      PanelSectionHeader {
        id: controlHeader
        text: Model.controlTitle(control.controlKey)
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: controlPercent
        textFormat: Text.PlainText
        // Gamma and temperature are the session's ramp, not this monitor's, so
        // they say so rather than looking like more panel knobs.
        text: (Model.controlScope(control.controlKey) === "session" ? "all displays · " : "") + Model.formatControl(control.controlKey, control.currentValue)
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    CursorSurface {
      id: controlRow
      width: parent.width
      height: controlSlider.implicitHeight + Style.spacing.controlGap
      hasCursor: control.focused
      onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(controlRow)
      foreground: root.bar.foreground
      outline: true

      PanelSlider {
        id: controlSlider
        bar: root.bar
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        // Every slider is 0..100 units of travel; the control's own curve turns
        // a position into a value, so gamma gets a log track while the rest
        // stay linear and the knob never has a dead stretch.
        minimum: 0
        maximum: 100
        step: 1
        integer: false
        value: Model.sliderFromValue(control.controlKey, control.currentValue)
        onMoved: function(v) { root.previewControl(control.controlKey, Model.valueFromSlider(control.controlKey, v)) }
        onReleased: function(v) {
          commitDebounce.stop()
          root.dragControl = ""
          root.commitControl(control.controlKey, Model.valueFromSlider(control.controlKey, v))
        }
      }

      HoverHandler {
        onHoveredChanged: if (hovered && !root.reflowingText) {
          root.cursorActive = true
          root.focusSection = control.controlKey
          root.selectedIndex = -1
        }
      }
    }
  }

  component ScalePill: Button {
    id: pill
    required property string scaleValue
    required property int scaleIndex

    text: root.effectiveScale(scaleValue) + "x"
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.activeScaleIndex() === scaleIndex
    hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === scaleIndex

    onClicked: root.setScale(scaleValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "scale"
      root.selectedIndex = pill.scaleIndex
    }
  }

  component MonitorRow: CursorSurface {
    id: monitorRow
    required property var display
    required property int rowIndex

    readonly property bool isFocused: display && display.focused
    readonly property bool canToggle: display && (!display.enabled || root.enabledDisplayCount > 1)

    hasCursor: root.cursorActive && root.focusSection === "monitors" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(monitorRow)
    current: isFocused
    foreground: root.bar.foreground
    fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
    currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)
    implicitHeight: monitorInner.implicitHeight + Style.spacing.xl
    opacity: canToggle ? 1.0 : 0.45

    Row {
      id: monitorInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: Model.ICON
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.name + (monitorRow.display.focused ? " · focused" : "")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(14) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.enabled ? "󰄬" : ""
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        width: Style.space(14)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: monitorRow.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
        root.cursorActive = true
        root.focusSection = "monitors"
        root.selectedIndex = monitorRow.rowIndex
      }
      onClicked: if (monitorRow.canToggle) root.toggleDisplay(monitorRow.display.name, monitorRow.display.enabled)
    }
  }
}
