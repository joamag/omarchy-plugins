.pragma library

// Pure helpers for the peripherals widget: snapshot parsing, the device with
// the least charge (which is the one the bar shows), per-device glyphs and
// the strings the bar label, tooltip and popup share.

var ICON = "󰂯"

// Nerd Font glyphs per upower device type; anything else gets the bluetooth
// mark, which is what most of these are.
var TYPE_ICONS = {
  mouse: "󰍽",
  keyboard: "󰌌",
  headset: "󰋎",
  headphones: "󰋋",
  speakers: "󰓃",
  "gaming-input": "󰊗",
  phone: "󰄜",
  pen: "󰏫"
}

// The same ten-step battery glyphs the first-party power panel draws.
var BATTERY_ICONS = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
var CHARGING_ICONS = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
var UNKNOWN_ICON = "󰂑"

// Coarse devices report a level word instead of a percentage; this is the
// charge each word stands for whenever a glyph or a sort order needs a number.
var LEVEL_PERCENT = { full: 100, high: 75, normal: 50, low: 20, critical: 5 }

function num(value) {
  // Number(null) is 0; a device that reports no charge must stay unknown
  // rather than read as flat.
  if (value === null || value === undefined || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

// peripherals.sh emits "solaar<TAB>0|1" and one "device<TAB>path<TAB>type
// <TAB>model<TAB>state<TAB>pct<TAB>level<TAB>minutes" line per device.
function parseSnapshot(raw) {
  var out = { solaar: false, devices: [] }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var parts = line.split("\t")
    if (parts[0] === "solaar") {
      out.solaar = parts[1] === "1"
    } else if (parts[0] === "device") {
      if (parts.length < 8) continue
      out.devices.push({
        key: parts[1],
        path: parts[1],
        type: parts[2] || "unknown",
        model: parts[3],
        state: parts[4],
        pct: num(parts[5]),
        level: parts[6],
        minutes: num(parts[7])
      })
    }
  }
  out.devices.sort(compareDevices)
  return out
}

// Least charge first, unknown charge last, then alphabetical, so the device
// that needs attention is on top and the list is stable across refreshes.
function compareDevices(a, b) {
  var pa = chargePercent(a)
  var pb = chargePercent(b)
  var ka = isFinite(pa) ? pa : 101
  var kb = isFinite(pb) ? pb : 101
  if (ka !== kb) return ka - kb
  var na = deviceName(a)
  var nb = deviceName(b)
  return na < nb ? -1 : (na > nb ? 1 : 0)
}

// The model when upower knows it, otherwise the tail of the device path
// ("hidpp_battery_0").
function deviceName(device) {
  if (!device) return ""
  if (device.model) return String(device.model)
  var segments = String(device.path || "").split("/")
  return segments[segments.length - 1] || String(device.path || "")
}

function typeLabel(device) {
  return String(device && device.type || "unknown").replace(/-/g, " ")
}

function isCharging(device) {
  return !!device && (device.state === "charging" || device.state === "pending-charge")
}

// A coarse device carries one of the level words; a fine one carries "none"
// or nothing at all in that field.
function isCoarse(device) {
  return !!device && LEVEL_PERCENT[String(device.level)] !== undefined
}

// The charge as a number: the percentage for a fine device, the level's stand
// in for a coarse one, NaN when the device has not said.
function chargePercent(device) {
  if (!device) return NaN
  if (isCoarse(device)) return LEVEL_PERCENT[device.level]
  return num(device.pct)
}

function batteryGlyph(percent, charging) {
  var n = num(percent)
  if (!isFinite(n)) return UNKNOWN_ICON
  var index = Math.max(0, Math.min(9, Math.round(n / 10) - 1))
  return (charging ? CHARGING_ICONS : BATTERY_ICONS)[index]
}

function typeIcon(device) {
  var icon = device ? TYPE_ICONS[device.type] : ""
  return icon || ICON
}

function lowestDevice(snapshot) {
  if (!snapshot || snapshot.devices.length === 0) return null
  return snapshot.devices[0]
}

// Devices at or below the warning threshold that are not being charged: a
// mouse on its cable is being dealt with already.
function lowDevices(snapshot, warnPct) {
  if (!snapshot) return []
  var limit = num(warnPct)
  if (!isFinite(limit)) limit = 20
  var out = []
  for (var i = 0; i < snapshot.devices.length; i++) {
    var d = snapshot.devices[i]
    var pct = chargePercent(d)
    if (isFinite(pct) && pct <= limit && !isCharging(d)) out.push(d)
  }
  return out
}

function chargingCount(snapshot) {
  if (!snapshot) return 0
  var n = 0
  for (var i = 0; i < snapshot.devices.length; i++) if (isCharging(snapshot.devices[i])) n++
  return n
}

function formatPercent(value) {
  var n = num(value)
  return isFinite(n) && n >= 0 ? Math.round(n) + "%" : "—"
}

function formatMinutes(minutes) {
  var n = Math.max(0, Math.round(num(minutes) || 0))
  if (n < 60) return n + "m"
  var h = Math.floor(n / 60)
  var m = n % 60
  return m === 0 ? h + "h" : h + "h " + m + "m"
}

// What the device says about its charge, in its own terms: "Full" for a
// coarse device, "82%" for a fine one.
function levelLabel(device) {
  if (!device) return "—"
  if (isCoarse(device)) {
    var level = String(device.level)
    return level.charAt(0).toUpperCase() + level.slice(1)
  }
  return formatPercent(device.pct)
}

function stateLabel(device) {
  switch (device ? String(device.state) : "") {
  case "charging": return "charging"
  case "discharging": return "discharging"
  case "fully-charged": return "fully charged"
  case "pending-charge": return "waiting to charge"
  case "pending-discharge": return "waiting to discharge"
  case "empty": return "empty"
  default: return ""
  }
}

function deviceDetail(device) {
  if (!device) return ""
  var parts = [typeLabel(device)]
  var state = stateLabel(device)
  if (state) parts.push(state)
  if (isFinite(device.minutes) && device.minutes > 0) parts.push(formatMinutes(device.minutes) + (isCharging(device) ? " to full" : " left"))
  return parts.join(" · ")
}

// Text on the bar button: the glyph of the emptiest device, plus its level
// when wanted and the bar is horizontal.
function barText(snapshot, showLevel, vertical) {
  var lowest = lowestDevice(snapshot)
  if (!lowest) return ICON
  var glyph = batteryGlyph(chargePercent(lowest), isCharging(lowest))
  if (!showLevel || vertical) return glyph
  return glyph + " " + levelLabel(lowest)
}

function tooltip(snapshot, warnPct) {
  if (!snapshot) return "Peripherals"
  if (snapshot.devices.length === 0) return "Peripherals · no wireless devices"
  var parts = []
  for (var i = 0; i < snapshot.devices.length; i++) {
    var d = snapshot.devices[i]
    parts.push(deviceName(d) + " " + levelLabel(d) + (isCharging(d) ? " charging" : ""))
  }
  var low = lowDevices(snapshot, warnPct)
  if (low.length > 0) parts.push(low.length + " low")
  return "Peripherals · " + parts.join(" · ")
}

function heroStatus(snapshot, warnPct) {
  if (!snapshot) return "SCANNING"
  var n = snapshot.devices.length
  if (n === 0) return "NO WIRELESS DEVICES"
  var parts = [n + (n === 1 ? " DEVICE" : " DEVICES")]
  var low = lowDevices(snapshot, warnPct).length
  if (low > 0) parts.push(low + " LOW")
  var charging = chargingCount(snapshot)
  if (charging > 0) parts.push(charging + " CHARGING")
  return parts.join(" · ")
}
