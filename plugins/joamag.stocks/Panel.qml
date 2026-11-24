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
  // Last series the big chart drew with points, held on screen while the next
  // range or symbol is fetched.
  property var heldSeries: null
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
  readonly property bool searching: searchProc.running
  // Drag and drop reordering: the row being dragged, how far it has travelled
  // from the press and the index it would land on (-1 = no drag in progress).
  property int dragIndex: -1
  property int dragTarget: -1
  property real dragOffset: 0
  // Popup tab, one of Model.TABS; every open starts on markets.
  property string tab: "markets"
  // News tab: whose headlines show ("symbol" for the charted symbol, "top"
  // for the top stories), feed -> { items, error, fetchedAt }, and the feed
  // the running fetch is for.
  property string newsScope: "symbol"
  property var newsCache: ({})
  property bool newsLoading: false
  property string newsQuery: ""
  // Symbol the remove dialog is asking about ("" = no dialog).
  property string removalSymbol: ""

  // Chart point under the pointer, or null. While set, the hero shows that
  // point's price and its change against the previous close. A held chart
  // belongs to another range or symbol, so it takes no hover.
  readonly property var hoveredPoint: chartHeld ? null : bigChart.hoverPoint
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
  // Market data on its way from Yahoo: sweeps the activity line above the
  // chart and turns the Refresh icon.
  readonly property bool loading: quotesLoading || seriesLoading
  // What the big chart draws: the active series, or the held one, dimmed,
  // while the active one is still being fetched.
  readonly property bool chartLoading: Model.chartLoading(range, activeQuote, quotesLoading, seriesLoading)
  readonly property var chartSeries: Model.chartSeries(activeSeries, heldSeries, chartLoading)
  readonly property bool chartHeld: chartSeries !== null && chartSeries !== activeSeries
  readonly property string newsFeed: newsScope === "top" ? Model.TOP_FEED : activeSymbol
  readonly property var newsItems: newsCache[newsFeed] ? newsCache[newsFeed].items : []

  readonly property var actions: [
    { label: "Refresh", icon: "󰑐", tooltip: root.tab === "news" ? "Refresh headlines" : "Refresh quotes", spins: true, run: function() { root.refreshView() } },
    { label: "Pin", icon: "󰐃", tooltip: "Show " + Model.shortLabel(root.activeSymbol) + " in the bar", run: function() { root.pinSymbol(root.activeSymbol) } },
    { label: "Open", icon: "󰏌", tooltip: "Open " + Model.shortLabel(root.activeSymbol) + " on Yahoo Finance", run: function() { root.openInBrowser(root.activeSymbol) } },
    { label: "Add", icon: "󰐕", tooltip: "Add a symbol to the watchlist", run: function() { root.startAdding() } }
  ]

  // Keyboard cursor walks the list first (the watchlist rows, or the headlines
  // on the news tab), then the footer actions.
  readonly property int listCount: tab === "news" ? newsItems.length : symbols.length
  readonly property int cursorCount: listCount + actions.length

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

  // Refresh asked for from the popup: the headlines on the news tab, quotes
  // everywhere else. The timer and the bar's middle click stay on quotes.
  function refreshView() {
    if (tab === "news") ensureNews(true)
    else refresh()
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

  function ensureNews(force) {
    if (!opened || tab !== "news") return
    var key = newsFeed
    if ((force !== true && Model.newsFresh(newsCache[key])) || newsProc.running) return
    newsLoading = true
    newsQuery = key
    newsProc.command = key === Model.TOP_FEED ? [root.scriptPath, "news"] : [root.scriptPath, "news", key]
    newsProc.running = true
  }

  function applyNews(raw) {
    var result = Model.parseNews(raw)
    var next = {}
    for (var key in newsCache) next[key] = newsCache[key]
    next[newsQuery] = Model.newsEntry(newsCache[newsQuery], result, Date.now())
    newsCache = next
    if (result.error !== "") lastError = result.error
  }

  function selectSymbol(symbol) {
    if (symbols.indexOf(symbol) < 0) return
    selectedSymbol = symbol
    ensureSeries()
  }

  function setTab(key) {
    var next = key === "news" ? "news" : "markets"
    if (next === tab) return
    if (editing) cancelAdding()
    tab = next
    cursorActive = false
    cursorIndex = next === "markets" ? Math.max(0, symbols.indexOf(activeSymbol)) : 0
    ensureNews()
  }

  function setNewsScope(scope) {
    newsScope = scope === "top" ? "top" : "symbol"
    cursorIndex = 0
  }

  // Headline links come from outside feeds, so the command is built by
  // Model.browserCommand, which only lets an http(s) link through, quoted.
  function openHeadline(item) {
    var command = item ? Model.browserCommand(item.link) : ""
    if (!root.bar || command === "") return
    root.bar.run(command)
    root.close()
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

  // ✕ on a row and `x` ask first through the dialog; the removeSymbol IPC
  // stays immediate for scripts. The last symbol cannot go anyway, so it gets
  // the usual message rather than a question.
  function confirmRemove(symbol) {
    if (symbols.indexOf(symbol) < 0) return
    if (symbols.length <= 1) {
      removeSymbol(symbol)
      return
    }
    removeConfirm.selectedIndex = 1
    removalSymbol = symbol
    Qt.callLater(function() { removeConfirm.forceActiveFocus() })
  }

  function cancelRemove() {
    removalSymbol = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitRemove() {
    var symbol = removalSymbol
    cancelRemove()
    removeSymbol(symbol)
  }

  function moveSymbol(symbol, delta) {
    var idx = symbols.indexOf(symbol)
    var target = idx + delta
    if (idx < 0 || target < 0 || target >= symbols.length) return
    saveSymbols(Model.reorder(symbols, idx, target))
    cursorActive = true
    cursorIndex = target
  }

  // A row was picked up: from here the row follows the pointer and the rows it
  // passes slide out of its way, until the release commits the new order.
  function startDrag(index) {
    if (index < 0 || index >= symbols.length) return
    dragIndex = index
    dragTarget = index
    dragOffset = 0
  }

  function updateDrag(offset, pitch) {
    if (dragIndex < 0) return
    dragOffset = offset
    dragTarget = Model.dropIndex(dragIndex, offset, pitch, symbols.length)
  }

  function endDrag() {
    var from = dragIndex
    var target = dragTarget
    // Cleared first so the rows are back at their own places by the time the
    // new watchlist reaches the repeater.
    cancelDrag()
    if (from < 0 || target < 0 || target === from) return
    saveSymbols(Model.reorder(symbols, from, target))
    cursorActive = true
    cursorIndex = target
  }

  function cancelDrag() {
    dragIndex = -1
    dragTarget = -1
    dragOffset = 0
  }

  function cursorSymbol() {
    return cursorActive && cursorIndex < symbols.length ? symbols[cursorIndex] : activeSymbol
  }

  function startAdding() {
    setTab("markets")
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
    if (cursorIndex < listCount) {
      if (tab === "news") openHeadline(newsItems[cursorIndex])
      else selectSymbol(symbols[cursorIndex])
      return
    }
    var action = actions[cursorIndex - listCount]
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
    function version(): string { return "0.6.0" }
  }

  onOpenedChanged: {
    if (opened) {
      tab = "markets"
      selectedSymbol = barSymbol
      cursorActive = false
      cursorIndex = Math.max(0, symbols.indexOf(barSymbol))
      cancelDrag()
      refresh()
      ensureSeries()
    } else {
      if (editing) cancelAdding()
      removalSymbol = ""
    }
  }

  onSymbolsChanged: refresh()

  onActiveSeriesChanged: if (activeSeries && activeSeries.points && activeSeries.points.length > 0) heldSeries = activeSeries

  onNewsFeedChanged: ensureNews()

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

  Process {
    id: newsProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyNews(text) }
    onExited: {
      root.newsLoading = false
      // The symbol or the feed may have moved while this fetch ran.
      Qt.callLater(root.ensureNews)
    }
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
      blocked: root.editing || root.removalSymbol !== ""
      onDeleteRequested: if (root.tab === "markets" && root.cursorActive && root.cursorIndex < root.symbols.length) root.confirmRemove(root.symbols[root.cursorIndex])
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) { root.moveCursor(dy); return }
        // Left/right steps the range (the feed, on news) while the cursor
        // sits on the list, and moves along the footer once it reaches it.
        if (root.cursorActive && root.cursorIndex >= root.listCount) root.moveCursor(dx)
        else if (root.tab === "news") root.setNewsScope(dx > 0 ? "top" : "symbol")
        else root.stepRange(dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "o") root.openInBrowser(root.activeSymbol)
        else if (text === "p") root.pinSymbol(root.activeSymbol)
        else if (text === "r") root.refreshView()
        else if (text === "a") root.startAdding()
        else if (text === "n") root.setTab(root.tab === "news" ? "markets" : "news")
        else if (text === "J" && root.tab === "markets") root.moveSymbol(root.cursorSymbol(), 1)
        else if (text === "K" && root.tab === "markets") root.moveSymbol(root.cursorSymbol(), -1)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Tabs: Markets · News ----------
        Row {
          id: tabRow
          width: parent.width
          spacing: Style.space(6)

          readonly property real cellWidth: (width - spacing * (Model.TABS.length - 1)) / Model.TABS.length

          Repeater {
            model: Model.TABS

            Button {
              required property var modelData
              width: tabRow.cellWidth
              height: Style.spacing.controlHeight
              text: modelData.label
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.xs
              bordered: true
              active: root.tab === modelData.key
              onClicked: root.setTab(modelData.key)
            }
          }
        }

        // The Markets sections below keep their place on the news tab, only
        // hidden, so the news view can sit over them at the same height.

        // ---------- Hero: selected symbol · name/state · price and change ----------
        Item {
          id: hero
          width: parent.width
          implicitHeight: Math.max(heroLabels.implicitHeight, heroValues.implicitHeight)
          opacity: root.tab === "markets" ? 1 : 0
          enabled: root.tab === "markets"

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
          opacity: root.tab === "markets" ? 1 : 0
          enabled: root.tab === "markets"

          // Activity line in the gap above the chart while quotes or a chart
          // series are on their way.
          ActivityLine {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.top
            anchors.bottomMargin: Style.space(5)
            active: root.loading
          }

          // The chart and the labels read from it, dimmed while a held chart
          // stands in for the range or symbol being fetched.
          Item {
            anchors.fill: parent
            opacity: root.chartHeld ? 0.35 : 1

            Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }

            LineChart {
              id: bigChart
              anchors.fill: parent
              points: root.chartSeries && root.chartSeries.points ? root.chartSeries.points : []
              referenceValue: root.chartSeries ? Number(root.chartSeries.prevClose) : NaN
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
          }

          // The range being shown stays at full strength over a held chart,
          // so it names what is loading.
          Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: isFinite(root.activeRangePct) ? Model.rangeLabel(root.range) + " " + Model.trendGlyph(root.activeRangePct) + Model.formatPct(Math.abs(root.activeRangePct), false) : Model.rangeLabel(root.range)
            color: root.trendColor(root.activeRangePct)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Row {
            anchors.centerIn: parent
            visible: bigChart.points.length === 0
            spacing: Style.space(6)

            Spinner {
              visible: root.chartLoading
              spinning: root.chartLoading
              opacity: 0.5
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: Model.chartPlaceholder(root.chartLoading, root.lastError, root.range)
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Hover crosshair: hairline and dot on the nearest point, with a
          // small bubble carrying time and price. The hero above mirrors it.
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            cursorShape: bigChart.points.length > 0 && !root.chartHeld ? Qt.CrossCursor : Qt.ArrowCursor
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
          opacity: root.tab === "markets" ? 1 : 0
          enabled: root.tab === "markets"

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
        PanelSeparator {
          foreground: root.foreground
          opacity: root.tab === "markets" ? 1 : 0
        }

        Column {
          id: watchlist
          width: parent.width
          spacing: Style.space(2)
          opacity: root.tab === "markets" ? 1 : 0
          enabled: root.tab === "markets"

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
              rowPitch: height + watchlist.spacing
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

              // Turns while a search or the Enter check runs. The spinner keeps
              // its slot and the text keeps the idle hint's width, so the field
              // does not change size each time a search comes and goes.
              Row {
                id: addHint
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Spinner {
                  spinning: root.searching || root.validating
                  opacity: spinning ? 0.5 : 0
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: addHintText
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(implicitWidth, Math.ceil(idleHint.advanceWidth))
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: root.validating ? "Checking " + Model.shortLabel(root.pendingSymbol) + "…" : (root.searching ? "Searching…" : "Enter adds · Esc done")
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption

                  TextMetrics {
                    id: idleHint
                    font: addHintText.font
                    text: "Enter adds · Esc done"
                  }
                }
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
            text: "a add · x remove · drag or J / K reorder · or edit symbols in shell.json"
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
              iconSpinning: modelData.spins === true && (root.tab === "news" ? root.newsLoading : root.loading)
              text: modelData.label
              tooltipText: modelData.tooltip
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              hasCursor: root.cursorActive && root.cursorIndex === root.listCount + index
              onClicked: modelData.run()
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.cursorIndex = root.listCount + index
                }
              }
            }
          }
        }
      }

      // ---------- News: the symbol's headlines or the top stories ----------
      // Sits over the Markets sections, in the same place and at the same
      // height, so switching tabs never resizes the popup; the headlines
      // scroll inside it.
      Item {
        id: newsView
        anchors.left: column.left
        anchors.right: column.right
        y: column.y + hero.y
        height: watchlist.y + watchlist.height - hero.y
        visible: root.tab === "news"

        Row {
          id: scopeRow
          width: parent.width
          spacing: Style.space(6)

          readonly property real cellWidth: (width - spacing) / 2

          Repeater {
            model: [
              { key: "symbol", label: Model.shortLabel(root.activeSymbol) },
              { key: "top", label: "Top stories" }
            ]

            Button {
              required property var modelData
              width: scopeRow.cellWidth
              height: Style.spacing.controlHeight
              text: modelData.label
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.xs
              bordered: true
              active: root.newsScope === modelData.key
              onClicked: root.setNewsScope(modelData.key)
            }
          }
        }

        ActivityLine {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: newsList.top
          anchors.bottomMargin: Style.space(5)
          active: root.newsLoading
        }

        ListView {
          id: newsList
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: scopeRow.bottom
          anchors.topMargin: Style.space(12)
          anchors.bottom: newsHint.top
          anchors.bottomMargin: Style.space(4)
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          model: root.newsItems
          // Follows the keyboard cursor so j / k never walk out of view.
          currentIndex: root.cursorActive && root.cursorIndex < root.newsItems.length ? root.cursorIndex : -1
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          // One headline: the title on up to two lines, publisher and age
          // under it. Click opens it in the browser.
          delegate: CursorSurface {
            id: headline
            required property var modelData
            required property int index

            width: newsList.width
            implicitHeight: headlineText.implicitHeight + Style.spacing.lg
            hasCursor: root.cursorActive && root.cursorIndex === index
            foreground: root.foreground

            Column {
              id: headlineText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: String(headline.modelData.title)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: Model.newsMeta(headline.modelData)
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) {
                root.cursorActive = true
                root.cursorIndex = headline.index
              }
              onClicked: root.openHeadline(headline.modelData)
            }
          }
        }

        Row {
          anchors.centerIn: newsList
          visible: root.newsItems.length === 0
          spacing: Style.space(6)

          Spinner {
            visible: root.newsLoading
            spinning: root.newsLoading
            opacity: 0.5
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: Model.newsPlaceholder(root.newsLoading, root.newsCache[root.newsFeed] ? root.newsCache[root.newsFeed].error : "", root.newsFeed)
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          id: newsHint
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: "h / l switch feed · Enter opens · n back to Markets"
          color: root.foreground
          opacity: 0.35
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Asks before a symbol leaves the watchlist, and holds the keyboard
      // while open: Enter removes, Esc or a click outside the card keeps it.
      ConfirmDialog {
        id: removeConfirm
        anchors.fill: parent
        z: 10
        opened: root.removalSymbol !== ""
        message: "Remove " + Model.shortLabel(root.removalSymbol) + " from the watchlist?"
        confirmText: "Remove"
        background: Color.popups.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelRemove()
        onConfirmed: root.commitRemove()
        Keys.onPressed: function(event) { if (removeConfirm.handleKey(event)) event.accepted = true }
      }
    }
  }

  // One watchlist row: label over name, a sparkline of the day, price over
  // the daily change. Click charts it, right click opens it in the browser,
  // drag it up or down to reorder the watchlist.
  component QuoteRow: CursorSurface {
    id: row
    required property string symbol
    required property int rowIndex
    // Height of a row plus the gap to the next one, which is the distance the
    // pointer covers to move the dragged row one place.
    required property real rowPitch

    readonly property var quote: root.quotes[symbol]
    readonly property real pct: Model.changePct(quote)
    readonly property color trendColor: root.trendColor(pct)
    readonly property bool dragging: root.dragIndex === rowIndex
    // No quote yet while one is being fetched: the row pulses until it lands,
    // the way the Tailscale panel marks an account it is switching to.
    readonly property bool pending: !quote && root.quotesLoading

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: root.activeSymbol === symbol
    foreground: root.foreground
    implicitHeight: inner.implicitHeight + Style.spacing.xl
    // The dragged row floats over its neighbours while they slide to open the
    // gap it will drop into. Both move through a transform rather than `y`,
    // which belongs to the Column that lays the rows out.
    z: dragging ? 1 : 0

    transform: Translate {
      y: row.dragging ? root.dragOffset : Model.dragShift(row.rowIndex, root.dragIndex, root.dragTarget) * row.rowPitch

      Behavior on y {
        enabled: !row.dragging
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    Row {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      // Leaves room for the remove control at the right edge.
      anchors.rightMargin: Style.space(8) + Style.space(18) + Style.space(6)
      spacing: Style.space(10)
      opacity: row.pending ? 0.45 : 1

      SequentialAnimation on opacity {
        running: row.pending && root.opened && !Style.reduceMotion
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: Style.duration(950); easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.45; duration: Style.duration(950); easing.type: Easing.InOutSine }
      }

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

    // A press that crosses the threshold becomes a reorder, anything shorter
    // stays a click, the same way the bar tells a module click from a module
    // drag. No drag.target here: the row is owned by a Column positioner.
    MouseArea {
      id: rowPointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedY: 0
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.cursorIndex = row.rowIndex
      }

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedY = mouse.y
      }

      onPositionChanged: function(mouse) {
        if (!(mouse.buttons & Qt.LeftButton) || root.symbols.length < 2) return
        if (!dragging) {
          if (Math.abs(mouse.y - pressedY) < dragThreshold) return
          dragging = true
          root.startDrag(row.rowIndex)
        }
        // The row keeps up with the pointer, so the press point stays under
        // the cursor and every event measures one step, not the whole travel.
        root.updateDrag(root.dragOffset + mouse.y - pressedY, row.rowPitch)
      }

      onReleased: {
        if (!dragging) return
        dragging = false
        suppressClick = true
        root.endDrag()
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.cancelDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          return
        }
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
        onClicked: root.confirmRemove(row.symbol)
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

  // Thin strip in the gap above a chart or a list: a short segment sweeps
  // across while `active`, and holds still under the shell's reduced motion.
  component ActivityLine: Item {
    id: line
    property bool active: false

    height: 2
    clip: true
    opacity: active ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(root.foreground, 0.08)
    }

    Rectangle {
      id: sweep
      width: Style.reduceMotion ? parent.width : parent.width * 0.28
      height: parent.height
      color: Color.accent
      opacity: Style.reduceMotion ? 0.4 : 1

      NumberAnimation on x {
        from: -sweep.width
        to: line.width
        duration: 1100
        easing.type: Easing.InOutQuad
        loops: Animation.Infinite
        running: line.visible && root.opened && !Style.reduceMotion
        onRunningChanged: if (!running) sweep.x = 0
      }
    }
  }

  // Refresh glyph that turns while `spinning`, the way the disks and home
  // widgets mark a busy row. Shared by the chart placeholder and the add
  // field hint; holds still under the shell's reduced motion.
  component Spinner: Text {
    id: spinner
    property bool spinning: false

    textFormat: Text.PlainText
    text: "󰑐"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall

    RotationAnimation on rotation {
      from: 0
      to: 360
      duration: Style.duration(900)
      loops: Animation.Infinite
      running: spinner.spinning && !Style.reduceMotion
      onRunningChanged: if (!running) spinner.rotation = 0
    }
  }
}
