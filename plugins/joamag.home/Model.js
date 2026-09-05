.pragma library

// Pure helpers for the Home Assistant widget: envelope parsing, what each
// entity is and can do, climate maths, and the strings the bar label, tooltip
// and popup share.

var ICON = "󰋜"

var DOMAIN_ICONS = {
  climate: "󰔏",
  light: "󰌵",
  switch: "󰔡",
  input_boolean: "󰔡",
  fan: "󰈐",
  cover: "󰖝",
  scene: "󰐊",
  script: "󰐊"
}

// Home Assistant's hvac modes, as the popup names and draws them.
var MODE_LABELS = { off: "Off", cool: "Cool", heat: "Heat", heat_cool: "Auto", auto: "Auto", dry: "Dry", fan_only: "Fan" }
var MODE_ICONS = { off: "󰐥", cool: "󰜗", heat: "󰈸", heat_cool: "󰔏", auto: "󰔏", dry: "󰔏", fan_only: "󰈐" }

var DEFAULT_MIN_TEMP = 7
var DEFAULT_MAX_TEMP = 35

function num(value) {
  // Number(null) is 0; a reading the entity does not have must stay unknown.
  if (value === null || value === undefined || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

function parseResult(raw) {
  try {
    var obj = JSON.parse(String(raw || "").trim())
    if (obj && typeof obj === "object" && obj.state) return obj
  } catch (e) {
    // fall through
  }
  return { state: "error", error: "Home Assistant returned no data" }
}

function hasEntities(result) {
  return !!result && Array.isArray(result.entities)
}

function isOk(result) {
  return !!result && result.state === "ok" && hasEntities(result)
}

// Whether the popup should show the sign-in form instead of the entities.
function needsCredentials(result) {
  return !!result && (result.state === "unconfigured" || result.state === "unauthorized")
}

// Values the sign-in form starts from: whatever the script already knows.
function prefill(result, fallbackUrl) {
  return {
    url: result && result.url ? String(result.url) : String(fallbackUrl || ""),
    username: result && result.username ? String(result.username) : ""
  }
}

function entities(result) {
  return hasEntities(result) ? result.entities : []
}

function domainOf(id) {
  var s = String(id || "")
  var dot = s.indexOf(".")
  return dot > 0 ? s.slice(0, dot) : ""
}

function entityName(entity) {
  if (!entity) return ""
  return String(entity.name || entity.id || "")
}

function isClimate(entity) {
  return !!entity && entity.domain === "climate"
}

function isAvailable(entity) {
  if (!entity) return false
  var state = String(entity.state || "")
  return state !== "" && state !== "unavailable" && state !== "unknown"
}

// "On" in the sense a row shows: a light lit, a cover open, a climate in any
// mode but off.
function isOn(entity) {
  if (!isAvailable(entity)) return false
  var state = String(entity.state)
  if (isClimate(entity)) return state !== "off"
  if (entity.domain === "cover") return state === "open" || state === "opening"
  return state === "on"
}

// The popup's sections, in the order they stack.
function groupOf(entity) {
  switch (entity ? String(entity.domain) : "") {
  case "climate": return "climate"
  case "light": return "lights"
  case "cover": return "covers"
  case "scene":
  case "script": return "scenes"
  default: return "switches"
  }
}

// What Enter or a click does on the row.
function rowAction(entity) {
  if (!entity) return ""
  if (isClimate(entity)) return "climate"
  if (entity.domain === "scene" || entity.domain === "script") return "activate"
  return "toggle"
}

function typeIcon(entity) {
  if (!entity) return ICON
  if (isClimate(entity)) return modeIcon(entity.state)
  return DOMAIN_ICONS[entity.domain] || ICON
}

function modeLabel(mode) {
  var key = String(mode || "")
  return MODE_LABELS[key] || (key ? key.charAt(0).toUpperCase() + key.slice(1) : "—")
}

function modeIcon(mode) {
  return MODE_ICONS[String(mode || "")] || DOMAIN_ICONS.climate
}

// The modes the thermostat offers, off always among them so it can be shut.
// A list that has crossed a Repeater's modelData comes back as a QVariantList,
// which Array.isArray rejects, so anything with a length is read as a list.
function climateModes(entity) {
  var raw = entity ? entity.modes : null
  var list = []
  if (raw && typeof raw !== "string" && typeof raw.length === "number") for (var i = 0; i < raw.length; i++) list.push(String(raw[i]))
  if (list.indexOf("off") < 0) list = ["off"].concat(list)
  return list
}

function nextMode(entity, delta) {
  var modes = climateModes(entity)
  var idx = modes.indexOf(String(entity && entity.state))
  if (idx < 0) idx = 0
  var n = modes.length
  return modes[((idx + delta) % n + n) % n]
}

function climateStep(entity) {
  var step = num(entity ? entity.step : NaN)
  return isFinite(step) && step > 0 ? step : 1
}

// What one press of - or + moves the target by. Some thermostats report a
// 0.1 degree grid, which is a precision, not a step anyone wants to click
// through, so the buttons move at least half a degree and the result is
// still snapped to the device's own grid.
function climateUiStep(entity) {
  return Math.max(0.5, climateStep(entity))
}

// A target inside the thermostat's range, snapped to its step, rounded so
// 21.499999 does not reach the API.
function clampTemperature(entity, value) {
  var n = num(value)
  if (!isFinite(n)) return NaN
  var lo = num(entity ? entity.min : NaN)
  var hi = num(entity ? entity.max : NaN)
  if (!isFinite(lo)) lo = DEFAULT_MIN_TEMP
  if (!isFinite(hi)) hi = DEFAULT_MAX_TEMP
  var step = climateStep(entity)
  var snapped = Math.round(n / step) * step
  return Math.round(Math.max(lo, Math.min(hi, snapped)) * 10) / 10
}

function formatTemp(value) {
  var n = num(value)
  if (!isFinite(n)) return "—"
  return (Math.round(n * 10) / 10) + "°"
}

// What the thermostat is doing right now, when it says.
function climateAction(entity) {
  switch (entity ? String(entity.action || "") : "") {
  case "cooling": return "cooling"
  case "heating": return "heating"
  case "drying": return "drying"
  case "fan": return "fan"
  case "idle": return "idle"
  default: return ""
  }
}

function climateDetail(entity) {
  if (!entity) return ""
  var parts = [modeLabel(entity.state)]
  var current = num(entity.current)
  if (isFinite(current)) parts.push(formatTemp(current) + " now")
  var action = climateAction(entity)
  if (action && isOn(entity)) parts.push(action)
  return parts.join(" · ")
}

// Brightness as a percentage: what the light reports when lit, zero when off,
// unknown for a light that cannot dim.
function brightnessPct(entity) {
  if (!entity || entity.domain !== "light") return NaN
  if (!isOn(entity)) return 0
  var raw = num(entity.brightness)
  return isFinite(raw) ? Math.round(raw / 255 * 100) : NaN
}

function canDim(entity) {
  return !!entity && entity.domain === "light" && isFinite(num(entity.brightness))
}

function entityDetail(entity) {
  if (!entity) return ""
  if (isClimate(entity)) return climateDetail(entity)
  if (!isAvailable(entity)) return "unavailable"
  switch (String(entity.domain)) {
  case "light": {
    var pct = brightnessPct(entity)
    return isOn(entity) ? (isFinite(pct) && pct > 0 ? "on · " + pct + "%" : "on") : "off"
  }
  case "cover": return String(entity.state)
  case "scene": return "scene"
  case "script": return String(entity.state) === "on" ? "running" : "script"
  default: return isOn(entity) ? "on" : "off"
  }
}

function lightsOn(result) {
  var list = entities(result)
  var n = 0
  for (var i = 0; i < list.length; i++) if (list[i].domain === "light" && isOn(list[i])) n++
  return n
}

function lightsTotal(result) {
  var list = entities(result)
  var n = 0
  for (var i = 0; i < list.length; i++) if (list[i].domain === "light") n++
  return n
}

// The thermostat the bar and hero talk about: the first one running, else
// the first one at all.
function activeClimate(result) {
  var list = entities(result)
  var first = null
  for (var i = 0; i < list.length; i++) {
    if (!isClimate(list[i])) continue
    if (isOn(list[i])) return list[i]
    if (!first) first = list[i]
  }
  return first
}

// Text on the bar button: lights lit, the running thermostat's target, both
// or the icon alone.
function barText(result, mode, vertical) {
  if (vertical || !isOk(result) || mode === "none") return ICON
  var parts = []
  var climate = activeClimate(result)
  if ((mode === "both" || mode === "lights") && lightsTotal(result) > 0) parts.push(String(lightsOn(result)))
  if ((mode === "both" || mode === "climate") && climate && isOn(climate)) parts.push(modeIcon(climate.state) + " " + formatTemp(climate.temperature))
  return parts.length > 0 ? ICON + " " + parts.join(" · ") : ICON
}

function tooltip(result) {
  if (!result) return "Home"
  switch (result.state) {
  case "unconfigured": return "Home Assistant: not signed in"
  case "unauthorized": return "Home Assistant: sign-in refused"
  case "unreachable": return "Home Assistant unreachable" + (entities(result).length > 0 ? " · showing last known state" : "")
  case "error": return "Home Assistant: " + (result.error || "request failed")
  }
  var parts = []
  if (lightsTotal(result) > 0) parts.push(lightsOn(result) + " of " + lightsTotal(result) + " lights on")
  var climate = activeClimate(result)
  if (climate) parts.push(entityName(climate) + " " + (isOn(climate) ? modeLabel(climate.state).toLowerCase() + " " + formatTemp(climate.temperature) : "off"))
  if (parts.length === 0) parts.push(entities(result).length + " entities")
  return "Home · " + parts.join(" · ")
}

function heroStatus(result) {
  if (!result) return "LOADING"
  if (!hasEntities(result) || entities(result).length === 0) return String(result.state === "ok" ? "NOTHING TO CONTROL" : result.state).toUpperCase()
  var parts = []
  if (lightsTotal(result) > 0) parts.push(lightsOn(result) + " OF " + lightsTotal(result) + " LIGHTS ON")
  var climate = activeClimate(result)
  if (climate) parts.push(isOn(climate) ? modeLabel(climate.state).toUpperCase() + " " + formatTemp(climate.temperature) : "CLIMATE OFF")
  if (result.state === "unreachable") parts.push("CACHED")
  return parts.join(" · ")
}

// The big number in the hero: the room temperature when there is a
// thermostat, otherwise how many lights are lit.
function heroValue(result) {
  if (!isOk(result) && !(result && result.state === "unreachable" && entities(result).length > 0)) return "—"
  var climate = activeClimate(result)
  if (climate && isFinite(num(climate.current))) return formatTemp(climate.current)
  if (climate && isFinite(num(climate.temperature))) return formatTemp(climate.temperature)
  return String(lightsOn(result))
}

function stateTitle(result) {
  switch (result ? result.state : "") {
  case "unconfigured": return "Home Assistant is not set up"
  case "unauthorized": return "Home Assistant refused the sign-in"
  case "unreachable": return "Home Assistant is unreachable"
  case "error": return "Home Assistant request failed"
  default: return "Loading Home Assistant"
  }
}

function stateDetail(result) {
  switch (result ? result.state : "") {
  case "unconfigured":
    return "Sign in below with the address of your Home Assistant and your usual account. Only a refresh token is kept; the password is used once and never stored."
  case "unauthorized": return result.error || "Sign in again below."
  case "unreachable": return (result.error || "No response") + (entities(result).length > 0 ? ". Showing the last state that was fetched." : "")
  case "error": return result.error || ""
  default: return ""
  }
}

var GROUPS = [
  { key: "climate", title: "CLIMATE", tab: "Climate" },
  { key: "lights", title: "LIGHTS", tab: "Lights" },
  { key: "switches", title: "SWITCHES", tab: "Switches" },
  { key: "covers", title: "COVERS", tab: "Covers" },
  { key: "scenes", title: "SCENES", tab: "Scenes" }
]

// A house can have hundreds of switches; past this many rows on one tab the
// list stops and says so, and the filter is the way in.
var ROW_LIMIT = 60

// The tabs above the list: one per group that has members, and "All" in
// front when there is more than one group to switch between.
function tabs(result) {
  var list = entities(result)
  var out = []
  for (var g = 0; g < GROUPS.length; g++) {
    var n = 0
    for (var i = 0; i < list.length; i++) if (groupOf(list[i]) === GROUPS[g].key) n++
    if (n > 0) out.push({ key: GROUPS[g].key, title: GROUPS[g].tab, count: n })
  }
  if (out.length > 1) out.unshift({ key: "all", title: "All", count: list.length })
  return out
}

// A tab that is no longer there (the entities changed) falls back to "all".
function normalizeTab(result, tab) {
  var list = tabs(result)
  for (var i = 0; i < list.length; i++) if (list[i].key === tab) return tab
  return "all"
}

function nextTab(result, current, delta) {
  var list = tabs(result)
  if (list.length === 0) return "all"
  var idx = -1
  for (var i = 0; i < list.length; i++) if (list[i].key === current) idx = i
  if (idx < 0) idx = 0
  var n = list.length
  return list[((idx + delta) % n + n) % n].key
}

// Case-insensitive match on the name or the id, every word of the query
// having to appear somewhere, so "bedroom radiant" finds the radiant
// thermostat of any bedroom.
function matchesQuery(entity, query) {
  var words = String(query || "").toLowerCase().split(/\s+/).filter(function(w) { return w !== "" })
  if (words.length === 0) return true
  var hay = (entityName(entity) + " " + String(entity && entity.id || "")).toLowerCase()
  for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false
  return true
}

// The popup list for one tab: the matching entities, under a header per
// group when the tab is "all", cut off at ROW_LIMIT with a row that says how
// many more there are. The keyboard cursor walks everything with one index.
function visibleRows(result, tab, query, limit) {
  var out = []
  var list = entities(result)
  var selected = normalizeTab(result, tab)
  var cap = isFinite(num(limit)) && num(limit) > 0 ? num(limit) : ROW_LIMIT
  var shown = 0
  var hidden = 0
  for (var g = 0; g < GROUPS.length; g++) {
    if (selected !== "all" && GROUPS[g].key !== selected) continue
    var members = []
    for (var i = 0; i < list.length; i++) {
      if (groupOf(list[i]) === GROUPS[g].key && matchesQuery(list[i], query)) members.push(list[i])
    }
    if (members.length === 0) continue
    if (selected === "all") out.push({ header: true, key: GROUPS[g].key, title: GROUPS[g].title, count: members.length })
    for (var j = 0; j < members.length; j++) {
      if (shown >= cap) { hidden++; continue }
      out.push(members[j])
      shown++
    }
  }
  if (hidden > 0) out.push({ more: true, key: "more", hidden: hidden })
  return out
}

function isHeader(row) {
  return !!row && row.header === true
}

function isMore(row) {
  return !!row && row.more === true
}

// Rows the cursor never lands on.
function isPassive(row) {
  return isHeader(row) || isMore(row)
}

function nextRowIndex(rows, current, delta) {
  if (!rows || rows.length === 0) return -1
  var n = rows.length
  var idx = current
  for (var step = 0; step < n; step++) {
    idx = ((idx + delta) % n + n) % n
    if (!isPassive(rows[idx])) return idx
  }
  return -1
}

function firstRowIndex(rows) {
  return nextRowIndex(rows, -1, 1)
}
