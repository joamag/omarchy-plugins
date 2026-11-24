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
  { key: "1y", label: "1Y" },
  { key: "5y", label: "5Y" }
]

// How long a fetched series stays fresh before the popup refetches it, per
// range; intraday moves, a year of weekly or five of monthly closes does not.
var SERIES_TTL_MS = { "1d": 60000, "5d": 300000, "1mo": 900000, "6mo": 1800000, "1y": 3600000, "5y": 3600000 }

// Popup tabs: the chart and watchlist, and the headlines, each with the
// Material Design icon its button shows beside the label.
var TABS = [
  { key: "markets", label: "Markets", icon: "󰄪" },
  { key: "news", label: "News", icon: "󱀂" }
]

// News tab: the feed name quotes.sh gives the top stories, how many
// headlines a list keeps and how long one stays fresh.
var TOP_FEED = "markets"
var NEWS_LIMIT = 30
var NEWS_TTL_MS = 300000

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

var CURRENCY_SYMBOLS = { USD: "$", EUR: "€", GBP: "£", JPY: "¥", CHF: "CHF ", CAD: "C$", AUD: "A$", HKD: "HK$", INR: "₹", BRL: "R$" }
// London quotes come in pence, which reads as a suffix ("120.50p"), not a prefix.
var CURRENCY_SUFFIXES = { GBp: "p" }

function num(value) {
  // Number(null) is 0, which would turn a missing previous close into a
  // full-price gain; only real numbers and numeric strings count.
  if (value === null || value === undefined || value === "") return NaN
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

// Rounds half away from zero on the decimal representation, so 458.015 shows
// as 458.02 the way the exchange prints it, not the 458.01 toFixed gives for
// the binary value just below it.
function roundTo(value, decimals) {
  var shifted = Number(Math.abs(value) + "e" + decimals)
  return Number(Math.round(shifted) + "e-" + decimals)
}

function formatNumber(value, decimals) {
  var n = num(value)
  if (!isFinite(n)) return "—"
  var fixed = roundTo(n, decimals).toFixed(decimals)
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
  if (prefix !== undefined) return prefix + text
  var suffix = CURRENCY_SUFFIXES[cur]
  if (suffix !== undefined) return text + suffix
  return text + (cur ? " " + cur : "")
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

// Move one entry of the watchlist to another position, returning a new list.
// An index outside the list, or a move that goes nowhere, leaves the order
// untouched.
function reorder(symbols, from, to) {
  var out = (symbols || []).slice()
  if (from < 0 || from >= out.length || to < 0 || to >= out.length || from === to) return out
  out.splice(to, 0, out.splice(from, 1)[0])
  return out
}

// Where a dragged row lands: the pointer's travel from the press point turned
// into whole rows and clamped to the list. `pitch` is a row's height plus the
// spacing between rows.
function dropIndex(from, offsetY, pitch, count) {
  if (count <= 0) return 0
  var travel = num(offsetY)
  var steps = isFinite(travel) && pitch > 0 ? Math.round(travel / pitch) : 0
  return Math.max(0, Math.min(count - 1, from + steps))
}

// How far a row slides while another row is dragged over it, in whole rows:
// the ones between the drag's origin and its target close the gap it left,
// everything else stays where it is.
function dragShift(index, from, to) {
  if (from < 0 || to < 0 || from === to || index === from) return 0
  if (from < to) return index > from && index <= to ? -1 : 0
  return index >= to && index < from ? 1 : 0
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

// Whether the active chart itself is on its way: the 1d chart comes with the
// symbol's quote, the longer ranges with their own series. Refreshing a quote
// that is already there does not count, so a symbol Yahoo has no chart for
// keeps its message through every timed refresh.
function chartLoading(range, quote, quotesLoading, seriesLoading) {
  return range === "1d" ? !!quotesLoading && !quote : !!seriesLoading
}

// Series the big chart draws: the active one, or while a fetch for it is
// running and nothing is there yet, the last chart that had points, held on
// screen so the frame never goes blank between ranges or symbols.
function chartSeries(active, held, loading) {
  if (active || !loading) return active || null
  return held && held.points && held.points.length > 0 ? held : null
}

// Text in the big chart while it has nothing to draw, naming the range that
// is on its way.
function chartPlaceholder(loading, error, range) {
  if (loading) return "Loading " + rangeLabel(range) + " chart…"
  return error ? String(error) : "No chart data"
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

// Named references RSS titles carry; numeric ones ("&#x2019;") are decoded
// from their code point.
var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " }

// Feed text back to plain text: CDATA wrappers dropped, character references
// decoded, anything unknown left as it was.
function decodeEntities(text) {
  var s = String(text || "").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
  return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, function(all, ref) {
    if (ref.charAt(0) !== "#") return Object.prototype.hasOwnProperty.call(ENTITIES, ref) ? ENTITIES[ref] : all
    var code = ref.charAt(1) === "x" ? parseInt(ref.slice(2), 16) : parseInt(ref.slice(1), 10)
    return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : all
  })
}

// A headline or publisher as it shows: decoded, on one line.
function newsText(text) {
  return decodeEntities(text).replace(/\s+/g, " ").trim()
}

// Offsets of the zone names RSS dates use, in minutes east of UTC.
var ZONES = { GMT: 0, UT: 0, UTC: 0, Z: 0, EST: -300, EDT: -240, CST: -360, CDT: -300, MST: -420, MDT: -360, PST: -480, PDT: -420 }

// RSS pubDate (RFC 822) to unix seconds: "Tue, 24 Nov 2026 12:55 GMT" as
// CNBC writes its channel date, "Tue, 24 Nov 2026 12:56:00 GMT" or a numeric
// offset. Parsed by hand because Date.parse reads RFC 822 differently from one
// JavaScript engine to the next.
function parseRssDate(text) {
  var m = /(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([A-Za-z]+|[+-]\d{4})?/.exec(String(text || ""))
  if (!m) return NaN
  var month = MONTHS.indexOf(m[2].charAt(0).toUpperCase() + m[2].slice(1).toLowerCase())
  var zone = (m[7] || "GMT").toUpperCase()
  var offset = /^[+-]\d{4}$/.test(zone)
    ? (zone.charAt(0) === "-" ? -1 : 1) * (Number(zone.slice(1, 3)) * 60 + Number(zone.slice(3)))
    : ZONES[zone]
  if (month < 0 || offset === undefined) return NaN
  return Date.UTC(Number(m[3]), month, Number(m[1]), Number(m[4]), Number(m[5]), Number(m[6] || 0)) / 1000 - offset * 60
}

// Text of the first <tag> inside an RSS item, attributes allowed, or "".
function rssField(item, tag) {
  var m = new RegExp("<" + tag + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + tag + ">").exec(item)
  return m ? m[1] : ""
}

// Headlines of one RSS feed, credited to `source`. Only <item> blocks count,
// so the channel's own title and image never pass for a story; items without
// a title or a link are dropped.
function parseRss(xml, source) {
  var out = []
  var items = String(xml || "").match(/<item[\s>][\s\S]*?<\/item>/g) || []
  for (var i = 0; i < items.length; i++) {
    var title = newsText(rssField(items[i], "title"))
    var link = newsText(rssField(items[i], "link"))
    if (title === "" || link === "") continue
    out.push({ title: title, publisher: String(source || ""), time: parseRssDate(rssField(items[i], "pubDate")), link: link })
  }
  return out
}

// Several feeds' headlines as one list, newest first, up to `limit`. The same
// story twice (same link, or same title in another feed) shows once; items
// without a time keep their order below the dated ones.
function mergeNews(lists, limit) {
  var all = []
  var seen = {}
  for (var i = 0; i < lists.length; i++) {
    var list = lists[i] || []
    for (var j = 0; j < list.length; j++) {
      var item = list[j]
      if (!item || !item.title || !item.link) continue
      var title = newsText(item.title)
      var byLink = "l:" + item.link
      var byTitle = "t:" + title.toLowerCase()
      if (seen[byLink] || seen[byTitle]) continue
      seen[byLink] = seen[byTitle] = true
      all.push({ title: title, publisher: newsText(item.publisher), time: num(item.time), link: String(item.link), order: all.length })
    }
  }
  all.sort(function(a, b) {
    var ta = isFinite(a.time) ? a.time : -Infinity
    var tb = isFinite(b.time) ? b.time : -Infinity
    if (ta === tb) return a.order - b.order
    return tb > ta ? 1 : -1
  })
  var out = []
  for (var k = 0; k < all.length && k < limit; k++) {
    out.push({ title: all[k].title, publisher: all[k].publisher, time: all[k].time, link: all[k].link })
  }
  return out
}

// quotes.sh news output: a symbol's Yahoo headlines as { feed, items }, or
// one { feed, source, xml } line per RSS feed for the top stories, with
// { feed, source, error } for a feed that failed. Returns the merged list and
// every failure, so one feed down still shows the others.
function parseNews(raw) {
  var feed = ""
  var lists = []
  var errors = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    try {
      var obj = JSON.parse(line)
      if (!obj || typeof obj !== "object" || !obj.feed) continue
      feed = String(obj.feed)
      if (obj.error) errors.push(obj.source ? obj.source + ": " + obj.error : String(obj.error))
      if (typeof obj.xml === "string") lists.push(parseRss(obj.xml, obj.source))
      else if (Array.isArray(obj.items)) lists.push(obj.items)
    } catch (e) {
      // skip
    }
  }
  return { feed: feed, items: mergeNews(lists, NEWS_LIMIT), error: errors.join(" · ") }
}

// Cache entry after a news fetch. One that brought nothing back keeps the
// headlines already on screen and does not count as fresh, so the next look
// tries again; the error is kept either way for the status line.
function newsEntry(previous, result, now) {
  if (result.items.length > 0 || result.error === "") return { items: result.items, error: result.error, fetchedAt: now }
  return { items: previous && previous.items ? previous.items : [], error: result.error, fetchedAt: 0 }
}

function newsFresh(entry) {
  if (!entry || !entry.fetchedAt) return false
  return Date.now() - entry.fetchedAt < NEWS_TTL_MS
}

// How long ago a headline came out: "now", "9m ago", "3h ago", "2d ago", then
// the date once it is a week old. A clock slightly behind the feed reads now.
function formatAge(unixSeconds, nowMs) {
  var t = num(unixSeconds)
  if (!isFinite(t)) return ""
  var minutes = Math.floor(((nowMs === undefined ? Date.now() : nowMs) / 1000 - t) / 60)
  if (minutes < 1) return "now"
  if (minutes < 60) return minutes + "m ago"
  if (minutes < 24 * 60) return Math.floor(minutes / 60) + "h ago"
  if (minutes < 7 * 24 * 60) return Math.floor(minutes / (24 * 60)) + "d ago"
  return formatDay(t)
}

// Line under a headline: publisher and age, whichever are known.
function newsMeta(item, nowMs) {
  var parts = []
  if (item.publisher) parts.push(item.publisher)
  var age = formatAge(item.time, nowMs)
  if (age) parts.push(age)
  return parts.join(" · ")
}

// Text in the news list while it has nothing to show, naming the feed, or
// saying the source filter took every headline out (`hidden` of them).
function newsPlaceholder(loading, error, feed, hidden) {
  var top = feed === TOP_FEED
  if (loading) return "Loading " + (top ? "top stories" : shortLabel(feed) + " news") + "…"
  if (hidden > 0) return "All " + hidden + (hidden === 1 ? " headline here is" : " headlines here are") + " from hidden sources"
  if (error) return String(error)
  return top ? "No top stories right now" : "No news for " + shortLabel(feed)
}

// Shell command that opens a headline in the browser, or "" for anything but
// an http(s) link. Feeds are outside data, so the URL is single quoted with
// its own quotes escaped and can never break out of the argument.
function browserCommand(url) {
  var link = String(url || "").trim()
  if (!/^https?:\/\/\S+$/i.test(link)) return ""
  return "omarchy-launch-browser '" + link.replace(/'/g, "'\\''") + "'"
}

// Source filter: a publisher is matched by name, ignoring case and spaces at
// the ends.
function sourceKey(name) {
  return String(name === undefined || name === null ? "" : name).trim().toLowerCase()
}

// hiddenSources setting: a list of publisher names (what the popup writes) or
// a comma separated string (handier by hand). Blanks and repeats are dropped,
// the spelling of the first one kept.
function parseHiddenSources(value) {
  var list = Array.isArray(value) ? value : String(value === undefined || value === null ? "" : value).split(",")
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var key = sourceKey(list[i])
    if (key === "" || seen["k:" + key]) continue
    seen["k:" + key] = true
    out.push(String(list[i]).trim())
  }
  return out
}

// A feed's headlines without the hidden publishers, and how many that took
// out. Headlines without a publisher always show.
function filterNews(items, hidden) {
  var keys = {}
  for (var i = 0; i < hidden.length; i++) keys["k:" + sourceKey(hidden[i])] = true
  var out = []
  for (var j = 0; j < items.length; j++) {
    var key = sourceKey(items[j].publisher)
    if (key === "" || !keys["k:" + key]) out.push(items[j])
  }
  return { items: out, hidden: items.length - out.length }
}

// Sources checklist for a feed: every publisher in it with its headline
// count, plus every hidden one so it can be brought back, A to Z.
function newsSources(items, hidden) {
  var names = []
  for (var i = 0; i < items.length; i++) names.push({ name: items[i].publisher, hidden: false })
  for (var j = 0; j < hidden.length; j++) names.push({ name: hidden[j], hidden: true })
  var byKey = {}
  var out = []
  for (var k = 0; k < names.length; k++) {
    var key = sourceKey(names[k].name)
    if (key === "") continue
    var entry = byKey["k:" + key]
    if (!entry) {
      entry = { name: String(names[k].name).trim(), count: 0, hidden: false }
      byKey["k:" + key] = entry
      out.push(entry)
    }
    if (names[k].hidden) entry.hidden = true
    else entry.count++
  }
  // Rows are one per name already, so two never compare equal.
  out.sort(function(a, b) {
    return sourceKey(a.name) < sourceKey(b.name) ? -1 : 1
  })
  return out
}

// Hidden list after switching one publisher: a hidden one comes back, a
// shown one joins the list under the name the feed spells it with.
function toggleSource(hidden, name) {
  var key = sourceKey(name)
  var out = []
  var found = false
  for (var i = 0; i < hidden.length; i++) {
    if (sourceKey(hidden[i]) === key) found = true
    else out.push(hidden[i])
  }
  if (!found && key !== "") out.push(String(name).trim())
  return out
}

// Right-hand side of a Sources row.
function sourceCount(count) {
  if (!(count > 0)) return "not in this feed"
  return count + (count === 1 ? " headline" : " headlines")
}

// Sources button: says how many headlines the filter takes out of the feed
// on screen, so a shorter list never looks like a broken feed.
function sourcesLabel(hidden) {
  return hidden > 0 ? "Sources · " + hidden + " hidden" : "Sources"
}
