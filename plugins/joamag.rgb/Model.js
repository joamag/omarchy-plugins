.pragma library

// Pure helpers for the RGB widget: snapshot parsing, the mode each device is
// driven in and the effects it offers, colour, brightness and speed
// arithmetic, the state remembered for each device, and the strings the bar,
// tooltip and popup share.

var ICON = "󰏘"

// Glyph per OpenRGB device type, lowercased; anything else is a bulb.
var TYPE_ICONS = {
  "gpu": "󰢮",
  "led strip": "󱁑",
  "cooler": "󰈐",
  "keyboard": "󰌌",
  "mouse": "󰍽"
}

var DEFAULT_TYPE_ICON = "󰌵"

// The colours a click away in the popup, in the order 1-9 pick them; any
// other goes in the hex field.
var SWATCHES = [
  { label: "White", color: "FFFFFF" },
  { label: "Red", color: "FF0000" },
  { label: "Orange", color: "FF6000" },
  { label: "Yellow", color: "FFD000" },
  { label: "Green", color: "00FF00" },
  { label: "Cyan", color: "00FFFF" },
  { label: "Blue", color: "0000FF" },
  { label: "Purple", color: "8000FF" },
  { label: "Pink", color: "FF0080" }
]

// Modes that hold a whole device on one colour, best first. "Static" and
// "Fixed" are effects the controller keeps running by itself; "Direct" is
// OpenRGB writing every LED, which nearly every device it drives offers.
var SOLID_MODES = ["static", "fixed", "direct"]

var DEFAULT_COLOR = "FFFFFF"
var MIN_BRIGHTNESS = 5
var MAX_BRIGHTNESS = 100
var BRIGHTNESS_STEP = 5

// Effect speed as a percentage of the mode's own range, which OpenRGB maps
// onto it: 0-4 on an NZXT hub, 0-100 or 0-255 on others.
var DEFAULT_SPEED = 50
var SPEED_STEP = 5

function num(value) {
  // Number() makes 0 of null and a blank string and 1 of true; only a number
  // or the text of one counts, so a hand edit gone wrong falls back instead.
  if (typeof value === "string") value = value.trim()
  if ((typeof value !== "number" && typeof value !== "string") || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

// rgb.sh emits "state<TAB>value", optionally "error<TAB>message", then one
// "device<TAB>index<TAB>name<TAB>type<TAB>serial<TAB>modes" per device, each
// given the key its remembered state is stored under.
function parseSnapshot(raw) {
  var out = { state: "error", error: "", devices: [] }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var parts = line.split("\t")
    if (parts[0] === "device") {
      if (parts.length < 4 || !/^\d+$/.test(parts[1])) continue
      var modes = parseModes(parts.slice(5).join("\t"))
      out.devices.push({
        index: Number(parts[1]),
        key: "",
        name: parts[2] !== "" ? parts[2] : "Device " + parts[1],
        type: parts[3],
        serial: parts.length > 4 ? parts[4] : "",
        modes: modes.names,
        activeMode: modes.active
      })
    } else if (parts[0] === "state") {
      out.state = parts[1] || "error"
    } else if (parts[0] === "error") {
      out.error = parts.slice(1).join("\t")
    }
  }
  if (out.state === "error" && out.error === "") out.error = "OpenRGB returned no data"
  assignKeys(out.devices)
  return out
}

// The key each device's state is remembered under: its name, which a person
// can read and edit in shell.json. Two devices of the same model share a name,
// so those are told apart by their serial, which stays with the hardware
// whatever order it is detected in, or failing one (memory sticks report
// none, and are listed in the order of their fixed bus addresses) by their
// place among the ones without, "#2" for the second.
function assignKeys(devices) {
  var counts = {}
  var seen = {}
  var used = {}
  for (var i = 0; i < devices.length; i++) counts[devices[i].name] = (counts[devices[i].name] || 0) + 1
  for (var j = 0; j < devices.length; j++) {
    var device = devices[j]
    var key = device.name
    if (counts[device.name] > 1 && device.serial !== "") {
      key = device.name + " #" + device.serial
    } else {
      seen[device.name] = (seen[device.name] || 0) + 1
      if (seen[device.name] > 1) key = device.name + " #" + seen[device.name]
    }
    // A serial two devices share, or one that reads like a place, tells them
    // apart no better than nothing; the later one is numbered on from it.
    var base = key
    for (var n = 2; used[key]; n++) key = base + " #" + n
    used[key] = true
    device.key = key
  }
  return devices
}

// OpenRGB's mode list: names separated by spaces, one with a space in it in
// single quotes, the active one in square brackets ("[Direct] Fixed 'Cover
// Marquee'", or "['Super Rainbow']" while that one runs).
function parseModes(raw) {
  var out = { names: [], active: "" }
  var text = String(raw || "")
  var pattern = /(\[)?(?:'([^']*)'|([^\s'\[\]]+))(\])?/g
  var match
  while ((match = pattern.exec(text)) !== null) {
    var name = match[2] !== undefined ? match[2] : match[3]
    if (name === "") continue
    out.names.push(name)
    if (match[1] && match[4]) out.active = name
  }
  return out
}

// The device's own spelling of a mode, matched without regard to case the way
// OpenRGB matches it, or "" when the device has no such mode. A device that
// has crossed a Repeater's modelData carries its modes as a QVariantList,
// which Array.isArray rejects, so anything with a length is read as a list.
function findMode(device, wanted) {
  var modes = device ? device.modes : null
  if (!modes || typeof modes === "string" || typeof modes.length !== "number") return ""
  var key = String(wanted || "").toLowerCase()
  for (var i = 0; i < modes.length; i++) {
    if (String(modes[i]).toLowerCase() === key) return modes[i]
  }
  return ""
}

function solidMode(device) {
  for (var i = 0; i < SOLID_MODES.length; i++) {
    var mode = findMode(device, SOLID_MODES[i])
    if (mode !== "") return mode
  }
  return ""
}

function offMode(device) {
  return findMode(device, "off")
}

// Only a device with a single-colour mode can be set from here; the rest run
// whatever effect they were left in.
function isControllable(device) {
  return solidMode(device) !== ""
}

// The animations a device offers: every mode but Off and the single-colour
// ones, Direct among them, which is OpenRGB painting each LED rather than an
// effect of the controller's own. Empty for a device that cannot be set at all.
function effectModes(device) {
  if (solidMode(device) === "") return []
  var out = []
  var modes = device.modes
  for (var i = 0; i < modes.length; i++) {
    var name = String(modes[i])
    var key = name.toLowerCase()
    if (key === "off" || SOLID_MODES.indexOf(key) >= 0) continue
    out.push(name)
  }
  return out
}

// The effect a device is to run, in its own spelling, or "" for its solid
// colour; a remembered effect the device no longer offers counts as solid.
function activeEffect(device, state) {
  var wanted = state && state.effect ? String(state.effect).toLowerCase() : ""
  if (wanted === "") return ""
  var effects = effectModes(device)
  for (var i = 0; i < effects.length; i++) if (effects[i].toLowerCase() === wanted) return effects[i]
  return ""
}

// The effect `delta` steps away from the current one, solid colour first in
// the ring, so stepping past the last effect comes back to a plain colour.
function nextEffect(device, state, delta) {
  var ring = [""].concat(effectModes(device))
  var index = ring.indexOf(activeEffect(device, state))
  var n = ring.length
  return ring[((index + Math.round(num(delta) || 0)) % n + n) % n]
}

function effectLabel(effect) {
  return effect ? String(effect) : "Solid"
}

// A typed colour as OpenRGB takes it, six upper-case hex digits: "#ff8000",
// "ff8000" and the short "#f80" all read as "FF8000". "" for anything else.
function normalizeColor(text) {
  var s = String(text || "").trim().replace(/^#/, "")
  if (/^[0-9a-fA-F]{3}$/.test(s)) s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  if (!/^[0-9a-fA-F]{6}$/.test(s)) return ""
  return s.toUpperCase()
}

// Whole percent, never so low that a lit device reads as off; anything that is
// not a number is full brightness.
function clampBrightness(value) {
  var n = num(value)
  if (!isFinite(n)) return MAX_BRIGHTNESS
  return Math.max(MIN_BRIGHTNESS, Math.min(MAX_BRIGHTNESS, Math.round(n)))
}

// Whole percent of the effect's speed range; anything that is not a number is
// the middle of it.
function clampSpeed(value) {
  var n = num(value)
  if (!isFinite(n)) return DEFAULT_SPEED
  return Math.max(0, Math.min(100, Math.round(n)))
}

// The colour as the LEDs are asked to show it: every channel scaled by the
// brightness. Few solid modes carry a brightness of their own, so this is
// what intensity means on every device alike.
function scaleColor(color, brightness) {
  var hex = normalizeColor(color) || DEFAULT_COLOR
  var factor = clampBrightness(brightness) / MAX_BRIGHTNESS
  var out = ""
  for (var i = 0; i < 6; i += 2) {
    var channel = Math.round(parseInt(hex.slice(i, i + 2), 16) * factor)
    out += (channel < 16 ? "0" : "") + channel.toString(16)
  }
  return out.toUpperCase()
}

// Which swatch a colour is, or -1 when it was typed.
function swatchIndex(color) {
  var hex = normalizeColor(color)
  for (var i = 0; i < SWATCHES.length; i++) if (SWATCHES[i].color === hex) return i
  return -1
}

// The swatch's name, or the hex of a typed colour; "" for no colour at all.
function colorName(color) {
  var index = swatchIndex(color)
  if (index >= 0) return SWATCHES[index].label
  var hex = normalizeColor(color)
  return hex !== "" ? "#" + hex : ""
}

// What is remembered for a device, filled in: whether it is on, its colour at
// full brightness, the brightness, the effect it runs ("" for a solid colour)
// and that effect's speed. `known` is false for a device the widget has never
// set, whose real state OpenRGB cannot report back.
function lightState(lights, key) {
  var has = !!lights && typeof lights === "object" && Object.prototype.hasOwnProperty.call(lights, key)
  var entry = has ? lights[key] : null
  if (!entry || typeof entry !== "object") {
    return { known: false, on: true, color: DEFAULT_COLOR, brightness: MAX_BRIGHTNESS, effect: "", speed: DEFAULT_SPEED }
  }
  return {
    known: true,
    on: entry.on !== false && entry.on !== "false",
    color: normalizeColor(entry.color) || DEFAULT_COLOR,
    brightness: clampBrightness(entry.brightness),
    effect: typeof entry.effect === "string" ? entry.effect.trim() : "",
    speed: clampSpeed(entry.speed)
  }
}

// The remembered states with one device's changed, as a fresh object for
// shell.json; every other device is carried over as it was.
function setLight(lights, key, patch) {
  var out = {}
  if (lights && typeof lights === "object" && !Array.isArray(lights)) {
    for (var k in lights) if (Object.prototype.hasOwnProperty.call(lights, k)) out[k] = lights[k]
  }
  var current = lightState(lights, key)
  var change = patch || {}
  out[key] = {
    on: change.on !== undefined ? change.on === true : current.on,
    color: change.color !== undefined ? (normalizeColor(change.color) || current.color) : current.color,
    brightness: change.brightness !== undefined ? clampBrightness(change.brightness) : current.brightness,
    effect: change.effect !== undefined ? String(change.effect || "").trim() : current.effect,
    speed: change.speed !== undefined ? clampSpeed(change.speed) : current.speed
  }
  return out
}

// The rgb.sh arguments that put a device in a state: its effect with the
// colour and the speed, or its solid mode with the colour, the colour scaled to
// the brightness either way; or switched off, through its own Off mode when it
// has one and black otherwise. An effect that takes no colour leaves it unused.
// Empty for a device with no solid mode.
function applyArgs(device, state) {
  var solid = solidMode(device)
  if (solid === "") return []
  var s = state || lightState(null, "")
  var index = String(device.index)
  if (!s.on) {
    var off = offMode(device)
    return off !== "" ? ["set", index, off] : ["set", index, solid, "000000"]
  }
  var color = scaleColor(s.color, s.brightness)
  var effect = activeEffect(device, s)
  if (effect !== "") return ["set", index, effect, color, String(clampSpeed(s.speed))]
  return ["set", index, solid, color]
}

// rgb.sh set prints "error<TAB>message" when it fails and nothing otherwise.
function actionError(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] === "error") return parts.slice(1).join("\t") || "OpenRGB failed"
  }
  return ""
}

// The devices the popup lists. The filter is a comma separated list of names
// or types: a device shows when its name contains one of them or its type is
// one ("nzxt, gpu"). Empty shows every device OpenRGB found.
function visibleDevices(snapshot, filter) {
  var devices = snapshot && Array.isArray(snapshot.devices) ? snapshot.devices : []
  var terms = String(filter || "").split(",")
    .map(function(term) { return term.trim().toLowerCase() })
    .filter(function(term) { return term !== "" })
  if (terms.length === 0) return devices
  return devices.filter(function(device) {
    var name = String(device.name).toLowerCase()
    var type = String(device.type).toLowerCase()
    for (var i = 0; i < terms.length; i++) {
      if (name.indexOf(terms[i]) >= 0 || type === terms[i]) return true
    }
    return false
  })
}

// Devices whose remembered state has not been put back this session yet. The
// hardware forgets its colours when it loses power, and a device can turn up
// after the shell starts, so this is asked after every snapshot, not once.
function pendingRestore(devices, lights, done) {
  var out = []
  var list = Array.isArray(devices) ? devices : []
  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    if (done && done[device.key]) continue
    if (!lightState(lights, device.key).known || !isControllable(device)) continue
    out.push(device)
  }
  return out
}

// Whether a remembered device is still owed its state: not restored yet, and
// not one the last snapshot shows hidden by the devices setting or unable to
// take it. One that snapshot does not list at all may yet turn up, since the
// openrgb service can still be detecting when the shell asks at login.
function awaitingRestore(snapshot, filter, lights, done) {
  if (!lights || typeof lights !== "object") return false
  var listed = {}
  var all = snapshot && Array.isArray(snapshot.devices) ? snapshot.devices : []
  for (var i = 0; i < all.length; i++) listed[all[i].key] = all[i]
  var shown = {}
  var visible = visibleDevices(snapshot, filter)
  for (var j = 0; j < visible.length; j++) shown[visible[j].key] = true
  for (var key in lights) {
    if (!Object.prototype.hasOwnProperty.call(lights, key) || !lightState(lights, key).known) continue
    if (done && done[key]) continue
    var device = listed[key]
    if (device && (!shown[key] || !isControllable(device))) continue
    return true
  }
  return false
}

// The restore marks worth keeping after a snapshot. A device a good snapshot no
// longer lists has lost its colours along with its power, so it is restored
// again when it comes back; a failed snapshot says nothing about what is there.
function pruneRestored(done, snapshot) {
  var out = {}
  if (!done || typeof done !== "object") return out
  var listed = null
  if (isOk(snapshot)) {
    listed = {}
    for (var i = 0; i < snapshot.devices.length; i++) listed[snapshot.devices[i].key] = true
  }
  for (var key in done) {
    if (Object.prototype.hasOwnProperty.call(done, key) && done[key] && (!listed || listed[key])) out[key] = true
  }
  return out
}

// The restore marks without one device's: what was sent to it did not land,
// so the next snapshot puts its remembered state back.
function forgetRestored(done, key) {
  var out = {}
  if (!done || typeof done !== "object") return out
  for (var k in done) {
    if (Object.prototype.hasOwnProperty.call(done, k) && done[k] && k !== key) out[k] = true
  }
  return out
}

function litCount(devices, lights) {
  var n = 0
  var list = Array.isArray(devices) ? devices : []
  for (var i = 0; i < list.length; i++) {
    if (isControllable(list[i]) && lightState(lights, list[i].key).on) n++
  }
  return n
}

// What an all on or off asked for before the devices were listed comes to once
// they are: "on" and "off" say it, "toggle" (the bar's right click) flips what
// is lit by then. null for no request at all.
function requestedPower(request, anyOn) {
  switch (String(request || "")) {
  case "on": return true
  case "off": return false
  case "toggle": return !anyOn
  default: return null
  }
}

function typeIcon(device) {
  var icon = device ? TYPE_ICONS[String(device.type).toLowerCase()] : ""
  return icon || DEFAULT_TYPE_ICON
}

function isOk(snapshot) {
  return !!snapshot && snapshot.state === "ok"
}

// Headline for the popup when there is no device to show.
function stateTitle(snapshot) {
  switch (snapshot ? snapshot.state : "") {
  case "missing": return "OpenRGB is not installed"
  case "error": return "OpenRGB error"
  case "ok": return "No lighting found"
  default: return "Looking for lighting"
  }
}

// Why the list is empty: OpenRGB is missing or failed, it found nothing, or
// the devices setting hides everything it found. "" when nothing is wrong.
function stateDetail(snapshot, filter) {
  switch (snapshot ? snapshot.state : "") {
  case "missing": return "Install openrgb, then enable its service (sudo systemctl enable --now openrgb) so a change lands in a moment instead of waiting for every device to be detected again."
  case "error": return snapshot.error || ""
  case "ok": {
    var count = snapshot.devices.length
    if (count === 0)
      return "OpenRGB found nothing it can light. Its udev rules give your account the hardware once they are loaded, so reboot after installing it, or run the openrgb service, which reaches it as root."
    var terms = String(filter || "").trim()
    return terms !== "" ? "None of the " + count + " devices OpenRGB found match \"" + terms + "\"." : ""
  }
  default: return ""
  }
}

// The line under a device's name: "Red · 80%", "Breathing · Red · 80%", "Off",
// or why it cannot be set.
function deviceDetail(device, state) {
  if (!isControllable(device)) return "No single-colour mode in OpenRGB"
  var s = state || lightState(null, "")
  if (!s.known) return "Not set from here yet"
  if (!s.on) return "Off"
  var effect = activeEffect(device, s)
  return (effect !== "" ? effect + " · " : "") + colorName(s.color) + " · " + s.brightness + "%"
}

function heroStatus(snapshot, devices, lights) {
  if (!snapshot) return "LOOKING FOR DEVICES"
  if (!isOk(snapshot)) return String(snapshot.state).toUpperCase()
  var total = Array.isArray(devices) ? devices.length : 0
  if (total === 0) return "NO DEVICES"
  var lit = litCount(devices, lights)
  if (lit === 0) return "ALL OFF"
  return lit + " ON · " + total + (total === 1 ? " DEVICE" : " DEVICES")
}

function tooltip(snapshot, devices, lights) {
  if (!snapshot) return "RGB"
  if (!isOk(snapshot)) return stateTitle(snapshot)
  var list = Array.isArray(devices) ? devices : []
  if (list.length === 0) return "RGB · no devices"
  var parts = []
  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    var s = lightState(lights, device.key)
    var detail
    if (!isControllable(device)) detail = "not settable"
    else if (!s.known) detail = "not set"
    else if (!s.on) detail = "off"
    else {
      var effect = activeEffect(device, s)
      detail = (effect !== "" ? effect.toLowerCase() + " " : "") + colorName(s.color).toLowerCase() + " " + s.brightness + "%"
    }
    parts.push(device.name + " " + detail)
  }
  return "RGB · " + parts.join(" · ")
}
