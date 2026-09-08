import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Sleeping-face icon in the bar, crossed out while auto sleep is off, with
// the timeout next to it; the popup sets that timeout from a row of presets
// or a typed duration, toggles Omarchy's stay awake, and can sleep the
// machine now. The sleeping itself is done by Service.qml, which this widget
// binds to directly through the shell.
Panel {
  id: root
  moduleName: "joamag.suspend"
  // The service owns the plugin's own IPC target; the popup answers on its
  // own, so `omarchy-shell joamag.suspend.panel toggle` opens it.
  ipcTarget: "joamag.suspend.panel"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("joamag.suspend") : null
  readonly property bool showLabel: setting("showLabel", true) !== false
  // The service is the source of truth for the timeout, since it is what
  // sleeps; the setting is what it reads, so the two agree.
  readonly property int timeoutSeconds: service ? service.timeoutSeconds : Model.timeoutSeconds({ timeoutSec: setting("timeoutSec", Model.DEFAULT_TIMEOUT_SECONDS) }, Model.DEFAULT_TIMEOUT_SECONDS)
  readonly property bool armed: timeoutSeconds > 0
  readonly property bool idle: service ? service.idle : false
  readonly property string lastVerdict: service ? service.lastVerdict : ""
  readonly property string lastReason: service ? service.lastReason : ""
  readonly property int presetIndex: Model.presetIndex(timeoutSeconds)

  property bool stayAwake: false
  property bool stayAwakeKnown: false
  property string customError: ""
  // "Sleep now" asks twice: the first press arms the button for a few
  // seconds, the second one runs it.
  property string armedKey: ""
  property bool cursorActive: false
  // The cursor walks the presets first, then the footer actions.
  property int cursorIndex: 0

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string barText: Model.barText(armed, timeoutSeconds, showLabel, vertical)
  readonly property bool barHasLabel: showLabel && !vertical && armed
  readonly property real openPanelIndicatorWidth: barHasLabel ? button.labelWidth : 0

  readonly property var actions: [
    { label: root.stayAwake ? "Allow sleep" : "Stay awake", icon: root.stayAwake ? "󰒲" : "󰛊", tooltip: root.stayAwake ? "Let the machine idle and sleep again" : "Keep the machine awake until switched back (Omarchy's stay awake)", run: function() { root.toggleStayAwake() } },
    { label: root.armedKey === "sleep" ? "Sure?" : "Sleep now", icon: "󰤄", tooltip: "Suspend the machine right away, after the usual checks", run: function() { root.sleepNow() } }
  ]

  readonly property int cursorCount: Model.PRESETS.length + actions.length

  // Persist inline on this widget's shell.json entry, which is the entry the
  // service reads its timeout from, so a click here changes the sleep.
  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setTimeout(seconds) {
    var n = Math.max(0, Math.round(Number(seconds) || 0))
    customError = ""
    persistSetting("timeoutSec", n)
  }

  function applyCustom() {
    var seconds = Model.parseDuration(customField.text)
    if (!isFinite(seconds)) {
      customError = "Try 45, 45m, 1.5h or 2h30; 0 or never switches it off"
      return
    }
    setTimeout(seconds)
    customField.text = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function focusCustom() {
    Qt.callLater(function() { customField.forceActiveFocus() })
  }

  function refreshStayAwake() {
    if (!stayAwakeProc.running) stayAwakeProc.running = true
  }

  function toggleStayAwake() {
    if (toggleProc.running) return
    toggleProc.running = true
  }

  function sleepNow() {
    if (!service) return
    if (armedKey !== "sleep") {
      armedKey = "sleep"
      disarmTimer.restart()
      return
    }
    armedKey = ""
    disarmTimer.stop()
    service.fire("panel")
    root.close()
  }

  function moveCursor(delta) {
    var n = cursorCount
    if (n === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = presetIndex >= 0 ? presetIndex : 0
      return
    }
    cursorIndex = ((cursorIndex + delta) % n + n) % n
  }

  function activateCursor() {
    if (!cursorActive) return
    if (cursorIndex < Model.PRESETS.length) {
      setTimeout(Model.PRESETS[cursorIndex].seconds)
      return
    }
    var action = actions[cursorIndex - Model.PRESETS.length]
    if (action) action.run()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = presetIndex >= 0 ? presetIndex : 0
      armedKey = ""
      customError = ""
      refreshStayAwake()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Omarchy's stay awake state, from the idle service's own report.
  Process {
    id: stayAwakeProc
    command: ["omarchy-shell", "idle", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var status = JSON.parse(String(text || "").trim())
          root.stayAwake = status && status.stayAwake === true
          root.stayAwakeKnown = true
        } catch (e) {
          root.stayAwakeKnown = false
        }
      }
    }
  }

  Process {
    id: toggleProc
    command: ["omarchy-toggle-idle", "toggle"]
    onExited: root.refreshStayAwake()
  }

  Timer {
    id: disarmTimer
    interval: 4000
    onTriggered: root.armedKey = ""
  }

  // The stay awake indicator can be flipped from the bar too; keep in step
  // while the popup is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refreshStayAwake()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    dimmed: !root.armed
    fontSize: Style.font.body
    horizontalMargin: root.barHasLabel ? 8.75 : 6
    fixedWidth: root.barHasLabel ? -1 : Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.armed, root.timeoutSeconds, root.lastVerdict, root.lastReason)

    onPressed: function(b) {
      // Right click flips between the configured timeout and never.
      if (b === Qt.RightButton) root.setTimeout(root.armed ? 0 : Model.DEFAULT_TIMEOUT_SECONDS)
      else if (b === Qt.MiddleButton) root.refreshStayAwake()
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
      blocked: customField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dx !== 0 ? dx : dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "c") root.focusCustom()
        else if (text === "s") root.sleepNow()
        else if (text === "w") root.toggleStayAwake()
        else if (text === "n") root.setTimeout(0)
        else if (/^[1-5]$/.test(text)) root.setTimeout(Model.PRESETS[Number(text) - 1].seconds)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: icon · title/status · timeout ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: Model.barIcon(root.armed)
            color: root.armed ? root.foreground : Util.alpha(root.foreground, 0.45)
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
            anchors.right: heroValue.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Suspend"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: Model.heroStatus(root.armed, root.timeoutSeconds, root.idle, root.stayAwake)
              color: root.stayAwake ? Color.urgent : Qt.darker(root.foreground, 1.4)
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
            text: Model.shortTimeout(root.timeoutSeconds)
            color: root.armed ? root.foreground : Util.alpha(root.foreground, 0.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Presets ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "SLEEP AFTER"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: presetRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * (Model.PRESETS.length - 1)) / Model.PRESETS.length

            Repeater {
              model: Model.PRESETS

              Button {
                required property var modelData
                required property int index
                width: presetRow.cellWidth
                height: Style.spacing.controlHeight
                text: modelData.label
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.sm
                verticalPadding: Style.spacing.xs
                bordered: true
                active: root.presetIndex === index
                hasCursor: root.cursorActive && root.cursorIndex === index
                onClicked: root.setTimeout(modelData.seconds)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.cursorIndex = index
                  }
                }
              }
            }
          }

          // A custom timeout, typed. Enter applies, Esc gives the keys back.
          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: customField
              width: parent.width - customHint.width - parent.spacing
              placeholderText: root.presetIndex < 0 && root.armed ? "Custom: " + Model.describeTimeout(root.timeoutSeconds) + "  (c to change)" : "Custom, e.g. 45m or 1.5h  (c)"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.customError = ""

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  customField.text = ""
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.applyCustom()
                  event.accepted = true
                }
              }
            }

            Text {
              id: customHint
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Enter sets"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: root.customError !== ""
            textFormat: Text.PlainText
            text: root.customError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }

        // ---------- What the service knows ----------
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          InfoPair { label: "Service"; value: root.service ? (root.armed ? "armed" : "off") : "not running" }
          InfoPair { label: "Idle now"; value: root.service ? (root.idle ? "yes" : "no") : "—" }
          InfoPair { label: "Stay awake"; value: root.stayAwakeKnown ? (root.stayAwake ? "on" : "off") : "—" }
          InfoPair { visible: root.lastVerdict !== ""; label: "Last"; value: Model.verdictLabel(root.lastVerdict, root.lastReason) }
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
              foreground: index === 1 && root.armedKey === "sleep" ? Color.urgent : root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              hasCursor: root.cursorActive && root.cursorIndex === Model.PRESETS.length + index
              onClicked: modelData.run()
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.cursorIndex = Model.PRESETS.length + index
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      textFormat: Text.PlainText
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
