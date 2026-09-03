.pragma library

// Pure helpers for the display widget. The scale, text-size and monitor-list
// helpers are forked from Omarchy's first-party omarchy.monitor plugin; the
// snapshot parsing and the brightness / contrast / gamma logic below are the
// additions this widget is for.

var ICON = "󰍹"
var ICON_MULTI = "󰍺"

// The sliders, in the order the popup stacks them. `key` doubles as the
// keyboard section name and as the display.sh action.
//
// Brightness and contrast are the monitor's own DDC/CI features and are
// percentages of its scale. Gamma is a true exponent on the compositor's gamma
// ramp, with the same 0.30-2.80 range and 1.00 neutral the NVIDIA control
// panel uses, so a value carried over from Windows means the same thing here.
// Temperature is the same ramp's white point, which is what night light is.
// `curve` is how the value is spread along the slider. Gamma is a ratio: 0.5
// is as far from neutral as 2.0 is, and on a linear track the whole darkening
// half would be squeezed into the first 28% of travel while the top third did
// almost nothing visible. A log track gives equal travel to equal ratio and
// puts 1.00 near the middle.
var CONTROLS = [
  { key: "brightness", title: "BRIGHTNESS", minimum: 1, maximum: 100, step: 1, decimals: 0, unit: "%", neutral: NaN, scope: "monitor", curve: "linear" },
  { key: "contrast", title: "CONTRAST", minimum: 0, maximum: 100, step: 1, decimals: 0, unit: "%", neutral: NaN, scope: "monitor", curve: "linear" },
  { key: "gamma", title: "GAMMA", minimum: 0.3, maximum: 2.8, step: 0.01, decimals: 2, unit: "", neutral: 1, scope: "session", curve: "log" },
  { key: "temperature", title: "TEMPERATURE", minimum: 2500, maximum: 6500, step: 100, decimals: 0, unit: "K", neutral: 6500, scope: "session", curve: "linear" }
]

// Every slider runs 0..100 units of travel whatever its control measures, so
// the panel never has to know which curve a control uses.
var SLIDER_TRAVEL = 100

function num(value) {
  // Number(null) is 0; a control the machine cannot report must stay unknown
  // rather than read as a hard zero the slider would then write back.
  if (value === null || value === undefined || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

// display.sh emits "key<TAB>value" lines; every control is absent from the
// output when nothing on this machine can report it.
function parseSnapshot(raw) {
  var out = { monitor: "", bus: "", brightness: NaN, contrast: NaN, gamma: NaN, temperature: NaN, scale: "", displays: [], enabledDisplayCount: 0 }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var parts = line.split("\t")
    if (parts.length < 2) continue
    var value = parts.slice(1).join("\t")
    switch (parts[0]) {
    case "monitor": out.monitor = value; break
    case "bus": out.bus = value; break
    case "brightness": out.brightness = num(value); break
    case "contrast": out.contrast = num(value); break
    case "gamma": out.gamma = num(value); break
    case "temperature": out.temperature = num(value); break
    case "scale": out.scale = normalizeScale(value); break
    case "displays": {
      var parsed = parseDisplays(value)
      out.displays = parsed.displays
      out.enabledDisplayCount = parsed.enabledDisplayCount
      break
    }
    }
  }
  return out
}

function controlValue(snapshot, key) {
  if (!snapshot) return NaN
  return num(snapshot[key])
}

function hasControl(snapshot, key) {
  return isFinite(controlValue(snapshot, key))
}

// Which sliders the popup shows: a laptop panel reports brightness but no
// contrast, a machine without hyprsunset has no gamma, and a monitor with
// DDC/CI switched off in its menu has neither of the first two.
function visibleControls(snapshot) {
  var out = []
  for (var i = 0; i < CONTROLS.length; i++) {
    if (hasControl(snapshot, CONTROLS[i].key)) out.push(CONTROLS[i].key)
  }
  return out
}

function controlByKey(key) {
  for (var i = 0; i < CONTROLS.length; i++) if (CONTROLS[i].key === key) return CONTROLS[i]
  return null
}

function controlMinimum(key) {
  var control = controlByKey(key)
  return control ? control.minimum : 0
}

function controlMaximum(key) {
  var control = controlByKey(key)
  return control ? control.maximum : 100
}

function controlStep(key) {
  var control = controlByKey(key)
  return control ? control.step : 1
}

function controlDecimals(key) {
  var control = controlByKey(key)
  return control ? control.decimals : 0
}

function controlTitle(key) {
  var control = controlByKey(key)
  return control ? control.title : ""
}

// Whether the control belongs to the monitor or to the whole session, which
// is the difference between a setting that survives a reboot in the panel's
// own memory and one the compositor applies to every screen.
function controlScope(key) {
  var control = controlByKey(key)
  return control ? control.scope : "monitor"
}

// Clamped into the control's own range and snapped to its step, so a drag
// across a 0.30-2.80 gamma track lands on 1.35 rather than 1.3487261.
function clampControl(key, value) {
  var n = num(value)
  var control = controlByKey(key)
  if (!control) return 0
  if (!isFinite(n)) return isFinite(control.neutral) ? control.neutral : control.minimum
  var stepped = Math.round(n / control.step) * control.step
  var clamped = Math.max(control.minimum, Math.min(control.maximum, stepped))
  // Snapping by multiplication leaves binary dust (1.35 as 1.3500000000000003),
  // so the value is rounded to the decimals the control is written in.
  var factor = Math.pow(10, control.decimals)
  return Math.round(clamped * factor) / factor
}

function clampBrightness(value) {
  return clampControl("brightness", value)
}

function clamp01(value) {
  var n = num(value)
  if (!isFinite(n)) return 0
  return Math.max(0, Math.min(1, n))
}

// Where a control's value sits along its slider, 0..100 units of travel.
function sliderFromValue(key, value) {
  var control = controlByKey(key)
  if (!control) return 0
  var n = num(value)
  if (!isFinite(n)) n = isFinite(control.neutral) ? control.neutral : control.minimum
  n = Math.max(control.minimum, Math.min(control.maximum, n))
  var fraction
  if (control.curve === "log") {
    var low = Math.log(control.minimum)
    fraction = (Math.log(n) - low) / (Math.log(control.maximum) - low)
  } else {
    fraction = (n - control.minimum) / (control.maximum - control.minimum)
  }
  return clamp01(fraction) * SLIDER_TRAVEL
}

// The value a position along the slider means, snapped to the control's step.
function valueFromSlider(key, position) {
  var control = controlByKey(key)
  if (!control) return 0
  var fraction = clamp01(num(position) / SLIDER_TRAVEL)
  var raw
  if (control.curve === "log") {
    var low = Math.log(control.minimum)
    raw = Math.exp(low + fraction * (Math.log(control.maximum) - low))
  } else {
    raw = control.minimum + fraction * (control.maximum - control.minimum)
  }
  return clampControl(key, raw)
}

// How far one arrow-key press moves a control, in slider units. A log control
// gets a smaller press because each unit is already a fixed ratio.
function controlKeyStep(key) {
  var control = controlByKey(key)
  return control && control.curve === "log" ? 2 : 5
}

function isNeutral(key, value) {
  var control = controlByKey(key)
  if (!control || !isFinite(control.neutral)) return false
  return Math.abs(num(value) - control.neutral) < control.step / 2
}

// What the row shows on the right: "75%", "1.35", "4500K".
function formatControl(key, value) {
  var n = num(value)
  if (!isFinite(n)) return "—"
  var control = controlByKey(key)
  if (!control) return String(n)
  return n.toFixed(control.decimals) + control.unit
}

function formatPercent(value) {
  var n = num(value)
  return isFinite(n) ? Math.round(n) + "%" : "—"
}

// Playful mood-name for a given brightness percent. Bands intentionally
// span ~10-20 points so casual tweaks change the label, while small
// nudges within one band don't.
function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

// Gamma is an exponent around 1.00: above it the midtones lift and the image
// washes out, below it they deepen until the shadows crush.
function gammaName(value) {
  var n = num(value)
  if (!isFinite(n)) return "—"
  if (isNeutral("gamma", n)) return "Neutral"
  if (n >= 2) return "Washed out"
  if (n > 1) return "Lifted midtones"
  if (n >= 0.7) return "Deepened midtones"
  return "Crushed shadows"
}

function temperatureName(kelvin) {
  var n = num(kelvin)
  if (!isFinite(n)) return "—"
  if (isNeutral("temperature", n)) return "Neutral white"
  if (n >= 5500) return "Soft warm"
  if (n >= 4500) return "Warm"
  if (n >= 3500) return "Night light"
  return "Ember"
}

function controlName(key, value) {
  if (key === "gamma") return gammaName(value)
  if (key === "temperature") return temperatureName(value)
  if (key === "brightness") return brightnessName(value)
  return formatControl(key, value)
}

// The line under "Display" in the hero: the brightness mood, plus a note for
// each ramp control that has been moved off neutral.
function heroStatus(snapshot, previewBrightness) {
  if (!snapshot) return "READING DISPLAY"
  var parts = []
  var brightness = isFinite(num(previewBrightness)) ? num(previewBrightness) : controlValue(snapshot, "brightness")
  if (isFinite(brightness)) parts.push(brightnessName(brightness))
  else parts.push("Fixed brightness")
  var keys = ["gamma", "temperature"]
  for (var i = 0; i < keys.length; i++) {
    var value = controlValue(snapshot, keys[i])
    if (isFinite(value) && !isNeutral(keys[i], value)) parts.push(controlName(keys[i], value))
  }
  return parts.join(" · ").toUpperCase()
}

function tooltip(snapshot) {
  if (!snapshot) return "Display"
  var parts = []
  if (hasControl(snapshot, "brightness")) parts.push("Brightness " + formatControl("brightness", snapshot.brightness))
  if (hasControl(snapshot, "contrast")) parts.push("Contrast " + formatControl("contrast", snapshot.contrast))
  // A ramp control sitting at neutral is not worth a word in the tooltip.
  var keys = ["gamma", "temperature"]
  for (var i = 0; i < keys.length; i++) {
    var value = controlValue(snapshot, keys[i])
    if (isFinite(value) && !isNeutral(keys[i], value))
      parts.push(controlTitle(keys[i]).charAt(0) + controlTitle(keys[i]).slice(1).toLowerCase() + " " + formatControl(keys[i], value))
  }
  if (parts.length === 0) return "Display"
  return "Display · " + parts.join(" · ")
}

// Why a control is missing, for the line the popup shows when the monitor
// gives it nothing to drive.
function unavailableDetail(snapshot) {
  if (!snapshot) return ""
  if (visibleControls(snapshot).length > 0) return ""
  if (snapshot.bus === "")
    return "This display does not answer DDC/CI. Check that the monitor's on-screen menu has DDC/CI enabled."
  return "The monitor answered on i2c bus " + snapshot.bus + " but reported no brightness or contrast."
}

// Gamma and temperature come from the compositor's ramp rather than the
// monitor, so their absence has its own cause and its own fix.
function rampDetail(snapshot) {
  if (!snapshot) return ""
  if (hasControl(snapshot, "gamma") || hasControl(snapshot, "temperature")) return ""
  return "Gamma and temperature need wl-gammarelay-rs running; it could not be started."
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}
