// Tests for joamag.stocks: Model.js in declaration order, then quotes.sh.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadModel, fixture, FIXTURES, runJson, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.stocks")

// One quote as quotes.sh condenses it: S&P 500 up 1% on the day.
const GSPC = {
  symbol: "^GSPC", range: "1d", name: "S&P 500", currency: "USD", exchange: "SNP",
  price: 7742.16, prevClose: 7666.6, high: 7749.68, low: 7686.71, time: 1788453465, state: "",
  points: [[1788442200, 7707.12], [1788442500, 7700.0], [1788442800, 7742.16]],
}
const AMD = { symbol: "AMD", range: "1d", name: "Advanced Micro Devices, Inc.", currency: "USD", price: 458.015, prevClose: 457.06, time: 1788453465, state: "REGULAR", points: [[1788442200, 457.5]] }
const DOWN = { symbol: "INTC", range: "1d", name: "Intel Corporation", currency: "USD", price: 90.05, prevClose: 90.52, time: 1, state: "CLOSED", points: [] }
const BAD = { symbol: "BOGUS", range: "1d", error: "No data found, symbol may be delisted" }

describe("num", () => {
  it("parses finite numbers only", () => {
    assert.equal(Model.num("1.5"), 1.5)
    assert.ok(Number.isNaN(Model.num("x")))
    assert.ok(Number.isNaN(Model.num(null)))
  })
})

describe("parseLines", () => {
  it("keeps one object per valid line and drops the rest", () => {
    const raw = `${JSON.stringify(GSPC)}\nnot json\n\n{"nosymbol":1}\n${JSON.stringify(BAD)}\n`
    const list = Model.parseLines(raw)
    assert.deepEqual(list.map((q) => q.symbol), ["^GSPC", "BOGUS"])
    assert.deepEqual(Model.parseLines(""), [])
  })
})

describe("parseSymbols", () => {
  it("splits a comma list, trims, upper-cases and dedupes", () => {
    assert.deepEqual(Model.parseSymbols(" amd, ^gspc ,nvda,amd"), ["AMD", "^GSPC", "NVDA"])
  })

  it("accepts an array and falls back to the defaults when empty", () => {
    assert.deepEqual(Model.parseSymbols(["aapl", ""]), ["AAPL"])
    assert.deepEqual(Model.parseSymbols(""), Model.parseSymbols(Model.DEFAULT_SYMBOLS))
    assert.deepEqual(Model.parseSymbols(undefined), Model.parseSymbols(Model.DEFAULT_SYMBOLS))
    assert.equal(Model.parseSymbols(null).length, 8)
  })
})

describe("isIndex", () => {
  it("recognises the caret prefix", () => {
    assert.equal(Model.isIndex("^GSPC"), true)
    assert.equal(Model.isIndex("AMD"), false)
    assert.equal(Model.isIndex(undefined), false)
  })
})

describe("hasQuote", () => {
  it("needs a numeric price and no error", () => {
    assert.equal(Model.hasQuote(GSPC), true)
    assert.equal(Model.hasQuote(BAD), false)
    assert.equal(Model.hasQuote({ symbol: "X", price: "n/a" }), false)
    assert.equal(Model.hasQuote(null), false)
  })
})

describe("shortLabel", () => {
  it("prefers the alias", () => {
    assert.equal(Model.shortLabel("^GSPC"), "S&P 500")
    assert.equal(Model.shortLabel("AMD"), "AMD")
    assert.equal(Model.shortLabel(undefined), "")
  })
})

describe("cleanName", () => {
  it("strips legal suffixes and collapses whitespace", () => {
    assert.equal(Model.cleanName("Advanced Micro Devices, Inc."), "Advanced Micro Devices")
    assert.equal(Model.cleanName("Intel Corporation"), "Intel")
    assert.equal(Model.cleanName("Tesla Inc.                    R"), "Tesla Inc. R")
    assert.equal(Model.cleanName("Tesco PLC"), "Tesco")
    assert.equal(Model.cleanName(null), "")
  })
})

describe("primaryLabel", () => {
  it("uses the alias for indices and the symbol for stocks", () => {
    assert.equal(Model.primaryLabel("^GSPC", GSPC), "S&P 500")
    assert.equal(Model.primaryLabel("^XYZ", { name: "Some Index Ltd." }), "Some Index")
    assert.equal(Model.primaryLabel("^XYZ", null), "^XYZ")
    assert.equal(Model.primaryLabel("AMD", AMD), "AMD")
  })
})

describe("secondaryLabel", () => {
  it("gives the company name, or the raw symbol when it would repeat", () => {
    assert.equal(Model.secondaryLabel("AMD", AMD), "Advanced Micro Devices")
    assert.equal(Model.secondaryLabel("^GSPC", GSPC), "^GSPC")
    assert.equal(Model.secondaryLabel("^IXIC", { name: "NASDAQ Composite" }), "NASDAQ Composite")
    assert.equal(Model.secondaryLabel("^XYZ", { name: "Some Index" }), "^XYZ")
    assert.equal(Model.secondaryLabel("^XYZ", null), "^XYZ")
    assert.equal(Model.secondaryLabel("AMD", null), "")
  })
})

describe("change", () => {
  it("is price minus previous close", () => {
    assert.equal(Math.round(Model.change(GSPC) * 100) / 100, 75.56)
    assert.ok(Number.isNaN(Model.change(BAD)))
    assert.ok(Number.isNaN(Model.change({ symbol: "X", price: 1 })))
  })
})

describe("changePct", () => {
  it("is the relative move, undefined on a zero base", () => {
    assert.equal(Model.changePct(GSPC).toFixed(2), "0.99")
    assert.ok(Number.isNaN(Model.changePct({ symbol: "X", price: 1, prevClose: 0 })))
  })
})

describe("seriesChangePct", () => {
  it("compares the last close with the pre-range close, or the first point", () => {
    assert.equal(Model.seriesChangePct({ prevClose: 100, points: [[1, 105], [2, 110]] }), 10)
    assert.equal(Model.seriesChangePct({ prevClose: 0, points: [[1, 100], [2, 150]] }), 50)
    assert.ok(Number.isNaN(Model.seriesChangePct({ points: [] })))
    assert.ok(Number.isNaN(Model.seriesChangePct(null)))
  })
})

describe("trend", () => {
  it("collapses a number to -1, 0 or 1", () => {
    assert.equal(Model.trend(3), 1)
    assert.equal(Model.trend(-0.01), -1)
    assert.equal(Model.trend(0), 0)
    assert.equal(Model.trend("x"), 0)
  })
})

describe("trendGlyph", () => {
  it("shows a small triangle for a move", () => {
    assert.equal(Model.trendGlyph(1), "▴")
    assert.equal(Model.trendGlyph(-1), "▾")
    assert.equal(Model.trendGlyph(0), "")
  })
})

describe("groupThousands", () => {
  it("inserts separators every three digits", () => {
    assert.equal(Model.groupThousands("7742"), "7,742")
    assert.equal(Model.groupThousands("1234567"), "1,234,567")
    assert.equal(Model.groupThousands("12"), "12")
  })
})

describe("formatNumber", () => {
  it("groups and fixes decimals, keeping the sign", () => {
    assert.equal(Model.formatNumber(7742.16, 2), "7,742.16")
    assert.equal(Model.formatNumber(-1234.5, 1), "-1,234.5")
    assert.equal(Model.formatNumber(5, 0), "5")
    assert.equal(Model.formatNumber("x", 2), "—")
  })
})

describe("priceDecimals", () => {
  it("uses four decimals under one unit", () => {
    assert.equal(Model.priceDecimals(0.5), 4)
    assert.equal(Model.priceDecimals(45), 2)
    assert.equal(Model.priceDecimals(45000), 2)
    assert.equal(Model.priceDecimals(NaN), 2)
  })
})

describe("formatPrice", () => {
  it("formats indices bare and stocks with their currency", () => {
    assert.equal(Model.formatPrice(GSPC), "7,742.16")
    assert.equal(Model.formatPrice(AMD), "$458.02")
    assert.equal(Model.formatPrice(120.5, "GBp", "TSCO.L"), "120.50p")
    assert.equal(Model.formatPrice(12.3456, "SEK", "ERIC-B.ST"), "12.35 SEK")
    assert.equal(Model.formatPrice(0.1234, "", "X"), "0.1234")
    assert.equal(Model.formatPrice(BAD), "—")
  })
})

describe("formatPct", () => {
  it("adds a plus sign unless told otherwise", () => {
    assert.equal(Model.formatPct(0.986), "+0.99%")
    assert.equal(Model.formatPct(-0.5), "-0.50%")
    assert.equal(Model.formatPct(0.5, false), "0.50%")
    assert.equal(Model.formatPct(NaN), "—")
  })
})

describe("formatChange", () => {
  it("combines absolute and relative change", () => {
    assert.equal(Model.formatChange(GSPC), "+75.56 (+0.99%)")
    assert.equal(Model.formatChange(DOWN), "-0.47 (-0.52%)")
    assert.equal(Model.formatChange(BAD), "—")
  })
})

describe("barText", () => {
  it("builds label, optional price and change", () => {
    assert.equal(Model.barText("^GSPC", GSPC, false, true), "S&P 500 ▴0.99%")
    assert.equal(Model.barText("^GSPC", GSPC, true, false), "S&P 500 7,742")
    assert.equal(Model.barText("AMD", AMD, true, true), "AMD 458.02 ▴0.21%")
    assert.equal(Model.barText("INTC", DOWN, false, true), "INTC ▾0.52%")
    assert.equal(Model.barText("BOGUS", BAD, false, true), "BOGUS —")
    assert.equal(Model.barText("AMD", null, false, true), "AMD")
  })
})

describe("tooltip", () => {
  it("names the company with price and change, or the error", () => {
    assert.equal(Model.tooltip("AMD", AMD), "Advanced Micro Devices · $458.02 · +0.95 (+0.21%)")
    assert.equal(Model.tooltip("BOGUS", BAD), "BOGUS · No data found, symbol may be delisted")
    assert.equal(Model.tooltip("AMD", null), "AMD")
  })
})

describe("marketStateLabel", () => {
  it("maps Yahoo market states", () => {
    assert.equal(Model.marketStateLabel({ state: "REGULAR" }), "Market open")
    assert.equal(Model.marketStateLabel({ state: "PRE" }), "Pre-market")
    assert.equal(Model.marketStateLabel({ state: "POST" }), "After hours")
    assert.equal(Model.marketStateLabel({ state: "CLOSED" }), "Market closed")
    assert.equal(Model.marketStateLabel(null), "")
  })

  it("derives a label from the quote age when the state is missing", () => {
    const now = Math.floor(Date.now() / 1000)
    assert.equal(Model.marketStateLabel({ state: "", time: now - 60 }), "Live")
    assert.match(Model.marketStateLabel({ state: "", time: now - 3600 }), /^As of \d\d:\d\d$/)
    assert.match(Model.marketStateLabel({ state: "", time: now - 3 * 86400 }), /^Last close \d+ [A-Z][a-z]{2}$/)
    assert.equal(Model.marketStateLabel({ state: "" }), "")
  })
})

describe("nextSymbol", () => {
  it("cycles in both directions and copes with an unknown current", () => {
    assert.equal(Model.nextSymbol(["A", "B", "C"], "C", 1), "A")
    assert.equal(Model.nextSymbol(["A", "B", "C"], "A", -1), "C")
    assert.equal(Model.nextSymbol(["A", "B"], "Z", 1), "B")
    assert.equal(Model.nextSymbol([], "A", 1), "A")
  })
})

describe("rangeIndex", () => {
  it("finds a range or defaults to the first", () => {
    assert.equal(Model.rangeIndex("6mo"), 3)
    assert.equal(Model.rangeIndex("bogus"), 0)
  })
})

describe("normalizeRange", () => {
  it("returns a known key", () => {
    assert.equal(Model.normalizeRange("1y"), "1y")
    assert.equal(Model.normalizeRange("2y"), "1d")
  })
})

describe("rangeLabel", () => {
  it("gives the short label", () => {
    assert.equal(Model.rangeLabel("1mo"), "1M")
  })
})

describe("seriesKey", () => {
  it("joins symbol and range", () => {
    assert.equal(Model.seriesKey("AMD", "5d"), "AMD|5d")
  })
})

describe("seriesFresh", () => {
  it("honours the per-range TTL", () => {
    assert.equal(Model.seriesFresh({ fetchedAt: Date.now() }, "1d"), true)
    assert.equal(Model.seriesFresh({ fetchedAt: Date.now() - 120000 }, "1d"), false)
    assert.equal(Model.seriesFresh({ fetchedAt: Date.now() - 120000 }, "1y"), true)
    assert.equal(Model.seriesFresh({ fetchedAt: Date.now() - 1000 }, "unknown"), true)
    assert.equal(Model.seriesFresh(null, "1d"), false)
  })
})

describe("pad2", () => {
  it("zero-pads single digits", () => {
    assert.equal(Model.pad2(7), "07")
    assert.equal(Model.pad2(12), "12")
  })
})

describe("formatClock", () => {
  it("prints local HH:mm", () => {
    const d = new Date(2026, 8, 3, 9, 5)
    assert.equal(Model.formatClock(d.getTime() / 1000), "09:05")
  })
})

describe("formatDay", () => {
  it("prints day and month", () => {
    assert.equal(Model.formatDay(new Date(2026, 8, 3).getTime() / 1000), "3 Sep")
  })
})

describe("formatAxis", () => {
  it("adapts the axis label to the range", () => {
    const t = new Date(2026, 8, 3, 14, 30).getTime() / 1000
    assert.equal(Model.formatAxis(t, "1d"), "14:30")
    assert.equal(Model.formatAxis(t, "5d"), "Thu")
    assert.equal(Model.formatAxis(t, "1mo"), "3 Sep")
    assert.equal(Model.formatAxis(t, "6mo"), "Sep")
    assert.equal(Model.formatAxis(t, "1y"), "Sep 26")
  })
})

describe("parseSearch", () => {
  it("reads the search envelope and ignores anything else", () => {
    const parsed = Model.parseSearch('{"query":"tes","results":[{"symbol":"TSLA","name":"Tesla, Inc.","exchange":"NASDAQ","type":"Equity"}]}\n')
    assert.equal(parsed.query, "tes")
    assert.equal(parsed.results.length, 1)
    assert.equal(parsed.error, "")
    assert.equal(Model.parseSearch('{"query":"x","results":[],"error":"search failed"}').error, "search failed")
    assert.deepEqual(Model.parseSearch("garbage\n{\"nope\":1}"), { query: "", results: [], error: "" })
  })
})

describe("filterSuggestions", () => {
  it("hides symbols already on the watchlist and junk entries", () => {
    const results = [{ symbol: "TSLA" }, { symbol: "tl0.de" }, { name: "no symbol" }, null]
    assert.deepEqual(Model.filterSuggestions(results, ["TL0.DE"]).map((r) => r.symbol), ["TSLA"])
  })
})

describe("suggestionMeta", () => {
  it("joins exchange and type when present", () => {
    assert.equal(Model.suggestionMeta({ exchange: "NASDAQ", type: "Equity" }), "NASDAQ · Equity")
    assert.equal(Model.suggestionMeta({ type: "ETF" }), "ETF")
    assert.equal(Model.suggestionMeta({}), "")
  })
})

describe("formatPointTime", () => {
  it("shows time for intraday ranges and a date otherwise", () => {
    const t = new Date(2026, 8, 3, 14, 30).getTime() / 1000
    assert.equal(Model.formatPointTime(t, "1d"), "14:30")
    assert.equal(Model.formatPointTime(t, "5d"), "Thu 14:30")
    assert.equal(Model.formatPointTime(t, "1y"), "3 Sep 2026")
  })
})

describe("seriesStats", () => {
  it("finds min, max, first, last and the count of numeric points", () => {
    const stats = Model.seriesStats([[1, 5], [2, "x"], [3, 2], [4, 9]])
    assert.deepEqual(stats, { min: 2, max: 9, first: 5, last: 9, count: 3 })
    assert.equal(Model.seriesStats([]).count, 0)
    assert.equal(Model.seriesStats(null).count, 0)
  })
})

describe("chartGeometry", () => {
  it("spreads points across the width and scales within the padding", () => {
    const geo = Model.chartGeometry([[1, 10], [2, 20], [3, 15]], 200, 100, NaN, 10, 10)
    assert.equal(geo.points.length, 3)
    assert.deepEqual(geo.points.map((p) => p.x), [0, 100, 200])
    assert.equal(geo.points[1].y, 10)
    assert.equal(geo.points[0].y, 90)
    assert.ok(Number.isNaN(geo.baselineY))
    assert.equal(geo.min, 10)
    assert.equal(geo.max, 20)
  })

  it("keeps the baseline inside the scale", () => {
    const geo = Model.chartGeometry([[1, 10], [2, 12]], 100, 100, 20, 0, 0)
    assert.equal(geo.baselineY, 0)
    assert.equal(geo.points[0].y, 100)
    const below = Model.chartGeometry([[1, 10], [2, 12]], 100, 100, 5, 0, 0)
    assert.equal(below.baselineY, 100)
  })

  it("copes with a flat series, a single point and bad input", () => {
    const flat = Model.chartGeometry([[1, 10], [2, 10]], 100, 50, NaN, 0, 0)
    assert.equal(flat.points[0].y, 25)
    const single = Model.chartGeometry([[1, 10]], 100, 50, NaN, 0, 0)
    assert.equal(single.points.length, 1)
    assert.equal(single.points[0].x, 0)
    assert.deepEqual(Model.chartGeometry([], 100, 50, NaN, 0, 0).points, [])
    assert.deepEqual(Model.chartGeometry([[1, 10]], 0, 50, NaN, 0, 0).points, [])
    assert.equal(Model.chartGeometry([[1, "x"], [2, 3]], 100, 50, NaN, 0, 0).points.length, 1)
  })
})

describe("quotes.sh", () => {
  // A curl stand-in answering from fixtures by URL, logging every URL it was
  // asked for, and failing FLAKY once before succeeding.
  function fakeCurl(dir) {
    fakeCommand(dir, "curl", `
url="\${@: -1}"
[[ -n \${FAKE_LOG:-} ]] && printf '%s\\n' "$url" >> "$FAKE_LOG"
case "$url" in
  *finance/search*) cat "${FIXTURES}/yahoo-search-tes.json" ;;
  *chart/%5EGSPC*) cat "${FIXTURES}/yahoo-chart-gspc.json" ;;
  *chart/AMD*) cat "${FIXTURES}/yahoo-chart-amd-5d.json" ;;
  *chart/FLAKY*) if [[ -f "$FAKE_STATE" ]]; then cat "${FIXTURES}/yahoo-chart-gspc.json"; else touch "$FAKE_STATE"; cat "${FIXTURES}/yahoo-chart-error.json"; fi ;;
  *) cat "${FIXTURES}/yahoo-chart-error.json" ;;
esac`)
    return dir
  }

  it("fetches every symbol and keeps the order, errors included", (t) => {
    const dir = fakeCurl(tmpdir(t))
    const log = path.join(dir, "urls.log")
    const result = runJson("joamag.stocks", "quotes.sh", ["quotes", "^GSPC", "BOGUSXYZ"], { bin: dir, env: { FAKE_LOG: log } })
    assert.equal(result.status, 0)
    assert.equal(result.json.length, 2)
    const [gspc, bogus] = result.json
    assert.equal(gspc.symbol, "^GSPC")
    assert.equal(gspc.name, "S&P 500")
    assert.equal(gspc.range, "1d")
    assert.ok(gspc.points.length > 10)
    assert.ok(gspc.points.every((p) => p.length === 2 && Number.isFinite(p[1])))
    assert.equal(bogus.symbol, "BOGUSXYZ")
    assert.equal(bogus.error, "No data found, symbol may be delisted")
    const urls = fs.readFileSync(log, "utf8")
    assert.match(urls, /chart\/%5EGSPC\?range=1d&interval=5m/)
  })

  it("maps ranges to intervals for series", (t) => {
    const dir = fakeCurl(tmpdir(t))
    const log = path.join(dir, "urls.log")
    const expected = { "1d": "5m", "5d": "30m", "1mo": "1d", "6mo": "1d", "1y": "1wk", "5y": "1mo", bogus: "1d" }
    for (const [range, interval] of Object.entries(expected)) {
      const [series] = runJson("joamag.stocks", "quotes.sh", ["series", "AMD", range], { bin: dir, env: { FAKE_LOG: log } }).json
      assert.equal(series.symbol, "AMD")
      assert.equal(series.range, range)
      assert.ok(series.points.length > 0)
    }
    const urls = fs.readFileSync(log, "utf8").trim().split("\n")
    assert.deepEqual(urls.map((u) => u.match(/interval=(\w+)/)[1]), Object.values(expected))
  })

  it("retries a failed symbol once", (t) => {
    const dir = fakeCurl(tmpdir(t))
    const log = path.join(dir, "urls.log")
    const [quote] = runJson("joamag.stocks", "quotes.sh", ["quotes", "FLAKY"], { bin: dir, env: { FAKE_LOG: log, FAKE_STATE: path.join(dir, "flaky.once") } }).json
    assert.equal(quote.error, undefined)
    assert.equal(quote.name, "S&P 500")
    assert.equal(fs.readFileSync(log, "utf8").trim().split("\n").length, 2)
  })

  it("condenses search results", (t) => {
    const dir = fakeCurl(tmpdir(t))
    const [search] = runJson("joamag.stocks", "quotes.sh", ["search", "tes"], { bin: dir }).json
    assert.equal(search.query, "tes")
    assert.equal(search.results[0].symbol, "TSLA")
    assert.deepEqual(Object.keys(search.results[0]).sort(), ["exchange", "name", "symbol", "type"])
  })

  it("reports a search transport failure without breaking the envelope", (t) => {
    const dir = tmpdir(t)
    fakeCommand(dir, "curl", "exit 7")
    const [search] = runJson("joamag.stocks", "quotes.sh", ["search", "tes"], { bin: dir }).json
    assert.deepEqual(search, { query: "tes", results: [], error: "search failed" })
  })

  it("rejects bad invocations", () => {
    assert.equal(runScript("joamag.stocks", "quotes.sh", ["bogus"]).status, 1)
    assert.equal(runScript("joamag.stocks", "quotes.sh", ["series"]).status, 1)
    assert.equal(runScript("joamag.stocks", "quotes.sh", ["search"]).status, 1)
    const none = runScript("joamag.stocks", "quotes.sh", ["quotes"])
    assert.equal(none.status, 0)
    assert.equal(none.stdout, "")
  })
})
