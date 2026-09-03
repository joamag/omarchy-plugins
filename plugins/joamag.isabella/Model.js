.pragma library

// Pure helpers for the Isabella widget: envelope parsing, the flattened row
// list (pending first, done and cancelled after), counts and formatting.

var ICON = "󰃢"

var GLYPHS = {
  pending: "󰄱",
  done: "󰄵",
  cancelled: "󰅚",
  overdue: "󰗎"
}

function parseResult(raw) {
  try {
    var obj = JSON.parse(String(raw || "").trim())
    if (obj && typeof obj === "object" && obj.state) return obj
  } catch (e) {
    // fall through
  }
  return { state: "error", error: "Isabella returned no data" }
}

function hasDay(result) {
  return !!result && !!result.day && Array.isArray(result.day.sections)
}

function isOk(result) {
  return !!result && result.state === "ok" && hasDay(result)
}

// Every task of the day as a flat list, each carrying its section name.
function tasks(result) {
  var out = []
  if (!hasDay(result)) return out
  var sections = result.day.sections
  for (var i = 0; i < sections.length; i++) {
    var rows = sections[i].rows || []
    for (var j = 0; j < rows.length; j++) {
      var row = rows[j]
      out.push({
        kind: "task",
        id: row.id,
        key: "task:" + row.id,
        name: String(row.name || ""),
        minutes: Number(row.minutes) || 0,
        checked: row.checked === true,
        cancelled: row.cancelled === true,
        overBudget: row.over_budget === true,
        notes: row.notes || "",
        playbook: row.playbook || "",
        from: row.from || "",
        section: String(sections[i].name || ""),
        subtasks: Array.isArray(row.subtasks) ? row.subtasks : []
      })
    }
  }
  return out
}

function counts(result) {
  var all = tasks(result)
  var c = { total: 0, done: 0, pending: 0, cancelled: 0, overdue: 0, pendingMinutes: 0 }
  for (var i = 0; i < all.length; i++) {
    var t = all[i]
    if (t.cancelled) { c.cancelled++; continue }
    c.total++
    if (t.checked) c.done++
    else {
      c.pending++
      c.pendingMinutes += t.minutes
      if (t.from) c.overdue++
    }
  }
  return c
}

function status(task) {
  if (!task) return "pending"
  if (task.cancelled) return "cancelled"
  if (task.checked) return "done"
  return task.from ? "overdue" : "pending"
}

function glyph(task) {
  return GLYPHS[status(task)] || GLYPHS.pending
}

function subtaskGlyph(subtask, parent) {
  if (parent && parent.cancelled) return GLYPHS.cancelled
  return subtask && subtask.checked ? GLYPHS.done : GLYPHS.pending
}

// The popup list: a TO DO group with overdue tasks first, then a DONE group
// holding ticked and cancelled tasks. Subtasks follow their parent as
// indented rows so they can be ticked one by one.
function visibleRows(result) {
  var out = []
  if (!hasDay(result)) return out
  var all = tasks(result)
  var pending = []
  var finished = []
  for (var i = 0; i < all.length; i++) {
    var t = all[i]
    if (t.checked || t.cancelled) finished.push(t)
    else pending.push(t)
  }
  pending.sort(function(a, b) {
    var oa = a.from ? 0 : 1
    var ob = b.from ? 0 : 1
    return oa - ob
  })
  finished.sort(function(a, b) {
    var ca = a.cancelled ? 1 : 0
    var cb = b.cancelled ? 1 : 0
    return ca - cb
  })
  var groups = [
    { key: "pending", title: "TO DO", items: pending },
    { key: "done", title: "DONE", items: finished }
  ]
  for (var g = 0; g < groups.length; g++) {
    var group = groups[g]
    if (group.items.length === 0) continue
    out.push({ header: true, key: group.key, title: group.title, count: group.items.length })
    for (var j = 0; j < group.items.length; j++) {
      var task = group.items[j]
      out.push(task)
      for (var k = 0; k < task.subtasks.length; k++) {
        var sub = task.subtasks[k]
        out.push({
          kind: "subtask",
          id: sub.id,
          key: "sub:" + sub.id,
          name: String(sub.name || ""),
          minutes: Number(sub.minutes) || 0,
          checked: sub.checked === true,
          cancelled: task.cancelled,
          notes: sub.notes || "",
          parent: task
        })
      }
    }
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

function formatMinutes(minutes) {
  var n = Math.max(0, Math.round(Number(minutes) || 0))
  if (n < 60) return n + "m"
  var h = Math.floor(n / 60)
  var m = n % 60
  return m === 0 ? h + "h" : h + "h " + m + "m"
}

function budgetLine(result) {
  if (!hasDay(result) || !result.day.budget) return ""
  var b = result.day.budget
  return formatMinutes(b.estimated) + " of " + formatMinutes(b.minutes) + " budget"
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

function parseDay(iso) {
  var m = String(iso || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return null
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
}

function todayIso() {
  var d = new Date()
  var mm = d.getMonth() + 1
  var dd = d.getDate()
  return d.getFullYear() + "-" + (mm < 10 ? "0" : "") + mm + "-" + (dd < 10 ? "0" : "") + dd
}

// "Today · Thursday 4 Sep", "Tomorrow · Friday 5 Sep", "Wednesday 3 Sep".
function dayLabel(iso) {
  var d = parseDay(iso)
  if (!d) return String(iso || "")
  var today = parseDay(todayIso())
  var diff = Math.round((d - today) / 86400000)
  var text = DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
  if (diff === 0) return "Today · " + text
  if (diff === 1) return "Tomorrow · " + text
  if (diff === -1) return "Yesterday · " + text
  return text
}

function shortDay(iso) {
  var d = parseDay(iso)
  return d ? d.getDate() + " " + MONTHS[d.getMonth()] : String(iso || "")
}

function rowDetail(row) {
  if (!row || isHeader(row)) return ""
  var parts = []
  if (row.kind === "task") {
    if (row.from) parts.push("since " + shortDay(row.from))
    if (row.section && row.section !== "Overdue" && row.section !== "Scheduled") parts.push(row.section)
    if (row.subtasks && row.subtasks.length > 0) {
      var done = 0
      for (var i = 0; i < row.subtasks.length; i++) if (row.subtasks[i].checked) done++
      parts.push(done + "/" + row.subtasks.length + " steps")
    }
    if (row.overBudget) parts.push("over budget")
    if (row.cancelled) parts.push("cancelled today")
  }
  if (row.notes) parts.push(row.notes)
  return parts.join(" · ")
}

function barText(result, mode, vertical) {
  if (vertical || !isOk(result) || mode === "none") return ICON
  var c = counts(result)
  if (c.total === 0) return ICON
  switch (mode) {
  case "pending": return ICON + " " + c.pending
  case "done": return ICON + " " + c.done + "/" + c.total
  default: return ICON + " " + c.pending + " 󰄬" + c.done
  }
}

function tooltip(result) {
  if (!result) return "Isabella"
  switch (result.state) {
  case "unconfigured": return "Isabella: credentials missing"
  case "unauthorized": return "Isabella: login refused"
  case "unreachable": return "Isabella unreachable" + (hasDay(result) ? " · showing cached tasks" : "")
  case "error": return "Isabella: " + (result.error || "request failed")
  }
  var c = counts(result)
  if (c.total === 0) return "Isabella · nothing scheduled"
  var parts = [c.pending + " pending", c.done + " done"]
  if (c.overdue > 0) parts.push(c.overdue + " overdue")
  return "Isabella · " + parts.join(" · ")
}

function stateTitle(result) {
  switch (result ? result.state : "") {
  case "unconfigured": return "Isabella is not configured"
  case "unauthorized": return "Isabella refused the login"
  case "unreachable": return "Isabella is unreachable"
  case "error": return "Isabella request failed"
  default: return "Loading Isabella"
  }
}

function stateDetail(result) {
  switch (result ? result.state : "") {
  case "unconfigured":
    return "Fill in " + (result.file || "~/.config/omarchy/isabella.env") + " with ISABELLA_URL, ISABELLA_USERNAME and ISABELLA_PASSWORD" + (result.missing ? " (missing: " + result.missing.join(", ") + ")" : "") + "."
  case "unauthorized": return "Check the username and password in ~/.config/omarchy/isabella.env."
  case "unreachable": return (result.error || "No response") + (hasDay(result) ? ". Showing the last checklist that was fetched." : "")
  case "error": return result.error || ""
  default: return ""
  }
}

function heroStatus(result) {
  if (!result) return "LOADING"
  if (!hasDay(result)) return String(result.state).toUpperCase()
  var c = counts(result)
  var parts = []
  if (c.total === 0) parts.push("NOTHING SCHEDULED")
  else if (c.pending === 0) parts.push("ALL DONE")
  else parts.push(c.pending + " LEFT · " + formatMinutes(c.pendingMinutes))
  if (c.overdue > 0) parts.push(c.overdue + " OVERDUE")
  if (result.state === "unreachable") parts.push("CACHED")
  return parts.join(" · ")
}
