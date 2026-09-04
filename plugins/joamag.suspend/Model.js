.pragma library

// Pure helpers for the suspend service: reading its entry from shell.json,
// validating the idle timeout and interpreting what suspend.sh reported.

var DEFAULT_TIMEOUT_SECONDS = 1800

// The service has no bar widget, so its settings live inline on the
// `{ "id": "joamag.suspend", ... }` entry in shell.json's `plugins[]`.
function pluginEntry(config, id) {
  if (!config || !Array.isArray(config.plugins)) return null
  for (var i = 0; i < config.plugins.length; i++) {
    var entry = config.plugins[i]
    if (entry && typeof entry === "object" && String(entry.id || "") === id) return entry
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
