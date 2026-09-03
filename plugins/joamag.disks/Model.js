.pragma library

// Pure helpers for the disks widget: snapshot parsing, mount ordering and
// naming, usage formatting, and the flattened row list the popup walks.

var ICON = "󰋊"

function num(value) {
  // Number(null) is 0; a missing field must stay unknown rather than zero.
  if (value === null || value === undefined || value === "") return NaN
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

// disks.sh emits "mount", "volume" and scalar "key<TAB>value" lines.
function parseSnapshot(raw) {
  var out = { mounts: [], volumes: [], trashKb: NaN, trashItems: NaN, cacheKb: NaN, cacheFiles: NaN }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var parts = line.split("\t")
    switch (parts[0]) {
    case "mount":
      if (parts.length < 11) continue
      out.mounts.push({
        kind: "mount",
        key: "mount:" + parts[1],
        target: parts[1],
        source: parts[2],
        fstype: parts[3],
        sizeKb: num(parts[4]),
        usedKb: num(parts[5]),
        availKb: num(parts[6]),
        pct: num(parts[7]),
        label: parts[8],
        removable: parts[9] === "1",
        disk: parts[10]
      })
      break
    case "volume":
      if (parts.length < 6) continue
      out.volumes.push({ kind: "volume", key: "volume:" + parts[1], path: parts[1], label: parts[2], fstype: parts[3], size: parts[4], disk: parts[5] })
      break
    case "trash_kb": out.trashKb = num(parts[1]); break
    case "trash_items": out.trashItems = num(parts[1]); break
    case "pkgcache_kb": out.cacheKb = num(parts[1]); break
    case "pkgcache_files": out.cacheFiles = num(parts[1]); break
    }
  }
  out.mounts.sort(compareMounts)
  return out
}

// Root first, fixed disks by path, removable media last.
function compareMounts(a, b) {
  if (a.target === "/") return -1
  if (b.target === "/") return 1
  if (a.removable !== b.removable) return a.removable ? 1 : -1
  return a.target < b.target ? -1 : (a.target > b.target ? 1 : 0)
}

function isLoaded(snapshot) {
  return !!snapshot && Array.isArray(snapshot.mounts)
}

// Label when the filesystem has one, "Root" for /, otherwise the last path
// segment ("OMARCHY_202608", "boot", "home").
function mountName(mount) {
  if (!mount) return ""
  if (mount.label) return String(mount.label)
  if (mount.target === "/") return "Root"
  var segments = String(mount.target || "").split("/")
  return segments[segments.length - 1] || String(mount.target || "")
}

function volumeName(volume) {
  if (!volume) return ""
  return volume.label ? String(volume.label) : String(volume.path || "").replace(/^\/dev\//, "")
}

function rootMount(snapshot) {
  if (!isLoaded(snapshot)) return null
  for (var i = 0; i < snapshot.mounts.length; i++) if (snapshot.mounts[i].target === "/") return snapshot.mounts[i]
  return snapshot.mounts.length > 0 ? snapshot.mounts[0] : null
}

function removableCount(snapshot) {
  if (!isLoaded(snapshot)) return 0
  var n = 0
  for (var i = 0; i < snapshot.mounts.length; i++) if (snapshot.mounts[i].removable) n++
  return n
}

// Mounts at or above the warning threshold, read-only media excluded: a
// full ISO is full by design.
function overThreshold(snapshot, warnPct) {
  if (!isLoaded(snapshot)) return []
  var limit = num(warnPct)
  if (!isFinite(limit)) limit = 90
  var out = []
  for (var i = 0; i < snapshot.mounts.length; i++) {
    var m = snapshot.mounts[i]
    if (m.fstype === "iso9660" || m.fstype === "squashfs") continue
    if (isFinite(m.pct) && m.pct >= limit) out.push(m)
  }
  return out
}

function formatKb(kb) {
  var n = num(kb)
  if (!isFinite(n)) return "—"
  var gb = n / 1024 / 1024
  if (gb >= 1000) return (gb / 1024).toFixed(2) + " TB"
  if (gb >= 100) return Math.round(gb) + " GB"
  if (gb >= 1) return gb.toFixed(1) + " GB"
  if (n >= 1024) return Math.round(n / 1024) + " MB"
  return Math.round(n) + " KB"
}

function formatPercent(value) {
  var n = num(value)
  return isFinite(n) && n >= 0 ? Math.round(n) + "%" : "—"
}

function mountDetail(mount) {
  if (!mount) return ""
  var parts = [String(mount.target || "")]
  if (mount.fstype) parts.push(String(mount.fstype))
  parts.push(formatKb(mount.usedKb) + " of " + formatKb(mount.sizeKb))
  if (mount.removable) parts.push("removable")
  return parts.join(" · ")
}

function volumeDetail(volume) {
  if (!volume) return ""
  var parts = [String(volume.path || "")]
  if (volume.fstype) parts.push(String(volume.fstype))
  if (volume.size) parts.push(String(volume.size))
  parts.push("not mounted")
  return parts.join(" · ")
}

function trashDetail(snapshot) {
  if (!isLoaded(snapshot) || !isFinite(snapshot.trashItems)) return "—"
  if (snapshot.trashItems === 0) return "empty"
  return formatKb(snapshot.trashKb) + " · " + snapshot.trashItems + (snapshot.trashItems === 1 ? " item" : " items")
}

function cacheDetail(snapshot) {
  if (!isLoaded(snapshot) || !isFinite(snapshot.cacheKb)) return "—"
  var text = formatKb(snapshot.cacheKb)
  if (isFinite(snapshot.cacheFiles)) text += " · " + snapshot.cacheFiles + (snapshot.cacheFiles === 1 ? " package" : " packages")
  return text
}

// Text on the bar button: the root filesystem as a percentage, free or used
// space, or the icon alone.
function barText(snapshot, mode, vertical) {
  var root = rootMount(snapshot)
  if (vertical || !root || mode === "none") return ICON
  switch (mode) {
  case "free": return ICON + " " + formatKb(root.availKb)
  case "used": return ICON + " " + formatKb(root.usedKb)
  default: return ICON + " " + formatPercent(root.pct)
  }
}

function tooltip(snapshot, warnPct) {
  var root = rootMount(snapshot)
  if (!root) return "Disks"
  var parts = ["Root " + formatKb(root.availKb) + " free"]
  var others = isLoaded(snapshot) ? snapshot.mounts.length - 1 : 0
  if (others > 0) parts.push(others + " other mount" + (others === 1 ? "" : "s"))
  var hot = overThreshold(snapshot, warnPct)
  if (hot.length > 0) parts.push(hot.length + " over " + Math.round(num(warnPct)) + "%")
  return "Disks · " + parts.join(" · ")
}

function heroStatus(snapshot, warnPct) {
  if (!isLoaded(snapshot)) return "LOADING"
  var parts = [snapshot.mounts.length + (snapshot.mounts.length === 1 ? " MOUNT" : " MOUNTS")]
  var removable = removableCount(snapshot) + snapshot.volumes.length
  if (removable > 0) parts.push(removable + " REMOVABLE")
  var hot = overThreshold(snapshot, warnPct)
  if (hot.length > 0) parts.push(hot.length + " OVER " + Math.round(num(warnPct)) + "%")
  return parts.join(" · ")
}

// The popup list: mounts, then unmounted removable volumes, then the two
// cleanup rows, each group under a header so the keyboard cursor can walk
// everything with one index.
function visibleRows(snapshot) {
  var out = []
  if (!isLoaded(snapshot)) return out
  if (snapshot.mounts.length > 0) {
    out.push({ header: true, key: "mounts", title: "MOUNTS", count: snapshot.mounts.length })
    for (var i = 0; i < snapshot.mounts.length; i++) out.push(snapshot.mounts[i])
  }
  if (snapshot.volumes.length > 0) {
    out.push({ header: true, key: "volumes", title: "NOT MOUNTED", count: snapshot.volumes.length })
    for (var j = 0; j < snapshot.volumes.length; j++) out.push(snapshot.volumes[j])
  }
  out.push({ header: true, key: "cleanup", title: "CLEANUP", count: 2 })
  out.push({ kind: "trash", key: "trash" })
  out.push({ kind: "cache", key: "cache" })
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
