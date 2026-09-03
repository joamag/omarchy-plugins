import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One symbol in the bar with its daily move; the popup charts the selected
// symbol over a switchable range and lists the whole watchlist with
// sparklines. Left click opens, right click pins the next symbol, scroll walks
// the list, middle click refreshes.
Panel {
  id: root
  moduleName: "joamag.stocks"
  ipcTarget: "joamag.stocks"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add refresh/cycleSymbol/version to open/close/toggle.
  manageIpc: false

  // symbol -> latest intraday quote object from quotes.sh
  property var quotes: ({})
  // "symbol|range" -> { points, prevClose, fetchedAt }
  property var seriesCache: ({})
  property string selectedSymbol: ""
  property string range: Model.normalizeRange(setting("range", "1d"))
  property bool quotesLoading: false
  property bool seriesLoading: false
  property string lastError: ""
  property double lastUpdated: 0
  property bool cursorActive: false
  property int cursorIndex: 0
  // Interactive watchlist editing: the add field at the bottom of the list,
  // the symbol being validated against Yahoo and the last validation error.
  property bool editing: false
  property bool validating: false
  property string pendingSymbol: ""
  property string addError: ""
  // Autocomplete for the add field: Yahoo search results for the current
  // text, and which one the arrow keys have highlighted (-1 = typed text).
  property var suggestions: []
  property int suggestionIndex: -1
  property string searchQuery: ""

  // Chart point under the pointer, or null. While set, the hero shows that
  // point's price and its change against the previous close.
  readonly property var hoveredPoint: bigChart.hoverPoint
  readonly property real hoveredChange: hoveredPoint && root.activeSeries ? hoveredPoint.v - Number(root.activeSeries.prevClose) : NaN
  readonly property real hoveredChangePct: {
    if (!hoveredPoint || !root.activeSeries) return NaN
    var prev = Number(root.activeSeries.prevClose)
    return isFinite(prev) && prev !== 0 ? (hoveredPoint.v - prev) / prev * 100 : NaN
  }

  readonly property var symbols: Model.parseSymbols(setting("symbols", Model.DEFAULT_SYMBOLS))
  readonly property string barSymbol: {
    var configured = String(setting("barSymbol", symbols[0]) || "").trim()
    return symbols.indexOf(configured) >= 0 ? configured : symbols[0]
  }
  readonly property bool showPrice: setting("showPrice", false) === true
  readonly property bool showChange: setting("showChange", true) !== false
  readonly property int refreshIntervalSec: Math.max(15, Math.round(Number(setting("refreshIntervalSec", 60)) || 60))
  readonly property string scriptPath: String(Qt.resolvedUrl("quotes.sh")).replace(/^file:\/\//, "")

  readonly property var barQuote: quotes[barSymbol]
  readonly property real barChangePct: Model.changePct(barQuote)
  readonly property string barText: vertical ? Model.ICON : Model.barText(barSymbol, barQuote, showPrice, showChange)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color upColor: Color.accent
  readonly property color downColor: Color.urgent
  readonly property real openPanelIndicatorWidth: vertical ? 0 : button.labelWidth

  readonly property string activeSymbol: selectedSymbol !== "" && symbols.indexOf(selectedSymbol) >= 0 ? selectedSymbol : barSymbol
  readonly property var activeQuote: quotes[activeSymbol]
  readonly property var activeSeries: {
    // The 1d range is what quotes.sh already fetched for every row; longer
    // ranges come from the series cache.
    if (range === "1d") return activeQuote && activeQuote.points ? { points: activeQuote.points, prevClose: activeQuote.prevClose } : null
    var entry = seriesCache[Model.seriesKey(activeSymbol, range)]
    return entry || null
  }
  readonly property real activeRangePct: range === "1d" ? Model.changePct(activeQuote) : Model.seriesChangePct(activeSeries)

  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: "Refresh quotes", run: function() { root.refresh() } },
    { label: "Pin", icon: "󰐃", tooltip: "Show " + Model.shortLabel(root.activeSymbol) + " in the bar", run: function() { root.pinSymbol(root.activeSymbol) } },
    { label: "Open", icon: "󰏌", tooltip: "Open " + Model.shortLabel(root.activeSymbol) + " on Yahoo Finance", run: function() { root.openInBrowser(root.activeSymbol) } },
    { label: "Add", icon: "󰐕", tooltip: "Add a symbol to the watchlist", run: function() { root.startAdding() } }
  ]

  // Keyboard cursor walks the watchlist rows first, then the footer actions.
  readonly property int cursorCount: symbols.length + actions.length

  function trendColor(value) {
    var t = Model.trend(value)
    if (t > 0) return upColor
    if (t < 0) return downColor
    return foreground
  }

  function refresh() {
    if (quotesProc.running || symbols.length === 0) return
    quotesLoading = true
    quotesProc.command = [root.scriptPath, "quotes"].concat(symbols)
    quotesProc.running = true
  }

  function applyQuotes(raw) {
    var list = Model.parseLines(raw)
    if (list.length === 0) {
      lastError = "No market data returned"
      return
    }
    var next = {}
    for (var key in quotes) next[key] = quotes[key]
    var failures = []
    for (var i = 0; i < list.length; i++) {
      var q = list[i]
      if (q.error) {
        // Keep the last good quote, remember the failure for the status line.
        if (!next[q.symbol]) next[q.symbol] = q
        failures.push(q.symbol)
        continue
      }
      next[q.symbol] = q
    }
    quotes = next
    lastUpdated = Date.now()
    lastError = failures.length > 0 ? "No data for " + failures.join(", ") : ""
  }

  function ensureSeries() {
    if (!opened || range === "1d") return
    var key = Model.seriesKey(activeSymbol, range)
    if (Model.seriesFresh(seriesCache[key], range) || seriesProc.running) return
    seriesLoading = true
    seriesProc.command = [root.scriptPath, "series", activeSymbol, range]
    seriesProc.running = true
  }

  function applySeries(raw) {
    var list = Model.parseLines(raw)
    if (list.length === 0 || list[0].error) {
      lastError = list.length > 0 ? String(list[0].error) : "No chart data returned"
      return
    }
    var s = list[0]
    var next = {}
    for (var key in seriesCache) next[key] = seriesCache[key]
    next[Model.seriesKey(s.symbol, s.range)] = { points: s.points || [], prevClose: s.prevClose, fetchedAt: Date.now() }
    seriesCache = next
  }

  function selectSymbol(symbol) {
    if (symbols.indexOf(symbol) < 0) return
    selectedSymbol = symbol
    ensureSeries()
  }

  function setRange(key) {
    range = Model.normalizeRange(key)
    persistSetting("range", range)
    ensureSeries()
  }

  function stepRange(delta) {
    var idx = Model.rangeIndex(range) + delta
    var n = Model.RANGES.length
    setRange(Model.RANGES[((idx % n) + n) % n].key)
  }

  function cycleSymbol(delta) {
    pinSymbol(Model.nextSymbol(symbols, barSymbol, delta === undefined ? 1 : delta))
  }

  // Persist inline settings on this widget's shell.json entry, the way the
  // clock stores its format, so they survive a shell restart. The watchlist
  // lives there too, which is why editing it in the popup and editing the
  // file are the same thing.
  function persistSettings(changes) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var key in changes) entry[key] = changes[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistSetting(key, value) {
    var changes = {}
    changes[key] = value
    persistSettings(changes)
  }

  // ---- Watchlist editing -------------------------------------------------

  function saveSymbols(list) {
    var cleaned = Model.parseSymbols(list)
    var changes = { symbols: cleaned.join(",") }
    if (cleaned.indexOf(barSymbol) < 0) changes.barSymbol = cleaned[0]
    persistSettings(changes)
    if (cleaned.indexOf(selectedSymbol) < 0) selectedSymbol = cleaned[0]
    if (cursorIndex >= cursorCount) cursorIndex = Math.max(0, cursorCount - 1)
  }

  function addSymbol(symbol) {
    var s = String(symbol || "").trim().toUpperCase()
    if (s === "" || symbols.indexOf(s) >= 0) return false
    saveSymbols(symbols.concat([s]))
    return true
  }

  function removeSymbol(symbol) {
    var idx = symbols.indexOf(symbol)
    if (idx < 0) return false
    if (symbols.length <= 1) {
      lastError = "Keep at least one symbol in the watchlist"
      return false
    }
    var next = symbols.slice()
    next.splice(idx, 1)
    saveSymbols(next)
    return true
  }

  function moveSymbol(symbol, delta) {
    var idx = symbols.indexOf(symbol)
    var target = idx + delta
    if (idx < 0 || target < 0 || target >= symbols.length) return
    var next = symbols.slice()
    next.splice(idx, 1)
    next.splice(target, 0, symbol)
    saveSymbols(next)
    cursorActive = true
    cursorIndex = target
  }

  function cursorSymbol() {
    return cursorActive && cursorIndex < symbols.length ? symbols[cursorIndex] : activeSymbol
  }

  function startAdding() {
    editing = true
    addError = ""
    addField.text = ""
    clearSuggestions()
    Qt.callLater(function() { addField.forceActiveFocus() })
  }

  function cancelAdding() {
    editing = false
    validating = false
    pendingSymbol = ""
    addError = ""
    clearSuggestions()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function clearSuggestions() {
    suggestions = []
    suggestionIndex = -1
    searchQuery = ""
    searchDebounce.stop()
  }

  // Debounced Yahoo symbol search for whatever is in the add field.
  function runSearch() {
    var query = String(addField.text || "").trim()
    if (!editing || query.length < 1) { clearSuggestions(); return }
    if (searchProc.running) { searchDebounce.restart(); return }
    searchQuery = query
    searchProc.command = [root.scriptPath, "search", query]
    searchProc.running = true
  }

  function applySearch(raw) {
    var result = Model.parseSearch(raw)
    // Ignore answers for text the user has already typed past.
    if (!editing || result.query !== String(addField.text || "").trim()) return
    suggestions = Model.filterSuggestions(result.results, symbols)
    if (suggestionIndex >= suggestions.length) suggestionIndex = suggestions.length - 1
  }

  function moveSuggestion(delta) {
    if (suggestions.length === 0) { suggestionIndex = -1; return }
    suggestionIndex = Math.max(-1, Math.min(suggestions.length - 1, suggestionIndex + delta))
  }

  function chooseSuggestion(index) {
    if (index < 0 || index >= suggestions.length) return
    commitAdd(String(suggestions[index].symbol))
  }

  // Enter in the add field: check the symbol exists on Yahoo before it lands
  // in the list, so a typo shows an error instead of a dead row. A highlighted
  // suggestion takes precedence over the typed text.
  function commitAdd(symbolOverride) {
    var symbol = String(symbolOverride || addField.text || "").trim().toUpperCase()
    if (symbol === "") { cancelAdding(); return }
    if (symbols.indexOf(symbol) >= 0) {
      addError = Model.shortLabel(symbol) + " is already in the watchlist"
      return
    }
    if (validateProc.running) return
    pendingSymbol = symbol
    validating = true
    addError = ""
    validateProc.command = [root.scriptPath, "quotes", symbol]
    validateProc.running = true
  }

  function applyValidation(raw) {
    var list = Model.parseLines(raw)
    var symbol = pendingSymbol
    validating = false
    pendingSymbol = ""
    if (symbol === "" || !editing) return
    if (list.length === 0 || list[0].error) {
      addError = "Unknown symbol " + symbol + (list.length > 0 && list[0].error ? " · " + list[0].error : "")
      return
    }
    // Seed the quote so the new row shows data right away, then persist.
    var next = {}
    for (var key in quotes) next[key] = quotes[key]
    next[symbol] = list[0]
    quotes = next
    addSymbol(symbol)
    selectedSymbol = symbol
    cursorActive = true
    cursorIndex = Math.max(0, symbols.indexOf(symbol))
    ensureSeries()
    // Stay in the field so several symbols can be typed in a row.
    addField.text = ""
    clearSuggestions()
    addField.forceActiveFocus()
  }

  function pinSymbol(symbol) {
    if (symbols.indexOf(symbol) < 0) return
    persistSetting("barSymbol", symbol)
  }

  function openInBrowser(symbol) {
    if (!root.bar || !symbol) return
    root.bar.run("omarchy-launch-browser 'https://finance.yahoo.com/quote/" + encodeURIComponent(symbol) + "'")
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
    if (cursorIndex < symbols.length) {
      selectSymbol(symbols[cursorIndex])
      return
    }
    var action = actions[cursorIndex - symbols.length]
    if (action) action.run()
  }

  IpcHandler {
    target: "joamag.stocks"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function cycleSymbol(): void { root.cycleSymbol(1) }
    function addSymbol(symbol: string): string { return root.addSymbol(symbol) ? "ok" : "exists" }
    function removeSymbol(symbol: string): string { return root.removeSymbol(String(symbol || "").trim().toUpperCase()) ? "ok" : "unknown" }
    function version(): string { return "0.2.0" }
  }

  onOpenedChanged: {
    if (opened) {
      selectedSymbol = barSymbol
      cursorActive = false
      cursorIndex = Math.max(0, symbols.indexOf(barSymbol))
      refresh()
      ensureSeries()
    } else if (editing) {
      cancelAdding()
    }
  }

  onSymbolsChanged: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: quotesProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyQuotes(text) }
    onExited: root.quotesLoading = false
  }

  Process {
    id: seriesProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySeries(text) }
    onExited: {
      root.seriesLoading = false
      // The selection may have moved while this fetch ran.
      Qt.callLater(root.ensureSeries)
    }
  }

  Process {
    id: validateProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyValidation(text) }
    onExited: if (root.validating) root.applyValidation("")
  }

  Process {
    id: searchProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySearch(text) }
  }

  Timer {
    id: searchDebounce
    interval: 220
    repeat: false
    onTriggered: root.runSearch()
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
    // A falling pinned symbol turns the label urgent, the way the microphone
    // turns urgent while it is live.
    active: root.showChange && Model.trend(root.barChangePct) < 0
    dimmed: !Model.hasQuote(root.barQuote) && root.quotesLoading
    fontSize: Style.font.body
    horizontalMargin: root.vertical ? 6 : 8.75
    fixedWidth: root.vertical ? Style.bar.iconSlot : -1
    tooltipText: root.opened ? "" : Model.tooltip(root.barSymbol, root.barQuote)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleSymbol(1)
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.cycleSymbol(delta > 0 ? -1 : 1) }
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
      blocked: root.editing
      onDeleteRequested: if (root.cursorActive && root.cursorIndex < root.symbols.length) root.removeSymbol(root.symbols[root.cursorIndex])
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) { root.moveCursor(dy); return }
        // Left/right steps the range while the cursor sits on the chart or
        // the watchlist, and moves along the footer once it reaches it.
        if (root.cursorActive && root.cursorIndex >= root.symbols.length) root.moveCursor(dx)
        else root.stepRange(dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "o") root.openInBrowser(root.activeSymbol)
        else if (text === "p") root.pinSymbol(root.activeSymbol)
        else if (text === "r") root.refresh()
        else if (text === "a") root.startAdding()
        else if (text === "J") root.moveSymbol(root.cursorSymbol(), 1)
        else if (text === "K") root.moveSymbol(root.cursorSymbol(), -1)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: selected symbol · name/state · price and change ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroLabels.implicitHeight, heroValues.implicitHeight)

          Column {
            id: heroLabels
            anchors.left: parent.left
            anchors.right: heroValues.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: Model.primaryLabel(root.activeSymbol, root.activeQuote)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: {
                var parts = []
                var secondary = Model.secondaryLabel(root.activeSymbol, root.activeQuote)
                if (secondary) parts.push(secondary)
                if (root.hoveredPoint) parts.push("At " + Model.formatPointTime(root.hoveredPoint.t, root.range))
                else {
                  var state = Model.marketStateLabel(root.activeQuote)
                  if (state) parts.push(state)
                  if (root.quotesLoading) parts.push("Updating")
                }
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

          Column {
            id: heroValues
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.hoveredPoint
                ? Model.formatPrice(root.hoveredPoint.v, root.activeQuote ? root.activeQuote.currency : "", root.activeSymbol)
                : Model.formatPrice(root.activeQuote)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
              anchors.right: parent.right
            }

            Text {
              textFormat: Text.PlainText
              text: {
                if (root.hoveredPoint) {
                  if (!isFinite(root.hoveredChange)) return "—"
                  var sign = root.hoveredChange > 0 ? "+" : ""
                  return Model.trendGlyph(root.hoveredChange) + " " + sign + Model.formatNumber(root.hoveredChange, Model.priceDecimals(root.hoveredPoint.v)) + " (" + Model.formatPct(root.hoveredChangePct) + ")"
                }
                return Model.hasQuote(root.activeQuote) ? Model.trendGlyph(Model.change(root.activeQuote)) + " " + Model.formatChange(root.activeQuote) : "—"
              }
              color: root.trendColor(root.hoveredPoint ? root.hoveredChange : Model.change(root.activeQuote))
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              anchors.right: parent.right

              Behavior on color { ColorAnimation { duration: 200 } }
            }
          }
        }

        // ---------- Big chart ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(132)

          LineChart {
            id: bigChart
            anchors.fill: parent
            points: root.activeSeries && root.activeSeries.points ? root.activeSeries.points : []
            referenceValue: root.activeSeries ? Number(root.activeSeries.prevClose) : NaN
            lineColor: root.trendColor(root.activeRangePct)
            fillTop: Util.alpha(root.trendColor(root.activeRangePct), 0.28)
            fillBottom: Util.alpha(root.trendColor(root.activeRangePct), 0.0)
            baselineColor: Util.alpha(root.foreground, 0.35)
            gridColor: Util.alpha(root.foreground, 0.08)
            lineWidth: 1.6
            padTop: Style.space(16)
            padBottom: Style.space(14)
            showEndDot: true
          }

          // Range extremes in the corners, axis labels along the bottom.
          Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: isFinite(bigChart.maxValue) ? "H " + Model.formatNumber(bigChart.maxValue, Model.priceDecimals(bigChart.maxValue)) : ""
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: isFinite(root.activeRangePct) ? Model.rangeLabel(root.range) + " " + Model.trendGlyph(root.activeRangePct) + Model.formatPct(Math.abs(root.activeRangePct), false) : Model.rangeLabel(root.range)
            color: root.trendColor(root.activeRangePct)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: bigChart.points.length > 0 ? Model.formatAxis(bigChart.points[0][0], root.range) : ""
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: isFinite(bigChart.minValue) ? "L " + Model.formatNumber(bigChart.minValue, Model.priceDecimals(bigChart.minValue)) : ""
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: bigChart.points.length > 0 ? Model.formatAxis(bigChart.points[bigChart.points.length - 1][0], root.range) : ""
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.centerIn: parent
            visible: bigChart.points.length === 0
            text: root.seriesLoading || root.quotesLoading ? "Loading chart…" : (root.lastError !== "" ? root.lastError : "No chart data")
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // Hover crosshair: hairline and dot on the nearest point, with a
          // small bubble carrying time and price. The hero above mirrors it.
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            cursorShape: bigChart.points.length > 0 ? Qt.CrossCursor : Qt.ArrowCursor
            onPositionChanged: function(mouse) { bigChart.hoverIndex = bigChart.indexAt(mouse.x) }
            onExited: bigChart.hoverIndex = -1
          }

          Rectangle {
            visible: root.hoveredPoint !== null
            x: root.hoveredPoint ? Math.round(root.hoveredPoint.x) : 0
            y: bigChart.padTop
            width: 1
            height: parent.height - bigChart.padTop - bigChart.padBottom
            color: Util.alpha(root.foreground, 0.35)
          }

          Rectangle {
            visible: root.hoveredPoint !== null
            x: root.hoveredPoint ? root.hoveredPoint.x - width / 2 : 0
            y: root.hoveredPoint ? root.hoveredPoint.y - height / 2 : 0
            width: Style.space(9)
            height: Style.space(9)
            radius: width / 2
            color: Color.popups.background
            border.width: 2
            border.color: root.trendColor(root.activeRangePct)
          }

          Rectangle {
            id: hoverBubble
            visible: root.hoveredPoint !== null
            width: hoverBubbleText.implicitWidth + Style.space(12)
            height: hoverBubbleText.implicitHeight + Style.space(6)
            // Centered on the point, kept inside the chart, flipped below the
            // point when there is no room above it.
            x: root.hoveredPoint ? Math.max(0, Math.min(parent.width - width, root.hoveredPoint.x - width / 2)) : 0
            y: {
              if (!root.hoveredPoint) return 0
              var above = root.hoveredPoint.y - height - Style.space(10)
              return above >= bigChart.padTop ? above : root.hoveredPoint.y + Style.space(10)
            }
            radius: Math.min(4, Style.cornerRadius)
            color: Color.tooltip.background
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.35)

            Text {
              id: hoverBubbleText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.hoveredPoint
                ? Model.formatPointTime(root.hoveredPoint.t, root.range) + "  " + Model.formatPrice(root.hoveredPoint.v, root.activeQuote ? root.activeQuote.currency : "", root.activeSymbol) + "  " + Model.trendGlyph(root.hoveredChangePct) + Model.formatPct(Math.abs(root.hoveredChangePct), false)
                : ""
              color: Color.tooltip.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---------- Range picker ----------
        Row {
          id: rangeRow
          width: parent.width
          spacing: Style.space(6)

          readonly property real cellWidth: (width - spacing * (Model.RANGES.length - 1)) / Model.RANGES.length

          Repeater {
            model: Model.RANGES

            Button {
              required property var modelData
              width: rangeRow.cellWidth
              height: Style.spacing.controlHeight
              text: modelData.label
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.xs
              bordered: true
              active: root.range === modelData.key
              onClicked: root.setRange(modelData.key)
            }
          }
        }

        // ---------- Watchlist ----------
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(2)

          PanelSectionHeader {
            text: "WATCHLIST"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Item { width: 1; height: Style.space(4) }

          Repeater {
            model: root.symbols

            QuoteRow {
              required property string modelData
              required property int index
              width: parent.width
              symbol: modelData
              rowIndex: index
            }
          }

          Item { width: 1; height: Style.space(4) }

          // Add field, opened from the footer or with `a`. Enter validates the
          // symbol against Yahoo before it lands in the list.
          Column {
            visible: root.editing
            width: parent.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: addField
                width: parent.width - addHint.width - parent.spacing
                enabled: !root.validating
                placeholderText: "Symbol, e.g. TSLA or ^PSI20"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: {
                  root.addError = ""
                  root.suggestionIndex = -1
                  if (root.editing && !root.validating) searchDebounce.restart()
                }

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.cancelAdding()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    root.moveSuggestion(1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    root.moveSuggestion(-1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Tab && root.suggestions.length > 0) {
                    // Tab completes the highlighted (or first) suggestion into the field.
                    var idx = root.suggestionIndex >= 0 ? root.suggestionIndex : 0
                    addField.text = String(root.suggestions[idx].symbol)
                    root.suggestionIndex = idx
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.suggestionIndex >= 0) root.chooseSuggestion(root.suggestionIndex)
                    else root.commitAdd()
                    event.accepted = true
                  }
                }
              }

              Text {
                id: addHint
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.validating ? "Checking…" : "Enter adds · Esc done"
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              visible: root.addError !== ""
              textFormat: Text.PlainText
              text: root.addError
              color: root.downColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }

            // Autocomplete matches: symbol, name, exchange. Click or Enter adds.
            Repeater {
              model: root.suggestions

              CursorSurface {
                id: suggestionRow
                required property var modelData
                required property int index

                width: parent.width
                implicitHeight: suggestionInner.implicitHeight + Style.spacing.lg
                hasCursor: root.suggestionIndex === index
                foreground: root.foreground

                Row {
                  id: suggestionInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: String(suggestionRow.modelData.symbol)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    width: Style.space(84)
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Model.cleanName(suggestionRow.modelData.name)
                    color: root.foreground
                    opacity: 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    width: parent.width - Style.space(84) - suggestionMeta.width - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: suggestionMeta
                    textFormat: Text.PlainText
                    text: Model.suggestionMeta(suggestionRow.modelData)
                    color: root.foreground
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignRight
                    width: Math.min(implicitWidth, Style.space(120))
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: if (containsMouse) root.suggestionIndex = suggestionRow.index
                  onClicked: root.chooseSuggestion(suggestionRow.index)
                }
              }
            }
          }

          Text {
            visible: !root.editing
            textFormat: Text.PlainText
            text: "a add · x remove · J / K reorder · or edit symbols in shell.json"
            color: root.foreground
            opacity: 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        // ---------- Footer: status line + actions ----------
        PanelSeparator { foreground: root.foreground }

        Text {
          visible: root.lastError !== ""
          textFormat: Text.PlainText
          text: root.lastError
          color: root.downColor
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
              hasCursor: root.cursorActive && root.cursorIndex === root.symbols.length + index
              onClicked: modelData.run()
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.cursorIndex = root.symbols.length + index
                }
              }
            }
          }
        }
      }
    }
  }

  // One watchlist row: label over name, a sparkline of the day, price over
  // the daily change. Click charts it, right click opens it in the browser.
  component QuoteRow: CursorSurface {
    id: row
    required property string symbol
    required property int rowIndex

    readonly property var quote: root.quotes[symbol]
    readonly property real pct: Model.changePct(quote)
    readonly property color trendColor: root.trendColor(pct)

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: root.activeSymbol === symbol
    foreground: root.foreground
    implicitHeight: inner.implicitHeight + Style.spacing.xl

    Row {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      // Leaves room for the remove control at the right edge.
      anchors.rightMargin: Style.space(8) + Style.space(18) + Style.space(6)
      spacing: Style.space(10)

      Column {
        width: parent.width - spark.width - values.width - parent.spacing * 2
        spacing: Style.space(1)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: Model.primaryLabel(row.symbol, row.quote)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: row.quote && row.quote.error ? String(row.quote.error) : Model.secondaryLabel(row.symbol, row.quote)
          visible: text !== ""
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      LineChart {
        id: spark
        width: Style.space(72)
        height: Style.space(24)
        anchors.verticalCenter: parent.verticalCenter
        points: row.quote && row.quote.points ? row.quote.points : []
        referenceValue: row.quote ? Number(row.quote.prevClose) : NaN
        lineColor: row.trendColor
        fillTop: Util.alpha(row.trendColor, 0.22)
        fillBottom: Util.alpha(row.trendColor, 0.0)
        baselineColor: Util.alpha(root.foreground, 0.25)
        gridColor: "transparent"
        lineWidth: 1.2
        padTop: 2
        padBottom: 2
        showEndDot: false
      }

      Column {
        id: values
        width: Style.space(92)
        spacing: Style.space(1)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: Model.formatPrice(row.quote)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: isFinite(row.pct) ? Model.trendGlyph(row.pct) + Model.formatPct(Math.abs(row.pct), false) : "—"
          color: row.trendColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          horizontalAlignment: Text.AlignRight
          width: parent.width

          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.cursorIndex = row.rowIndex
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.openInBrowser(row.symbol)
        else root.selectSymbol(row.symbol)
      }
    }

    // Remove control at the row's right edge, revealed while the row holds
    // the cursor. Declared after the row MouseArea so it receives the click.
    Rectangle {
      visible: row.hasCursor && root.symbols.length > 1
      width: Style.space(18)
      height: Style.space(18)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      radius: Math.min(4, Style.cornerRadius)
      color: removeArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "✕"
        color: removeArea.containsMouse ? root.downColor : Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: removeArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.removeSymbol(row.symbol)
      }
    }
  }

  // Canvas line chart with a soft area fill, a dashed previous-close
  // baseline and an optional dot on the last point. Shared by the hero chart
  // and the row sparklines; only the sizes and paddings differ.
  component LineChart: Canvas {
    id: chart
    property var points: []
    property real referenceValue: NaN
    property color lineColor: Color.foreground
    property color fillTop: "transparent"
    property color fillBottom: "transparent"
    property color baselineColor: "transparent"
    property color gridColor: "transparent"
    property real lineWidth: 1.5
    property real padTop: 0
    property real padBottom: 0
    property bool showEndDot: false

    readonly property var geometry: Model.chartGeometry(points, width, height, referenceValue, padTop, padBottom)
    readonly property real minValue: geometry.min
    readonly property real maxValue: geometry.max

    // Index of the point under the pointer (-1 when not hovering) and that
    // point's geometry, for the crosshair drawn by the host.
    property int hoverIndex: -1
    readonly property var hoverPoint: hoverIndex >= 0 && hoverIndex < geometry.points.length ? geometry.points[hoverIndex] : null

    function indexAt(x) {
      var n = geometry.points.length
      if (n === 0 || width <= 0) return -1
      return Math.max(0, Math.min(n - 1, Math.round(x / width * (n - 1))))
    }

    onPointsChanged: hoverIndex = -1

    // Qt's Context2D wants CSS color strings; QML color values carry r,g,b,a
    // as 0..1 floats.
    function css(c) {
      return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")"
    }

    antialiasing: true
    onGeometryChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onFillTopChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      var geo = chart.geometry
      var pts = geo.points
      if (pts.length === 0) return

      // Faint horizontal guides at quarter heights of the plotted band.
      if (chart.gridColor.a > 0) {
        ctx.strokeStyle = chart.css(chart.gridColor)
        ctx.lineWidth = 1
        var usable = height - chart.padTop - chart.padBottom
        for (var g = 0; g <= 4; g++) {
          var gy = Math.round(chart.padTop + usable * g / 4) + 0.5
          ctx.beginPath()
          ctx.moveTo(0, gy)
          ctx.lineTo(width, gy)
          ctx.stroke()
        }
      }

      // Dashed previous-close baseline, drawn by hand so it does not depend
      // on setLineDash support.
      if (isFinite(geo.baselineY) && chart.baselineColor.a > 0) {
        var by = Math.round(geo.baselineY) + 0.5
        ctx.strokeStyle = chart.css(chart.baselineColor)
        ctx.lineWidth = 1
        ctx.beginPath()
        for (var x = 0; x < width; x += 6) {
          ctx.moveTo(x, by)
          ctx.lineTo(Math.min(width, x + 3), by)
        }
        ctx.stroke()
      }

      // Area under the line.
      if (chart.fillTop.a > 0 || chart.fillBottom.a > 0) {
        var gradient = ctx.createLinearGradient(0, chart.padTop, 0, height)
        gradient.addColorStop(0, chart.css(chart.fillTop))
        gradient.addColorStop(1, chart.css(chart.fillBottom))
        ctx.fillStyle = gradient
        ctx.beginPath()
        ctx.moveTo(pts[0].x, height)
        for (var i = 0; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
        ctx.lineTo(pts[pts.length - 1].x, height)
        ctx.closePath()
        ctx.fill()
      }

      // The line itself.
      ctx.strokeStyle = chart.css(chart.lineColor)
      ctx.lineWidth = chart.lineWidth
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.beginPath()
      ctx.moveTo(pts[0].x, pts[0].y)
      for (var j = 1; j < pts.length; j++) ctx.lineTo(pts[j].x, pts[j].y)
      ctx.stroke()

      if (chart.showEndDot) {
        var last = pts[pts.length - 1]
        ctx.fillStyle = chart.css(chart.lineColor)
        ctx.beginPath()
        ctx.arc(Math.min(width - 3, last.x), last.y, 3, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }
}
