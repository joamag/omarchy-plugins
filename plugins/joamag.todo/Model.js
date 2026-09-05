.pragma library

// Pure helpers for the to-do widget: parsing todo.sh's listing, the order
// tasks are shown in, tags, ages, and the strings the bar label, tooltip and
// popup share.

var ICON = "󰄵"

var GLYPHS = {
  pending: "󰄱",
  done: "󰄵"
}

// The priorities the popup cycles through with `p`; anything else a hand
// edit puts in the file is shown as it is.
var PRIORITIES = ["A", "B", "C"]

function num(value) {
  if (value === null || value === undefined || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

// todo.sh emits "file<TAB>path" then one "task<TAB>line<TAB>done<TAB>
// priority<TAB>created<TAB>completed<TAB>text" per task, or "error<TAB>msg".
function parseSnapshot(raw) {
  var out = { file: "", error: "", tasks: [] }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var parts = line.split("\t")
    if (parts[0] === "file") {
      out.file = parts.slice(1).join("\t")
    } else if (parts[0] === "error") {
      out.error = parts.slice(1).join("\t")
    } else if (parts[0] === "task") {
      if (parts.length < 7) continue
      var text = parts.slice(6).join("\t")
      var found = tags(text)
      out.tasks.push({
        kind: "task",
        key: "task:" + parts[1],
        line: num(parts[1]),
        done: parts[2] === "1",
        priority: parts[3],
        created: parts[4],
        completed: parts[5],
        text: text,
        title: stripTags(text),
        projects: found.projects,
        contexts: found.contexts
      })
    }
  }
  out.tasks.sort(compareTasks)
  return out
}

// +project and @context words, wherever they sit in the task.
function tags(text) {
  var projects = []
  var contexts = []
  var words = String(text || "").split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    var w = words[i]
    if (w.length > 1 && w.charAt(0) === "+" && projects.indexOf(w.slice(1)) < 0) projects.push(w.slice(1))
    else if (w.length > 1 && w.charAt(0) === "@" && contexts.indexOf(w.slice(1)) < 0) contexts.push(w.slice(1))
  }
  return { projects: projects, contexts: contexts }
}

// The task without its tags and key:value pairs, for the row title; the
// tags go on the detail line instead.
function stripTags(text) {
  var words = String(text || "").split(/\s+/)
  var kept = []
  for (var i = 0; i < words.length; i++) {
    var w = words[i]
    if (w.length > 1 && (w.charAt(0) === "+" || w.charAt(0) === "@")) continue
    if (/^[A-Za-z]+:[^\s]+$/.test(w)) continue
    if (w !== "") kept.push(w)
  }
  return kept.join(" ")
}

function priorityRank(priority) {
  var p = String(priority || "")
  return p === "" ? 27 : p.charCodeAt(0) - 64
}

// Pending before done. Pending by priority then file order, so a new task
// lands at the bottom of its band; done by completion date, newest first.
function compareTasks(a, b) {
  if (a.done !== b.done) return a.done ? 1 : -1
  if (!a.done) {
    var ra = priorityRank(a.priority)
    var rb = priorityRank(b.priority)
    if (ra !== rb) return ra - rb
    return a.line - b.line
  }
  var ca = String(a.completed || "")
  var cb = String(b.completed || "")
  if (ca !== cb) return ca < cb ? 1 : -1
  return b.line - a.line
}

function isLoaded(snapshot) {
  return !!snapshot && Array.isArray(snapshot.tasks)
}

function counts(snapshot) {
  var c = { pending: 0, done: 0, urgent: 0 }
  if (!isLoaded(snapshot)) return c
  for (var i = 0; i < snapshot.tasks.length; i++) {
    var t = snapshot.tasks[i]
    if (t.done) c.done++
    else {
      c.pending++
      if (t.priority === "A") c.urgent++
    }
  }
  return c
}

function glyph(task) {
  return task && task.done ? GLYPHS.done : GLYPHS.pending
}

// How the priority colours the row: A is urgent, B gets the accent, the
// rest are plain.
function priorityTone(task) {
  if (!task || task.done) return "normal"
  if (task.priority === "A") return "urgent"
  if (task.priority === "B") return "accent"
  return "normal"
}

// The next priority `p` moves to: none, A, B, C, none again. A priority
// outside that ring (a hand-edited D) drops to none.
function nextPriority(priority) {
  var idx = PRIORITIES.indexOf(String(priority || ""))
  if (idx < 0) return priority ? "" : PRIORITIES[0]
  return idx + 1 < PRIORITIES.length ? PRIORITIES[idx + 1] : ""
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

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

// "today", "yesterday", "3d", "2w", or the date once it is far enough back.
function formatAge(iso, today) {
  var d = parseDay(iso)
  if (!d) return ""
  var now = parseDay(today || todayIso())
  var days = Math.round((now - d) / 86400000)
  if (days <= 0) return "today"
  if (days === 1) return "yesterday"
  if (days < 14) return days + "d"
  if (days < 60) return Math.floor(days / 7) + "w"
  return d.getDate() + " " + MONTHS[d.getMonth()]
}

function taskDetail(task, today) {
  if (!task) return ""
  var parts = []
  for (var i = 0; i < task.projects.length; i++) parts.push("+" + task.projects[i])
  for (var j = 0; j < task.contexts.length; j++) parts.push("@" + task.contexts[j])
  if (task.done) {
    var doneAge = formatAge(task.completed, today)
    parts.push(doneAge ? "done " + doneAge : "done")
  } else {
    var age = formatAge(task.created, today)
    if (age && age !== "today") parts.push("added " + age)
  }
  return parts.join(" · ")
}

// Text on the bar button: the count still to do, or the icon alone.
function barText(snapshot, mode, vertical) {
  if (vertical || !isLoaded(snapshot) || mode === "none") return ICON
  var c = counts(snapshot)
  if (c.pending === 0) return ICON
  return ICON + " " + c.pending
}

function tooltip(snapshot) {
  if (!isLoaded(snapshot)) return "To do"
  if (snapshot.error) return "To do: " + snapshot.error
  var c = counts(snapshot)
  if (c.pending === 0 && c.done === 0) return "To do · nothing yet"
  var parts = [c.pending + " to do"]
  if (c.urgent > 0) parts.push(c.urgent + " urgent")
  if (c.done > 0) parts.push(c.done + " done")
  return "To do · " + parts.join(" · ")
}

function heroStatus(snapshot) {
  if (!isLoaded(snapshot)) return "LOADING"
  var c = counts(snapshot)
  if (c.pending === 0 && c.done === 0) return "NOTHING YET"
  if (c.pending === 0) return "ALL DONE"
  var parts = [c.pending + " LEFT"]
  if (c.urgent > 0) parts.push(c.urgent + " URGENT")
  return parts.join(" · ")
}

// The popup list: a TO DO group, then a DONE group holding at most doneLimit
// of the most recent ticks, each under a header so the keyboard cursor can
// walk everything with one index.
function visibleRows(snapshot, doneLimit) {
  var out = []
  if (!isLoaded(snapshot)) return out
  var pending = []
  var done = []
  for (var i = 0; i < snapshot.tasks.length; i++) (snapshot.tasks[i].done ? done : pending).push(snapshot.tasks[i])
  var limit = num(doneLimit)
  if (!isFinite(limit) || limit < 0) limit = 5
  if (pending.length > 0) {
    out.push({ header: true, key: "pending", title: "TO DO", count: pending.length })
    for (var p = 0; p < pending.length; p++) out.push(pending[p])
  }
  if (done.length > 0 && limit > 0) {
    var shown = Math.min(limit, done.length)
    out.push({ header: true, key: "done", title: "DONE", count: done.length, shown: shown })
    for (var d = 0; d < shown; d++) out.push(done[d])
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
