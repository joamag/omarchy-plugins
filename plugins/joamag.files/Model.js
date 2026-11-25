.pragma library

// Pure helpers for the files widget: paths and places, tabs and their
// history, listing order and the on-screen filter, kinds and formatting,
// selection, name conflicts, and parsing what files.sh prints.

var ICON = "󰉋"
// Locations that are not folders on disk.
var RECENT = "recent:"
var TRASH = "trash:"
// A folder inside an archive: ARCHIVE_PREFIX, the archive's path, the
// separator, and the folder inside it ("" for its top).
var ARCHIVE_PREFIX = "archive:"
var ARCHIVE_SEPARATOR = "::/"
// Names bsdtar reads as archives, longest suffixes first.
var ARCHIVE_SUFFIXES = [".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tar.lz4", ".zip", ".jar", ".tar", ".tgz", ".txz", ".tzst", ".tbz2", ".tbz", ".7z", ".rar", ".iso", ".cpio", ".xar", ".cab"]
// Names bsdtar writes from the suffix alone.
var COMPRESS_SUFFIXES = [".zip", ".7z", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.zst", ".tzst", ".tar.bz2", ".tbz2"]
var MAX_TABS = 12
// files.sh lists no more matches than this for a search below a folder.
var SEARCH_LIMIT = 200

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
  pptx: "slides", ppt: "slides", odp: "slides",
  ttf: "font", otf: "font", woff: "font", woff2: "font"
}

var KIND_ICONS = {
  dir: "󰉋", image: "󰈟", video: "󰈫", audio: "󰈣", pdf: "󰈦", text: "󰈙", code: "󰈮",
  archive: "󰗄", disc: "󰆜", sheet: "󰈛", document: "󰈬", slides: "󰈧", font: "󰊔", file: "󰈔"
}

var KIND_LABELS = {
  image: "Image", video: "Video", audio: "Audio", pdf: "PDF document", text: "Text", code: "Source code", archive: "Archive",
  disc: "Disk image", sheet: "Spreadsheet", document: "Document", slides: "Presentation", font: "Font", file: "File"
}

// A finer type name for the text and code files people open most.
var TYPE_LABELS = {
  md: "Markdown", txt: "Plain text", json: "JSON", yml: "YAML", yaml: "YAML", toml: "TOML", csv: "CSV", xml: "XML", log: "Log",
  js: "JavaScript", ts: "TypeScript", qml: "QML", py: "Python", sh: "Shell script", rs: "Rust", go: "Go", lua: "Lua", html: "HTML", css: "CSS"
}

// Formats Qt's image reader decodes, so the grid and the preview can show
// the picture itself.
var THUMBNAIL_EXTENSIONS = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"]

// Kinds a system thumbnailer can draw (the ones Nautilus uses): a video
// frame, an album cover, a document's first page, a font sample, and
// pictures Qt cannot read itself, such as HEIC.
var THUMBNAILED_KINDS = ["video", "audio", "document", "sheet", "slides", "font", "image"]

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
    { key: "j/k", label: "move" }, { key: "l", label: "open" }, { key: "h", label: "up" }, { key: "Space", label: "preview" },
    { key: "y", label: "copy" }, { key: "x", label: "cut" }, { key: "p", label: "paste" }, { key: "r", label: "rename" },
    { key: "a", label: "folder" }, { key: "d", label: "trash" }, { key: "o", label: "open with" }, { key: "/", label: "filter" },
    { key: "f", label: "find" }, { key: "g", label: "go to" }, { key: "w", label: "window" }, { key: "?", label: "keys" }
  ],
  trash: [
    { key: "j/k", label: "move" }, { key: "Enter", label: "restore" }, { key: "Space", label: "preview" },
    { key: "Delete", label: "delete for good" }, { key: "g", label: "go to" }, { key: "?", label: "keys" }
  ],
  find: [{ key: "type", label: "the start of a name" }, { key: "Backspace", label: "erase" }, { key: "Enter", label: "open" }, { key: "Esc", label: "stop" }],
  filter: [{ key: "type", label: "to filter" }, { key: "Enter", label: "search below" }, { key: "↓", label: "to the results" }, { key: "Esc", label: "clear" }],
  rename: [{ key: "Enter", label: "rename" }, { key: "Esc", label: "cancel" }],
  archive: [
    { key: "j/k", label: "move" }, { key: "l", label: "open" }, { key: "h", label: "up" }, { key: "Space", label: "preview" },
    { key: "y", label: "copy out" }, { key: "E", label: "extract all" }, { key: "g", label: "go to" }, { key: "?", label: "keys" }
  ],
  prompt: [{ key: "Enter", label: "go ahead" }, { key: "Esc", label: "cancel" }],
  path: [{ key: "Enter", label: "go" }, { key: "Esc", label: "cancel" }],
  jump: [{ key: "type", label: "to find" }, { key: "↑↓", label: "choose" }, { key: "Enter", label: "open" }, { key: "Ctrl+Enter", label: "in a new tab" }, { key: "Esc", label: "close" }],
  chooser: [{ key: "Enter", label: "open, pick" }, { key: "Tab", label: "name" }, { key: "Ctrl+S", label: "done" }, { key: "Ctrl+Space", label: "select" }, { key: "Ctrl+P", label: "jump" }, { key: "Esc", label: "cancel" }]
}

// Every key, for the `?` sheet: the panel keys of the other widgets and the
// Nautilus shortcuts side by side.
var KEYS = [
  ["j k  ↓ ↑", "Move"], ["J K  Shift+↓ ↑", "Extend the selection"], ["l  Enter", "Open"], ["h  Backspace  Alt+↑", "Up a folder"],
  ["Alt+← Alt+→", "Back, forward"], ["Space", "Large preview: j k step, Space or Esc closes"], ["Ctrl+Space  Ctrl+click", "Select"], ["Middle click  Ctrl+double click", "Folder in a new tab"], ["Ctrl+A", "Select all"], ["y  Ctrl+C", "Copy"],
  ["x  Ctrl+X", "Cut"], ["p  Ctrl+V", "Paste"], ["r  F2", "Rename"], ["a  Ctrl+Shift+N", "New folder"],
  ["n", "New file"], ["d  Delete", "Move to Trash"], ["Ctrl+Z", "Undo the move to Trash"], ["Shift+Delete", "Delete for good"],
  ["o", "Open with"], ["E", "Extract the archive here"], ["Z", "Compress to .zip"],
  ["<  >", "Previous, next PDF page in the preview"], ["p, in the large preview", "Play or pause"], ["/  Ctrl+F", "Filter, Enter searches below"], ["f", "Find a name by typing its start"], ["g", "Go to a place"], ["Ctrl+P", "Jump to a recent folder"], ["e  Ctrl+L", "Type a path"], ["t  Ctrl+T", "New tab"],
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

// MAP's own value for KEY, never one every object inherits: a file named
// "notes.constructor" is a plain file.
function ownValue(map, key) {
  return Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined
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
  if (value === RECENT || value === TRASH || isArchiveLocation(value)) return value
  if (value.indexOf("file://") === 0) return urlToPath(value)
  if (value === "~" || value.indexOf("~/") === 0) value = String(home || "") + value.slice(1)
  else if (value.charAt(0) !== "/") value = String(base || home || "") + "/" + value
  return normalizePath(value)
}

// Not a folder on disk: Recent, the Trash, or a folder inside an archive.
function isVirtual(path) {
  return path === RECENT || path === TRASH || isArchiveLocation(path)
}

function isUnder(path, root) {
  var p = String(path || "")
  var r = String(root || "")
  if (p === "" || r === "" || isVirtual(p) || isVirtual(r)) return p === r && p !== ""
  if (p === r) return true
  return p.indexOf(r === "/" ? "/" : r + "/") === 0
}

// "" when there is nothing above: the root, or Recent and Trash. Above the
// top of an archive is the folder the archive sits in.
function parentPath(path) {
  var p = String(path || "")
  var inside = splitArchive(p)
  if (inside) return inside.inner === "" ? parentPath(inside.archive) : archiveLocation(inside.archive, parentPath("/" + inside.inner).slice(1))
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
  var inside = splitArchive(p)
  if (inside) return prettyPath(inside.archive, home) + (inside.inner !== "" ? " › " + inside.inner : "")
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

// What a drag of files carries: the list of files file managers, browsers
// and most apps take, and the paths as text for terminals and text fields.
function dragData(paths) {
  return { "text/uri-list": uriList(paths), "text/plain": (paths || []).join("\n") }
}

// ---------- Archives ----------

function isArchiveName(name) {
  var n = String(name || "").toLowerCase()
  for (var i = 0; i < ARCHIVE_SUFFIXES.length; i++) {
    var suffix = ARCHIVE_SUFFIXES[i]
    if (n.length > suffix.length && n.slice(-suffix.length) === suffix) return true
  }
  return false
}

// A file that opens as a folder: an archive on disk, or one inside an
// archive (it is extracted first).
function isArchive(entry) {
  return !!entry && !entry.dir && !entry.trashName && isArchiveName(entry.name)
}

function archiveLocation(archive, inner) {
  return ARCHIVE_PREFIX + archive + ARCHIVE_SEPARATOR + String(inner || "").replace(/^\/+|\/+$/g, "")
}

function isArchiveLocation(path) {
  return String(path || "").indexOf(ARCHIVE_PREFIX) === 0
}

// { archive, inner } for a folder inside an archive, or null. The archive
// ends at the first separator that follows an archive's name, so a folder
// on the way to it may hold the separator in its own name.
function splitArchive(path) {
  var p = String(path || "")
  if (!isArchiveLocation(p)) return null
  var rest = p.slice(ARCHIVE_PREFIX.length)
  var first = rest.indexOf(ARCHIVE_SEPARATOR)
  var at = first
  while (at >= 0 && !isArchiveName(baseName(rest.slice(0, at)))) at = rest.indexOf(ARCHIVE_SEPARATOR, at + 1)
  if (at < 0) at = first
  if (at < 0) return { archive: rest, inner: "" }
  return { archive: rest.slice(0, at), inner: rest.slice(at + ARCHIVE_SEPARATOR.length) }
}

// The name an archive extracts into: "photos.tar.gz" becomes "photos".
function archiveStem(name) {
  var n = String(name || "")
  var lower = n.toLowerCase()
  for (var i = 0; i < ARCHIVE_SUFFIXES.length; i++) {
    var suffix = ARCHIVE_SUFFIXES[i]
    if (lower.length > suffix.length && lower.slice(-suffix.length) === suffix) return n.slice(0, n.length - suffix.length)
  }
  return n
}

var MONTH_INDEX = { Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5, Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11 }

// files.sh archive-list: bsdtar's listing in the C locale, one member a
// line: mode, links, owner, group, size, date, name. Dates within the last
// six months show a time instead of the year. Folders many zips never list
// are made up from the paths below them. Members as { inner, dir, size,
// modified }, inner without leading or trailing slashes.
function parseArchiveListing(raw, nowMs) {
  var now = new Date(num(nowMs) || Date.now())
  var byPath = Object.create(null)
  var out = []
  var lines = String(raw || "").split("\n")
  var re = /^(\S)\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{1,2}:\d{2}|\d{4})\s(.+)$/
  function add(inner, dir, size, modified) {
    if (inner === "" || byPath[inner]) {
      if (byPath[inner] && dir && isFinite(modified)) byPath[inner].modified = modified
      return
    }
    var member = { inner: inner, dir: dir, size: dir ? NaN : size, modified: modified }
    byPath[inner] = member
    out.push(member)
  }
  for (var i = 0; i < lines.length; i++) {
    var m = re.exec(lines[i])
    if (!m) continue
    var name = m[6]
    if (m[1] === "l") name = name.replace(/ -> .*$/, "")
    else if (m[1] === "h") name = name.replace(/ link to .*$/, "")
    name = name.replace(/^\.\//, "")
    var dir = m[1] === "d" || /\/$/.test(name)
    name = name.replace(/^\/+|\/+$/g, "")
    if (name === "" || name === ".") continue
    var month = MONTH_INDEX[m[3]]
    var date
    if (m[5].indexOf(":") >= 0) {
      var hm = m[5].split(":")
      date = new Date(now.getFullYear(), month, Number(m[4]), Number(hm[0]), Number(hm[1]))
      // A time means within the last six months, so a later date is last year's.
      if (date.getTime() > now.getTime() + 86400000) date.setFullYear(now.getFullYear() - 1)
    } else {
      date = new Date(Number(m[5]), month, Number(m[4]))
    }
    var parts = name.split("/")
    for (var j = 1; j < parts.length; j++) add(parts.slice(0, j).join("/"), true, NaN, NaN)
    add(name, dir, Number(m[2]), date.getTime())
  }
  return out
}

// The entries of one folder inside an archive, as a listing shows them.
function archiveEntries(members, archive, inner) {
  var prefix = inner ? inner + "/" : ""
  var out = []
  for (var i = 0; i < (members || []).length; i++) {
    var m = members[i]
    if (prefix !== "" && m.inner.indexOf(prefix) !== 0) continue
    var rest = m.inner.slice(prefix.length)
    if (rest === "" || rest.indexOf("/") >= 0) continue
    out.push(makeEntry({ path: archiveLocation(archive, m.inner), name: rest, dir: m.dir, size: m.size, modified: m.modified }))
  }
  return out
}

// What an archive holds, for the preview: counts, the unpacked size, and
// the first few names.
function archiveSummary(members, limit) {
  var files = 0
  var dirs = 0
  var bytes = 0
  var names = []
  for (var i = 0; i < (members || []).length; i++) {
    var m = members[i]
    if (m.dir) dirs++
    else {
      files++
      if (isFinite(m.size)) bytes += m.size
    }
    if (names.length < limit) names.push(m.inner + (m.dir ? "/" : ""))
  }
  return { files: files, dirs: dirs, bytes: bytes, names: names, more: Math.max(0, (members || []).length - names.length) }
}

// Where "Extract here" puts an archive, always a folder it makes: one
// holding a single top folder unpacks as that folder, the rest into a
// folder named after the archive, either way under a free name.
function extractTarget(members, archiveName, names) {
  var tops = Object.create(null)
  var count = 0
  var single = null
  for (var i = 0; i < (members || []).length; i++) {
    var top = members[i].inner.split("/")[0]
    if (tops[top]) continue
    tops[top] = true
    count++
    single = members[i].inner === top ? members[i] : { inner: top, dir: true }
  }
  if (count === 1 && single.dir) return { name: uniqueName(names, single.inner, true), strip: 1 }
  return { name: uniqueName(names, archiveStem(archiveName) || "Archive", true), strip: 0 }
}

// How many leading folders to drop when copying out of FOLDER inside an
// archive, so the files land where they are pasted rather than under it.
function stripCount(inner) {
  return inner ? String(inner).split("/").length : 0
}

// EXTRACTED, the copies taken out of archives by their location inside
// one, without those of ARCHIVE: a new version of it was read, so its
// members are taken out again when next asked for.
function withoutMembers(extracted, archive) {
  var out = {}
  for (var location in extracted || {}) {
    var at = splitArchive(location)
    if (!at || at.archive !== archive) out[location] = extracted[location]
  }
  return out
}

// The name offered for a new archive: the file's or folder's own name for
// one item, "Archive" for several, as a free .zip in that folder.
function compressName(entries, names) {
  var list = entries || []
  var stem = list.length === 1 ? (list[0].dir ? list[0].name : archiveStem(list[0].name).replace(/\.[^.]+$/, "") || list[0].name) : "Archive"
  return uniqueName(names, stem + ".zip", false)
}

// A name bsdtar can tell the format of.
function canCompressTo(name) {
  var n = String(name || "").toLowerCase()
  for (var i = 0; i < COMPRESS_SUFFIXES.length; i++) {
    var suffix = COMPRESS_SUFFIXES[i]
    if (n.length > suffix.length && n.slice(-suffix.length) === suffix) return true
  }
  return false
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
  var inside = splitArchive(path)
  if (inside) return baseName(inside.inner || inside.archive)
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
  if (isArchiveLocation(path)) return KIND_ICONS.archive
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
  // Inside an archive: the way to the archive, the archive, then its folders.
  var inside = splitArchive(path)
  if (inside) {
    var out = crumbs(parentPath(inside.archive) || "/", home, drives)
    out.push({ label: baseName(inside.archive), path: archiveLocation(inside.archive, "") })
    var parts = inside.inner === "" ? [] : inside.inner.split("/")
    for (var a = 0; a < parts.length; a++) out.push({ label: parts[a], path: archiveLocation(inside.archive, parts.slice(0, a + 1).join("/")) })
    return out
  }
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

// ---------- Jump to a folder ----------

var VISITED_MAX = 50

// Folders opened in the widget, newest first, for Ctrl+P. Recent, the
// Trash and folders inside archives are not kept.
function addVisited(visited, path, max) {
  var p = String(path || "")
  var list = Array.isArray(visited) ? visited.filter(function(v) { return typeof v === "string" && v !== p }) : []
  if (p === "" || isVirtual(p)) return list.slice(0, max || VISITED_MAX)
  list.unshift(p)
  return list.slice(0, max || VISITED_MAX)
}

// Everything Ctrl+P can jump to, each folder once, in the order shown before
// anything is typed: the other open tabs, folders opened here (newest
// first), folders used lately in any app, bookmarks, the standard folders
// and mounted drives.
function jumpCandidates(tabs, active, visited, recent, bookmarks, places, drives, home) {
  var out = []
  var seen = {}
  function add(path, source, extra) {
    if (!path || seen[path]) return
    seen[path] = true
    var item = { path: path, source: source, label: placeLabel(path, home, places, drives), icon: placeIcon(path, home, places, drives), tabIndex: -1 }
    for (var k in extra) item[k] = extra[k]
    out.push(item)
  }
  var i
  for (i = 0; i < (tabs || []).length; i++) if (i !== active) add(tabs[i].path, "tab", { tabIndex: i })
  for (i = 0; i < (visited || []).length; i++) add(visited[i], "visited")
  for (i = 0; i < (recent || []).length; i++) {
    var e = recent[i]
    add(e.dir ? e.path : parentPath(e.path), "recent")
  }
  for (i = 0; i < (bookmarks || []).length; i++) add(bookmarks[i].path, "bookmark", { label: bookmarks[i].label, icon: GLYPHS.bookmark })
  for (i = 0; i < (places || []).length; i++) add(places[i].path, "place")
  for (i = 0; i < (drives || []).length; i++) if (drives[i].mount) add(drives[i].mount, "drive")
  return out
}

// How well QUERY's letters, in order, fit TEXT, the way an editor's quick
// open matches: a letter starting a word or following the last one counts
// most, a long gap costs, spaces in QUERY are skipped. Every place the
// first letter appears is tried and the best fit kept. -1 when the letters
// do not all appear, and never below 0 when they do.
function fuzzyScore(query, text) {
  var q = String(query || "").toLowerCase().replace(/\s+/g, "")
  var t = String(text || "").toLowerCase()
  if (q === "") return 0
  // The fit from the first letter at START, each next letter taken as soon
  // as it shows up; null when one is missing.
  function fit(start) {
    var score = 0
    var from = 0
    var last = -2
    for (var i = 0; i < q.length; i++) {
      var at = i === 0 ? start : t.indexOf(q.charAt(i), from)
      if (at < 0) return null
      score += 1
      if (at === last + 1) score += 5
      if (at === 0 || "/ -_.".indexOf(t.charAt(at - 1)) >= 0) score += 8
      score -= Math.min(5, at - from) * 0.5
      last = at
      from = at + 1
    }
    return score
  }
  var best = null
  for (var start = t.indexOf(q.charAt(0)); start >= 0; start = t.indexOf(q.charAt(0), start + 1)) {
    var score = fit(start)
    // A later start cannot find letters an earlier one missed.
    if (score === null) break
    if (best === null || score > best) best = score
  }
  return best === null ? -1 : Math.max(0, best)
}

// The candidates QUERY fits, best first; any fit inside the folder's own
// name beats one spread over the path, and ties keep the candidates' order.
function jumpMatches(candidates, query, home, limit) {
  var list = candidates || []
  var max = limit || 50
  if (String(query || "").trim() === "") return list.slice(0, max)
  var scored = []
  for (var i = 0; i < list.length; i++) {
    var named = fuzzyScore(query, list[i].label)
    var score = fuzzyScore(query, prettyPath(list[i].path, home))
    if (score < 0) score = named
    if (score < 0) continue
    scored.push({ item: list[i], named: named >= 0 ? 1 : 0, score: score, index: i })
  }
  scored.sort(function(a, b) { return b.named - a.named || b.score - a.score || a.index - b.index })
  return scored.slice(0, max).map(function(s) { return s.item })
}

// Typed text Ctrl+P offers to go to as it is: an absolute or home path.
function looksLikePath(text) {
  var t = String(text || "").trim()
  return t.charAt(0) === "/" || t === "~" || t.indexOf("~/") === 0
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

// A location as a plain path: inside an archive, the archive file stands
// for the folder it opens as.
function walkable(path) {
  var inside = splitArchive(path)
  if (!inside) return String(path || "")
  return inside.archive + (inside.inner !== "" ? "/" + inside.inner : "")
}

// Which way a move goes, for the views to slide the new folder in from that
// side: out to a folder it was in (-1), or anywhere else (1).
function moveDirection(from, to) {
  var a = walkable(from)
  var b = walkable(to)
  return a !== b && isUnder(a, b) ? -1 : 1
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
// ejected drive sends them all to TO itself with WHOLE. A tab inside an
// archive goes by the archive's own path. History would point at paths
// that no longer exist, so it starts over.
function retargetTabs(tabs, from, to, whole) {
  var changed = false
  var out = []
  for (var i = 0; i < (tabs || []).length; i++) {
    var tab = tabs[i]
    var at = splitArchive(tab.path)
    var disk = at ? at.archive : tab.path
    if (!isUnder(disk, from) || isVirtual(from)) {
      out.push(tab)
      continue
    }
    var path = to ? (whole ? to : to + disk.slice(from.length)) : (parentPath(from) || "/")
    if (at && to && !whole) path = archiveLocation(path, at.inner)
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
  return ownValue(EXTENSIONS, extensionOf(name)) || "file"
}

function typeLabel(entry) {
  if (!entry) return ""
  if (entry.dir) return "Folder"
  var ext = extensionOf(entry.name)
  return typeFor(ext, ownValue(EXTENSIONS, ext) || "file")
}

function typeFor(ext, kind) {
  if (ownValue(TYPE_LABELS, ext)) return TYPE_LABELS[ext]
  if (kind === "image" && ext !== "") return ext.toUpperCase() + " image"
  return KIND_LABELS[kind]
}

function kindIcon(kind) {
  return KIND_ICONS[kind] || KIND_ICONS.file
}

// The icon theme's name for a dragged entry, the picture under the pointer.
var DRAG_ICONS = {
  dir: "folder", image: "image-x-generic", video: "video-x-generic", audio: "audio-x-generic", pdf: "application-pdf",
  text: "text-x-generic", code: "text-x-script", archive: "package-x-generic", disc: "media-optical", sheet: "x-office-spreadsheet",
  document: "x-office-document", slides: "x-office-presentation", font: "font-x-generic", file: "text-x-generic"
}

function dragIcon(entry) {
  return entry && DRAG_ICONS[entry.kind] ? DRAG_ICONS[entry.kind] : "text-x-generic"
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

// What the preview can show for an entry: the picture itself, a PDF page
// (Qt draws those), what an archive holds, the first lines of a text file,
// a picture a system thumbnailer makes, or nothing beyond the glyph and the
// details.
function previewKind(entry) {
  if (!entry || !entry.path) return "none"
  if (entry.dir) return "dir"
  if (isImage(entry)) return "image"
  if (extensionOf(entry.name) === "pdf") return "pdf"
  if (isArchive(entry)) return "archive"
  if (isTextual(entry)) return "text"
  if (THUMBNAILED_KINDS.indexOf(entry.kind) >= 0) return "thumbnail"
  return "none"
}

// What the large preview shows: what the pane shows, except that video and
// music on disk play rather than show a still. Inside an archive they are
// not taken out to be played.
function lookKind(entry) {
  var kind = previewKind(entry)
  if (kind === "thumbnail" && (entry.kind === "video" || entry.kind === "audio") && !isArchiveLocation(entry.path)) return entry.kind
  return kind
}

// One thumbnail per file version and size.
function thumbnailKey(entry, size) {
  return entry ? entry.path + "|" + entry.modified + "|" + size : ""
}

// The first lines of a text file for the preview, from its first SIZE
// characters (8192 unless told), or null when it turns out to be binary: a
// file without an extension is often a program.
function previewText(text, lines, size) {
  var head = String(text || "").slice(0, size || 8192)
  if (/[\u0000-\u0008\u000E-\u001A\u001C-\u001F\uFFFD]/.test(head.slice(0, 8192))) return null
  return head.split("\n").slice(0, lines).join("\n")
}

// What the preview offers to do with an entry, by what it is and where.
function previewActions(entry) {
  if (!entry || !entry.path) return []
  if (entry.trashName) return [{ id: "restore", label: "Restore" }, { id: "purge", label: "Delete" }]
  if (isArchiveLocation(entry.path)) return [{ id: "open", label: "Open" }, { id: "copy", label: "Copy out" }]
  if (isArchive(entry)) return [{ id: "open", label: "Browse" }, { id: "extracthere", label: "Extract here" }]
  if (entry.dir) return [{ id: "open", label: "Open" }, { id: "opentab", label: "In new tab" }]
  return [{ id: "open", label: "Open" }, { id: "openwith", label: "Open with" }]
}

// The details the preview lists, as label and value pairs. MORE adds what
// only the preview knows: how many items a folder holds, a PDF's pages,
// a video's or a song's length.
function previewFacts(entry, home, more) {
  if (!entry || !entry.path) return []
  var extra = more || {}
  var rows = [["Kind", entry.type]]
  if (!entry.dir) rows.push(["Size", formatSize(entry.size)])
  else if (extra.items !== undefined) rows.push(["Contains", plural(extra.items, "item")])
  if (extra.pages > 0) rows.push(["Pages", String(extra.pages)])
  if (extra.length) rows.push(["Length", extra.length])
  if (isFinite(entry.modified)) rows.push([entry.trashName ? "Deleted" : "Modified", formatFullDate(entry.modified)])
  rows.push([entry.trashName ? "From" : "Where", prettyPath(parentPath(entry.trashName ? entry.origin : entry.path), home)])
  return rows
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
  var kind = dir ? "dir" : (ownValue(EXTENSIONS, ext) || "file")
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
// is padded to one width, so "file2" sorts before "file10". The digits are
// kept as text, so long runs keep their order; one longer than the width
// sorts after every padded run, by its length first.
function naturalKey(text) {
  return String(text || "").toLowerCase().replace(/\d+/g, function(digits) {
    var d = digits.replace(/^0+(?=\d)/, "")
    if (d.length <= ZEROS.length) return ZEROS.slice(d.length) + d
    return ":" + ("000" + d.length).slice(-3) + d
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

// Whether two listings show the same rows: the same files in the same
// order, with the same size and date. A folder read again unchanged keeps
// its rows, and its scroll, rather than being drawn anew. Object.is counts
// two unknown values (NaN, a folder's size) as the same.
function sameListing(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    var x = a[i]
    var y = b[i]
    if (x !== y && (x.path !== y.path || x.dir !== y.dir || !Object.is(x.size, y.size) || !Object.is(x.modified, y.modified))) return false
  }
  return true
}

// The actions that take their entries out of the folder on screen, which
// fade as they run.
var LEAVES = ["trash", "delete", "purge", "restore"]

var SETTLE_MAX = 24

// How the folder on screen changed when read again, for its rows to settle
// from where they were: by path, how many places each entry still there
// moved (shifts, only those that moved), and the entries that are new
// (arrived). null when nothing came or went, or more than MAX did: a
// listing that changed that much is shown as it is.
function settleMoves(before, after, max) {
  var limit = max || SETTLE_MAX
  var was = before || []
  var now = after || []
  var at = Object.create(null)
  var i
  for (i = 0; i < was.length; i++) at[was[i].path] = i
  var shifts = {}
  var arrived = {}
  var kept = 0
  var changes = 0
  for (i = 0; i < now.length; i++) {
    var path = now[i].path
    if (at[path] === undefined) {
      arrived[path] = true
      changes++
    } else {
      kept++
      if (at[path] !== i) shifts[path] = at[path] - i
    }
  }
  changes += was.length - kept
  if (changes === 0 || changes > limit) return null
  return { shifts: shifts, arrived: arrived }
}

var LISTING_CACHE_MAX = 32
var LISTING_CACHE_BIG = 5000

// Listings of folders seen lately, by path, oldest first, so a folder shown
// again is on screen at once while it is read again. The oldest go past
// MAX, and a folder of more than LISTING_CACHE_BIG entries is not kept, to
// hold memory in bounds.
function rememberListing(cache, path, entries, max) {
  var limit = max || LISTING_CACHE_MAX
  var old = cache || {}
  var keys = Object.keys(old).filter(function(k) { return k !== path })
  var keep = String(path || "") !== "" && Array.isArray(entries) && entries.length <= LISTING_CACHE_BIG
  var out = {}
  for (var i = Math.max(0, keys.length - (keep ? limit - 1 : limit)); i < keys.length; i++) out[keys[i]] = old[keys[i]]
  if (keep) out[path] = entries
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

// A media position or length in milliseconds as the players show it:
// 2:34, or 1:02:03 past an hour.
function formatDuration(ms) {
  var total = Math.floor(num(ms) / 1000)
  if (!isFinite(total) || total < 0) total = 0
  var h = Math.floor(total / 3600)
  var m = Math.floor(total / 60) % 60
  var sec = pad2(total % 60)
  return h > 0 ? h + ":" + pad2(m) + ":" + sec : m + ":" + sec
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
  var sel = Object.create(null)
  for (var j = 0; j < (selected || []).length; j++) sel[selected[j]] = true
  for (var i = 0; i < (list || []).length; i++) if (sel[list[i].path]) out.push(list[i])
  if (out.length === 0 && list && cursor >= 0 && cursor < list.length) out.push(list[cursor])
  return out
}

// What a command from a menu or a preview applies to: PICKED, the
// selection, when ENTRY is part of it, else ENTRY alone, the one a preview
// shows once the cursor has left the selection. Without ENTRY, PICKED.
function entriesFor(picked, entry) {
  var list = picked || []
  if (!entry || !entry.path) return list
  for (var i = 0; i < list.length; i++) if (list[i].path === entry.path) return list
  return [entry]
}

// Drop selected paths that are no longer listed, after a refresh.
function keepSelected(selected, list) {
  var listed = Object.create(null)
  for (var j = 0; j < (list || []).length; j++) listed[list[j].path] = true
  var out = []
  for (var i = 0; i < (selected || []).length; i++) if (listed[selected[i]]) out.push(selected[i])
  return out
}

// Where typing the start of a name lands the cursor, the way Explorer finds
// it: a first letter moves on to the next name after the cursor with it, so
// typing it again steps through them; more letters keep the cursor on its
// name while it still fits and look further when it no longer does; the
// same letter over and over steps through the names it starts. Names match
// whatever their case; -1 when none does.
function typeAheadIndex(list, prefix, from) {
  var entries = list || []
  var text = String(prefix || "").toLowerCase()
  if (text === "" || entries.length === 0) return -1
  var start = Math.max(0, Math.min(entries.length - 1, from || 0))
  function next(head, offset) {
    for (var i = 0; i < entries.length; i++) {
      var at = (start + offset + i) % entries.length
      if (entries[at].lower.indexOf(head) === 0) return at
    }
    return -1
  }
  if (text.length === 1) return next(text, 1)
  var hit = next(text, 0)
  if (hit < 0 && text.split("").every(function(c) { return c === text.charAt(0) })) hit = next(text.charAt(0), 1)
  return hit
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

// ---------- Columns ----------

// Width of every column in the columns view, before the shell's spacing
// scale, and the room a row takes besides the name (margins, icon and
// arrow) when a column is fitted to its names.
var COLUMN_WIDTH = 190
var COLUMN_MIN = 120
var COLUMN_MAX = 480
var COLUMN_CHROME = 56

// A column width from settings or a dragged divider, whole and in range.
function columnWidth(value) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return COLUMN_WIDTH
  return Math.max(COLUMN_MIN, Math.min(COLUMN_MAX, n))
}

// The COUNT longest names, the ones worth measuring when a column is
// fitted: the length in characters picks them well enough.
function longestNames(entries, count) {
  return (entries || []).map(function(e) { return String(e.name || "") })
    .sort(function(a, b) { return b.length - a.length })
    .slice(0, count || 8)
}

// Width of the window's places sidebar, and of the preview pane in the
// popup and in the window, before the shell's spacing scale. Dragging a
// pane's edge sets them; a double click on it puts the default back.
var SIDEBAR_WIDTH = 210
var SIDEBAR_MIN = 150
var SIDEBAR_MAX = 360
var PREVIEW_WIDTH = 240
var PREVIEW_WINDOW_WIDTH = 290
var PREVIEW_MIN = 180
var PREVIEW_MAX = 560

// A pane width from settings or a dragged edge, whole and between MIN and
// MAX, or FALLBACK for anything that is not a number.
function paneWidth(value, min, max, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

function sidebarWidth(value) {
  return paneWidth(value, SIDEBAR_MIN, SIDEBAR_MAX, SIDEBAR_WIDTH)
}

// FALLBACK is the popup's default or the window's.
function previewWidth(value, fallback) {
  return paneWidth(value, PREVIEW_MIN, PREVIEW_MAX, fallback || PREVIEW_WIDTH)
}

// The scroll offset that brings START to END into a view VIEW wide,
// moving from OFFSET only as far as that needs and never past LAST; when
// both ends do not fit, the start shows.
function revealOffset(offset, start, end, last, view) {
  var x = Math.min(offset, last)
  if (end - x > view) x = end - view
  if (start < x) x = start
  return Math.max(0, x)
}

// Where a grid tile at INDEX was, in tiles across and rows down from where
// it is, after it moved SHIFT places back in a grid COLUMNS wide.
function slotOffset(index, shift, columns) {
  var c = Math.max(1, Math.floor(columns) || 1)
  var from = index + (shift || 0)
  return { x: (from % c) - (index % c), y: Math.floor(from / c) - Math.floor(index / c) }
}

// ---------- Copy, move and name conflicts ----------

// The first free "name (copy).ext", "name (copy 2).ext" ... Folders and dot
// files keep their whole name as the stem.
function uniqueName(names, name, dir) {
  var taken = Object.create(null)
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
  // Another spelling of a folder (a bookmark with // in it) is the same one.
  var to = normalizePath(dest)
  for (var i = 0; i < (sources || []).length; i++) {
    var src = sources[i]
    var name = baseName(src)
    var dir = !!(dirs && dirs[src])
    if (isUnder(to, src)) {
      plan.error = "Cannot put " + name + " inside itself"
      plan.jobs = []
      return plan
    }
    if (parentPath(src) === to) {
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

// files.sh clipboard-get: the files on the clipboard file managers share
// and whether they were cut. state is "files", "empty" (text or nothing)
// or "unavailable" (no wl-paste, so only this widget's own clipboard).
function parseClipboard(raw) {
  var out = { state: "empty", mode: "copy", paths: [] }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] === "clipboard") {
      if (parts[1] === "unavailable") out.state = "unavailable"
      else if (parts[1] === "cut") out.mode = "cut"
    } else if (parts[0] === "file" && parts.length > 1 && parts[1] !== "") {
      out.paths.push(parts.slice(1).join("\t"))
    }
  }
  if (out.paths.length > 0) out.state = "files"
  return out
}

// files.sh thumbnail: the PNG made for a file, or "" when none could be.
function parseThumbnail(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] === "thumbnail" && parts.length > 1 && parts[1] !== "") return parts.slice(1).join("\t")
  }
  return ""
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
// renames, trashed and restored items, created files, mounts, the progress
// figures of a long copy, and a cancel that kept what it wrote.
function parseResult(raw) {
  var out = { errors: [], done: [], trashed: [], restored: [], created: [], mounted: "", total: NaN, progress: NaN, cancelled: false, kept: false }
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
    case "cancelled": out.cancelled = true; out.kept = parts[1] === "kept"; break
    }
  }
  return out
}

// ---------- Text on screen ----------

function statusText(list, selected, deep, where) {
  var n = (list || []).length
  var text = plural(n, "item")
  if (deep) text += " found below " + where + (n >= SEARCH_LIMIT ? " (a search stops at " + SEARCH_LIMIT + ")" : "")
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

// The large preview's hint line, by what it shows.
function lookHints(kind) {
  var out = [{ key: "j/k", label: "previous / next" }, { key: "Space Esc", label: "close" }, { key: "Enter", label: "open" }]
  if (kind === "pdf") out.push({ key: "< >", label: "pages" })
  if (kind === "video" || kind === "audio") out.push({ key: "p", label: "play / pause" })
  if (kind !== "dir") out.push({ key: "o", label: "open with" })
  return out
}

// Where a menu goes in an area: its corner at the pointer, or its right
// edge on X for a button at the right end of the header; turned to the
// other side of the anchor where it would run off the area, and kept inside.
function menuPosition(x, y, width, height, areaWidth, areaHeight, alignRight) {
  var left = alignRight ? x - width : x
  if (!alignRight && left + width > areaWidth) left = x - width
  var top = y
  if (top + height > areaHeight) top = y - height
  return { x: Math.max(0, Math.min(areaWidth - width, left)), y: Math.max(0, Math.min(areaHeight - height, top)) }
}

// Right click on an item. Trash items can only go back or go for good;
// what is inside an archive can be opened, copied out or extracted.
function itemMenu(entry, count, clipboard, bookmarked) {
  if (!entry) return []
  if (entry.trashName) return [
    { id: "restore", label: "Restore", icon: "󰦛", shortcut: "Enter" },
    { id: "purge", label: "Delete for good", icon: "󰆴", shortcut: "Shift+Del", danger: true }
  ]
  if (isArchiveLocation(entry.path)) {
    var inside = [{ id: "open", label: "Open", icon: "󰳋", shortcut: "Enter" }]
    if (!entry.dir) inside.push({ id: "openwith", label: "Open with…", icon: "󰀻", shortcut: "o" })
    inside.push({ id: "copy", label: "Copy out", icon: "󰆏", shortcut: "y" })
    inside.push({ id: "extractto", label: "Extract to…", icon: "󰇚" })
    return inside
  }
  var items = [{ id: "open", label: isArchive(entry) ? "Open as a folder" : "Open", icon: "󰳋", shortcut: "Enter" }]
  if (entry.dir) items.push({ id: "opentab", label: "Open in new tab", icon: "󰐕", shortcut: "Ctrl+Enter" })
  else items.push({ id: "openwith", label: "Open with…", icon: "󰀻", shortcut: "o" })
  if (isArchive(entry)) {
    items.push({ id: "extracthere", label: "Extract here", icon: "󰇚", shortcut: "E" })
    items.push({ id: "extractto", label: "Extract to…", icon: "󰇚" })
  }
  items.push({ id: "compress", label: "Compress to .zip…", icon: "󰗄", shortcut: "Z" })
  items.push({ id: "copy", label: "Copy", icon: "󰆏", shortcut: "y" })
  items.push({ id: "cut", label: "Cut", icon: "󰆐", shortcut: "x" })
  items.push({ id: "copypath", label: "Copy path", icon: "󰌷" })
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
  if (isArchiveLocation(path)) items.push({ id: "extractall", label: "Extract the archive here", icon: "󰇚", shortcut: "E" })
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

// ---------- File chooser ----------

// MIME types whose extensions are not simply the part after the slash.
var MIME_EXTENSIONS = {
  "image/jpeg": ["jpg", "jpeg"],
  "image/svg+xml": ["svg"],
  "image/tiff": ["tif", "tiff"],
  "text/plain": ["txt", "text"],
  "text/markdown": ["md", "markdown"],
  "text/html": ["html", "htm"],
  "application/x-7z-compressed": ["7z"],
  "application/gzip": ["gz", "tgz"],
  "audio/mpeg": ["mp3"],
  "video/quicktime": ["mov"],
  "video/x-matroska": ["mkv"]
}

// The app that asked, from the portal's app id: "com.google.Chrome" is
// Chrome; an app without an id has no name to show.
function chooserApp(appId) {
  var id = String(appId || "")
  return id.slice(id.lastIndexOf(".") + 1)
}

// One of the portal's filters, (label, [(0, glob) or (1, MIME type)]), as
// { label, globs, mimes }.
function chooserFilter(raw) {
  var out = { label: String(raw && raw[0] || ""), globs: [], mimes: [] }
  var patterns = raw && Array.isArray(raw[1]) ? raw[1] : []
  for (var i = 0; i < patterns.length; i++) {
    var p = patterns[i]
    if (!Array.isArray(p) || String(p[1] || "") === "") continue
    if (Number(p[0]) === 1) out.mimes.push(String(p[1]).toLowerCase())
    else out.globs.push(String(p[1]))
  }
  return out
}

// The request's filters; its current filter goes first when the list
// leaves it out, which filechooser.py does the same way to read the answer.
function chooserFilters(list, current) {
  var out = (Array.isArray(list) ? list : []).map(chooserFilter)
  if (current) {
    var c = chooserFilter(current)
    if (!out.some(function(f) { return f.label === c.label })) out.unshift(c)
  }
  return out
}

// What filechooser.py hands the widget for one OpenFile, SaveFile or
// SaveFiles request, as { id, kind, title, app, accept, name, folder,
// files, filters, filter, multiple }: kind is open, folder, save or
// savefiles, and the words, the folder and the name fall back to sensible
// ones when the app gives none.
function chooserRequest(raw, home) {
  var r = raw || {}
  var method = String(r.method || "")
  var kind = method === "SaveFile" ? "save" : method === "SaveFiles" ? "savefiles" : r.directory === true ? "folder" : "open"
  var file = String(r.currentFile || "")
  var folder = String(r.currentFolder || "") || (file ? parentPath(file) : "")
  var filters = chooserFilters(r.filters, r.currentFilter)
  var current = r.currentFilter ? chooserFilter(r.currentFilter).label : ""
  var at = filters.map(function(f) { return f.label }).indexOf(current)
  var saving = kind === "save" || kind === "savefiles"
  return {
    id: String(r.id || ""),
    kind: kind,
    title: String(r.title || "") || (saving ? "Save" : kind === "folder" ? "Choose a folder" : "Open"),
    app: chooserApp(r.app),
    accept: String(r.acceptLabel || "").replace(/_/g, "") || (saving ? "Save" : kind === "folder" ? "Select" : "Open"),
    name: String(r.currentName || "") || (file ? baseName(file) : ""),
    folder: folder.charAt(0) === "/" ? normalizePath(folder) : String(home || "/"),
    files: (Array.isArray(r.files) ? r.files : []).map(String).filter(function(f) { return f !== "" }),
    filters: filters,
    filter: Math.max(0, at),
    multiple: r.multiple === true && (kind === "open" || kind === "folder")
  }
}

// A glob as the portal sends it ("*.pdf", "photo-??.[jp]ng"), matched the
// way people expect a file dialog to, regardless of case.
function globRegExp(glob) {
  var out = ""
  var g = String(glob || "")
  for (var i = 0; i < g.length; i++) {
    var c = g.charAt(i)
    if (c === "*") out += ".*"
    else if (c === "?") out += "."
    else if (c === "[" && g.indexOf("]", i + 2) > i) {
      var end = g.indexOf("]", i + 2)
      var set = g.slice(i + 1, end).replace(/\\/g, "\\\\")
      out += "[" + (set.charAt(0) === "!" ? "^" + set.slice(1) : set) + "]"
      i = end
    } else out += c.replace(/[.+^${}()|[\]\\]/g, "\\$&")
  }
  return new RegExp("^" + out + "$", "i")
}

// Whether a file's name fits MIME, as far as a name tells: image/*, a
// known type, or one whose extension follows its slash.
function mimeFits(mime, entry) {
  var m = String(mime || "").toLowerCase()
  if (m === "*" || m === "*/*" || m === "application/octet-stream") return true
  var major = m.split("/")[0]
  var minor = m.slice(major.length + 1)
  if (minor === "*") {
    if (major === "text") return isTextual(entry)
    return kindOf(entry.name, false) === major
  }
  var exts = MIME_EXTENSIONS[m] || [minor.replace(/^x-/, "")]
  return exts.indexOf(extensionOf(entry.name)) >= 0
}

// Whether FILTER takes the file ENTRY; no filter takes everything.
function filterTakes(filter, entry) {
  if (!filter || (filter.globs.length === 0 && filter.mimes.length === 0)) return true
  for (var i = 0; i < filter.globs.length; i++) if (globRegExp(filter.globs[i]).test(entry.name)) return true
  for (var j = 0; j < filter.mimes.length; j++) if (mimeFits(filter.mimes[j], entry)) return true
  return false
}

// Whether ENTRY can be chosen for REQUEST under its FILTER: a folder when a
// folder is asked for, a file when a file is and the filter takes it;
// nothing in the Trash or inside an archive, which are not files an app
// can open.
function chooserPicks(request, filter, entry) {
  if (!request || !entry || entry.trashName || isArchiveLocation(entry.path)) return false
  if (entry.dir) return request.kind === "folder"
  if (request.kind === "folder" || request.kind === "savefiles") return false
  return filterTakes(request.filters[filter] || null, entry)
}

// The places row above the name: the folder on screen, the folders opened
// lately and the desktop, each once, folders on disk only, MAX at most.
function chooserPlaces(location, visited, home, max) {
  var out = []
  var limit = max || 5
  function add(path) {
    if (!path || isVirtual(path) || out.indexOf(path) >= 0 || out.length >= limit) return
    out.push(path)
  }
  add(location)
  for (var i = 0; i < (visited || []).length; i++) add(visited[i])
  add(joinPath(home, "Desktop"))
  return out
}

// What the dialog answers with: the file to save as NAME in LOCATION, the
// files SaveFiles named there, or what was PICKED that the request can
// take (the first only, unless it takes several); asking for a folder with
// none picked answers with the folder on screen.
function chooserPaths(request, location, name, picked, filter) {
  if (!request) return []
  if (request.kind === "save") return [joinPath(location, String(name || "").trim())]
  if (request.kind === "savefiles") return request.files.map(function(f) { return joinPath(location, f) })
  var list = (picked || []).filter(function(e) { return chooserPicks(request, filter, e) }).map(function(e) { return e.path })
  if (request.kind === "folder" && list.length === 0 && !isVirtual(location)) list = [location]
  return request.multiple ? list : list.slice(0, 1)
}

// Why the dialog cannot answer yet, or "": a name to type or fix, a folder
// to open (the Trash, Recent and archives are not ones to save in), or
// nothing picked.
function chooserProblem(request, location, name, paths) {
  if (!request) return ""
  var saving = request.kind === "save" || request.kind === "savefiles"
  if ((saving || request.kind === "folder") && isVirtual(location)) return saving ? "Open a folder to save in" : "Open a folder first"
  if (request.kind === "save") {
    var n = String(name || "").trim()
    if (n === "") return "Type a name"
    if (n.indexOf("/") >= 0) return "A name cannot hold /"
    if (n === "." || n === "..") return "Type another name"
  }
  if (request.kind === "open" && (paths || []).length === 0) return "Pick a file"
  return ""
}

// The names in the way of PATHS in the folder listed as ENTRIES: files to
// replace or keep both of, and folders, which nothing can be saved over.
function chooserClash(entries, paths) {
  var out = { files: [], folders: [] }
  for (var i = 0; i < (paths || []).length; i++) {
    var at = indexOfPath(entries, paths[i])
    if (at < 0) continue
    if (entries[at].dir) out.folders.push(entries[at].name)
    else out.files.push(entries[at].name)
  }
  return out
}

// PATHS with each name already taken in the listing ENTRIES given a free
// "(copy)" one, for Keep both.
function chooserKeepBoth(entries, paths) {
  var names = (entries || []).map(function(e) { return e.name })
  return (paths || []).map(function(p) {
    var name = uniqueName(names, baseName(p), false)
    names.push(name)
    return joinPath(parentPath(p), name)
  })
}

// ---------- Integrations ----------

// What the widget sets up outside shell.json, in the order files.sh
// applies it: the default file manager, the file chooser and the launcher
// entry.
var INTEGRATIONS = ["default", "chooser", "launcher"]

// The next one files.sh should apply, as { name, state } (on or off), from
// what the settings WANT (by name, true or false) and what was last
// APPLIED (by name, on or off); null once all are in place.
function nextIntegration(want, applied) {
  for (var i = 0; i < INTEGRATIONS.length; i++) {
    var name = INTEGRATIONS[i]
    var state = want && want[name] ? "on" : "off"
    if (!applied || applied[name] !== state) return { name: name, state: state }
  }
  return null
}
