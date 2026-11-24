.pragma library

// Pure helpers for the files widget: paths and places, tabs and their
// history, listing order and the on-screen filter, kinds and formatting,
// selection, name conflicts, and parsing what files.sh prints.

var ICON = "󰉋"
// Locations that are not folders on disk.
var RECENT = "recent:"
var TRASH = "trash:"
var MAX_TABS = 12

var VIEWS = [
  { key: "list", label: "List", icon: "󰉹" },
  { key: "grid", label: "Grid", icon: "󰕰" },
  { key: "columns", label: "Columns", icon: "󰕴" }
]

var SORT_KEYS = [
  { key: "name", label: "Name" },
  { key: "modified", label: "Modified" },
  { key: "size", label: "Size" },
  { key: "type", label: "Type" }
]

var PLACE_LABELS = { home: "Home", desktop: "Desktop", documents: "Documents", downloads: "Downloads", music: "Music", pictures: "Pictures", videos: "Videos" }
var PLACE_ICONS = { home: "󰋜", desktop: "󰍹", documents: "󰈙", downloads: "󰇚", music: "󰎇", pictures: "󰋩", videos: "󰕧" }
var GLYPHS = {
  recent: "󰋚",
  trash: "󰩹",
  bookmark: "󰃀",
  drive: "󰋊",
  removable: "󱊞",
  eject: "󰇪",
  hiddenShown: "󰈈",
  hiddenHidden: "󰈉"
}

var EXTENSIONS = {
  png: "image", jpg: "image", jpeg: "image", gif: "image", webp: "image", bmp: "image", svg: "image", avif: "image", heic: "image", tif: "image", tiff: "image", ico: "image",
  mp4: "video", mkv: "video", webm: "video", mov: "video", avi: "video", m4v: "video",
  mp3: "audio", flac: "audio", ogg: "audio", opus: "audio", wav: "audio", m4a: "audio", aac: "audio",
  pdf: "pdf",
  txt: "text", md: "text", log: "text", csv: "text", conf: "text", ini: "text", toml: "text", yml: "text", yaml: "text", json: "text", xml: "text",
  js: "code", ts: "code", qml: "code", py: "code", sh: "code", rs: "code", go: "code", c: "code", h: "code", cpp: "code", rb: "code", lua: "code", java: "code", css: "code", html: "code",
  zip: "archive", tar: "archive", gz: "archive", tgz: "archive", xz: "archive", zst: "archive", bz2: "archive", "7z": "archive", rar: "archive",
  iso: "disc", img: "disc",
  xlsx: "sheet", xls: "sheet", ods: "sheet",
  docx: "document", doc: "document", odt: "document", rtf: "document",
  pptx: "slides", ppt: "slides", odp: "slides"
}

var KIND_ICONS = {
  dir: "󰉋", image: "󰈟", video: "󰈫", audio: "󰈣", pdf: "󰈦", text: "󰈙", code: "󰈮",
  archive: "󰗄", disc: "󰆜", sheet: "󰈛", document: "󰈬", slides: "󰈧", file: "󰈔"
}

var KIND_LABELS = {
  image: "Image", video: "Video", audio: "Audio", pdf: "PDF document", text: "Text", code: "Source code", archive: "Archive",
  disc: "Disk image", sheet: "Spreadsheet", document: "Document", slides: "Presentation", file: "File"
}

// A finer type name for the text and code files people open most.
var TYPE_LABELS = {
  md: "Markdown", txt: "Plain text", json: "JSON", yml: "YAML", yaml: "YAML", toml: "TOML", csv: "CSV", xml: "XML", log: "Log",
  js: "JavaScript", ts: "TypeScript", qml: "QML", py: "Python", sh: "Shell script", rs: "Rust", go: "Go", lua: "Lua", html: "HTML", css: "CSS"
}

// Formats Qt's image reader decodes, so the grid and the preview can show
// the picture itself.
var THUMBNAIL_EXTENSIONS = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"]

// `g` then one of these jumps there; bookmarks and drives take the digits.
var GO_KEYS = [
  { key: "h", place: "home" },
  { key: "k", place: "desktop" },
  { key: "D", place: "documents" },
  { key: "d", place: "downloads" },
  { key: "m", place: "music" },
  { key: "p", place: "pictures" },
  { key: "v", place: "videos" },
  { key: "r", path: RECENT },
  { key: "t", path: TRASH },
  { key: "/", path: "/" }
]

var HINTS = {
  browse: [
    { key: "j/k", label: "move" }, { key: "l", label: "open" }, { key: "h", label: "up" }, { key: "Space", label: "select" },
    { key: "y", label: "copy" }, { key: "x", label: "cut" }, { key: "p", label: "paste" }, { key: "r", label: "rename" },
    { key: "a", label: "folder" }, { key: "d", label: "trash" }, { key: "o", label: "open with" }, { key: "/", label: "filter" },
    { key: "g", label: "go to" }, { key: "w", label: "window" }, { key: "?", label: "keys" }
  ],
  trash: [
    { key: "j/k", label: "move" }, { key: "Enter", label: "restore" }, { key: "Space", label: "select" },
    { key: "Delete", label: "delete for good" }, { key: "g", label: "go to" }, { key: "?", label: "keys" }
  ],
  filter: [{ key: "type", label: "to filter" }, { key: "Enter", label: "search below" }, { key: "↓", label: "to the results" }, { key: "Esc", label: "clear" }],
  rename: [{ key: "Enter", label: "rename" }, { key: "Esc", label: "cancel" }],
  path: [{ key: "Enter", label: "go" }, { key: "Tab", label: "complete" }, { key: "Esc", label: "cancel" }]
}

// Every key, for the `?` sheet: the panel keys of the other widgets and the
// Nautilus shortcuts side by side.
var KEYS = [
  ["j k  ↓ ↑", "Move"], ["J K  Shift+↓ ↑", "Extend the selection"], ["l  Enter", "Open"], ["h  Backspace  Alt+↑", "Up a folder"],
  ["Alt+← Alt+→", "Back, forward"], ["Space  Ctrl+click", "Select"], ["Ctrl+A", "Select all"], ["y  Ctrl+C", "Copy"],
  ["x  Ctrl+X", "Cut"], ["p  Ctrl+V", "Paste"], ["r  F2", "Rename"], ["a  Ctrl+Shift+N", "New folder"],
  ["n", "New file"], ["d  Delete", "Move to Trash"], ["Ctrl+Z", "Undo the move to Trash"], ["Shift+Delete", "Delete for good"],
  ["o", "Open with"],
  ["/  Ctrl+F", "Filter, Enter searches below"], ["g", "Go to a place"], ["e  Ctrl+L", "Type a path"], ["t  Ctrl+T", "New tab"],
  ["q  Ctrl+W", "Close the tab"], ["[ ]  Ctrl+Tab", "Previous, next tab"], ["1-9", "Go to a tab"], ["v  Ctrl+1 2 3", "List, grid, columns"],
  [".  Ctrl+H", "Hidden files"], ["i", "Preview pane"], ["s", "Sort by the next column"], ["Ctrl+D", "Bookmark the folder"],
  ["w", "Pop out or dock"], ["N", "Open in Nautilus"], ["Esc", "Clear, then close"], ["Tab", "Next widget"]
]

function num(value) {
  // Number(null) is 0; a missing field must stay unknown rather than zero.
  if (value === null || value === undefined || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

// ---------- Paths ----------

// Collapses repeated slashes, "." and ".." and the trailing slash, so two
// spellings of a folder compare equal. Relative input stays relative.
function normalizePath(path) {
  var text = String(path || "")
  if (text === "") return ""
  var absolute = text.charAt(0) === "/"
  var out = []
  var parts = text.split("/")
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i]
    if (part === "" || part === ".") continue
    if (part === "..") {
      if (out.length > 0 && out[out.length - 1] !== "..") out.pop()
      else if (!absolute) out.push("..")
      continue
    }
    out.push(part)
  }
  return (absolute ? "/" : "") + out.join("/") || (absolute ? "/" : ".")
}

// What the path field accepts: ~ and ~/ for home, a file:// URL, a path
// relative to the folder on screen, or an absolute path.
function expandPath(text, home, base) {
  var value = String(text || "").trim()
  if (value === "") return ""
  if (value === RECENT || value === TRASH) return value
  if (value.indexOf("file://") === 0) return urlToPath(value)
  if (value === "~" || value.indexOf("~/") === 0) value = String(home || "") + value.slice(1)
  else if (value.charAt(0) !== "/") value = String(base || home || "") + "/" + value
  return normalizePath(value)
}

function isVirtual(path) {
  return path === RECENT || path === TRASH
}

function isUnder(path, root) {
  var p = String(path || "")
  var r = String(root || "")
  if (p === "" || r === "" || isVirtual(p) || isVirtual(r)) return p === r && p !== ""
  if (p === r) return true
  return p.indexOf(r === "/" ? "/" : r + "/") === 0
}

// "" when there is nothing above: the root, or Recent and Trash.
function parentPath(path) {
  var p = String(path || "")
  if (p === "" || p === "/" || isVirtual(p)) return ""
  var idx = p.lastIndexOf("/")
  if (idx < 0) return ""
  return idx === 0 ? "/" : p.slice(0, idx)
}

function baseName(path) {
  var p = String(path || "")
  if (p === "/") return "/"
  var idx = p.lastIndexOf("/")
  return idx < 0 ? p : p.slice(idx + 1)
}

function joinPath(dir, name) {
  var d = String(dir || "")
  return (d === "/" ? "" : d) + "/" + String(name || "")
}

function prettyPath(path, home) {
  var p = String(path || "")
  var h = String(home || "")
  if (h !== "" && p === h) return "~"
  if (h !== "" && p.indexOf(h + "/") === 0) return "~" + p.slice(h.length)
  return p
}

function fileUrl(path) {
  return "file://" + String(path || "").split("/").map(encodeURIComponent).join("/")
}

// Drops and the path field hand over file:// URLs; anything else is not a
// local file and becomes "".
function urlToPath(url) {
  var text = String(url || "")
  if (text.indexOf("file://") !== 0) return ""
  var rest = text.slice(7)
  // file://host/path: only the local host (or none) is a local file.
  var slash = rest.indexOf("/")
  if (slash < 0) return ""
  var host = rest.slice(0, slash)
  if (host !== "" && host !== "localhost") return ""
  try {
    return normalizePath(decodeURIComponent(rest.slice(slash)))
  } catch (e) {
    return ""
  }
}

// text/uri-list body for a drag out to another app.
function uriList(paths) {
  var out = []
  for (var i = 0; i < (paths || []).length; i++) out.push(fileUrl(paths[i]))
  return out.length > 0 ? out.join("\r\n") + "\r\n" : ""
}

// ---------- Places ----------

// files.sh places: standard folders, bookmarks, drives and the trash count.
function parsePlaces(raw) {
  var out = { places: [], bookmarks: [], drives: [], trashCount: 0 }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    switch (parts[0]) {
    case "place":
      if (parts.length < 3 || parts[2] === "") continue
      out.places.push({ key: parts[1], label: PLACE_LABELS[parts[1]] || baseName(parts[2]), icon: PLACE_ICONS[parts[1]] || KIND_ICONS.dir, path: parts[2] })
      break
    case "bookmark":
      if (parts.length < 2 || parts[1] === "") continue
      out.bookmarks.push({ path: parts[1], label: parts[2] ? parts[2] : baseName(parts[1]) })
      break
    case "drive":
      if (parts.length < 7) continue
      var drive = { mount: parts[1], device: parts[2], label: parts[3], size: num(parts[4]), avail: num(parts[5]), removable: parts[6] === "1" }
      drive.key = "drive:" + (drive.device || drive.mount)
      drive.name = driveLabel(drive)
      out.drives.push(drive)
      break
    case "trash":
      out.trashCount = num(parts[1]) || 0
      break
    }
  }
  return out
}

// The filesystem label, "System" for the root, or the device name: a mount
// point named after a UUID tells nobody anything.
function driveLabel(drive) {
  if (!drive) return ""
  if (drive.label) return String(drive.label)
  if (drive.mount === "/") return "System"
  var device = baseName(drive.device || "")
  return device !== "" ? device : baseName(drive.mount || "")
}

// The mounted drive holding PATH: the deepest mount point above it.
function driveFor(path, drives) {
  var best = null
  for (var i = 0; i < (drives || []).length; i++) {
    var d = drives[i]
    if (!d.mount || !isUnder(path, d.mount)) continue
    if (!best || d.mount.length > best.mount.length) best = d
  }
  return best
}

function placeFor(path, places) {
  for (var i = 0; i < (places || []).length; i++) if (places[i].path === path) return places[i]
  return null
}

function placeLabel(path, home, places, drives) {
  if (path === TRASH) return "Trash"
  if (path === RECENT) return "Recent"
  var place = placeFor(path, places)
  if (place) return place.label
  if (path === home) return "Home"
  for (var i = 0; i < (drives || []).length; i++) if (drives[i].mount === path) return drives[i].name || driveLabel(drives[i])
  if (path === "/") return "System"
  return baseName(path)
}

function placeIcon(path, home, places, drives) {
  if (path === TRASH) return GLYPHS.trash
  if (path === RECENT) return GLYPHS.recent
  var place = placeFor(path, places)
  if (place) return place.icon
  if (path === home) return PLACE_ICONS.home
  for (var i = 0; i < (drives || []).length; i++) if (drives[i].mount === path) return drives[i].removable ? GLYPHS.removable : GLYPHS.drive
  if (path === "/") return GLYPHS.drive
  return KIND_ICONS.dir
}

// Path bar segments from the nearest root the user thinks in: home, a
// drive, or the system root. The columns view shows one column per segment.
function crumbs(path, home, drives) {
  if (isVirtual(path)) return [{ label: placeLabel(path, home, [], drives), path: path }]
  var p = normalizePath(path)
  var root = "/"
  var drive = driveFor(p, drives)
  if (home && isUnder(p, home) && !(drive && drive.mount !== "/" && isUnder(drive.mount, home))) root = home
  else if (drive) root = drive.mount
  var out = [{ label: placeLabel(root, home, [], drives), path: root }]
  if (p === root) return out
  var rest = p.slice(root === "/" ? 1 : root.length + 1).split("/")
  var current = root
  for (var i = 0; i < rest.length; i++) {
    current = joinPath(current, rest[i])
    out.push({ label: rest[i], path: current })
  }
  return out
}

// The `g` menu: standard folders by their letter, Recent, Trash and the
// system root, then bookmarks and mounted drives on the digits.
function goTargets(places, bookmarks, drives) {
  var out = []
  for (var i = 0; i < GO_KEYS.length; i++) {
    var g = GO_KEYS[i]
    if (g.place) {
      var place = null
      for (var j = 0; j < (places || []).length; j++) if (places[j].key === g.place) place = places[j]
      if (place) out.push({ key: g.key, label: place.label, path: place.path, icon: place.icon })
    } else {
      out.push({ key: g.key, label: g.path === "/" ? "System" : placeLabel(g.path, "", [], []), path: g.path, icon: g.path === "/" ? GLYPHS.drive : placeIcon(g.path, "", [], []) })
    }
  }
  var digit = 1
  for (var b = 0; b < (bookmarks || []).length && digit <= 9; b++, digit++) out.push({ key: String(digit), label: bookmarks[b].label, path: bookmarks[b].path, icon: GLYPHS.bookmark })
  for (var d = 0; d < (drives || []).length && digit <= 9; d++) {
    if (!drives[d].mount || drives[d].mount === "/") continue
    out.push({ key: String(digit), label: drives[d].name || driveLabel(drives[d]), path: drives[d].mount, icon: drives[d].removable ? GLYPHS.removable : GLYPHS.drive })
    digit++
  }
  return out
}

// ---------- Tabs ----------

function normalizeView(key) {
  for (var i = 0; i < VIEWS.length; i++) if (VIEWS[i].key === key) return key
  return "list"
}

function newTab(path, view) {
  return { path: path, view: normalizeView(view), history: [path], pos: 0 }
}

// The saved tabs on the widget's shell.json entry: a list of { path, view }
// (or bare paths). Unknown entries are dropped; an empty list opens home.
function parseTabs(value, home) {
  var list = value
  if (typeof list === "string") {
    try { list = JSON.parse(list) } catch (e) { list = [] }
  }
  var out = []
  if (Array.isArray(list)) {
    for (var i = 0; i < list.length && out.length < MAX_TABS; i++) {
      var item = list[i]
      var path = typeof item === "string" ? item : (item && item.path)
      if (typeof path !== "string" || path === "") continue
      path = isVirtual(path) ? path : normalizePath(path)
      if (!isVirtual(path) && path.charAt(0) !== "/") continue
      out.push(newTab(path, item && item.view))
    }
  }
  if (out.length === 0) out.push(newTab(home || "/", "list"))
  return out
}

function serializeTabs(tabs) {
  var out = []
  for (var i = 0; i < (tabs || []).length; i++) out.push({ path: tabs[i].path, view: tabs[i].view })
  return out
}

// Going somewhere drops the forward history, the way a browser does.
function navigateTab(tab, path) {
  if (!tab || !path || path === tab.path) return tab
  var history = tab.history.slice(0, tab.pos + 1)
  history.push(path)
  return { path: path, view: tab.view, history: history, pos: history.length - 1 }
}

function canGoBack(tab) {
  return !!tab && tab.pos > 0
}

function canGoForward(tab) {
  return !!tab && tab.pos < tab.history.length - 1
}

function tabBack(tab) {
  if (!canGoBack(tab)) return tab
  return { path: tab.history[tab.pos - 1], view: tab.view, history: tab.history, pos: tab.pos - 1 }
}

function tabForward(tab) {
  if (!canGoForward(tab)) return tab
  return { path: tab.history[tab.pos + 1], view: tab.view, history: tab.history, pos: tab.pos + 1 }
}

function withView(tab, view) {
  return { path: tab.path, view: normalizeView(view), history: tab.history, pos: tab.pos }
}

function nextView(view) {
  for (var i = 0; i < VIEWS.length; i++) if (VIEWS[i].key === view) return VIEWS[(i + 1) % VIEWS.length].key
  return "list"
}

function wrapIndex(index, count) {
  if (count <= 0) return 0
  return ((index % count) + count) % count
}

// A new tab lands right after the active one.
function addTab(tabs, active, tab) {
  if (tabs.length >= MAX_TABS) return { tabs: tabs, active: active }
  var next = tabs.slice()
  var at = Math.max(0, Math.min(tabs.length, active + 1))
  next.splice(at, 0, tab)
  return { tabs: next, active: at }
}

// The last tab stays open.
function closeTab(tabs, index, active) {
  if (tabs.length <= 1 || index < 0 || index >= tabs.length) return { tabs: tabs, active: active }
  var next = tabs.slice()
  next.splice(index, 1)
  var nextActive = active
  if (index < active || active >= next.length) nextActive = active - 1
  return { tabs: next, active: Math.max(0, Math.min(next.length - 1, nextActive)) }
}

// A folder that moved or got renamed takes the tabs inside it along; one
// that went away (Trash, delete) sends them to the folder above it, and an
// ejected drive sends them all to TO itself with WHOLE. History would point
// at paths that no longer exist, so it starts over.
function retargetTabs(tabs, from, to, whole) {
  var changed = false
  var out = []
  for (var i = 0; i < (tabs || []).length; i++) {
    var tab = tabs[i]
    if (!isUnder(tab.path, from) || isVirtual(from)) {
      out.push(tab)
      continue
    }
    var path = to ? (whole ? to : to + tab.path.slice(from.length)) : (parentPath(from) || "/")
    out.push(newTab(path, tab.view))
    changed = true
  }
  return changed ? out : tabs
}

// ---------- Listing ----------

function extensionOf(name) {
  var n = String(name || "")
  var idx = n.lastIndexOf(".")
  if (idx <= 0 || idx === n.length - 1) return ""
  return n.slice(idx + 1).toLowerCase()
}

function kindOf(name, dir) {
  if (dir) return "dir"
  return EXTENSIONS[extensionOf(name)] || "file"
}

function typeLabel(entry) {
  if (!entry) return ""
  if (entry.dir) return "Folder"
  var ext = extensionOf(entry.name)
  return typeFor(ext, EXTENSIONS[ext] || "file")
}

function typeFor(ext, kind) {
  if (TYPE_LABELS[ext]) return TYPE_LABELS[ext]
  if (kind === "image" && ext !== "") return ext.toUpperCase() + " image"
  return KIND_LABELS[kind]
}

function kindIcon(kind) {
  return KIND_ICONS[kind] || KIND_ICONS.file
}

function isImage(entry) {
  return !!entry && !entry.dir && THUMBNAIL_EXTENSIONS.indexOf(extensionOf(entry.name)) >= 0
}

// Small text files get their first lines in the preview pane.
function isTextual(entry) {
  if (!entry || entry.dir) return false
  var kind = kindOf(entry.name, false)
  return (kind === "text" || kind === "code" || (kind === "file" && extensionOf(entry.name) === "")) && !(entry.size > 262144)
}

// One row of a listing, from the folder model or a files.sh entry line.
// modified is in milliseconds; size is NaN for folders. The lower-cased
// name, its natural sort key and the type label are worked out once here,
// so sorting and filtering a big folder never redo them per comparison.
function makeEntry(fields) {
  var path = String(fields.path || "")
  var name = fields.name !== undefined ? String(fields.name) : baseName(path)
  var dir = fields.dir === true
  var lower = name.toLowerCase()
  var ext = dir ? "" : extensionOf(name)
  var kind = dir ? "dir" : (EXTENSIONS[ext] || "file")
  return {
    name: name,
    path: path,
    dir: dir,
    size: dir ? NaN : num(fields.size),
    modified: num(fields.modified),
    hidden: name.charAt(0) === ".",
    kind: kind,
    type: dir ? "Folder" : typeFor(ext, kind),
    lower: lower,
    key: /\d/.test(lower) ? naturalKey(lower) : lower,
    origin: fields.origin ? String(fields.origin) : "",
    trashName: fields.trashName ? String(fields.trashName) : ""
  }
}

// files.sh hands times over as seconds since the epoch (search), or as the
// ISO dates the trash and the recent list store: local time, or UTC with a
// trailing Z. Milliseconds, or NaN when it is neither.
function parseTime(value) {
  var text = value === null || value === undefined ? "" : String(value).trim()
  if (text === "") return NaN
  var seconds = Number(text)
  if (isFinite(seconds)) return seconds * 1000
  var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z?)$/.exec(text)
  if (!m) return NaN
  var ms = m[7] ? Math.floor(Number(m[7]) * 1000) : 0
  if (m[8] === "Z") return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]), ms)
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]), ms).getTime()
}

// files.sh recent / trashed / search: entry type size time path origin
// trashname. A trashed item shows under its old name.
function parseEntries(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] !== "entry" || parts.length < 5 || parts[4] === "") continue
    out.push(makeEntry({
      path: parts[4],
      name: parts[5] ? baseName(parts[5]) : undefined,
      dir: parts[1] === "d",
      size: parts[2],
      modified: parseTime(parts[3]),
      origin: parts[5] || "",
      trashName: parts[6] || ""
    }))
  }
  return out
}

var ZEROS = "0000000000000000"

// A number as a fixed-width string, so plain string order is numeric order.
function padNumber(n) {
  var s = String(Math.max(0, Math.floor(n)))
  return s.length >= ZEROS.length ? s : ZEROS.slice(s.length) + s
}

// Natural, case-insensitive order as a plain string: every run of digits
// is padded to one width, so "file2" sorts before "file10".
function naturalKey(text) {
  return String(text || "").toLowerCase().replace(/\d+/g, function(digits) {
    return padNumber(Number(digits))
  })
}

function normalizeSortKey(key) {
  for (var i = 0; i < SORT_KEYS.length; i++) if (SORT_KEYS[i].key === key) return key
  return "name"
}

// Newest and largest first are what people mean by "sort by date / size".
function defaultDescending(key) {
  return key === "modified" || key === "size"
}

// A click on the current column flips it; another column starts in its
// natural direction.
function nextSort(key, descending, clicked) {
  var k = normalizeSortKey(clicked)
  if (k === key) return { key: k, descending: !descending }
  return { key: k, descending: defaultDescending(k) }
}

function cycleSortKey(key) {
  for (var i = 0; i < SORT_KEYS.length; i++) if (SORT_KEYS[i].key === key) return SORT_KEYS[(i + 1) % SORT_KEYS.length].key
  return "name"
}

// The string an entry sorts by for KEY: the column, then the natural name,
// then the raw name so the order is the same every time.
function sortString(entry, key) {
  var primary = ""
  if (key === "modified") primary = padNumber(isFinite(entry.modified) ? entry.modified : 0)
  else if (key === "size") primary = padNumber(isFinite(entry.size) ? entry.size + 1 : 0)
  else if (key === "type") primary = entry.type.toLowerCase()
  return primary + "\u0001" + entry.key + "\u0001" + entry.name
}

// Folders always first, each group in the column's order or its reverse.
// Each entry becomes one string carrying its index, and the engine's own
// sort orders those: a comparator called from JavaScript for every pair is
// what makes a big folder slow to open in the shell.
function sortEntries(list, key, descending) {
  var k = normalizeSortKey(key)
  var items = list || []
  var tagged = []
  for (var i = 0; i < items.length; i++) tagged.push((items[i].dir ? "0" : "1") + sortString(items[i], k) + "\u0001" + i)
  tagged.sort()
  var dirs = []
  var files = []
  for (var j = 0; j < tagged.length; j++) {
    var t = tagged[j]
    var entry = items[Number(t.slice(t.lastIndexOf("\u0001") + 1))]
    if (entry.dir) dirs.push(entry)
    else files.push(entry)
  }
  if (descending) {
    dirs.reverse()
    files.reverse()
  }
  return dirs.concat(files)
}

// The filter typed into the header: a case-insensitive part of the name.
// Hidden files stay out unless they are switched on.
function filterEntries(list, query, showHidden) {
  var needle = String(query || "").toLowerCase()
  var out = []
  for (var i = 0; i < (list || []).length; i++) {
    var e = list[i]
    if (e.hidden && !showHidden) continue
    if (needle !== "" && e.lower.indexOf(needle) < 0) continue
    out.push(e)
  }
  return out
}

// ---------- Formatting ----------

// Decimal units, the way GNOME Files counts.
function formatSize(bytes) {
  var n = num(bytes)
  if (!isFinite(n) || n < 0) return ""
  if (n < 1000) return Math.round(n) + (Math.round(n) === 1 ? " byte" : " bytes")
  var units = ["kB", "MB", "GB", "TB", "PB"]
  var i = -1
  do {
    n /= 1000
    i++
  } while (n >= 999.5 && i < units.length - 1)
  return (n >= 100 ? Math.round(n) : n.toFixed(1)) + " " + units[i]
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// Today's files show the time, yesterday's say so, this year's the day and
// month, older ones the year too.
function formatDate(ms, nowMs) {
  var t = num(ms)
  if (!isFinite(t) || t <= 0) return ""
  var d = new Date(t)
  var now = new Date(num(nowMs) || Date.now())
  var day = function(x) { return new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime() }
  var diff = Math.round((day(now) - day(d)) / 86400000)
  if (diff === 0) return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  if (diff === 1) return "Yesterday"
  if (d.getFullYear() === now.getFullYear()) return d.getDate() + " " + MONTHS[d.getMonth()]
  return d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
}

function formatFullDate(ms) {
  var t = num(ms)
  if (!isFinite(t) || t <= 0) return ""
  var d = new Date(t)
  return d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear() + ", " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : (many || one + "s"))
}

// One name, or how many, for messages about a group of items.
function itemsLabel(count, firstName) {
  return count === 1 ? String(firstName || "") : plural(count, "item")
}

// ---------- Selection ----------

function indexOfPath(list, path) {
  for (var i = 0; i < (list || []).length; i++) if (list[i].path === path) return i
  return -1
}

function clampIndex(index, count) {
  if (count <= 0) return 0
  return Math.max(0, Math.min(count - 1, index))
}

function toggleSelected(selected, path) {
  var out = (selected || []).slice()
  var idx = out.indexOf(path)
  if (idx >= 0) out.splice(idx, 1)
  else out.push(path)
  return out
}

// Shift+click and Shift+j/k: every path between the anchor and the cursor.
function rangePaths(list, from, to) {
  var out = []
  if (!list || list.length === 0) return out
  var a = clampIndex(Math.min(from, to), list.length)
  var z = clampIndex(Math.max(from, to), list.length)
  for (var i = a; i <= z; i++) out.push(list[i].path)
  return out
}

// What an action applies to: the selection in list order, or the entry
// under the cursor when nothing is selected.
function pickedEntries(list, selected, cursor) {
  var out = []
  var sel = selected || []
  for (var i = 0; i < (list || []).length; i++) if (sel.indexOf(list[i].path) >= 0) out.push(list[i])
  if (out.length === 0 && list && cursor >= 0 && cursor < list.length) out.push(list[cursor])
  return out
}

// Drop selected paths that are no longer listed, after a refresh.
function keepSelected(selected, list) {
  var out = []
  for (var i = 0; i < (selected || []).length; i++) if (indexOfPath(list, selected[i]) >= 0) out.push(selected[i])
  return out
}

// ---------- Wheel ----------

// Wheel turns into whole rows: a notch (120) is PER rows, and a touchpad's
// small deltas add up until they make one. Rows toward the top are
// positive, the way the wheel reports them; what is left waits for the
// next event.
function wheelRows(carry, delta, per) {
  var unit = 120 / Math.max(1, per)
  var total = (Number(carry) || 0) + (Number(delta) || 0)
  // || 0 turns the -0 a small upward remainder rounds to into 0.
  var rows = (total > 0 ? Math.floor(total / unit) : Math.ceil(total / unit)) || 0
  return { rows: rows, carry: total - rows * unit }
}

// The scroll offset ROWS rows further down (negative goes up), on a row
// edge and inside the content, so the view never glides or stops between
// rows.
function steppedScroll(offset, rows, pitch, contentSize, viewSize) {
  if (!(pitch > 0)) return offset
  var last = Math.max(0, contentSize - viewSize)
  var row = Math.round(offset / pitch) + rows
  return Math.max(0, Math.min(last, row * pitch))
}

// ---------- Copy, move and name conflicts ----------

// The first free "name (copy).ext", "name (copy 2).ext" ... Folders and dot
// files keep their whole name as the stem.
function uniqueName(names, name, dir) {
  var taken = {}
  for (var i = 0; i < (names || []).length; i++) taken[names[i]] = true
  if (!taken[name]) return name
  var stem = name
  var ext = ""
  var idx = name.lastIndexOf(".")
  if (!dir && idx > 0) {
    stem = name.slice(0, idx)
    ext = name.slice(idx)
  }
  for (var n = 1; ; n++) {
    var candidate = stem + (n === 1 ? " (copy)" : " (copy " + n + ")") + ext
    if (!taken[candidate]) return candidate
  }
}

// What a paste or a drop would do before anything is asked: every source
// with the name it lands under and whether that name is taken in DEST.
// Moving a folder into itself is refused outright; moving within the same
// folder does nothing; copying into the same folder makes a "(copy)", the
// way pasting a file next to itself does.
function planTransfer(sources, dest, mode, destNames, dirs) {
  var plan = { error: "", jobs: [] }
  var assigned = (destNames || []).slice()
  for (var i = 0; i < (sources || []).length; i++) {
    var src = sources[i]
    var name = baseName(src)
    var dir = !!(dirs && dirs[src])
    if (isUnder(dest, src)) {
      plan.error = "Cannot put " + name + " inside itself"
      plan.jobs = []
      return plan
    }
    if (parentPath(src) === dest) {
      if (mode === "move") continue
      var copyName = uniqueName(assigned, name, dir)
      assigned.push(copyName)
      plan.jobs.push({ source: src, name: copyName, dir: dir, conflict: false, decision: "new" })
      continue
    }
    var taken = assigned.indexOf(name) >= 0
    plan.jobs.push({ source: src, name: name, dir: dir, conflict: taken, decision: taken ? "" : "new" })
    assigned.push(name)
  }
  return plan
}

// The next conflict still waiting for an answer, or -1.
function conflictIndex(jobs) {
  for (var i = 0; i < (jobs || []).length; i++) if (jobs[i].conflict && jobs[i].decision === "") return i
  return -1
}

// Skip, keep both or replace for the job at INDEX, and with ALL for every
// conflict after it too.
function decideConflict(jobs, index, how, all) {
  var out = []
  for (var i = 0; i < jobs.length; i++) {
    var job = jobs[i]
    var open = job.conflict && job.decision === ""
    if (i === index || (all && open && i > index)) out.push({ source: job.source, name: job.name, dir: job.dir, conflict: job.conflict, decision: how })
    else out.push(job)
  }
  return out
}

// files.sh transfer arguments: source, target and policy per job. Kept
// copies take the next free name, counting the names this transfer adds.
function transferArgs(jobs, dest, destNames) {
  var args = []
  var assigned = (destNames || []).slice()
  for (var i = 0; i < (jobs || []).length; i++) assigned.push(jobs[i].name)
  for (var j = 0; j < (jobs || []).length; j++) {
    var job = jobs[j]
    if (job.decision === "skip" || job.decision === "") continue
    var name = job.name
    if (job.decision === "keep") {
      name = uniqueName(assigned, job.name, job.dir)
      assigned.push(name)
    }
    args.push(job.source, joinPath(dest, name), job.decision === "replace" ? "replace" : "new")
  }
  return args
}

function transferLabel(mode, count, firstName, destLabel) {
  return (mode === "move" ? "Moving " : "Copying ") + itemsLabel(count, firstName) + " to " + destLabel
}

// ---------- files.sh output ----------

function parseNames(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] === "name" && parts.length > 1 && parts[1] !== "") out.push(parts.slice(1).join("\t"))
  }
  return out
}

// "Open with": the default app first, then the others by name.
function parseApps(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] !== "app" || parts.length < 3 || parts[1] === "") continue
    out.push({ id: parts[1], name: parts[2] || parts[1], isDefault: parts[3] === "1" })
  }
  out.sort(function(a, b) {
    if (a.isDefault !== b.isDefault) return a.isDefault ? -1 : 1
    var x = naturalKey(a.name)
    var y = naturalKey(b.name)
    return x < y ? -1 : (x > y ? 1 : 0)
  })
  return out
}

function parseFree(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] === "free" && parts.length >= 3) return { avail: num(parts[1]), size: num(parts[2]) }
  }
  return { avail: NaN, size: NaN }
}

// Everything an action prints, line by line: errors, finished transfers and
// renames, trashed and restored items, created files, mounts, and the
// progress figures of a long copy.
function parseResult(raw) {
  var out = { errors: [], done: [], trashed: [], restored: [], created: [], mounted: "", total: NaN, progress: NaN, cancelled: false }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    switch (parts[0]) {
    case "error": out.errors.push(parts.slice(1).join("\t")); break
    case "done": out.done.push({ from: parts[1] || "", to: parts[2] || "" }); break
    case "trashed": out.trashed.push({ name: parts[1] || "", path: parts[2] || "" }); break
    case "restored": out.restored.push({ name: parts[1] || "", path: parts[2] || "" }); break
    case "created": out.created.push(parts[1] || ""); break
    case "mounted": out.mounted = parts[1] || ""; break
    case "total": out.total = num(parts[1]); break
    case "progress": out.progress = num(parts[1]); break
    case "cancelled": out.cancelled = true; break
    }
  }
  return out
}

// ---------- Text on screen ----------

function statusText(list, selected, deep, where) {
  var n = (list || []).length
  var text = plural(n, "item")
  if (deep) text += " found below " + where
  var picked = pickedEntries(list, selected, -1)
  if (picked.length > 0) {
    var bytes = 0
    for (var i = 0; i < picked.length; i++) if (isFinite(picked[i].size)) bytes += picked[i].size
    text += " · " + picked.length + " selected" + (bytes > 0 ? ", " + formatSize(bytes) : "")
  }
  return text
}

function emptyText(path, query, deep, where) {
  if (query) return "Nothing named “" + query + "” " + (deep ? "below " + where : "here")
  if (path === TRASH) return "Trash is empty"
  if (path === RECENT) return "Nothing opened lately"
  return "This folder is empty"
}

function tooltip(tabs, active, label) {
  if (!tabs || tabs.length === 0) return "Files"
  var text = "Files · " + label
  if (tabs.length > 1) text += " · " + plural(tabs.length, "tab")
  return text
}

function hints(mode) {
  return HINTS[mode] || HINTS.browse
}

// Right click on an item. Trash items can only go back or go for good.
function itemMenu(entry, count, clipboard, bookmarked) {
  if (!entry) return []
  if (entry.trashName) return [
    { id: "restore", label: "Restore", icon: "󰦛", shortcut: "Enter" },
    { id: "purge", label: "Delete for good", icon: "󰆴", shortcut: "Shift+Del", danger: true }
  ]
  var items = [{ id: "open", label: "Open", icon: "󰳋", shortcut: "Enter" }]
  if (entry.dir) items.push({ id: "opentab", label: "Open in new tab", icon: "󰐕", shortcut: "Ctrl+Enter" })
  else items.push({ id: "openwith", label: "Open with…", icon: "󰀻", shortcut: "o" })
  items.push({ id: "copy", label: "Copy", icon: "󰆏", shortcut: "y" })
  items.push({ id: "cut", label: "Cut", icon: "󰆐", shortcut: "x" })
  if (entry.dir) items.push({ id: "pasteinto", label: "Paste into folder", icon: "󰆒", disabled: !clipboard })
  items.push({ id: "rename", label: "Rename", icon: "󰏫", shortcut: "F2", disabled: count > 1 })
  if (entry.dir) items.push({ id: "bookmark", label: bookmarked ? "Remove bookmark" : "Bookmark", icon: "󰃀", shortcut: "Ctrl+D" })
  items.push({ id: "trash", label: "Move to Trash", icon: "󰩹", shortcut: "d", danger: true })
  items.push({ id: "purge", label: "Delete for good", icon: "󰆴", shortcut: "Shift+Del", danger: true })
  return items
}

// Right click on empty space, and the header's ⋮ button.
function folderMenu(path, clipboard, showHidden, sortKey, bookmarked) {
  if (path === TRASH) return [{ id: "emptytrash", label: "Empty Trash", icon: "󰆴", danger: true }]
  var items = []
  if (!isVirtual(path)) {
    items.push({ id: "newfolder", label: "New folder", icon: "󰉗", shortcut: "a" })
    items.push({ id: "newfile", label: "New file", icon: "󰝒", shortcut: "n" })
    items.push({ id: "paste", label: "Paste", icon: "󰆒", shortcut: "p", disabled: !clipboard })
  }
  items.push({ id: "selectall", label: "Select all", icon: "󰄬", shortcut: "Ctrl+A" })
  items.push({ id: "hidden", label: showHidden ? "Hide hidden files" : "Show hidden files", icon: showHidden ? GLYPHS.hiddenHidden : GLYPHS.hiddenShown, shortcut: "Ctrl+H" })
  for (var i = 0; i < SORT_KEYS.length; i++) items.push({ id: "sort:" + SORT_KEYS[i].key, label: "Sort by " + SORT_KEYS[i].label.toLowerCase() + (sortKey === SORT_KEYS[i].key ? "  ✓" : ""), icon: "󰒺" })
  if (!isVirtual(path)) {
    items.push({ id: "bookmark", label: bookmarked ? "Remove bookmark" : "Bookmark this folder", icon: "󰃀", shortcut: "Ctrl+D" })
    items.push({ id: "nautilus", label: "Open in Nautilus", icon: "󰏌", shortcut: "N" })
  }
  return items
}
