.pragma library

// Pure helpers for the stocks widget: parsing quotes.sh output, quote math,
// number formatting and the geometry the Canvas charts draw from.

var ICON = "󰄧"
var DEFAULT_SYMBOLS = "^GSPC,^IXIC,^DJI,AMD,INTC,NVDA,AAPL,MSFT"

var RANGES = [
  { key: "1d", label: "1D" },
  { key: "5d", label: "5D" },
  { key: "1mo", label: "1M" },
  { key: "6mo", label: "6M" },
  { key: "1y", label: "1Y" }
]

// How long a fetched series stays fresh before the popup refetches it, per
// range; intraday moves, a year of weekly closes does not.
var SERIES_TTL_MS = { "1d": 60000, "5d": 300000, "1mo": 900000, "6mo": 1800000, "1y": 3600000 }

// Friendly labels for the common indices, which Yahoo only knows by caret
// symbols nobody wants to read in a bar.
var ALIASES = {
  "^GSPC": "S&P 500",
  "^IXIC": "NASDAQ",
  "^DJI": "DOW",
  "^RUT": "RUSSELL 2K",
  "^VIX": "VIX",
  "^NDX": "NASDAQ 100",
  "^FTSE": "FTSE 100",
  "^GDAXI": "DAX",
  "^FCHI": "CAC 40",
  "^STOXX50E": "STOXX 50",
  "^N225": "NIKKEI",
  "^HSI": "HANG SENG",
  "^PSI20": "PSI",
  "^TNX": "US 10Y"
}

var CURRENCY_SYMBOLS = { USD: "$", EUR: "€", GBP: "£", GBp: "p", JPY: "¥", CHF: "CHF ", CAD: "C$", AUD: "A$", HKD: "HK$", INR: "₹", BRL: "R$" }

function num(value) {
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

// One JSON object per line; a malformed line is dropped rather than taking the
// whole refresh down with it.
function parseLines(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    try {
      var obj = JSON.parse(line)
      if (obj && typeof obj === "object" && obj.symbol) out.push(obj)
    } catch (e) {
      // skip
    }
  }
  return out
}

// Watchlist setting: a comma separated string (what the settings UI edits) or
// an array (what a hand-written shell.json may carry).
function parseSymbols(value) {
  var list = []
  if (Array.isArray(value)) list = value
  else list = String(value === undefined || value === null ? DEFAULT_SYMBOLS : value).split(",")
  var out = []
  for (var i = 0; i < list.length; i++) {
    var s = String(list[i] || "").trim()
    if (s === "") continue
    s = s.toUpperCase()
    if (out.indexOf(s) < 0) out.push(s)
  }
  return out.length > 0 ? out : parseSymbols(DEFAULT_SYMBOLS)
}

function isIndex(symbol) {
  return String(symbol || "").charAt(0) === "^"
}

function hasQuote(quote) {
  return !!quote && !quote.error && isFinite(num(quote.price))
}

function shortLabel(symbol) {
  return ALIASES[symbol] || String(symbol || "")
}

// Company names as Yahoo ships them are legal names; trim the suffixes so
// "Advanced Micro Devices, Inc." fits a row.
function cleanName(name) {
  var s = String(name || "").replace(/\s+/g, " ")
  s = s.replace(/,?\s+(Inc\.?|Incorporated|Corporation|Corp\.?|Co\.?|Company|Ltd\.?|Limited|plc|PLC|S\.A\.|SA|N\.V\.|NV|AG|SE|Holdings?)\s*$/g, "")
  return s.trim()
}

function primaryLabel(symbol, quote) {
  if (isIndex(symbol)) return ALIASES[symbol] || (quote && quote.name ? cleanName(quote.name) : symbol)
  return symbol
}

function secondaryLabel(symbol, quote) {
  if (!quote || !quote.name) return isIndex(symbol) ? symbol : ""
  var name = cleanName(quote.name)
  if (isIndex(symbol)) {
    // With an alias the full name is the subtitle, unless it says the same
    // thing ("S&P 500" twice), in which case the raw symbol is more useful.
    if (!ALIASES[symbol]) return symbol
    return name !== ALIASES[symbol] ? name : symbol
  }
  return name
}

function change(quote) {
  if (!hasQuote(quote)) return NaN
  var prev = num(quote.prevClose)
  return isFinite(prev) ? num(quote.price) - prev : NaN
}

function changePct(quote) {
  if (!hasQuote(quote)) return NaN
  var prev = num(quote.prevClose)
  return isFinite(prev) && prev !== 0 ? (num(quote.price) - prev) / prev * 100 : NaN
}

// Change over a fetched series: last close against the close before the
// range started, which is what Yahoo puts in chartPreviousClose.
function seriesChangePct(series) {
  if (!series || !series.points || series.points.length === 0) return NaN
  var prev = num(series.prevClose)
  var last = num(series.points[series.points.length - 1][1])
  if (!isFinite(prev) || prev === 0) prev = num(series.points[0][1])
  return isFinite(prev) && prev !== 0 && isFinite(last) ? (last - prev) / prev * 100 : NaN
}

function trend(value) {
  var n = num(value)
  if (!isFinite(n) || n === 0) return 0
  return n > 0 ? 1 : -1
}

function trendGlyph(value) {
  var t = trend(value)
  return t > 0 ? "▴" : (t < 0 ? "▾" : "")
}

function groupThousands(intText) {
  var out = ""
  var count = 0
  for (var i = intText.length - 1; i >= 0; i--) {
    out = intText.charAt(i) + out
    if (++count % 3 === 0 && i > 0) out = "," + out
  }
  return out
}

function formatNumber(value, decimals) {
  var n = num(value)
  if (!isFinite(n)) return "—"
  var fixed = Math.abs(n).toFixed(decimals)
  var parts = fixed.split(".")
  var text = groupThousands(parts[0]) + (parts.length > 1 ? "." + parts[1] : "")
  return (n < 0 ? "-" : "") + text
}

function priceDecimals(value) {
  var n = Math.abs(num(value))
  if (!isFinite(n)) return 2
  if (n >= 1000) return 2
  if (n >= 1) return 2
  return 4
}

function formatPrice(quoteOrValue, currency, symbol) {
  var value = (quoteOrValue && typeof quoteOrValue === "object") ? quoteOrValue.price : quoteOrValue
  var cur = currency !== undefined ? currency : (quoteOrValue && typeof quoteOrValue === "object" ? quoteOrValue.currency : "")
  var sym = symbol !== undefined ? symbol : (quoteOrValue && typeof quoteOrValue === "object" ? quoteOrValue.symbol : "")
  var text = formatNumber(value, priceDecimals(value))
  if (text === "—" || isIndex(sym)) return text
  var prefix = CURRENCY_SYMBOLS[cur]
  return prefix !== undefined ? prefix + text : text + (cur ? " " + cur : "")
}

function formatPct(value, withSign) {
  var n = num(value)
  if (!isFinite(n)) return "—"
  var sign = withSign === false ? "" : (n > 0 ? "+" : "")
  return sign + n.toFixed(2) + "%"
}

function formatChange(quote) {
  var c = change(quote)
  if (!isFinite(c)) return "—"
  var sign = c > 0 ? "+" : ""
  return sign + formatNumber(c, priceDecimals(quote.price)) + " (" + formatPct(changePct(quote)) + ")"
}

// Text on the bar button. The label is the alias or symbol, then optionally
// the price and the signed daily change with a trend arrow.
function barText(symbol, quote, showPrice, showChange) {
  var parts = [shortLabel(symbol)]
  if (hasQuote(quote)) {
    if (showPrice) parts.push(formatNumber(quote.price, isIndex(symbol) ? 0 : 2))
    if (showChange) {
      var pct = changePct(quote)
      if (isFinite(pct)) parts.push(trendGlyph(pct) + formatPct(Math.abs(pct), false))
    }
  } else if (quote && quote.error) {
    parts.push("—")
  }
  return parts.join(" ")
}

function tooltip(symbol, quote) {
  if (!hasQuote(quote)) return shortLabel(symbol) + (quote && quote.error ? " · " + quote.error : "")
  var name = cleanName(quote.name || symbol)
  return name + " · " + formatPrice(quote) + " · " + formatChange(quote)
}

function marketStateLabel(quote) {
  if (!quote) return ""
  switch (String(quote.state || "").toUpperCase()) {
  case "REGULAR": return "Market open"
  case "PRE": return "Pre-market"
  case "PREPRE": return "Pre-market"
  case "POST": return "After hours"
  case "POSTPOST": return "After hours"
  case "CLOSED": return "Market closed"
  }
  var t = num(quote.time)
  if (!isFinite(t)) return ""
  var ageMin = (Date.now() / 1000 - t) / 60
  if (ageMin < 20) return "Live"
  if (ageMin < 24 * 60) return "As of " + formatClock(t)
  return "Last close " + formatDay(t)
}

function nextSymbol(symbols, current, delta) {
  if (!symbols || symbols.length === 0) return current
  var idx = symbols.indexOf(current)
  if (idx < 0) idx = 0
  var n = symbols.length
  return symbols[((idx + delta) % n + n) % n]
}

function rangeIndex(key) {
  for (var i = 0; i < RANGES.length; i++) if (RANGES[i].key === key) return i
  return 0
}

function normalizeRange(key) {
  return RANGES[rangeIndex(key)].key
}

function rangeLabel(key) {
  return RANGES[rangeIndex(key)].label
}

function seriesKey(symbol, range) {
  return symbol + "|" + range
}

function seriesFresh(entry, range) {
  if (!entry || !entry.fetchedAt) return false
  var ttl = SERIES_TTL_MS[range] || 900000
  return Date.now() - entry.fetchedAt < ttl
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function formatClock(unixSeconds) {
  var d = new Date(num(unixSeconds) * 1000)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function formatDay(unixSeconds) {
  var d = new Date(num(unixSeconds) * 1000)
  return d.getDate() + " " + MONTHS[d.getMonth()]
}

// Axis label for a point given the chart range.
function formatAxis(unixSeconds, range) {
  var d = new Date(num(unixSeconds) * 1000)
  switch (range) {
  case "1d": return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  case "5d": return DAYS[d.getDay()]
  case "1mo": return d.getDate() + " " + MONTHS[d.getMonth()]
  case "6mo": return MONTHS[d.getMonth()]
  default: return MONTHS[d.getMonth()] + " " + String(d.getFullYear()).slice(2)
  }
}

// quotes.sh search output: { query, results: [{symbol, name, exchange, type}] }.
function parseSearch(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    try {
      var obj = JSON.parse(line)
      if (obj && Array.isArray(obj.results)) return { query: String(obj.query || ""), results: obj.results, error: obj.error || "" }
    } catch (e) {
      // skip
    }
  }
  return { query: "", results: [], error: "" }
}

// Suggestions the add field shows: matches not already on the watchlist.
function filterSuggestions(results, symbols) {
  var out = []
  for (var i = 0; i < results.length; i++) {
    var r = results[i]
    if (!r || !r.symbol) continue
    if (symbols.indexOf(String(r.symbol).toUpperCase()) >= 0) continue
    out.push(r)
  }
  return out
}

function suggestionMeta(result) {
  var parts = []
  if (result.exchange) parts.push(result.exchange)
  if (result.type) parts.push(result.type)
  return parts.join(" · ")
}

// Timestamp shown while hovering a chart point.
function formatPointTime(unixSeconds, range) {
  var d = new Date(num(unixSeconds) * 1000)
  if (range === "1d") return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  if (range === "5d") return DAYS[d.getDay()] + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  return d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
}

function seriesStats(points) {
  var stats = { min: NaN, max: NaN, first: NaN, last: NaN, count: 0 }
  if (!points || points.length === 0) return stats
  for (var i = 0; i < points.length; i++) {
    var v = num(points[i][1])
    if (!isFinite(v)) continue
    if (!isFinite(stats.min) || v < stats.min) stats.min = v
    if (!isFinite(stats.max) || v > stats.max) stats.max = v
    if (!isFinite(stats.first)) stats.first = v
    stats.last = v
    stats.count++
  }
  return stats
}

// Map [time, close] points into canvas coordinates. The vertical scale
// includes the baseline (previous close) so the dashed reference line is
// always on screen, and pads a little so the stroke never kisses the edges.
function chartGeometry(points, width, height, baseline, padTop, padBottom) {
  var geo = { points: [], baselineY: NaN, min: NaN, max: NaN }
  var stats = seriesStats(points)
  if (stats.count === 0 || width <= 0 || height <= 0) return geo
  var lo = stats.min
  var hi = stats.max
  var base = num(baseline)
  if (isFinite(base)) {
    if (base < lo) lo = base
    if (base > hi) hi = base
  }
  if (hi === lo) { hi += 1; lo -= 1 }
  var top = padTop || 0
  var bottom = padBottom || 0
  var usable = Math.max(1, height - top - bottom)
  var span = Math.max(1, stats.count - 1)
  var idx = 0
  for (var i = 0; i < points.length; i++) {
    var v = num(points[i][1])
    if (!isFinite(v)) continue
    geo.points.push({
      x: span === 0 ? width / 2 : idx / span * width,
      y: top + (hi - v) / (hi - lo) * usable,
      t: num(points[i][0]),
      v: v
    })
    idx++
  }
  if (isFinite(base)) geo.baselineY = top + (hi - base) / (hi - lo) * usable
  geo.min = stats.min
  geo.max = stats.max
  return geo
}
