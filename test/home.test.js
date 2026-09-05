// Tests for joamag.home: Model.js in declaration order, then home.sh against
// an in-process stand-in for the Home Assistant API.

const { describe, it, before, after } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const http = require("node:http")
const path = require("node:path")
const { loadModel, runJsonAsync, runScriptAsync, tmpdir, fixture } = require("./helpers")

const Model = loadModel("joamag.home")

// Entities the way home.sh condenses them: two thermostats, three lights, a
// switch, a fan, a cover, a scene and a script.
function row(id, state, extra = {}) {
  const domain = id.split(".")[0]
  return { id, domain, name: id, state, brightness: null, temperature: null, current: null, action: null, modes: [], step: 1, min: null, max: null, changed: "", ...extra }
}
const ac = row("climate.living_room", "cool", { name: "Living room AC", modes: ["off", "cool", "heat", "heat_cool", "fan_only"], current: 24.5, temperature: 22, step: 0.5, min: 16, max: 30, action: "cooling" })
const officeAc = row("climate.office", "off", { name: "Office AC", modes: ["off", "cool", "heat"], current: 23, temperature: 21 })
const kitchen = row("light.kitchen", "on", { name: "Kitchen", brightness: 204 })
const bedroom = row("light.bedroom", "off", { name: "Bedroom" })
const porch = row("light.porch", "on", { name: "Porch" })
const coffee = row("switch.coffee", "off", { name: "Coffee machine" })
const fan = row("fan.office", "on", { name: "Office fan" })
const garage = row("cover.garage", "closed", { name: "Garage door" })
const movie = row("scene.movie_night", "2026-09-03T21:00:00+00:00", { name: "Movie night" })
const goodnight = row("script.goodnight", "off", { name: "Goodnight" })
const OK = { state: "ok", url: "http://ha.local:8123", fetchedAt: 1, entities: [ac, officeAc, kitchen, bedroom, porch, coffee, fan, garage, movie, goodnight] }
const LIGHTS_ONLY = { state: "ok", url: "u", fetchedAt: 1, entities: [kitchen, bedroom] }
const EMPTY = { state: "ok", url: "u", fetchedAt: 1, entities: [] }

describe("num", () => {
  it("parses numbers and numeric strings and rejects the rest", () => {
    assert.equal(Model.num("22.5"), 22.5)
    assert.ok(Number.isNaN(Model.num(null)))
    assert.ok(Number.isNaN(Model.num("")))
    assert.ok(Number.isNaN(Model.num("warm")))
  })
})

describe("parseResult", () => {
  it("accepts an envelope with a state and rejects anything else", () => {
    assert.equal(Model.parseResult(JSON.stringify(OK)).state, "ok")
    assert.equal(Model.parseResult("{}").state, "error")
    assert.equal(Model.parseResult("not json").state, "error")
    assert.equal(Model.parseResult("").error, "Home Assistant returned no data")
    assert.equal(Model.parseResult(null).state, "error")
  })
})

describe("hasEntities", () => {
  it("needs an entities array", () => {
    assert.equal(Model.hasEntities(OK), true)
    assert.equal(Model.hasEntities({ state: "ok" }), false)
    assert.equal(Model.hasEntities(null), false)
  })
})

describe("isOk", () => {
  it("is true only for an ok state with entities", () => {
    assert.equal(Model.isOk(OK), true)
    assert.equal(Model.isOk({ state: "unreachable", entities: [] }), false)
    assert.equal(Model.isOk({ state: "ok" }), false)
  })
})

describe("needsCredentials", () => {
  it("wants the form for unconfigured and unauthorized", () => {
    assert.equal(Model.needsCredentials({ state: "unconfigured" }), true)
    assert.equal(Model.needsCredentials({ state: "unauthorized" }), true)
    assert.equal(Model.needsCredentials({ state: "unreachable" }), false)
    assert.equal(Model.needsCredentials(null), false)
  })
})

describe("prefill", () => {
  it("uses what the script knows, else the fallback", () => {
    assert.deepEqual(Model.prefill({ url: "http://ha", username: "joao" }, "x"), { url: "http://ha", username: "joao" })
    assert.deepEqual(Model.prefill(null, "http://fallback"), { url: "http://fallback", username: "" })
    assert.deepEqual(Model.prefill({}, undefined), { url: "", username: "" })
  })
})

describe("entities", () => {
  it("is the list or nothing", () => {
    assert.equal(Model.entities(OK).length, 10)
    assert.deepEqual(Model.entities({ state: "error" }), [])
  })
})

describe("domainOf", () => {
  it("is the part before the dot", () => {
    assert.equal(Model.domainOf("light.kitchen"), "light")
    assert.equal(Model.domainOf("nodot"), "")
    assert.equal(Model.domainOf(null), "")
  })
})

describe("entityName", () => {
  it("prefers the friendly name and falls back to the id", () => {
    assert.equal(Model.entityName(kitchen), "Kitchen")
    assert.equal(Model.entityName({ id: "light.x" }), "light.x")
    assert.equal(Model.entityName(null), "")
  })
})

describe("isClimate", () => {
  it("is true for thermostats only", () => {
    assert.equal(Model.isClimate(ac), true)
    assert.equal(Model.isClimate(kitchen), false)
    assert.equal(Model.isClimate(null), false)
  })
})

describe("isAvailable", () => {
  it("rejects unavailable, unknown and empty states", () => {
    assert.equal(Model.isAvailable(kitchen), true)
    assert.equal(Model.isAvailable(row("light.a", "unavailable")), false)
    assert.equal(Model.isAvailable(row("light.a", "unknown")), false)
    assert.equal(Model.isAvailable(row("light.a", "")), false)
    assert.equal(Model.isAvailable(null), false)
  })
})

describe("isOn", () => {
  it("knows what on means for each kind of entity", () => {
    assert.equal(Model.isOn(kitchen), true)
    assert.equal(Model.isOn(bedroom), false)
    assert.equal(Model.isOn(ac), true)
    assert.equal(Model.isOn(officeAc), false)
    assert.equal(Model.isOn(garage), false)
    assert.equal(Model.isOn(row("cover.g", "opening")), true)
    assert.equal(Model.isOn(row("light.a", "unavailable")), false)
  })
})

describe("groupOf", () => {
  it("files every domain under a section", () => {
    assert.equal(Model.groupOf(ac), "climate")
    assert.equal(Model.groupOf(kitchen), "lights")
    assert.equal(Model.groupOf(coffee), "switches")
    assert.equal(Model.groupOf(fan), "switches")
    assert.equal(Model.groupOf(garage), "covers")
    assert.equal(Model.groupOf(movie), "scenes")
    assert.equal(Model.groupOf(goodnight), "scenes")
    assert.equal(Model.groupOf(null), "switches")
  })
})

describe("rowAction", () => {
  it("names what Enter does on the row", () => {
    assert.equal(Model.rowAction(ac), "climate")
    assert.equal(Model.rowAction(movie), "activate")
    assert.equal(Model.rowAction(goodnight), "activate")
    assert.equal(Model.rowAction(kitchen), "toggle")
    assert.equal(Model.rowAction(garage), "toggle")
    assert.equal(Model.rowAction(null), "")
  })
})

describe("typeIcon", () => {
  it("draws the mode on a thermostat and the domain elsewhere", () => {
    assert.equal(Model.typeIcon(ac), Model.MODE_ICONS.cool)
    assert.equal(Model.typeIcon(officeAc), Model.MODE_ICONS.off)
    assert.equal(Model.typeIcon(kitchen), Model.DOMAIN_ICONS.light)
    assert.equal(Model.typeIcon(row("vacuum.bot", "docked")), Model.ICON)
    assert.equal(Model.typeIcon(null), Model.ICON)
  })
})

describe("modeLabel", () => {
  it("names the known modes and capitalises the rest", () => {
    assert.equal(Model.modeLabel("cool"), "Cool")
    assert.equal(Model.modeLabel("heat_cool"), "Auto")
    assert.equal(Model.modeLabel("fan_only"), "Fan")
    assert.equal(Model.modeLabel("eco"), "Eco")
    assert.equal(Model.modeLabel(""), "—")
  })
})

describe("modeIcon", () => {
  it("has a glyph per mode and a thermostat fallback", () => {
    assert.equal(Model.modeIcon("heat"), Model.MODE_ICONS.heat)
    assert.equal(Model.modeIcon("eco"), Model.DOMAIN_ICONS.climate)
  })
})

describe("climateModes", () => {
  it("lists the device's modes with off always among them", () => {
    assert.deepEqual(Model.climateModes(ac), ["off", "cool", "heat", "heat_cool", "fan_only"])
    assert.deepEqual(Model.climateModes(row("climate.x", "cool", { modes: ["cool", "heat"] })), ["off", "cool", "heat"])
    assert.deepEqual(Model.climateModes(row("climate.x", "off", { modes: "nope" })), ["off"])
    assert.deepEqual(Model.climateModes(null), ["off"])
  })

  it("reads a list that is array-like but not an Array, as QML hands it back", () => {
    // What a Repeater's modelData makes of a JS array: a QVariantList, with
    // a length and indices but failing Array.isArray.
    const qmlList = { length: 2, 0: "cool", 1: "off" }
    assert.deepEqual(Model.climateModes(row("climate.x", "cool", { modes: qmlList })), ["cool", "off"])
    assert.equal(Model.nextMode(row("climate.x", "cool", { modes: qmlList }), 1), "off")
  })
})

describe("nextMode", () => {
  it("cycles forward and back and wraps", () => {
    assert.equal(Model.nextMode(ac, 1), "heat")
    assert.equal(Model.nextMode(ac, -1), "off")
    assert.equal(Model.nextMode(officeAc, -1), "heat")
    assert.equal(Model.nextMode(row("climate.x", "eco", { modes: ["off", "cool"] }), 1), "cool")
  })
})

describe("climateStep", () => {
  it("is the device's step, or one degree", () => {
    assert.equal(Model.climateStep(ac), 0.5)
    assert.equal(Model.climateStep(officeAc), 1)
    assert.equal(Model.climateStep(row("climate.x", "off", { step: 0 })), 1)
    assert.equal(Model.climateStep(null), 1)
  })
})

describe("climateUiStep", () => {
  it("never steps finer than half a degree", () => {
    assert.equal(Model.climateUiStep(ac), 0.5)
    assert.equal(Model.climateUiStep(officeAc), 1)
    assert.equal(Model.climateUiStep(row("climate.x", "cool", { step: 0.1 })), 0.5)
    assert.equal(Model.climateUiStep(null), 1)
  })
})

describe("clampTemperature", () => {
  it("snaps to the step and stays inside the device's range", () => {
    assert.equal(Model.clampTemperature(ac, 22.3), 22.5)
    assert.equal(Model.clampTemperature(ac, 22.24), 22)
    assert.equal(Model.clampTemperature(ac, 40), 30)
    assert.equal(Model.clampTemperature(ac, 5), 16)
    assert.equal(Model.clampTemperature(officeAc, 21.6), 22)
  })

  it("uses sane defaults without a range and rejects garbage", () => {
    const bare = row("climate.x", "cool")
    assert.equal(Model.clampTemperature(bare, 50), Model.DEFAULT_MAX_TEMP)
    assert.equal(Model.clampTemperature(bare, -3), Model.DEFAULT_MIN_TEMP)
    assert.ok(Number.isNaN(Model.clampTemperature(ac, "warm")))
  })
})

describe("formatTemp", () => {
  it("writes a degree sign and one decimal at most", () => {
    assert.equal(Model.formatTemp(22), "22°")
    assert.equal(Model.formatTemp(24.5), "24.5°")
    assert.equal(Model.formatTemp(21.44), "21.4°")
    assert.equal(Model.formatTemp(null), "—")
  })
})

describe("climateAction", () => {
  it("names the known actions and nothing else", () => {
    assert.equal(Model.climateAction(ac), "cooling")
    assert.equal(Model.climateAction(row("climate.x", "heat", { action: "heating" })), "heating")
    assert.equal(Model.climateAction(row("climate.x", "heat", { action: "preheating" })), "")
    assert.equal(Model.climateAction(officeAc), "")
    assert.equal(Model.climateAction(null), "")
  })
})

describe("climateDetail", () => {
  it("joins mode, room temperature and what it is doing", () => {
    assert.equal(Model.climateDetail(ac), "Cool · 24.5° now · cooling")
    assert.equal(Model.climateDetail(officeAc), "Off · 23° now")
    assert.equal(Model.climateDetail(row("climate.x", "heat")), "Heat")
    assert.equal(Model.climateDetail(null), "")
  })
})

describe("brightnessPct", () => {
  it("is a percentage when lit, zero when off, unknown otherwise", () => {
    assert.equal(Model.brightnessPct(kitchen), 80)
    assert.equal(Model.brightnessPct(bedroom), 0)
    assert.ok(Number.isNaN(Model.brightnessPct(porch)))
    assert.ok(Number.isNaN(Model.brightnessPct(coffee)))
    assert.ok(Number.isNaN(Model.brightnessPct(null)))
  })
})

describe("canDim", () => {
  it("is true for a light that reports brightness", () => {
    assert.equal(Model.canDim(kitchen), true)
    assert.equal(Model.canDim(porch), false)
    assert.equal(Model.canDim(bedroom), false)
    assert.equal(Model.canDim(fan), false)
  })
})

describe("entityDetail", () => {
  it("describes every kind of row", () => {
    assert.equal(Model.entityDetail(kitchen), "on · 80%")
    assert.equal(Model.entityDetail(porch), "on")
    assert.equal(Model.entityDetail(bedroom), "off")
    assert.equal(Model.entityDetail(coffee), "off")
    assert.equal(Model.entityDetail(fan), "on")
    assert.equal(Model.entityDetail(garage), "closed")
    assert.equal(Model.entityDetail(movie), "scene")
    assert.equal(Model.entityDetail(goodnight), "script")
    assert.equal(Model.entityDetail(row("script.x", "on")), "running")
    assert.equal(Model.entityDetail(row("light.a", "unavailable")), "unavailable")
    assert.equal(Model.entityDetail(ac), "Cool · 24.5° now · cooling")
    assert.equal(Model.entityDetail(null), "")
  })
})

describe("lightsOn", () => {
  it("counts lit lights only", () => {
    assert.equal(Model.lightsOn(OK), 2)
    assert.equal(Model.lightsOn(EMPTY), 0)
    assert.equal(Model.lightsOn(null), 0)
  })
})

describe("lightsTotal", () => {
  it("counts lights of any state", () => {
    assert.equal(Model.lightsTotal(OK), 3)
    assert.equal(Model.lightsTotal({ state: "ok", entities: [coffee] }), 0)
  })
})

describe("activeClimate", () => {
  it("prefers a running thermostat, then any, then none", () => {
    assert.equal(Model.activeClimate(OK), ac)
    assert.equal(Model.activeClimate({ state: "ok", entities: [officeAc, ac] }), ac)
    assert.equal(Model.activeClimate({ state: "ok", entities: [officeAc] }), officeAc)
    assert.equal(Model.activeClimate(LIGHTS_ONLY), null)
    assert.equal(Model.activeClimate(null), null)
  })
})

describe("barText", () => {
  it("shows lights, the thermostat, both or the icon", () => {
    assert.equal(Model.barText(OK, "both", false), `${Model.ICON} 2 · ${Model.MODE_ICONS.cool} 22°`)
    assert.equal(Model.barText(OK, "lights", false), `${Model.ICON} 2`)
    assert.equal(Model.barText(OK, "climate", false), `${Model.ICON} ${Model.MODE_ICONS.cool} 22°`)
    assert.equal(Model.barText(OK, "none", false), Model.ICON)
    assert.equal(Model.barText(OK, "both", true), Model.ICON)
  })

  it("drops what there is nothing to say about", () => {
    assert.equal(Model.barText(LIGHTS_ONLY, "both", false), `${Model.ICON} 1`)
    assert.equal(Model.barText({ state: "ok", entities: [officeAc] }, "both", false), Model.ICON)
    assert.equal(Model.barText({ state: "unreachable", entities: [] }, "both", false), Model.ICON)
    assert.equal(Model.barText(null, "both", false), Model.ICON)
  })
})

describe("tooltip", () => {
  it("summarises lights and the thermostat, or the failing state", () => {
    assert.equal(Model.tooltip(OK), "Home · 2 of 3 lights on · Living room AC cool 22°")
    assert.equal(Model.tooltip({ state: "ok", entities: [officeAc] }), "Home · Office AC off")
    assert.equal(Model.tooltip({ state: "ok", entities: [coffee] }), "Home · 1 entities")
    assert.equal(Model.tooltip({ state: "unconfigured" }), "Home Assistant: not signed in")
    assert.equal(Model.tooltip({ state: "unauthorized" }), "Home Assistant: sign-in refused")
    assert.equal(Model.tooltip({ state: "unreachable", entities: [kitchen] }), "Home Assistant unreachable · showing last known state")
    assert.equal(Model.tooltip({ state: "unreachable", entities: [] }), "Home Assistant unreachable")
    assert.equal(Model.tooltip({ state: "error", error: "boom" }), "Home Assistant: boom")
    assert.equal(Model.tooltip(null), "Home")
  })
})

describe("heroStatus", () => {
  it("counts lights and names the thermostat's mode", () => {
    assert.equal(Model.heroStatus(OK), "2 OF 3 LIGHTS ON · COOL 22°")
    assert.equal(Model.heroStatus({ state: "ok", entities: [officeAc] }), "CLIMATE OFF")
    assert.equal(Model.heroStatus({ state: "unreachable", entities: [kitchen] }), "1 OF 1 LIGHTS ON · CACHED")
    assert.equal(Model.heroStatus(EMPTY), "NOTHING TO CONTROL")
    assert.equal(Model.heroStatus({ state: "unconfigured" }), "UNCONFIGURED")
    assert.equal(Model.heroStatus(null), "LOADING")
  })
})

describe("heroValue", () => {
  it("is the room temperature, else the target, else the lights lit", () => {
    assert.equal(Model.heroValue(OK), "24.5°")
    assert.equal(Model.heroValue({ state: "ok", entities: [row("climate.x", "cool", { temperature: 20 })] }), "20°")
    assert.equal(Model.heroValue(LIGHTS_ONLY), "1")
    assert.equal(Model.heroValue({ state: "unreachable", entities: [kitchen] }), "1")
    assert.equal(Model.heroValue({ state: "unreachable", entities: [] }), "—")
    assert.equal(Model.heroValue(null), "—")
  })
})

describe("stateTitle", () => {
  it("names every state", () => {
    assert.equal(Model.stateTitle({ state: "unconfigured" }), "Home Assistant is not set up")
    assert.equal(Model.stateTitle({ state: "unauthorized" }), "Home Assistant refused the sign-in")
    assert.equal(Model.stateTitle({ state: "unreachable" }), "Home Assistant is unreachable")
    assert.equal(Model.stateTitle({ state: "error" }), "Home Assistant request failed")
    assert.equal(Model.stateTitle(null), "Loading Home Assistant")
  })
})

describe("stateDetail", () => {
  it("explains every state", () => {
    assert.match(Model.stateDetail({ state: "unconfigured" }), /never stored/)
    assert.equal(Model.stateDetail({ state: "unauthorized", error: "nope" }), "nope")
    assert.equal(Model.stateDetail({ state: "unauthorized" }), "Sign in again below.")
    assert.equal(Model.stateDetail({ state: "unreachable", error: "timed out", entities: [kitchen] }), "timed out. Showing the last state that was fetched.")
    assert.equal(Model.stateDetail({ state: "unreachable", entities: [] }), "No response")
    assert.equal(Model.stateDetail({ state: "error", error: "boom" }), "boom")
    assert.equal(Model.stateDetail({ state: "error" }), "")
    assert.equal(Model.stateDetail(null), "")
  })
})

// A house with more switches than the list will show at once.
const BIG = { state: "ok", url: "u", fetchedAt: 1, entities: [ac].concat(Array.from({ length: 70 }, (_, i) => row(`switch.plug_${i}`, i % 2 ? "on" : "off", { name: `Plug ${i}` }))) }

describe("tabs", () => {
  it("lists the groups that have members, with All in front", () => {
    assert.deepEqual(Model.tabs(OK).map((t) => `${t.key}:${t.count}`), ["all:10", "climate:2", "lights:3", "switches:2", "covers:1", "scenes:2"])
    assert.deepEqual(Model.tabs(LIGHTS_ONLY).map((t) => t.key), ["lights"])
    assert.deepEqual(Model.tabs(EMPTY), [])
    assert.deepEqual(Model.tabs(null), [])
  })
})

describe("normalizeTab", () => {
  it("keeps a tab that exists and falls back to all", () => {
    assert.equal(Model.normalizeTab(OK, "lights"), "lights")
    assert.equal(Model.normalizeTab(OK, "all"), "all")
    assert.equal(Model.normalizeTab(OK, "vacuums"), "all")
    assert.equal(Model.normalizeTab(LIGHTS_ONLY, "all"), "all")
  })
})

describe("nextTab", () => {
  it("steps through the tabs and wraps", () => {
    assert.equal(Model.nextTab(OK, "all", 1), "climate")
    assert.equal(Model.nextTab(OK, "scenes", 1), "all")
    assert.equal(Model.nextTab(OK, "all", -1), "scenes")
    assert.equal(Model.nextTab(OK, "bogus", 1), "climate")
    assert.equal(Model.nextTab(EMPTY, "all", 1), "all")
  })
})

describe("matchesQuery", () => {
  it("wants every word somewhere in the name or id, case aside", () => {
    assert.equal(Model.matchesQuery(ac, "living"), true)
    assert.equal(Model.matchesQuery(ac, "LIVING ROOM"), true)
    assert.equal(Model.matchesQuery(ac, "room living"), true)
    assert.equal(Model.matchesQuery(ac, "climate.living"), true)
    assert.equal(Model.matchesQuery(ac, "kitchen"), false)
    assert.equal(Model.matchesQuery(ac, "living kitchen"), false)
    assert.equal(Model.matchesQuery(ac, "   "), true)
    assert.equal(Model.matchesQuery(null, "x"), false)
  })
})

describe("visibleRows", () => {
  it("groups the entities under headers in a fixed order on the All tab", () => {
    const rows = Model.visibleRows(OK, "all", "")
    assert.deepEqual(rows.filter(Model.isHeader).map((h) => `${h.title} ${h.count}`), ["CLIMATE 2", "LIGHTS 3", "SWITCHES 2", "COVERS 1", "SCENES 2"])
    assert.equal(rows.length, 15)
    assert.equal(rows[1], ac)
    assert.equal(rows[rows.length - 1], goodnight)
    assert.deepEqual(Model.visibleRows(OK), rows)
  })

  it("shows one group without a header on its own tab", () => {
    assert.deepEqual(Model.visibleRows(OK, "lights", ""), [kitchen, bedroom, porch])
    assert.deepEqual(Model.visibleRows(OK, "scenes", ""), [movie, goodnight])
    assert.equal(Model.visibleRows(OK, "vacuums", "").length, 15)
  })

  it("filters across groups and keeps the headers honest", () => {
    const rows = Model.visibleRows(OK, "all", "office")
    assert.deepEqual(rows.map((r) => r.header ? r.title + " " + r.count : r.id), ["CLIMATE 1", "climate.office", "SWITCHES 1", "fan.office"])
    assert.deepEqual(Model.visibleRows(OK, "lights", "office"), [])
  })

  it("stops at the row limit and says how many are behind it", () => {
    const rows = Model.visibleRows(BIG, "all", "")
    const more = rows[rows.length - 1]
    assert.equal(Model.isMore(more), true)
    assert.equal(more.hidden, 11)
    assert.equal(rows.filter((r) => !Model.isPassive(r)).length, Model.ROW_LIMIT)
    // The limit is per view, so a smaller one and a filter both lift it.
    assert.equal(Model.visibleRows(BIG, "switches", "", 10).filter(Model.isMore)[0].hidden, 60)
    assert.equal(Model.visibleRows(BIG, "switches", "plug_6").filter(Model.isMore).length, 0)
    assert.equal(Model.visibleRows(BIG, "switches", "plug_6").length, 11)
  })

  it("is empty without entities", () => {
    assert.deepEqual(Model.visibleRows(EMPTY), [])
    assert.deepEqual(Model.visibleRows(null), [])
  })
})

describe("isHeader", () => {
  it("only marks header rows", () => {
    assert.equal(Model.isHeader({ header: true }), true)
    assert.equal(Model.isHeader(kitchen), false)
    assert.equal(Model.isHeader(null), false)
  })
})

describe("isMore", () => {
  it("only marks the overflow row", () => {
    assert.equal(Model.isMore({ more: true, hidden: 3 }), true)
    assert.equal(Model.isMore({ header: true }), false)
    assert.equal(Model.isMore(null), false)
  })
})

describe("isPassive", () => {
  it("covers headers and the overflow row", () => {
    assert.equal(Model.isPassive({ header: true }), true)
    assert.equal(Model.isPassive({ more: true }), true)
    assert.equal(Model.isPassive(kitchen), false)
  })
})

describe("nextRowIndex", () => {
  it("walks over headers and the overflow row and wraps", () => {
    const rows = Model.visibleRows(OK)
    assert.equal(Model.nextRowIndex(rows, 0, 1), 1)
    assert.equal(Model.nextRowIndex(rows, 2, 1), 4)
    assert.equal(Model.nextRowIndex(rows, 1, -1), rows.length - 1)
    const big = Model.visibleRows(BIG)
    assert.equal(Model.nextRowIndex(big, big.length - 2, 1), 1)
    assert.equal(Model.nextRowIndex([], 0, 1), -1)
    assert.equal(Model.nextRowIndex([{ header: true }, { more: true }], 0, 1), -1)
  })
})

describe("firstRowIndex", () => {
  it("is the first non-header row", () => {
    assert.equal(Model.firstRowIndex(Model.visibleRows(OK)), 1)
    assert.equal(Model.firstRowIndex([]), -1)
  })
})

describe("home.sh", () => {
  // The stand-in server: Home Assistant's login flow, bearer-checked REST
  // calls, and services that change the states it serves.
  const server = { calls: [], states: null, tokens: new Set(), password: "good", nextToken: 1, flows: new Set() }
  let base = ""

  function respond(res, status, body) {
    res.writeHead(status, { "Content-Type": "application/json" })
    res.end(JSON.stringify(body))
  }

  function findState(id) {
    return server.states.find((s) => s.entity_id === id)
  }

  before(async () => {
    const instance = http.createServer((req, res) => {
      let raw = ""
      req.on("data", (chunk) => { raw += chunk })
      req.on("end", () => {
        const url = new URL(req.url, "http://localhost")
        server.calls.push({ method: req.method, path: url.pathname, body: raw, auth: req.headers.authorization || "" })
        if (req.method === "POST" && url.pathname === "/auth/login_flow") {
          const body = JSON.parse(raw)
          if (!body.client_id || !body.redirect_uri || !Array.isArray(body.handler)) return respond(res, 400, { message: "bad flow" })
          server.flows.add("flow-1")
          return respond(res, 200, { type: "form", flow_id: "flow-1", step_id: "init" })
        }
        if (req.method === "POST" && url.pathname === "/auth/login_flow/flow-1") {
          const body = JSON.parse(raw)
          if (body.username === "mfa") return respond(res, 200, { type: "form", step_id: "mfa", flow_id: "flow-1" })
          if (body.password !== server.password) return respond(res, 200, { type: "form", step_id: "init", flow_id: "flow-1", errors: { base: "invalid_auth" } })
          return respond(res, 200, { type: "create_entry", result: "code-1", flow_id: "flow-1" })
        }
        if (req.method === "POST" && url.pathname === "/auth/token") {
          const form = new URLSearchParams(raw)
          if (form.get("grant_type") === "authorization_code" && form.get("code") === "code-1") {
            const token = `acc-${server.nextToken++}`
            server.tokens.add(token)
            return respond(res, 200, { access_token: token, refresh_token: "ref-1", expires_in: 1800, token_type: "Bearer" })
          }
          if (form.get("grant_type") === "refresh_token" && form.get("refresh_token") === "ref-1" && !server.refreshRevoked) {
            const token = `acc-${server.nextToken++}`
            server.tokens.add(token)
            return respond(res, 200, { access_token: token, expires_in: 1800, token_type: "Bearer" })
          }
          return respond(res, 400, { error: "invalid_grant" })
        }
        const bearer = (req.headers.authorization || "").replace(/^Bearer /, "")
        if (!server.tokens.has(bearer) && bearer !== "long-lived") return respond(res, 401, { message: "Unauthorized" })
        if (req.method === "GET" && url.pathname === "/api/states") return respond(res, 200, server.states)
        const service = /^\/api\/services\/(\w+)\/(\w+)$/.exec(url.pathname)
        if (req.method === "POST" && service) {
          const [, domain, name] = service
          const body = JSON.parse(raw)
          const target = findState(body.entity_id)
          if (!target) return respond(res, 400, { message: `Entity ${body.entity_id} not found` })
          if (name === "toggle") target.state = target.state === "on" ? "off" : (target.state === "open" ? "closed" : (target.state === "closed" ? "open" : "on"))
          else if (name === "turn_on") { target.state = "on"; if (body.brightness_pct !== undefined) target.attributes.brightness = Math.round(body.brightness_pct * 2.55) }
          else if (name === "turn_off") target.state = "off"
          else if (name === "open_cover") target.state = "open"
          else if (name === "close_cover") target.state = "closed"
          else if (name === "set_temperature") target.attributes.temperature = body.temperature
          else if (name === "set_hvac_mode") target.state = body.hvac_mode
          else return respond(res, 400, { message: `Unknown service ${domain}.${name}` })
          return respond(res, 200, [])
        }
        return respond(res, 404, { message: "Not found" })
      })
    })
    await new Promise((resolve) => instance.listen(0, "127.0.0.1", resolve))
    base = `http://127.0.0.1:${instance.address().port}`
    server.instance = instance
  })

  after(() => new Promise((resolve) => server.instance.close(resolve)))

  // A fresh state table, credentials file and cache directory for one test.
  function setup(t, { env: lines = null, signedIn = true, tokenFile = null } = {}) {
    server.states = JSON.parse(fixture("hass-states.json"))
    server.calls = []
    server.refreshRevoked = false
    const dir = tmpdir(t)
    const envFile = path.join(dir, "home.env")
    const cacheHome = path.join(dir, "cache")
    fs.writeFileSync(envFile, (lines || [`HOME_ASSISTANT_URL=${base}/`, "HOME_ASSISTANT_USERNAME=joao"]).join("\n") + "\n")
    const cacheDir = path.join(cacheHome, "omarchy", "home")
    fs.mkdirSync(cacheDir, { recursive: true })
    if (signedIn) {
      server.tokens.add("acc-0")
      fs.writeFileSync(path.join(cacheDir, "tokens.json"), JSON.stringify(tokenFile || { access_token: "acc-0", refresh_token: "ref-1", expires_at: Math.floor(Date.now() / 1000) + 3600 }))
    }
    const env = (extra = {}) => ({ HOME_ASSISTANT_ENV: envFile, XDG_CACHE_HOME: cacheHome, ...extra })
    const run = (args, extra) => runJsonAsync("joamag.home", "home.sh", args, { env: env(extra) })
    return { run, envFile, cacheDir, env }
  }

  it("reports what is missing when there is no credentials file", async (t) => {
    const { run, envFile } = setup(t, { signedIn: false })
    fs.rmSync(envFile)
    const [result] = (await run(["snapshot"])).json
    assert.equal(result.state, "unconfigured")
    assert.deepEqual(result.missing, ["HOME_ASSISTANT_URL", "sign-in"])
  })

  it("signs in through the login flow and keeps only the refresh token", async (t) => {
    const { run, envFile, cacheDir } = setup(t, { signedIn: false })
    fs.rmSync(envFile)
    const [result] = (await run(["configure"], { HOME_ASSISTANT_SET_URL: `${base}/`, HOME_ASSISTANT_SET_USERNAME: "joao", HOME_ASSISTANT_SET_PASSWORD: "good" })).json
    assert.equal(result.state, "ok")
    assert.equal(result.entities.length, 6)
    const written = fs.readFileSync(envFile, "utf8")
    assert.equal(written, `HOME_ASSISTANT_URL=${base}\nHOME_ASSISTANT_USERNAME=joao\n`)
    assert.ok(!written.includes("good"), "the password must never reach the file")
    const tokens = JSON.parse(fs.readFileSync(path.join(cacheDir, "tokens.json"), "utf8"))
    assert.equal(tokens.refresh_token, "ref-1")
    assert.match(tokens.access_token, /^acc-\d+$/)
    assert.ok(tokens.expires_at > Date.now() / 1000)
    assert.equal((fs.statSync(path.join(cacheDir, "tokens.json")).mode & 0o777), 0o600)
    assert.equal((fs.statSync(envFile).mode & 0o777), 0o600)
    const flow = server.calls.filter((c) => c.path.startsWith("/auth/")).map((c) => c.path)
    assert.deepEqual(flow, ["/auth/login_flow", "/auth/login_flow/flow-1", "/auth/token"])
  })

  it("leaves a working setup alone when the sign-in is rejected", async (t) => {
    const { run, envFile } = setup(t)
    const before = fs.readFileSync(envFile, "utf8")
    const [result] = (await run(["configure"], { HOME_ASSISTANT_SET_URL: base, HOME_ASSISTANT_SET_USERNAME: "joao", HOME_ASSISTANT_SET_PASSWORD: "wrong" })).json
    assert.equal(result.state, "unauthorized")
    assert.match(result.error, /rejected/)
    assert.equal(result.username, "joao")
    assert.equal(fs.readFileSync(envFile, "utf8"), before)
  })

  it("points an account with two-factor authentication at a long-lived token", async (t) => {
    const { run } = setup(t, { signedIn: false })
    const [result] = (await run(["configure"], { HOME_ASSISTANT_SET_URL: base, HOME_ASSISTANT_SET_USERNAME: "mfa", HOME_ASSISTANT_SET_PASSWORD: "good" })).json
    assert.equal(result.state, "unauthorized")
    assert.match(result.error, /two-factor/)
    assert.match(result.error, /HOME_ASSISTANT_TOKEN/)
  })

  it("reports an address that does not answer at sign-in", async (t) => {
    const { run } = setup(t, { signedIn: false })
    const [result] = (await run(["configure"], { HOME_ASSISTANT_SET_URL: "http://127.0.0.1:1", HOME_ASSISTANT_SET_USERNAME: "joao", HOME_ASSISTANT_SET_PASSWORD: "good" })).json
    assert.equal(result.state, "unreachable")
    assert.equal(result.url, "http://127.0.0.1:1")
  })

  it("refuses an incomplete sign-in without touching the network", async (t) => {
    const { run } = setup(t, { signedIn: false })
    const [result] = (await run(["configure"], { HOME_ASSISTANT_SET_URL: base, HOME_ASSISTANT_SET_USERNAME: "joao" })).json
    assert.equal(result.state, "error")
    assert.deepEqual(server.calls, [])
  })

  it("picks every climate, light and switch when no entities are listed", async (t) => {
    const { run } = setup(t)
    const [result] = (await run(["snapshot"])).json
    assert.equal(result.state, "ok")
    assert.equal(result.url, base)
    assert.ok(result.fetchedAt > 0)
    assert.deepEqual(result.entities.map((e) => e.id), ["climate.living_room", "climate.office", "light.bedroom", "light.kitchen", "light.porch", "switch.coffee"])
    const ac = result.entities[0]
    assert.equal(ac.name, "Living room AC")
    assert.equal(ac.temperature, 22)
    assert.equal(ac.current, 24.5)
    assert.equal(ac.step, 0.5)
    assert.deepEqual(ac.modes, ["off", "cool", "heat", "heat_cool", "fan_only"])
    assert.equal(ac.action, "cooling")
    assert.equal(result.entities[3].brightness, 204)
  })

  it("keeps the order of an explicit entity list and skips unknown ids", async (t) => {
    const { run } = setup(t)
    const [result] = (await run(["snapshot", "scene.movie_night, light.kitchen,climate.office,light.nope"])).json
    assert.deepEqual(result.entities.map((e) => e.id), ["scene.movie_night", "light.kitchen", "climate.office"])
  })

  it("toggles a light and answers with the refreshed list", async (t) => {
    const { run } = setup(t)
    const [result] = (await run(["toggle", "light.kitchen"], { HOME_ENTITIES: "light.kitchen" })).json
    assert.equal(result.state, "ok")
    assert.equal(result.entities[0].state, "off")
    const call = server.calls.find((c) => c.path === "/api/services/light/toggle")
    assert.deepEqual(JSON.parse(call.body), { entity_id: "light.kitchen" })
  })

  it("opens and closes covers instead of turning them on and off", async (t) => {
    const { run } = setup(t)
    assert.equal((await run(["turn_on", "cover.garage"], { HOME_ENTITIES: "cover.garage" })).json[0].entities[0].state, "open")
    assert.equal((await run(["turn_off", "cover.garage"], { HOME_ENTITIES: "cover.garage" })).json[0].entities[0].state, "closed")
    assert.deepEqual(server.calls.filter((c) => c.path.startsWith("/api/services/")).map((c) => c.path), ["/api/services/cover/open_cover", "/api/services/cover/close_cover"])
  })

  it("dims a light by percent and turns it off at zero", async (t) => {
    const { run } = setup(t)
    const [dimmed] = (await run(["brightness", "light.kitchen", "40"], { HOME_ENTITIES: "light.kitchen" })).json
    assert.equal(dimmed.entities[0].brightness, 102)
    assert.deepEqual(JSON.parse(server.calls.find((c) => c.path === "/api/services/light/turn_on").body), { entity_id: "light.kitchen", brightness_pct: 40 })
    const [off] = (await run(["brightness", "light.kitchen", "0"], { HOME_ENTITIES: "light.kitchen" })).json
    assert.equal(off.entities[0].state, "off")
    const [capped] = (await run(["brightness", "light.kitchen", "250"], { HOME_ENTITIES: "light.kitchen" })).json
    assert.equal(capped.entities[0].brightness, 255)
    assert.equal((await run(["brightness", "light.kitchen", "dim"])).json[0].state, "error")
  })

  it("sets a thermostat's target and mode", async (t) => {
    const { run } = setup(t)
    const [warmer] = (await run(["climate", "climate.living_room", "temperature", "23.5"], { HOME_ENTITIES: "climate.living_room" })).json
    assert.equal(warmer.entities[0].temperature, 23.5)
    const [heating] = (await run(["climate", "climate.living_room", "mode", "heat"], { HOME_ENTITIES: "climate.living_room" })).json
    assert.equal(heating.entities[0].state, "heat")
    assert.equal((await run(["climate", "climate.living_room", "temperature", "hot"])).json[0].state, "error")
    assert.equal((await run(["climate", "climate.living_room", "mode"])).json[0].state, "error")
    assert.equal((await run(["climate", "climate.living_room", "colour", "red"])).json[0].state, "error")
  })

  it("activates scenes and scripts through turn_on", async (t) => {
    const { run } = setup(t)
    assert.equal((await run(["activate", "scene.movie_night"])).json[0].state, "ok")
    assert.equal((await run(["activate", "script.goodnight"])).json[0].state, "ok")
    assert.deepEqual(server.calls.filter((c) => c.path.startsWith("/api/services/")).map((c) => c.path), ["/api/services/scene/turn_on", "/api/services/script/turn_on"])
  })

  it("surfaces a service that fails as an error", async (t) => {
    const { run } = setup(t)
    const [result] = (await run(["toggle", "light.nope"])).json
    assert.equal(result.state, "error")
    assert.match(result.error, /HTTP 400: Entity light.nope not found/)
  })

  it("mints a new access token when the saved one has expired", async (t) => {
    const { run, cacheDir } = setup(t, { tokenFile: { access_token: "acc-stale", refresh_token: "ref-1", expires_at: 1 } })
    const [result] = (await run(["snapshot"])).json
    assert.equal(result.state, "ok")
    assert.equal(server.calls[0].path, "/auth/token")
    assert.match(server.calls[0].body, /grant_type=refresh_token/)
    const tokens = JSON.parse(fs.readFileSync(path.join(cacheDir, "tokens.json"), "utf8"))
    assert.match(tokens.access_token, /^acc-\d+$/)
    assert.equal(tokens.refresh_token, "ref-1")
  })

  it("refreshes once and retries when Home Assistant rejects the access token early", async (t) => {
    const { run } = setup(t, { tokenFile: { access_token: "acc-revoked", refresh_token: "ref-1", expires_at: Math.floor(Date.now() / 1000) + 3600 } })
    const [result] = (await run(["snapshot"])).json
    assert.equal(result.state, "ok")
    assert.deepEqual(server.calls.map((c) => c.path), ["/api/states", "/auth/token", "/api/states"])
  })

  it("asks to sign in again when the refresh token is gone too", async (t) => {
    const { run } = setup(t, { tokenFile: { access_token: "acc-revoked", refresh_token: "ref-1", expires_at: Math.floor(Date.now() / 1000) + 3600 } })
    server.refreshRevoked = true
    const [result] = (await run(["snapshot"])).json
    assert.equal(result.state, "unauthorized")
    assert.equal(result.username, "joao")
  })

  it("uses a long-lived token from the file without any login flow", async (t) => {
    const { run } = setup(t, { signedIn: false, env: [`HOME_ASSISTANT_URL=${base}`, 'HOME_ASSISTANT_TOKEN="long-lived"'] })
    const [result] = (await run(["snapshot"])).json
    assert.equal(result.state, "ok")
    assert.equal(server.calls[0].auth, "Bearer long-lived")
    assert.ok(server.calls.every((c) => !c.path.startsWith("/auth/")))
  })

  it("shows the last fetched state when Home Assistant is unreachable", async (t) => {
    const { run, envFile } = setup(t)
    await run(["snapshot"])
    fs.writeFileSync(envFile, "HOME_ASSISTANT_URL=http://127.0.0.1:1\nHOME_ASSISTANT_USERNAME=joao\n")
    const [result] = (await run(["snapshot", "light.kitchen"])).json
    assert.equal(result.state, "unreachable")
    assert.deepEqual(result.entities.map((e) => e.id), ["light.kitchen"])
    assert.ok(result.error.length > 0)
  })

  it("reports unreachable with nothing when there is no cache yet", async (t) => {
    const { run } = setup(t, { env: ["HOME_ASSISTANT_URL=http://127.0.0.1:1", "HOME_ASSISTANT_USERNAME=joao"] })
    const [result] = (await run(["snapshot"])).json
    assert.equal(result.state, "unreachable")
    assert.deepEqual(result.entities, [])
  })

  it("lists every controllable entity for picking", async (t) => {
    const { run } = setup(t)
    const [result] = (await run(["discover"])).json
    assert.equal(result.state, "ok")
    assert.deepEqual(result.entities.map((e) => e.id), ["climate.living_room", "climate.office", "cover.garage", "fan.office", "light.attic", "light.bedroom", "light.kitchen", "light.porch", "scene.movie_night", "script.goodnight", "switch.coffee"])
    assert.deepEqual(result.entities[0], { id: "climate.living_room", name: "Living room AC", state: "cool" })
  })

  it("parses the credentials file strictly", async (t) => {
    const { run } = setup(t, { signedIn: false, env: ["# comment", `HOME_ASSISTANT_URL = '${base}/'`, "HOME_ASSISTANT_TOKEN=long-lived # not a comment", "export HOME_ASSISTANT_USERNAME=ignored", "rm -rf /"] })
    const [result] = (await run(["snapshot"])).json
    // The trailing comment is part of the value, so the token is wrong and
    // Home Assistant refuses it; the shell never ran anything.
    assert.equal(result.state, "unauthorized")
    assert.equal(server.calls[0].auth, "Bearer long-lived # not a comment")
  })

  it("rejects a bad invocation", async (t) => {
    const { env } = setup(t)
    const result = await runScriptAsync("joamag.home", "home.sh", ["bogus"], { env: env() })
    assert.equal(result.status, 1)
    assert.match(result.stderr, /Usage: home.sh/)
  })
})
