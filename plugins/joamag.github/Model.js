.pragma library

// Pure helpers for the GitHub radar: snapshot parsing, the attention count
// the bar shows, per-row glyphs and colours, and relative ages.

var ICON = "󰊤"

var SECTIONS = [
  { key: "reviews", title: "REVIEW REQUESTED", setting: "showReviews" },
  { key: "pulls", title: "MY PULL REQUESTS", setting: "showPulls" },
  { key: "issues", title: "ASSIGNED ISSUES", setting: "showIssues" },
  { key: "notifications", title: "NOTIFICATIONS", setting: "showNotifications" }
]

function parseSnapshot(raw) {
  try {
    var obj = JSON.parse(String(raw || "").trim())
    if (obj && typeof obj === "object" && obj.state) return obj
  } catch (e) {
    // fall through
  }
  return { state: "error", error: "GitHub returned no data" }
}

function isOk(snapshot) {
  return !!snapshot && snapshot.state === "ok"
}

function section(snapshot, key) {
  var s = isOk(snapshot) ? snapshot[key] : null
  return s && typeof s === "object" ? { total: Number(s.total) || 0, items: Array.isArray(s.items) ? s.items : [] } : { total: 0, items: [] }
}

function ciFailed(row) {
  var ci = String(row && row.ci || "").toUpperCase()
  return ci === "FAILURE" || ci === "ERROR"
}

function ciPending(row) {
  var ci = String(row && row.ci || "").toUpperCase()
  return ci === "PENDING" || ci === "EXPECTED"
}

function changesRequested(row) {
  return String(row && row.review || "").toUpperCase() === "CHANGES_REQUESTED"
}

// PRs of mine that need a move from me: red checks or reviewers asking for
// changes. Drafts are excluded, they are not ready by definition.
function failingPulls(snapshot) {
  var items = section(snapshot, "pulls").items
  var n = 0
  for (var i = 0; i < items.length; i++) {
    var row = items[i]
    if (row.draft) continue
    if (ciFailed(row) || changesRequested(row)) n++
  }
  return n
}

// The number in the bar: review requests, my PRs needing a move, unread
// notifications. Assigned issues are a backlog, not an interrupt.
function attentionCount(snapshot, settings) {
  if (!isOk(snapshot)) return 0
  var n = 0
  if (!settings || settings.showReviews !== false) n += section(snapshot, "reviews").total
  if (!settings || settings.showPulls !== false) n += failingPulls(snapshot)
  if (!settings || settings.showNotifications !== false) n += section(snapshot, "notifications").total
  return n
}

function hasFailures(snapshot) {
  return failingPulls(snapshot) > 0
}

function barText(snapshot, settings, vertical) {
  if (vertical || !isOk(snapshot)) return ICON
  var n = attentionCount(snapshot, settings)
  return n > 0 ? ICON + " " + n : ICON
}

function tooltip(snapshot, settings) {
  if (!snapshot) return "GitHub"
  switch (snapshot.state) {
  case "missing": return "GitHub CLI (gh) is not installed"
  case "unauthenticated": return "GitHub: run gh auth login"
  case "error": return "GitHub: " + (snapshot.error || "request failed")
  }
  var parts = []
  var reviews = section(snapshot, "reviews").total
  var failing = failingPulls(snapshot)
  var pulls = section(snapshot, "pulls").total
  var notifications = section(snapshot, "notifications").total
  if (reviews > 0) parts.push(reviews + " to review")
  if (failing > 0) parts.push(failing + " PR" + (failing === 1 ? "" : "s") + " need work")
  parts.push(pulls + " open PR" + (pulls === 1 ? "" : "s"))
  if (notifications > 0) parts.push(notifications + " unread")
  return "GitHub · " + parts.join(" · ")
}

function stateTitle(snapshot) {
  switch (snapshot ? snapshot.state : "") {
  case "missing": return "GitHub CLI is not installed"
  case "unauthenticated": return "GitHub CLI is not signed in"
  case "error": return "GitHub request failed"
  default: return "Loading GitHub"
  }
}

function stateDetail(snapshot) {
  switch (snapshot ? snapshot.state : "") {
  case "missing": return "Install gh (pacman -S github-cli) and sign in with gh auth login."
  case "unauthenticated": return "The widget reuses the gh CLI session, so it never stores a token of its own."
  case "error": return snapshot.error || ""
  default: return ""
  }
}

function heroStatus(snapshot, settings) {
  if (!snapshot) return "LOADING"
  if (!isOk(snapshot)) return String(snapshot.state).toUpperCase()
  var parts = []
  var reviews = section(snapshot, "reviews").total
  var failing = failingPulls(snapshot)
  var notifications = section(snapshot, "notifications").total
  if (reviews > 0) parts.push(reviews + " TO REVIEW")
  if (failing > 0) parts.push(failing + " NEED WORK")
  if (notifications > 0) parts.push(notifications + " UNREAD")
  if (parts.length === 0) parts.push("ALL QUIET")
  return parts.join(" · ")
}

// Row glyph: CI and review state for PRs, a type glyph for issues and
// notifications.
function rowGlyph(row) {
  if (!row) return ""
  if (row.kind === "pull") {
    if (row.draft) return "󰏫"
    if (ciFailed(row)) return "󰅙"
    if (changesRequested(row)) return "󰕒"
    if (String(row.review || "").toUpperCase() === "APPROVED") return "󰄬"
    if (ciPending(row)) return "󰔛"
    if (String(row.ci || "").toUpperCase() === "SUCCESS") return "󰗠"
    return "󰘭"
  }
  if (row.kind === "issue") return "󰀦"
  switch (String(row.type || "")) {
  case "PullRequest": return "󰘭"
  case "Issue": return "󰀦"
  case "Release": return "󰓹"
  case "Discussion": return "󰭹"
  case "Commit": return "󰜘"
  case "CheckSuite": return "󰙨"
  default: return "󰂚"
  }
}

// Which palette role the glyph takes: urgent for anything red, accent for
// approved, foreground otherwise.
function rowTone(row) {
  if (!row) return "normal"
  if (row.kind === "pull") {
    if (row.draft) return "muted"
    if (ciFailed(row) || changesRequested(row)) return "urgent"
    if (String(row.review || "").toUpperCase() === "APPROVED") return "accent"
    if (ciPending(row)) return "muted"
    return "normal"
  }
  if (row.kind === "notification") {
    var reason = String(row.reason || "")
    if (reason === "review_requested" || reason === "ci_activity") return "urgent"
    if (reason === "mention" || reason === "assign") return "accent"
  }
  return "normal"
}

function rowStatus(row) {
  if (!row) return ""
  if (row.kind === "pull") {
    var bits = []
    if (row.draft) bits.push("draft")
    var ci = String(row.ci || "").toUpperCase()
    if (ci === "SUCCESS") bits.push("checks passed")
    else if (ciFailed(row)) bits.push("checks failed")
    else if (ciPending(row)) bits.push("checks running")
    var review = String(row.review || "").toUpperCase()
    if (review === "APPROVED") bits.push("approved")
    else if (review === "CHANGES_REQUESTED") bits.push("changes requested")
    else if (review === "REVIEW_REQUIRED") bits.push("review required")
    return bits.join(" · ")
  }
  if (row.kind === "notification") return reasonLabel(row.reason)
  return ""
}

function reasonLabel(reason) {
  switch (String(reason || "")) {
  case "review_requested": return "review requested"
  case "mention": return "mentioned you"
  case "team_mention": return "team mentioned"
  case "assign": return "assigned to you"
  case "author": return "your thread"
  case "comment": return "new comment"
  case "ci_activity": return "workflow run"
  case "subscribed": return "subscribed"
  case "state_change": return "state changed"
  case "security_alert": return "security alert"
  default: return String(reason || "").replace(/_/g, " ")
  }
}

// Repo without the owner when it is one of the viewer's own; keeps rows short.
function repoLabel(row, login) {
  var repo = String(row && row.repo || "")
  if (login && repo.indexOf(login + "/") === 0) return repo.slice(login.length + 1)
  return repo
}

function rowTitle(row, login) {
  if (!row) return ""
  var ref = repoLabel(row, login)
  if (row.number) ref += "#" + row.number
  return ref
}

function formatAge(iso) {
  var t = Date.parse(String(iso || ""))
  if (!isFinite(t)) return ""
  var s = Math.max(0, (Date.now() - t) / 1000)
  if (s < 60) return "now"
  if (s < 3600) return Math.floor(s / 60) + "m"
  if (s < 86400) return Math.floor(s / 3600) + "h"
  if (s < 86400 * 30) return Math.floor(s / 86400) + "d"
  if (s < 86400 * 365) return Math.floor(s / (86400 * 30)) + "mo"
  return Math.floor(s / (86400 * 365)) + "y"
}

function formatFetched(fetchedAt) {
  var t = Number(fetchedAt)
  if (!isFinite(t) || t <= 0) return ""
  var age = formatAge(new Date(t * 1000).toISOString())
  return age === "now" ? "updated just now" : "updated " + age + " ago"
}

// Flatten the visible sections into one list of rows (with header markers)
// so the keyboard cursor can walk the whole popup with one index.
function visibleRows(snapshot, settings) {
  var out = []
  if (!isOk(snapshot)) return out
  for (var i = 0; i < SECTIONS.length; i++) {
    var sec = SECTIONS[i]
    if (settings && settings[sec.setting] === false) continue
    var data = section(snapshot, sec.key)
    if (data.items.length === 0) continue
    out.push({ header: true, key: sec.key, title: sec.title, total: data.total, shown: data.items.length })
    for (var j = 0; j < data.items.length; j++) out.push(data.items[j])
  }
  return out
}

function isHeader(row) {
  return !!row && row.header === true
}

function nextRowIndex(rows, current, delta) {
  if (!rows || rows.length === 0) return -1
  var n = rows.length
  var idx = current
  for (var step = 0; step < n; step++) {
    idx = ((idx + delta) % n + n) % n
    if (!isHeader(rows[idx])) return idx
  }
  return -1
}

function firstRowIndex(rows) {
  return nextRowIndex(rows, -1, 1)
}
