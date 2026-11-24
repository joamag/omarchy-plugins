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

describe("reorder", () => {
  it("moves an entry and closes the gap behind it", () => {
    assert.deepEqual(Model.reorder(["A", "B", "C", "D"], 0, 2), ["B", "C", "A", "D"])
    assert.deepEqual(Model.reorder(["A", "B", "C", "D"], 3, 1), ["A", "D", "B", "C"])
    assert.deepEqual(Model.reorder(["A", "B"], 1, 0), ["B", "A"])
  })

  it("leaves the order alone for a move that goes nowhere", () => {
    const list = ["A", "B", "C"]
    assert.deepEqual(Model.reorder(list, 1, 1), list)
    assert.deepEqual(Model.reorder(list, -1, 2), list)
    assert.deepEqual(Model.reorder(list, 0, 3), list)
    assert.deepEqual(Model.reorder(list, 3, 0), list)
    assert.deepEqual(Model.reorder(null, 0, 1), [])
  })

  it("never touches the list it was given", () => {
    const list = ["A", "B", "C"]
    Model.reorder(list, 0, 2)
    assert.deepEqual(list, ["A", "B", "C"])
  })
})

describe("dropIndex", () => {
  it("turns the pointer's travel into whole rows", () => {
    assert.equal(Model.dropIndex(0, 0, 40, 4), 0)
    assert.equal(Model.dropIndex(0, 19, 40, 4), 0)
    assert.equal(Model.dropIndex(0, 21, 40, 4), 1)
    assert.equal(Model.dropIndex(3, -80, 40, 4), 1)
  })

  it("clamps to the list and stays put on a pitch or travel it cannot use", () => {
    assert.equal(Model.dropIndex(0, -500, 40, 4), 0)
    assert.equal(Model.dropIndex(3, 500, 40, 4), 3)
    assert.equal(Model.dropIndex(2, 80, 0, 4), 2)
    assert.equal(Model.dropIndex(2, NaN, 40, 4), 2)
    assert.equal(Model.dropIndex(1, 40, 40, 0), 0)
  })
})

describe("dragShift", () => {
  it("slides the rows the drag passes over, one place towards the gap", () => {
    // Dragging row 1 down onto row 3 lifts the two rows it passes.
    assert.deepEqual([0, 1, 2, 3].map((i) => Model.dragShift(i, 1, 3)), [0, 0, -1, -1])
    // Dragging row 2 up onto row 0 pushes the two rows above it down.
    assert.deepEqual([0, 1, 2, 3].map((i) => Model.dragShift(i, 2, 0)), [1, 1, 0, 0])
  })

  it("holds every row still without a drag or without a move", () => {
    assert.deepEqual([0, 1, 2].map((i) => Model.dragShift(i, -1, -1)), [0, 0, 0])
    assert.deepEqual([0, 1, 2].map((i) => Model.dragShift(i, 1, 1)), [0, 0, 0])
    assert.equal(Model.dragShift(2, 2, 0), 0)
  })
})

describe("rangeIndex", () => {
  it("finds a range or defaults to the first", () => {
    assert.equal(Model.rangeIndex("6mo"), 3)
    assert.equal(Model.rangeIndex("5y"), 5)
    assert.equal(Model.rangeIndex("bogus"), 0)
  })
})

describe("normalizeRange", () => {
  it("returns a known key", () => {
    assert.equal(Model.normalizeRange("1y"), "1y")
    assert.equal(Model.normalizeRange("5y"), "5y")
    assert.equal(Model.normalizeRange("2y"), "1d")
  })
})

describe("rangeLabel", () => {
  it("gives the short label", () => {
    assert.equal(Model.rangeLabel("1mo"), "1M")
    assert.equal(Model.rangeLabel("5y"), "5Y")
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
    assert.equal(Model.seriesFresh({ fetchedAt: Date.now() - 1800000 }, "5y"), true)
    assert.equal(Model.seriesFresh({ fetchedAt: Date.now() - 7200000 }, "5y"), false)
    assert.equal(Model.seriesFresh({ fetchedAt: Date.now() - 1000 }, "unknown"), true)
    assert.equal(Model.seriesFresh(null, "1d"), false)
  })
})

describe("chartLoading", () => {
  it("waits on the quote for the 1d chart and on the series for the rest", () => {
    assert.equal(Model.chartLoading("1d", undefined, true, false), true)
    assert.equal(Model.chartLoading("5d", GSPC, false, true), true)
    assert.equal(Model.chartLoading("5d", undefined, true, false), false)
  })

  it("ignores a refresh of a quote the chart already has", () => {
    assert.equal(Model.chartLoading("1d", GSPC, true, false), false)
    // A failed quote is still an answer: its message stays put while the
    // next timed refresh runs instead of flipping to a loading state.
    assert.equal(Model.chartLoading("1d", BAD, true, false), false)
    // A series fetch still finishing for another range is not the 1d chart's.
    assert.equal(Model.chartLoading("1d", undefined, false, true), false)
  })

  it("is idle once nothing is being fetched", () => {
    assert.equal(Model.chartLoading("1d", undefined, false, false), false)
    assert.equal(Model.chartLoading("1y", null, undefined, undefined), false)
  })
})

describe("chartSeries", () => {
  const active = { points: [[1, 7742.16]], prevClose: 7666.6 }
  const held = { points: [[1, 457.5], [2, 458.015]], prevClose: 457.06 }

  it("draws the active series whenever there is one", () => {
    assert.equal(Model.chartSeries(active, held, true), active)
    assert.equal(Model.chartSeries(active, held, false), active)
    // A quote with no intraday points is still the chart to show, never
    // swapped for another symbol's held one.
    const empty = { points: [], prevClose: 90.52 }
    assert.equal(Model.chartSeries(empty, held, true), empty)
  })

  it("holds the last chart while the active one is fetched", () => {
    assert.equal(Model.chartSeries(null, held, true), held)
    assert.equal(Model.chartSeries(undefined, held, true), held)
  })

  it("lets the held chart go once nothing is loading", () => {
    assert.equal(Model.chartSeries(null, held, false), null)
    assert.equal(Model.chartSeries(undefined, undefined, false), null)
  })

  it("holds nothing without points to draw", () => {
    assert.equal(Model.chartSeries(null, null, true), null)
    assert.equal(Model.chartSeries(null, { points: [] }, true), null)
    assert.equal(Model.chartSeries(null, { prevClose: 1 }, true), null)
  })
})

describe("chartPlaceholder", () => {
  it("names the range on its way while loading, ahead of any error", () => {
    assert.equal(Model.chartPlaceholder(true, "", "5d"), "Loading 5D chart…")
    assert.equal(Model.chartPlaceholder(true, "No data for AMD", "1y"), "Loading 1Y chart…")
    assert.equal(Model.chartPlaceholder(true, "", "bogus"), "Loading 1D chart…")
  })

  it("shows the last error, or that there is nothing to draw", () => {
    assert.equal(Model.chartPlaceholder(false, "fetch failed", "1d"), "fetch failed")
    assert.equal(Model.chartPlaceholder(false, "", "1d"), "No chart data")
    assert.equal(Model.chartPlaceholder(false, undefined, "5d"), "No chart data")
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
    assert.equal(Model.formatAxis(t, "5y"), "Sep 26")
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
    assert.equal(Model.formatPointTime(t, "5y"), "3 Sep 2026")
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

describe("decodeEntities", () => {
  it("decodes the named references feeds use", () => {
    assert.equal(Model.decodeEntities("Jensen Huang&apos;s return"), "Jensen Huang's return")
    assert.equal(Model.decodeEntities("Best Buy &amp; more"), "Best Buy & more")
    assert.equal(Model.decodeEntities("&lt;b&gt; &quot;x&quot;&nbsp;"), "<b> \"x\" ")
  })

  it("decodes numeric references in hex and decimal", () => {
    assert.equal(Model.decodeEntities("won&#x2019;t"), "won’t")
    assert.equal(Model.decodeEntities("&#169; Dow Jones"), "© Dow Jones")
    assert.equal(Model.decodeEntities("&#x1F4C8;"), "\u{1F4C8}")
  })

  it("drops CDATA wrappers and decodes once only", () => {
    assert.equal(Model.decodeEntities("<![CDATA[Sanofi & Insmed]]>"), "Sanofi & Insmed")
    assert.equal(Model.decodeEntities("&amp;lt;"), "&lt;")
  })

  it("leaves what it does not know alone", () => {
    assert.equal(Model.decodeEntities("&bogus; &#0; &#x110000; & alone"), "&bogus; &#0; &#x110000; & alone")
    assert.equal(Model.decodeEntities("&constructor;"), "&constructor;")
    assert.equal(Model.decodeEntities(undefined), "")
  })
})

describe("newsText", () => {
  it("decodes and folds a feed field onto one trimmed line", () => {
    assert.equal(Model.newsText("\n  Sunday&#x2019;s pot roast\n   costs more  "), "Sunday’s pot roast costs more")
    assert.equal(Model.newsText(null), "")
  })
})

describe("parseRssDate", () => {
  const utc = (h, m, s) => Date.UTC(2026, 10, 24, h, m, s) / 1000

  it("reads RFC 822 dates with or without seconds", () => {
    assert.equal(Model.parseRssDate("Tue, 24 Nov 2026 12:56:00 GMT"), utc(12, 56, 0))
    assert.equal(Model.parseRssDate("Tue, 24 Nov 2026 12:55 GMT"), utc(12, 55, 0))
    assert.equal(Model.parseRssDate("24 nov 2026 12:55:09"), utc(12, 55, 9))
  })

  it("applies zone names and numeric offsets", () => {
    assert.equal(Model.parseRssDate("Tue, 24 Nov 2026 07:56:00 EST"), utc(12, 56, 0))
    assert.equal(Model.parseRssDate("Tue, 24 Nov 2026 07:56:00 -0500"), utc(12, 56, 0))
    assert.equal(Model.parseRssDate("Tue, 24 Nov 2026 14:26:00 +0130"), utc(12, 56, 0))
    assert.equal(Model.parseRssDate("Tue, 24 Nov 2026 12:56:00 utc"), utc(12, 56, 0))
  })

  it("gives NaN for anything it cannot place", () => {
    assert.ok(Number.isNaN(Model.parseRssDate("yesterday")))
    assert.ok(Number.isNaN(Model.parseRssDate("Tue, 24 Foo 2026 12:56 GMT")))
    assert.ok(Number.isNaN(Model.parseRssDate("Tue, 24 Nov 2026 12:56 XYZ")))
    assert.ok(Number.isNaN(Model.parseRssDate(undefined)))
  })
})

describe("rssField", () => {
  it("reads the first tag, attributes allowed, never a prefixed one", () => {
    assert.equal(Model.rssField('<guid isPermaLink="false">WP-1</guid>', "guid"), "WP-1")
    assert.equal(Model.rssField("<media:title>a</media:title><title>b</title><title>c</title>", "title"), "b")
    assert.equal(Model.rssField("<titles>a</titles>", "title"), "")
    assert.equal(Model.rssField("<link>x</link>", "pubDate"), "")
  })
})

describe("parseRss", () => {
  it("reads CNBC's items with decoded titles and their times", () => {
    const items = Model.parseRss(fixture("cnbc-top-news.xml"), "CNBC")
    assert.equal(items.length, 3)
    assert.deepEqual(items[0], {
      title: "Stock futures decline as Nvidia pulls back, giving back part of Monday’s rally: Live updates",
      publisher: "CNBC",
      time: Date.UTC(2026, 10, 24, 12, 37, 27) / 1000,
      link: "https://www.cnbc.com/2026/11/23/stock-market-today-live-updates.html",
    })
    assert.equal(items[1].title, "Six key questions raised by Jensen Huang's return to Nvidia")
    assert.equal(items[2].title, "Stocks making the biggest moves premarket: Nvidia, Anthropic, Best Buy & more")
  })

  it("never takes the channel's own title or image for a story", () => {
    const items = Model.parseRss(fixture("marketwatch-top-stories.xml"), "MarketWatch")
    assert.deepEqual(items.map((i) => i.title), [
      "Sunday’s pot roast now costs more than a Thanksgiving feast. Why beef won’t get cheaper for years.",
      "HPE just posted its strongest growth ever \u2014 but its stock is sinking",
      "The biggest biotech deal in nearly three years carries a hefty $41 billion price tag",
    ])
    assert.ok(items.every((i) => i.publisher === "MarketWatch" && i.link.startsWith("https://www.marketwatch.com/story/")))
  })

  it("drops items without a title or a link and copes with no feed", () => {
    const xml = '<item><title>no link</title></item><item rdf:about="x"><title>ok</title><link>https://a.b/c</link></item><item><link>https://a.b/d</link></item>'
    assert.deepEqual(Model.parseRss(xml, undefined), [{ title: "ok", publisher: "", time: NaN, link: "https://a.b/c" }])
    assert.deepEqual(Model.parseRss(null, "CNBC"), [])
  })
})

describe("mergeNews", () => {
  it("merges feeds newest first and keeps undated items last, in order", () => {
    const a = [{ title: "A old", link: "https://a/1", time: 100 }, { title: "A undated", link: "https://a/2" }]
    const b = [{ title: "B new", link: "https://b/1", time: 300, publisher: "B" }, { title: "B undated", link: "https://b/2", time: "soon" }]
    const merged = Model.mergeNews([a, b], 10)
    assert.deepEqual(merged.map((i) => i.title), ["B new", "A old", "A undated", "B undated"])
    assert.deepEqual(merged[0], { title: "B new", publisher: "B", time: 300, link: "https://b/1" })
  })

  it("shows a story once, matched by link or by title", () => {
    const a = [{ title: "Sanofi buys Insmed", link: "https://cnbc/1", time: 200 }]
    const b = [
      { title: "Other story", link: "https://cnbc/1", time: 300 },
      { title: "SANOFI  buys   Insmed", link: "https://mw/9", time: 250 },
      { title: "Fresh", link: "https://mw/10", time: 150 },
    ]
    assert.deepEqual(Model.mergeNews([a, b], 10).map((i) => i.link), ["https://cnbc/1", "https://mw/10"])
  })

  it("drops junk and stops at the limit", () => {
    const list = [null, { title: "", link: "x" }, { title: "no link" }, ...Array.from({ length: 5 }, (_, i) => ({ title: `t${i}`, link: `l${i}`, time: i }))]
    assert.deepEqual(Model.mergeNews([list, undefined], 3).map((i) => i.title), ["t4", "t3", "t2"])
    assert.deepEqual(Model.mergeNews([], 3), [])
  })
})

describe("parseNews", () => {
  it("reads a symbol's headlines", () => {
    const raw = JSON.stringify({ feed: "AAPL", items: [{ title: "Older", publisher: "Motley Fool", time: 10, link: "https://y/1" }, { title: "Newer", publisher: "Yahoo Finance", time: 20, link: "https://y/2" }] })
    const news = Model.parseNews(raw)
    assert.equal(news.feed, "AAPL")
    assert.deepEqual(news.items.map((i) => i.title), ["Newer", "Older"])
    assert.equal(news.error, "")
  })

  it("merges the top stories feeds newest first", () => {
    const raw = [
      JSON.stringify({ feed: "markets", source: "CNBC", xml: fixture("cnbc-top-news.xml") }),
      JSON.stringify({ feed: "markets", source: "MarketWatch", xml: fixture("marketwatch-top-stories.xml") }),
    ].join("\n")
    const news = Model.parseNews(raw)
    assert.equal(news.feed, Model.TOP_FEED)
    assert.deepEqual(news.items.map((i) => i.publisher), ["CNBC", "MarketWatch", "MarketWatch", "MarketWatch", "CNBC", "CNBC"])
    assert.equal(news.items[0].title, "Stocks making the biggest moves premarket: Nvidia, Anthropic, Best Buy & more")
    assert.equal(news.error, "")
  })

  it("keeps the feeds that answered and names the ones that did not", () => {
    const raw = [
      JSON.stringify({ feed: "markets", source: "CNBC", xml: fixture("cnbc-top-news.xml") }),
      JSON.stringify({ feed: "markets", source: "MarketWatch", error: "fetch failed" }),
    ].join("\n")
    const news = Model.parseNews(raw)
    assert.equal(news.items.length, 3)
    assert.equal(news.error, "MarketWatch: fetch failed")
    assert.deepEqual(Model.parseNews('{"feed":"AAPL","items":[],"error":"news failed"}'), { feed: "AAPL", items: [], error: "news failed" })
  })

  it("skips junk lines and caps the list", () => {
    const many = Array.from({ length: Model.NEWS_LIMIT + 5 }, (_, i) => ({ title: `t${i}`, link: `https://y/${i}`, time: i }))
    const raw = `not json\n{}\n{"items":[]}\n${JSON.stringify({ feed: "NVDA", items: many })}\n`
    const news = Model.parseNews(raw)
    assert.equal(news.feed, "NVDA")
    assert.equal(news.items.length, Model.NEWS_LIMIT)
    assert.deepEqual(Model.parseNews(""), { feed: "", items: [], error: "" })
  })
})

describe("newsEntry", () => {
  const previous = { items: [{ title: "kept" }], error: "", fetchedAt: 5 }

  it("stores a fetch that brought headlines, keeping any partial failure", () => {
    assert.deepEqual(Model.newsEntry(previous, { items: [{ title: "new" }], error: "" }, 9), { items: [{ title: "new" }], error: "", fetchedAt: 9 })
    assert.deepEqual(Model.newsEntry(null, { items: [{ title: "new" }], error: "MarketWatch: fetch failed" }, 9).error, "MarketWatch: fetch failed")
    // A feed with nothing in it is an answer, not a failure.
    assert.deepEqual(Model.newsEntry(previous, { items: [], error: "" }, 9), { items: [], error: "", fetchedAt: 9 })
  })

  it("keeps the headlines on screen when a fetch fails, and tries again next time", () => {
    assert.deepEqual(Model.newsEntry(previous, { items: [], error: "news failed" }, 9), { items: [{ title: "kept" }], error: "news failed", fetchedAt: 0 })
    assert.deepEqual(Model.newsEntry(undefined, { items: [], error: "news failed" }, 9), { items: [], error: "news failed", fetchedAt: 0 })
  })
})

describe("newsFresh", () => {
  it("honours the five minute TTL", () => {
    assert.equal(Model.newsFresh({ fetchedAt: Date.now() - 60000 }), true)
    assert.equal(Model.newsFresh({ fetchedAt: Date.now() - Model.NEWS_TTL_MS - 1 }), false)
    assert.equal(Model.newsFresh({ fetchedAt: 0 }), false)
    assert.equal(Model.newsFresh(null), false)
  })
})

describe("formatAge", () => {
  const t = 1795524188
  const at = (seconds) => (t + seconds) * 1000

  it("counts minutes, hours and days, then gives the date", () => {
    assert.equal(Model.formatAge(t, at(30)), "now")
    assert.equal(Model.formatAge(t, at(9 * 60)), "9m ago")
    assert.equal(Model.formatAge(t, at(3 * 3600 + 300)), "3h ago")
    assert.equal(Model.formatAge(t, at(2 * 86400)), "2d ago")
    assert.equal(Model.formatAge(t, at(8 * 86400)), Model.formatDay(t))
  })

  it("reads a story from slightly ahead of the clock as now", () => {
    assert.equal(Model.formatAge(t, at(-120)), "now")
    assert.equal(Model.formatAge(Date.now() / 1000), "now")
    assert.equal(Model.formatAge(NaN, at(0)), "")
  })
})

describe("newsMeta", () => {
  it("joins publisher and age when known", () => {
    const now = (1795524188 + 9 * 60) * 1000
    assert.equal(Model.newsMeta({ publisher: "CNBC", time: 1795524188 }, now), "CNBC · 9m ago")
    assert.equal(Model.newsMeta({ publisher: "", time: 1795524188 }, now), "9m ago")
    assert.equal(Model.newsMeta({ publisher: "CNBC", time: NaN }, now), "CNBC")
    assert.equal(Model.newsMeta({}, now), "")
  })
})

describe("newsPlaceholder", () => {
  it("names the feed on its way, ahead of any error", () => {
    assert.equal(Model.newsPlaceholder(true, "", "^GSPC"), "Loading S&P 500 news…")
    assert.equal(Model.newsPlaceholder(true, "news failed", Model.TOP_FEED), "Loading top stories…")
  })

  it("shows the error, or that the feed is empty", () => {
    assert.equal(Model.newsPlaceholder(false, "CNBC: fetch failed · MarketWatch: fetch failed", Model.TOP_FEED), "CNBC: fetch failed · MarketWatch: fetch failed")
    assert.equal(Model.newsPlaceholder(false, "", "AMD"), "No news for AMD")
    assert.equal(Model.newsPlaceholder(false, "", Model.TOP_FEED), "No top stories right now")
  })
})

describe("browserCommand", () => {
  it("opens http(s) links as one quoted argument", () => {
    assert.equal(Model.browserCommand(" https://www.cnbc.com/a.html "), "omarchy-launch-browser 'https://www.cnbc.com/a.html'")
    assert.equal(Model.browserCommand("HTTP://example.com"), "omarchy-launch-browser 'HTTP://example.com'")
  })

  it("keeps a quote in the link from breaking out of the argument", () => {
    const url = "https://example.com/it's'; touch /tmp/pwned; echo '"
    const command = Model.browserCommand(url.replace(/ /g, "%20"))
    // The same quoting under bash, with printf standing in for the launcher.
    const result = require("node:child_process").spawnSync("bash", ["-c", command.replace(/^omarchy-launch-browser /, "printf '%s\\n' ")], { encoding: "utf8" })
    assert.equal(result.stdout, url.replace(/ /g, "%20") + "\n")
  })

  it("refuses anything that is not a web link", () => {
    for (const url of ["javascript:alert(1)", "file:///etc/passwd", "ftp://x", "https://a b", "https://", "", undefined]) {
      assert.equal(Model.browserCommand(url), "", String(url))
    }
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
  *finance/search*newsCount=10*) cat "${FIXTURES}/yahoo-search-news-aapl.json" ;;
  *finance/search*) cat "${FIXTURES}/yahoo-search-tes.json" ;;
  *cnbc.com*) cat "${FIXTURES}/cnbc-top-news.xml" ;;
  *dowjones.io*) [[ -n \${FAKE_DOWN:-} ]] || cat "${FIXTURES}/marketwatch-top-stories.xml" ;;
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

  it("condenses a symbol's news", (t) => {
    const dir = fakeCurl(tmpdir(t))
    const log = path.join(dir, "urls.log")
    const result = runJson("joamag.stocks", "quotes.sh", ["news", "AAPL"], { bin: dir, env: { FAKE_LOG: log } })
    assert.equal(result.json.length, 1)
    const [news] = result.json
    assert.equal(news.feed, "AAPL")
    assert.equal(news.items.length, 3)
    assert.deepEqual(Object.keys(news.items[0]).sort(), ["link", "publisher", "time", "title"])
    assert.equal(news.items[0].publisher, "Yahoo Finance")
    assert.equal(news.items[0].time, 1795524188)
    assert.match(fs.readFileSync(log, "utf8"), /search\?q=AAPL&quotesCount=0&newsCount=10/)
  })

  it("reports a news transport failure without breaking the envelope", (t) => {
    const dir = tmpdir(t)
    fakeCommand(dir, "curl", "exit 7")
    const [news] = runJson("joamag.stocks", "quotes.sh", ["news", "^GSPC"], { bin: dir }).json
    assert.deepEqual(news, { feed: "^GSPC", items: [], error: "news failed" })
  })

  it("hands every top stories feed over whole, in order", (t) => {
    const dir = fakeCurl(tmpdir(t))
    const result = runJson("joamag.stocks", "quotes.sh", ["news"], { bin: dir })
    assert.equal(result.status, 0)
    assert.deepEqual(result.json.map((line) => [line.feed, line.source]), [["markets", "CNBC"], ["markets", "MarketWatch"]])
    assert.ok(result.json.every((line) => line.xml.includes("<item>")))
    // What the popup does with it: one list, both feeds, newest first.
    const news = Model.parseNews(result.stdout)
    assert.equal(news.items.length, 6)
    assert.equal(news.error, "")
  })

  it("marks a top stories feed that did not answer and keeps the other", (t) => {
    const dir = fakeCurl(tmpdir(t))
    const result = runJson("joamag.stocks", "quotes.sh", ["news"], { bin: dir, env: { FAKE_DOWN: "1" } })
    assert.equal(result.json[0].source, "CNBC")
    assert.deepEqual(result.json[1], { feed: "markets", source: "MarketWatch", error: "fetch failed" })
    assert.equal(Model.parseNews(result.stdout).error, "MarketWatch: fetch failed")
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
