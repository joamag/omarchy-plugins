.pragma library

// Pure helpers for the system monitor: snapshot parsing, percentages derived
// from two CPU samples, and the formatting the bar label and popup share.

var METRICS = ["cpu", "memory", "temperature", "gpu", "disk"]

var ICONS = {
  cpu: "󰍛",
  memory: "󰘚",
  temperature: "󰔏",
  gpu: "󰢮",
  disk: "󰋊"
}

var LABELS = {
  cpu: "CPU",
  memory: "Memory",
  temperature: "Temperature",
  gpu: "GPU",
  disk: "Disk"
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function num(value) {
  // Number(null) is 0; a missing field must stay unknown rather than zero.
  if (value === null || value === undefined || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

// stats.sh emits "key<TAB>value" lines plus "proc<TAB>pid<TAB>cpu<TAB>mem<TAB>name"
// rows. Everything scalar lands on the returned object as a string; processes
// collect under `procs`.
function parseSnapshot(raw) {
  var out = { procs: [] }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var parts = line.split("\t")
    if (parts[0] === "proc") {
      if (parts.length >= 5) {
        out.procs.push({
          pid: parts[1],
          cpu: num(parts[2]),
          mem: num(parts[3]),
          name: parts.slice(4).join("\t")
        })
      }
      continue
    }
    if (parts.length >= 2) out[parts[0]] = parts[1]
  }
  return out
}

// Busy fraction between two /proc/stat samples; -1 until a delta exists.
function cpuPercent(prev, next) {
  if (!prev || !next) return -1
  var dTotal = num(next.cpu_total) - num(prev.cpu_total)
  var dIdle = num(next.cpu_idle) - num(prev.cpu_idle)
  if (!(dTotal > 0) || !isFinite(dIdle)) return -1
  return clamp(100 * (1 - dIdle / dTotal), 0, 100)
}

function ratioPercent(used, total) {
  used = num(used)
  total = num(total)
  if (!(total > 0) || !isFinite(used)) return -1
  return clamp(100 * used / total, 0, 100)
}

function memPercent(s) {
  if (!s) return -1
  return ratioPercent(num(s.mem_total_kb) - num(s.mem_avail_kb), s.mem_total_kb)
}

function swapPercent(s) {
  if (!s) return -1
  return ratioPercent(num(s.swap_total_kb) - num(s.swap_free_kb), s.swap_total_kb)
}

function diskPercent(s) {
  if (!s) return -1
  return ratioPercent(s.disk_used_kb, s.disk_total_kb)
}

function gpuPercent(s) {
  if (!s || s.gpu_util === undefined) return -1
  var n = num(s.gpu_util)
  return isFinite(n) ? clamp(n, 0, 100) : -1
}

function gpuMemPercent(s) {
  if (!s) return -1
  return ratioPercent(s.gpu_mem_used_mb, s.gpu_mem_total_mb)
}

function cpuTemp(s) {
  if (!s || s.cpu_temp_c === undefined) return NaN
  return num(s.cpu_temp_c)
}

function gpuTemp(s) {
  if (!s || s.gpu_temp_c === undefined) return NaN
  return num(s.gpu_temp_c)
}

function hasGpu(s) {
  return !!s && s.gpu_util !== undefined
}

function formatKb(kb) {
  var n = num(kb)
  if (!isFinite(n)) return "—"
  var gb = n / 1024 / 1024
  if (gb >= 100) return Math.round(gb) + " GB"
  if (gb >= 1) return gb.toFixed(1) + " GB"
  return Math.round(n / 1024) + " MB"
}

function formatMb(mb) {
  var n = num(mb)
  if (!isFinite(n)) return "—"
  if (n >= 1024) return (n / 1024).toFixed(1) + " GB"
  return Math.round(n) + " MB"
}

function formatPercent(value) {
  var n = num(value)
  return isFinite(n) && n >= 0 ? Math.round(n) + "%" : "—"
}

function formatTemp(value) {
  var n = num(value)
  return isFinite(n) ? Math.round(n) + "°C" : "—"
}

function formatMhz(value) {
  var n = num(value)
  if (!isFinite(n)) return "—"
  return n >= 1000 ? (n / 1000).toFixed(2) + " GHz" : Math.round(n) + " MHz"
}

function formatUptime(seconds) {
  var n = num(seconds)
  if (!isFinite(n) || n < 0) return "—"
  var days = Math.floor(n / 86400)
  var hours = Math.floor((n % 86400) / 3600)
  var minutes = Math.floor((n % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + minutes + "m"
  return minutes + "m"
}

function normalizeMetric(metric) {
  var m = String(metric || "").toLowerCase()
  return METRICS.indexOf(m) >= 0 ? m : "cpu"
}

function nextMetric(metric, gpuAvailable) {
  var current = normalizeMetric(metric)
  var ring = gpuAvailable ? METRICS : METRICS.filter(function(m) { return m !== "gpu" })
  var idx = ring.indexOf(current)
  return ring[(idx + 1) % ring.length]
}

// Value the bar label shows for the configured metric.
function barValue(metric, cpu, snapshot) {
  switch (normalizeMetric(metric)) {
  case "memory": return formatPercent(memPercent(snapshot))
  case "temperature": return formatTemp(cpuTemp(snapshot))
  case "gpu": return formatPercent(gpuPercent(snapshot))
  case "disk": return formatPercent(diskPercent(snapshot))
  default: return formatPercent(cpu)
  }
}

// Headline percentage used to colour the bar icon when a metric runs hot.
function barLevel(metric, cpu, snapshot) {
  switch (normalizeMetric(metric)) {
  case "memory": return memPercent(snapshot)
  case "temperature": {
    var t = cpuTemp(snapshot)
    return isFinite(t) ? clamp(t, 0, 100) : -1
  }
  case "gpu": return gpuPercent(snapshot)
  case "disk": return diskPercent(snapshot)
  default: return cpu
  }
}

function tooltip(cpu, snapshot) {
  if (!snapshot) return "System monitor"
  var parts = ["CPU " + formatPercent(cpu), "Memory " + formatPercent(memPercent(snapshot))]
  var t = cpuTemp(snapshot)
  if (isFinite(t)) parts.push(formatTemp(t))
  if (hasGpu(snapshot)) parts.push("GPU " + formatPercent(gpuPercent(snapshot)))
  return parts.join(" · ")
}
