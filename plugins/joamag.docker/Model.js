.pragma library

// Pure helpers for the Docker widget: snapshot parsing, per-container glyphs
// and the strings the bar label, tooltip and popup share.

var ICON = "󰡨"

var STATE_ICONS = {
  running: "󰐊",
  paused: "󰏤",
  restarting: "󰑐",
  exited: "󰓛",
  dead: "󰓛",
  created: "󰆧",
  removing: "󰆧"
}

// docker.sh emits "state<TAB>value", optionally "error<TAB>message", then one
// "container<TAB>id<TAB>name<TAB>image<TAB>state<TAB>status<TAB>ports" per
// container.
function parseSnapshot(raw) {
  var out = { state: "error", error: "", containers: [] }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var parts = line.split("\t")
    if (parts[0] === "container") {
      if (parts.length < 6) continue
      out.containers.push({
        id: parts[1],
        name: parts[2],
        image: parts[3],
        state: parts[4],
        status: parts[5],
        ports: parts.length > 6 ? parts[6] : ""
      })
    } else if (parts[0] === "state") {
      out.state = parts[1] || "error"
    } else if (parts[0] === "error") {
      out.error = parts.slice(1).join("\t")
    }
  }
  if (out.state === "error" && out.error === "") out.error = "Docker returned no data"
  out.containers.sort(compareContainers)
  return out
}

// Running containers first, then alphabetical, so the list is stable across
// refreshes and the interesting rows sit at the top.
function compareContainers(a, b) {
  var ra = isRunning(a) ? 0 : 1
  var rb = isRunning(b) ? 0 : 1
  if (ra !== rb) return ra - rb
  return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
}

function isRunning(container) {
  return !!container && container.state === "running"
}

function isPaused(container) {
  return !!container && container.state === "paused"
}

function runningCount(snapshot) {
  if (!snapshot) return 0
  var n = 0
  for (var i = 0; i < snapshot.containers.length; i++) if (isRunning(snapshot.containers[i])) n++
  return n
}

function totalCount(snapshot) {
  return snapshot ? snapshot.containers.length : 0
}

function stateIcon(container) {
  var icon = container ? STATE_ICONS[container.state] : ""
  return icon || STATE_ICONS.created
}

// The command that toggles a container between running and stopped. Paused
// containers resume rather than stop, matching what a click on them means.
function toggleCommand(container) {
  if (isPaused(container)) return "unpause"
  return isRunning(container) ? "stop" : "start"
}

// Drop the registry and digest from an image reference so "ghcr.io/acme/api:1.2"
// reads as "acme/api:1.2" in a narrow column.
function shortImage(image) {
  var s = String(image || "")
  var at = s.indexOf("@")
  if (at > 0) s = s.slice(0, at)
  var slash = s.indexOf("/")
  if (slash > 0 && s.slice(0, slash).indexOf(".") >= 0) s = s.slice(slash + 1)
  return s
}

function isOk(snapshot) {
  return !!snapshot && snapshot.state === "ok"
}

// Headline for the popup when the container list cannot be shown.
function stateTitle(snapshot) {
  switch (snapshot ? snapshot.state : "") {
  case "missing": return "Docker is not installed"
  case "stopped": return "Docker daemon is not running"
  case "denied": return "Docker needs sudo on this account"
  case "error": return "Docker error"
  default: return "Checking Docker"
  }
}

function stateDetail(snapshot) {
  switch (snapshot ? snapshot.state : "") {
  case "missing": return "Install docker and start docker.socket to use this widget."
  case "stopped": return "Start the daemon to list containers."
  case "denied": return "Omarchy keeps accounts out of the docker group by default. Enable sudoless Docker to let the widget talk to the daemon, or open lazydocker which prompts for authorization."
  case "error": return snapshot.error || ""
  default: return ""
  }
}

function heroStatus(snapshot) {
  if (!snapshot) return "CHECKING"
  if (!isOk(snapshot)) return String(snapshot.state).toUpperCase()
  var running = runningCount(snapshot)
  var total = totalCount(snapshot)
  if (total === 0) return "NO CONTAINERS"
  return running + " RUNNING · " + total + " TOTAL"
}

function barText(snapshot, showCount, vertical) {
  if (!showCount || vertical || !isOk(snapshot)) return ICON
  return ICON + " " + runningCount(snapshot)
}

function tooltip(snapshot) {
  if (!snapshot) return "Docker"
  if (!isOk(snapshot)) return stateTitle(snapshot)
  var running = runningCount(snapshot)
  var total = totalCount(snapshot)
  if (total === 0) return "Docker · no containers"
  return "Docker · " + running + " of " + total + " running"
}
