.pragma library

// Pure helpers for the suspend plugin: reading its entry from shell.json,
// validating the idle timeout, the presets the popup offers, and interpreting
// what suspend.sh reported.

var DEFAULT_TIMEOUT_SECONDS = 1800

// One glyph says whether the machine will sleep on its own: the sleeping
// face, or the same face crossed out.
var ICON_ARMED = "󰒲"
var ICON_OFF = "󰒳"

// The timeouts the popup offers at a click; anything else goes in the field.
var PRESETS = [
  { label: "15 min", seconds: 900 },
  { label: "30 min", seconds: 1800 },
  { label: "1 h", seconds: 3600 },
  { label: "3 h", seconds: 10800 },
  { label: "Never", seconds: 0 }
]

var MAX_TIMEOUT_SECONDS = 86400

// The plugin's `{ "id": "joamag.suspend", ... }` entry in shell.json. Enabled
// as a bar widget it sits in the bar layout, which is where the popup writes
// it; enabled as a service alone it sits in `plugins[]`. The bar wins when
// both exist, since that is the one with a control on it.
function pluginEntry(config, id) {
  if (!config || typeof config !== "object") return null
  // Newer shells hand a plugin its bar config alone, older ones the whole
  // file; the same layout sits one level apart in the two.
  var bar = config.bar && typeof config.bar === "object" ? config.bar : config
  var layout = bar.layout && typeof bar.layout === "object" ? bar.layout : null
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var list = layout && Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (entry && typeof entry === "object" && String(entry.id || "") === id) return entry
    }
  }
  if (!Array.isArray(config.plugins)) return null
  for (var j = 0; j < config.plugins.length; j++) {
    var plugin = config.plugins[j]
    if (plugin && typeof plugin === "object" && String(plugin.id || "") === id) return plugin
  }
  return null
}

// `timeoutSec` is whole seconds of idle before suspending. 0 disarms the
// service; anything that is not a non-negative number falls back.
function timeoutSeconds(entry, fallback) {
  var value = entry ? entry.timeoutSec : undefined
  if (value === undefined || value === null || value === "") return fallback
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

// `dryRun: true` logs the decision without calling systemctl.
function dryRun(entry) {
  if (!entry) return false
  return entry.dryRun === true || entry.dryRun === "true"
}

// suspend.sh prints one "verdict<TAB>reason" line. Anything else is an error,
// described by the first stderr line or the exit status.
function parseResult(stdout, stderr, exitCode) {
  var line = firstLine(stdout)
  var tab = line.indexOf("\t")
  if (tab > 0) {
    var verdict = line.slice(0, tab)
    if (verdict === "suspend" || verdict === "skip" || verdict === "error") {
      return { verdict: verdict, reason: line.slice(tab + 1) }
    }
  }
  var detail = firstLine(stderr)
  return { verdict: "error", reason: detail || ("suspend.sh exited " + exitCode) }
}

function firstLine(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var trimmed = lines[i].trim()
    if (trimmed !== "") return trimmed
  }
  return ""
}

// Human form of the timeout for the status output and logs: "30 min", "90 s".
function describeTimeout(seconds) {
  if (!(seconds > 0)) return "off"
  if (seconds % 3600 === 0) return (seconds / 3600) + " h"
  if (seconds % 60 === 0) return (seconds / 60) + " min"
  return seconds + " s"
}

// Which preset a timeout is, or -1 when it is a custom value.
function presetIndex(seconds) {
  var n = Number(seconds)
  for (var i = 0; i < PRESETS.length; i++) if (PRESETS[i].seconds === n) return i
  return -1
}

// A typed duration as seconds: "45" is minutes, "45m", "1h", "1.5 h" and
// "2h30" are what they say, "0", "off" and "never" disarm. NaN for anything
// else; at least a minute, at most a day.
function parseDuration(text) {
  var s = String(text || "").trim().toLowerCase()
  if (s === "") return NaN
  if (s === "0" || s === "off" || s === "never" || s === "none") return 0
  var m = s.match(/^(\d+(?:[.,]\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)?(?:\s*(\d+)\s*(m|min|mins)?)?$/)
  if (!m) return NaN
  var value = Number(m[1].replace(",", "."))
  var unit = m[2] || "m"
  var seconds
  if (unit.charAt(0) === "h") seconds = value * 3600 + (m[3] ? Number(m[3]) * 60 : 0)
  else if (unit.charAt(0) === "s") seconds = value
  else seconds = value * 60
  if (!isFinite(seconds) || seconds <= 0) return NaN
  seconds = Math.round(seconds)
  if (seconds < 60) seconds = 60
  if (seconds > MAX_TIMEOUT_SECONDS) seconds = MAX_TIMEOUT_SECONDS
  return seconds
}

// The timeout the way the bar shows it: "30m", "1h", "1h 30m", "off".
function shortTimeout(seconds) {
  var n = Number(seconds)
  if (!(n > 0)) return "off"
  if (n < 60) return n + "s"
  var h = Math.floor(n / 3600)
  var m = Math.round((n % 3600) / 60)
  if (h === 0) return m + "m"
  return m === 0 ? h + "h" : h + "h " + m + "m"
}

// The compositor's idle notification cannot carry a long timeout on its own.
// Launching the screensaver and locking the session both register as activity
// and reset it, and a locked session reports active for as long as it stays
// locked, so a monitor set to half an hour never reaches its threshold. The
// monitor is therefore only asked to notice that the user has stopped touching
// the machine, on a short window that nothing else pre-empts, and the time
// away is accumulated from there.
var DETECTION_FLOOR_SECONDS = 5
var DETECTION_CEILING_SECONDS = 60

function detectionSeconds(timeoutSeconds) {
  var n = Number(timeoutSeconds)
  if (!isFinite(n) || n <= 0) return DETECTION_CEILING_SECONDS
  return Math.max(DETECTION_FLOOR_SECONDS, Math.min(DETECTION_CEILING_SECONDS, Math.floor(n)))
}

// Seconds since the user was first seen to be away, or 0 when they are not.
function awaySeconds(awaySince, now) {
  var since = Number(awaySince)
  var at = Number(now)
  if (!isFinite(since) || since <= 0 || !isFinite(at) || at < since) return 0
  return Math.floor((at - since) / 1000)
}

// A suspend that was skipped, because an update was holding sleep or the
// machine was told to stay awake, is worth trying again while the user is
// still away rather than waiting for them to come back and leave again.
var RETRY_SECONDS = 300

// Whether another suspend may be attempted during the same absence: either
// none has been tried yet, or a skipped one has waited out its retry.
function mayAttempt(alreadyFired, retryAfter, now) {
  if (!alreadyFired) return true
  var at = Number(retryAfter)
  var when = Number(now)
  if (!isFinite(at) || at <= 0 || !isFinite(when)) return false
  return when >= at
}

// Whether the machine has now been left alone for the whole timeout.
function isDue(awaySince, now, timeoutSeconds) {
  var timeout = Number(timeoutSeconds)
  if (!isFinite(timeout) || timeout <= 0) return false
  return awaySeconds(awaySince, now) >= timeout
}

// The lock and the idle services each answer their status IPC with one line of
// JSON. Either line may be missing when that service is not loaded, and a
// half-read answer is not worth failing over, so anything unparsable is simply
// not a reason to believe the user is away.
function parseAwayProbe(text) {
  var probe = { known: false, locked: false, authenticating: false, inIdleCycle: false, stayAwake: false }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var data = null
    try {
      data = JSON.parse(line)
    } catch (e) {
      continue
    }
    // JSON.parse gives a real array here, whatever the shell hands other
    // bindings, so a stray list is told apart from a status object safely.
    if (!data || typeof data !== "object" || Array.isArray(data)) continue
    probe.known = true
    if (data.locked === true) probe.locked = true
    if (data.authenticating === true) probe.authenticating = true
    if (data.inIdleCycle === true) probe.inIdleCycle = true
    if (data.stayAwake === true) probe.stayAwake = true
  }
  return probe
}

// A sleep is the only thing that stops the event loop for longer than a few
// seconds, so a tick that arrives this much later than the timer asked for
// means the machine has just come back from one.
var RESUME_GAP_FACTOR = 4

// Whether the machine slept between two ticks of a timer of `intervalMs`.
function resumed(lastTick, now, intervalMs) {
  var last = Number(lastTick)
  var at = Number(now)
  var interval = Number(intervalMs)
  if (!isFinite(last) || last <= 0) return false
  if (!isFinite(at) || !isFinite(interval) || interval <= 0) return false
  return at - last >= interval * RESUME_GAP_FACTOR
}

// Auto sleep only happens when a timeout is set and nothing is holding the
// machine awake, so Stay Awake shows the same crossed-out icon as no timeout
// at all; the bar would otherwise promise a sleep that never comes.
function barIcon(armed, stayAwake) {
  return armed && !stayAwake ? ICON_ARMED : ICON_OFF
}

// Text on the bar button: the icon that says armed or not, then the timeout
// when wanted and the bar is horizontal.
function barText(armed, seconds, showLabel, vertical, stayAwake) {
  var icon = barIcon(armed, stayAwake)
  if (!showLabel || vertical || !armed || stayAwake) return icon
  return icon + " " + shortTimeout(seconds)
}

// What suspend.sh last decided, in a sentence: "skipped, stay awake is on".
function verdictLabel(verdict, reason) {
  var r = String(reason || "")
  switch (String(verdict || "")) {
  case "suspend": return "last time it slept"
  case "skip":
    switch (r) {
    case "stay-awake": return "skipped, stay awake is on"
    case "suspend-off": return "skipped, suspend is off in the menu"
    case "inhibited": return "skipped, something is holding sleep"
    case "other-users": return "skipped, another user is logged in"
    default: return "skipped" + (r ? ", " + r : "")
    }
  case "error": return "failed" + (r ? ": " + r : "")
  default: return ""
  }
}

function heroStatus(armed, seconds, idle, stayAwake) {
  var parts = [armed ? "SLEEPS AFTER " + describeTimeout(seconds).toUpperCase() : "NEVER SLEEPS"]
  if (stayAwake) parts.push("STAY AWAKE ON")
  else if (armed && idle) parts.push("IDLE NOW")
  return parts.join(" · ")
}

function tooltip(armed, seconds, verdict, reason, stayAwake) {
  var text = armed ? "Sleeps after " + describeTimeout(seconds) + " idle" : "Auto sleep is off"
  if (armed && stayAwake) text = "Held awake by stay awake"
  var last = verdictLabel(verdict, reason)
  return "Suspend · " + text + (last ? " · " + last : "")
}
