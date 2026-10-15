.pragma library

// Pure helpers for the screen-off plugin: reading its entry from shell.json,
// validating the idle timeout, deciding when the displays go off and come
// back, and interpreting what screenoff.sh reported.

var DEFAULT_TIMEOUT_SECONDS = 900

var MAX_TIMEOUT_SECONDS = 86400

// A screen off asked for by hand waits for this long without input before the
// displays go, so the click or key press that asked for it, and the hand still
// on the mouse after it, does not wake them straight back.
var FORCED_SETTLE_SECONDS = 1

// shell.json as an object, or null for anything that is not one. The file is
// read straight from disk: the shell hands a third-party service the bar
// section alone, and a service with no widget is listed in `plugins[]`.
function parseConfig(text) {
  var source = String(text || "").trim()
  if (source === "") return null
  var data = null
  try {
    data = JSON.parse(source)
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return null
  return data
}

// The plugin's `{ "id": "joamag.screenoff", ... }` entry in `plugins[]`.
function pluginEntry(config, id) {
  if (!config || typeof config !== "object" || !Array.isArray(config.plugins)) return null
  for (var i = 0; i < config.plugins.length; i++) {
    var plugin = config.plugins[i]
    if (plugin && typeof plugin === "object" && String(plugin.id || "") === id) return plugin
  }
  return null
}

// `timeoutSec` is whole seconds of idle before the displays go off. 0 disarms
// the service; anything that is not a non-negative number falls back, and a
// day is the longest it waits.
function timeoutSeconds(entry, fallback) {
  var value = entry ? entry.timeoutSec : undefined
  // Number() would make a second of true and a zero of a blank string or an
  // empty list, so only a number or the text of one is taken for a timeout.
  if (typeof value === "string") value = value.trim()
  if ((typeof value !== "number" && typeof value !== "string") || value === "") return fallback
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.min(MAX_TIMEOUT_SECONDS, Math.floor(n))
}

// `dryRun: true` logs the decision without touching the displays.
function dryRun(entry) {
  if (!entry) return false
  return entry.dryRun === true || entry.dryRun === "true"
}

// `respectInhibitors: false` turns the displays off even while a Wayland idle
// inhibitor (video playback, a game, a call) asks for them to stay on.
function respectInhibitors(entry) {
  if (!entry) return true
  return !(entry.respectInhibitors === false || entry.respectInhibitors === "false")
}

// The idle service answers its status IPC with one line of JSON, and that is
// where Stay Awake is read from. The line may be missing while the shell is
// still starting, and a half-read answer is not worth acting on, so anything
// unparsable is simply not an answer.
function parseStayAwake(text) {
  var probe = { known: false, stayAwake: false }
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
    if (!data || typeof data !== "object" || Array.isArray(data)) continue
    probe.known = true
    if (data.stayAwake === true) probe.stayAwake = true
  }
  return probe
}

// What to do with the displays now. They go off once the user has been idle
// for the whole timeout while the service is watching, or as soon as a screen
// off asked for by hand finds the hands off the machine (`forced`), and come
// back as soon as neither holds: the user returned, or, for the timed blank,
// Stay Awake was switched off or the timeout was set to never.
function nextAction(watching, idle, blanked, forced) {
  var away = (!!watching && !!idle) || !!forced
  if (away && !blanked) return "off"
  if (!away && blanked) return "on"
  return ""
}

// Whether a run of screenoff.sh only pretends. That is the `dryRun` setting,
// except on the way back: displays are turned on the way they were turned
// off, so ones that really went dark really come back even when `dryRun` was
// switched on in between.
function runsDry(action, dryRun, blankWasDry) {
  return action === "on" ? !!blankWasDry : !!dryRun
}

// screenoff.sh prints one "verdict<TAB>reason" line. Anything else is an
// error, described by the first stderr line or the exit status.
function parseResult(stdout, stderr, exitCode) {
  var line = firstLine(stdout)
  var tab = line.indexOf("\t")
  if (tab > 0) {
    var verdict = line.slice(0, tab)
    if (verdict === "off" || verdict === "on" || verdict === "skip" || verdict === "error") {
      return { verdict: verdict, reason: line.slice(tab + 1) }
    }
  }
  var detail = firstLine(stderr)
  return { verdict: "error", reason: detail || ("screenoff.sh exited " + exitCode) }
}

function firstLine(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var trimmed = lines[i].trim()
    if (trimmed !== "") return trimmed
  }
  return ""
}

// Whether the displays are off once screenoff.sh has answered. Only its own
// word for it counts: a skip or an error leaves them as they were.
function displaysOff(verdict, wasOff) {
  if (verdict === "off") return true
  if (verdict === "on") return false
  return !!wasOff
}

// Human form of the timeout for the status output and logs: "15 min", "90 s".
function describeTimeout(seconds) {
  if (!(seconds > 0)) return "off"
  if (seconds % 3600 === 0) return (seconds / 3600) + " h"
  if (seconds % 60 === 0) return (seconds / 60) + " min"
  return seconds + " s"
}
