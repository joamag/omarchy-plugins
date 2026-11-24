// Tests for joamag.files: Model.js in declaration order, then files.sh in a
// scratch home against xdg-user-dir, lsblk, df, findmnt and gio stand-ins.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawn } = require("node:child_process")
const { loadModel, pluginDir, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.files")

const HOME = "/home/joamag"

// files.sh places the way it prints them: home and two standard folders,
// two bookmarks (one without a label), the system disk, a mounted USB stick,
// a data disk under /mnt with no label and an unmounted stick partition.
const PLACES = [
  "place\thome\t/home/joamag",
  "place\tdownloads\t/home/joamag/Downloads",
  "place\tpictures\t/home/joamag/Pictures",
  "place\tbroken\t",
  "bookmark\t/home/joamag/repo.private\trepo",
  "bookmark\t/home/joamag/Documents/Finance 2026\t",
  "bookmark\t",
  "drive\t/\t/dev/mapper/root\tSystem\t998038831104\t606104150016\t0",
  "drive\t/run/media/joamag/T7\t/dev/sdb1\tT7\t1000000000000\t400000000000\t1",
  "drive\t/mnt/data\t/dev/sda3\t\t400000000000\t\t0",
  "drive\t\t/dev/sdc1\tSTICK\t32000000000\t\t1",
  "drive\tshort",
  "trash\t3",
  "",
].join("\n")

const places = Model.parsePlaces(PLACES)

function entry(name, fields = {}) {
  return Model.makeEntry({ path: `${HOME}/Downloads/${name}`, ...fields })
}

// A folder the way the folder model hands it over.
const LISTING = [
  entry("Zeta", { dir: true, modified: 3000 }),
  entry("alpha", { dir: true, modified: 1000 }),
  entry("file10.txt", { size: 10, modified: 2000 }),
  entry("file2.txt", { size: 300, modified: 1000 }),
  entry("photo.PNG", { size: 50, modified: 5000 }),
  entry(".hidden", { size: 1, modified: 4000 }),
]

describe("num", () => {
  it("parses numbers and keeps missing values unknown", () => {
    assert.equal(Model.num("42"), 42)
    assert.ok(Number.isNaN(Model.num("")))
    assert.ok(Number.isNaN(Model.num(null)))
    assert.ok(Number.isNaN(Model.num(undefined)))
    assert.ok(Number.isNaN(Model.num("x")))
  })
})

describe("normalizePath", () => {
  it("collapses slashes, dots and the trailing slash", () => {
    assert.equal(Model.normalizePath("/home//joamag/./Downloads/"), "/home/joamag/Downloads")
    assert.equal(Model.normalizePath("/home/joamag/../joamag/Music"), "/home/joamag/Music")
    assert.equal(Model.normalizePath("/.."), "/")
    assert.equal(Model.normalizePath("/"), "/")
    assert.equal(Model.normalizePath(""), "")
  })

  it("keeps relative paths relative", () => {
    assert.equal(Model.normalizePath("a/../.."), "..")
    assert.equal(Model.normalizePath("./"), ".")
    assert.equal(Model.normalizePath("a/b/../c"), "a/c")
  })
})

describe("expandPath", () => {
  it("expands home, file URLs and relative names", () => {
    assert.equal(Model.expandPath("~", HOME, "/tmp"), HOME)
    assert.equal(Model.expandPath(" ~/Downloads/ ", HOME, "/tmp"), `${HOME}/Downloads`)
    assert.equal(Model.expandPath("file:///etc/X%2011", HOME, "/tmp"), "/etc/X 11")
    assert.equal(Model.expandPath("sub/../other", HOME, "/srv"), "/srv/other")
    assert.equal(Model.expandPath("Music", HOME, ""), `${HOME}/Music`)
    assert.equal(Model.expandPath("/etc//", HOME, "/tmp"), "/etc")
  })

  it("passes Recent and Trash through and turns blanks into nothing", () => {
    assert.equal(Model.expandPath("trash:", HOME, "/"), Model.TRASH)
    assert.equal(Model.expandPath("recent:", HOME, "/"), Model.RECENT)
    assert.equal(Model.expandPath("   ", HOME, "/"), "")
    assert.equal(Model.expandPath(null, HOME, "/"), "")
  })
})

describe("isVirtual", () => {
  it("knows Recent and Trash only", () => {
    assert.equal(Model.isVirtual(Model.RECENT), true)
    assert.equal(Model.isVirtual(Model.TRASH), true)
    assert.equal(Model.isVirtual("/"), false)
  })
})

describe("isUnder", () => {
  it("matches the folder itself and anything below it", () => {
    assert.equal(Model.isUnder(`${HOME}/Downloads`, HOME), true)
    assert.equal(Model.isUnder(HOME, HOME), true)
    assert.equal(Model.isUnder("/etc", "/"), true)
    assert.equal(Model.isUnder("/home/joamagic", HOME), false)
    assert.equal(Model.isUnder(HOME, `${HOME}/Downloads`), false)
  })

  it("treats Recent, Trash and blanks as separate places", () => {
    assert.equal(Model.isUnder(Model.TRASH, Model.TRASH), true)
    assert.equal(Model.isUnder(Model.TRASH, "/"), false)
    assert.equal(Model.isUnder("/x", Model.TRASH), false)
    assert.equal(Model.isUnder("", ""), false)
  })
})

describe("parentPath", () => {
  it("goes up one folder and stops at the root and the virtual places", () => {
    assert.equal(Model.parentPath(`${HOME}/Downloads`), HOME)
    assert.equal(Model.parentPath("/etc"), "/")
    assert.equal(Model.parentPath("/"), "")
    assert.equal(Model.parentPath(Model.TRASH), "")
    assert.equal(Model.parentPath("relative"), "")
    assert.equal(Model.parentPath(""), "")
  })
})

describe("baseName", () => {
  it("returns the last segment", () => {
    assert.equal(Model.baseName(`${HOME}/a b.txt`), "a b.txt")
    assert.equal(Model.baseName("/"), "/")
    assert.equal(Model.baseName("plain"), "plain")
    assert.equal(Model.baseName(null), "")
  })
})

describe("joinPath", () => {
  it("joins without doubling the root slash", () => {
    assert.equal(Model.joinPath("/", "etc"), "/etc")
    assert.equal(Model.joinPath(HOME, "x"), `${HOME}/x`)
  })
})

describe("prettyPath", () => {
  it("writes home as ~", () => {
    assert.equal(Model.prettyPath(HOME, HOME), "~")
    assert.equal(Model.prettyPath(`${HOME}/Music`, HOME), "~/Music")
    assert.equal(Model.prettyPath("/home/joamagic", HOME), "/home/joamagic")
    assert.equal(Model.prettyPath("/etc", ""), "/etc")
  })
})

describe("fileUrl", () => {
  it("percent-encodes each segment", () => {
    assert.equal(Model.fileUrl("/home/joamag/a b#1.txt"), "file:///home/joamag/a%20b%231.txt")
    assert.equal(Model.fileUrl("/"), "file:///")
  })
})

describe("urlToPath", () => {
  it("decodes local file URLs", () => {
    assert.equal(Model.urlToPath("file:///home/joamag/a%20b.txt"), "/home/joamag/a b.txt")
    assert.equal(Model.urlToPath("file://localhost/etc/"), "/etc")
  })

  it("refuses remote hosts, other schemes and bad escapes", () => {
    assert.equal(Model.urlToPath("file://server/share"), "")
    assert.equal(Model.urlToPath("file://nohost"), "")
    assert.equal(Model.urlToPath("https://example.com/x"), "")
    assert.equal(Model.urlToPath("file:///bad%zz"), "")
  })
})

describe("uriList", () => {
  it("joins file URLs with CRLF, the text/uri-list way", () => {
    assert.equal(Model.uriList(["/a b", "/c"]), "file:///a%20b\r\nfile:///c\r\n")
    assert.equal(Model.uriList([]), "")
    assert.equal(Model.uriList(null), "")
  })
})

describe("parsePlaces", () => {
  it("reads standard folders with their names and glyphs", () => {
    assert.deepEqual(places.places.map((p) => [p.key, p.label, p.path]), [
      ["home", "Home", HOME],
      ["downloads", "Downloads", `${HOME}/Downloads`],
      ["pictures", "Pictures", `${HOME}/Pictures`],
    ])
    assert.equal(places.places[1].icon, Model.PLACE_ICONS.downloads)
  })

  it("reads bookmarks, naming unlabelled ones after their folder", () => {
    assert.deepEqual(places.bookmarks, [
      { path: `${HOME}/repo.private`, label: "repo" },
      { path: `${HOME}/Documents/Finance 2026`, label: "Finance 2026" },
    ])
  })

  it("reads drives with sizes, the removable flag and a display name", () => {
    assert.equal(places.drives.length, 4)
    const [system, t7, data, stick] = places.drives
    assert.equal(system.name, "System")
    assert.equal(system.avail, 606104150016)
    assert.equal(t7.removable, true)
    assert.equal(t7.key, "drive:/dev/sdb1")
    assert.equal(data.name, "sda3")
    assert.ok(Number.isNaN(data.avail))
    assert.equal(stick.mount, "")
    assert.equal(places.trashCount, 3)
  })

  it("starts empty", () => {
    assert.deepEqual(Model.parsePlaces(""), { places: [], bookmarks: [], drives: [], trashCount: 0 })
    assert.equal(Model.parsePlaces("place\tmystery\t/srv/x").places[0].label, "x")
  })
})

describe("driveLabel", () => {
  it("prefers the label, then System for the root, then the device or mount name", () => {
    assert.equal(Model.driveLabel({ label: "T7", mount: "/x" }), "T7")
    assert.equal(Model.driveLabel({ label: "", mount: "/" }), "System")
    assert.equal(Model.driveLabel({ label: "", device: "/dev/sdb3", mount: "/run/media/u/1234-ABCD" }), "sdb3")
    assert.equal(Model.driveLabel({ label: "", device: "", mount: "/mnt/data" }), "data")
    assert.equal(Model.driveLabel(null), "")
  })
})

describe("driveFor", () => {
  it("finds the deepest mount above a path", () => {
    assert.equal(Model.driveFor("/run/media/joamag/T7/Backups", places.drives).name, "T7")
    assert.equal(Model.driveFor(`${HOME}/x`, places.drives).name, "System")
    assert.equal(Model.driveFor("/x", []), null)
  })
})

describe("placeFor", () => {
  it("finds a standard folder by path", () => {
    assert.equal(Model.placeFor(`${HOME}/Pictures`, places.places).key, "pictures")
    assert.equal(Model.placeFor("/nowhere", places.places), null)
    assert.equal(Model.placeFor("/nowhere", null), null)
  })
})

describe("placeLabel", () => {
  it("names places, drives and plain folders", () => {
    assert.equal(Model.placeLabel(Model.TRASH, HOME, [], []), "Trash")
    assert.equal(Model.placeLabel(Model.RECENT, HOME, [], []), "Recent")
    assert.equal(Model.placeLabel(`${HOME}/Downloads`, HOME, places.places, places.drives), "Downloads")
    assert.equal(Model.placeLabel(HOME, HOME, [], []), "Home")
    assert.equal(Model.placeLabel("/run/media/joamag/T7", HOME, places.places, places.drives), "T7")
    assert.equal(Model.placeLabel("/", HOME, [], []), "System")
    assert.equal(Model.placeLabel("/etc/X11", HOME, places.places, places.drives), "X11")
  })
})

describe("placeIcon", () => {
  it("picks a glyph per place, drive kind or plain folder", () => {
    assert.equal(Model.placeIcon(Model.TRASH, HOME, [], []), Model.GLYPHS.trash)
    assert.equal(Model.placeIcon(Model.RECENT, HOME, [], []), Model.GLYPHS.recent)
    assert.equal(Model.placeIcon(`${HOME}/Pictures`, HOME, places.places, []), Model.PLACE_ICONS.pictures)
    assert.equal(Model.placeIcon(HOME, HOME, [], []), Model.PLACE_ICONS.home)
    assert.equal(Model.placeIcon("/run/media/joamag/T7", HOME, [], places.drives), Model.GLYPHS.removable)
    assert.equal(Model.placeIcon("/mnt/data", HOME, [], places.drives), Model.GLYPHS.drive)
    assert.equal(Model.placeIcon("/", HOME, [], []), Model.GLYPHS.drive)
    assert.equal(Model.placeIcon("/etc", HOME, [], []), Model.KIND_ICONS.dir)
  })
})

describe("crumbs", () => {
  it("starts from home for paths inside it", () => {
    assert.deepEqual(Model.crumbs(`${HOME}/Downloads/fonts`, HOME, places.drives), [
      { label: "Home", path: HOME },
      { label: "Downloads", path: `${HOME}/Downloads` },
      { label: "fonts", path: `${HOME}/Downloads/fonts` },
    ])
    assert.deepEqual(Model.crumbs(HOME, HOME, places.drives), [{ label: "Home", path: HOME }])
  })

  it("starts from a drive or the system root otherwise", () => {
    assert.deepEqual(Model.crumbs("/run/media/joamag/T7/Backups", HOME, places.drives).map((c) => c.label), ["T7", "Backups"])
    assert.deepEqual(Model.crumbs("/etc/X11", HOME, []).map((c) => c.path), ["/", "/etc", "/etc/X11"])
    // A drive mounted inside home still starts from the drive.
    const inside = [{ mount: `${HOME}/mnt`, name: "Inside", device: "/dev/sdz1" }]
    assert.deepEqual(Model.crumbs(`${HOME}/mnt/a`, HOME, inside).map((c) => c.label), ["Inside", "a"])
  })

  it("is a single segment for Recent and Trash", () => {
    assert.deepEqual(Model.crumbs(Model.TRASH, HOME, []), [{ label: "Trash", path: Model.TRASH }])
  })
})

describe("goTargets", () => {
  it("maps letters to places and digits to bookmarks then drives", () => {
    const targets = Model.goTargets(places.places, places.bookmarks, places.drives)
    assert.deepEqual(targets.map((t) => `${t.key}:${t.label}`), [
      "h:Home", "d:Downloads", "p:Pictures", "r:Recent", "t:Trash", "/:System",
      "1:repo", "2:Finance 2026", "3:T7", "4:sda3",
    ])
    assert.equal(targets.find((t) => t.key === "/").path, "/")
  })

  it("stops at nine digits", () => {
    const many = Array.from({ length: 12 }, (_, i) => ({ path: `/b${i}`, label: `b${i}` }))
    const targets = Model.goTargets([], many, places.drives)
    assert.equal(targets.filter((t) => /^\d$/.test(t.key)).length, 9)
    assert.deepEqual(Model.goTargets(null, null, null).map((t) => t.key), ["r", "t", "/"])
  })
})

describe("normalizeView", () => {
  it("accepts the three views", () => {
    assert.equal(Model.normalizeView("grid"), "grid")
    assert.equal(Model.normalizeView("tree"), "list")
  })
})

describe("newTab", () => {
  it("starts a history at the path", () => {
    assert.deepEqual(Model.newTab(HOME, "columns"), { path: HOME, view: "columns", history: [HOME], pos: 0 })
    assert.equal(Model.newTab(HOME).view, "list")
  })
})

describe("parseTabs", () => {
  it("reads saved tabs, bare paths and JSON strings", () => {
    const tabs = Model.parseTabs([{ path: `${HOME}/Downloads/`, view: "grid" }, "/etc", { path: Model.TRASH }], HOME)
    assert.deepEqual(tabs.map((t) => [t.path, t.view]), [[`${HOME}/Downloads`, "grid"], ["/etc", "list"], [Model.TRASH, "list"]])
    assert.deepEqual(Model.parseTabs('[{"path":"/srv","view":"columns"}]', HOME).map((t) => t.view), ["columns"])
  })

  it("drops junk and falls back to home", () => {
    assert.deepEqual(Model.parseTabs([null, 3, { path: "" }, { path: "relative" }, { view: "grid" }], HOME).map((t) => t.path), [HOME])
    assert.deepEqual(Model.parseTabs("not json", HOME).map((t) => t.path), [HOME])
    assert.deepEqual(Model.parseTabs(undefined, "").map((t) => t.path), ["/"])
  })

  it("keeps at most MAX_TABS", () => {
    const many = Array.from({ length: 20 }, (_, i) => `/t${i}`)
    assert.equal(Model.parseTabs(many, HOME).length, Model.MAX_TABS)
  })
})

describe("serializeTabs", () => {
  it("saves path and view only", () => {
    assert.deepEqual(Model.serializeTabs([Model.navigateTab(Model.newTab(HOME, "grid"), "/etc")]), [{ path: "/etc", view: "grid" }])
    assert.deepEqual(Model.serializeTabs(null), [])
  })
})

describe("navigateTab", () => {
  it("pushes onto the history and drops what was forward", () => {
    let tab = Model.newTab("/a", "list")
    tab = Model.navigateTab(tab, "/b")
    tab = Model.navigateTab(tab, "/c")
    tab = Model.tabBack(Model.tabBack(tab))
    tab = Model.navigateTab(tab, "/d")
    assert.deepEqual(tab.history, ["/a", "/d"])
    assert.equal(tab.pos, 1)
  })

  it("does nothing for the same path or no path", () => {
    const tab = Model.newTab("/a", "list")
    assert.equal(Model.navigateTab(tab, "/a"), tab)
    assert.equal(Model.navigateTab(tab, ""), tab)
    assert.equal(Model.navigateTab(null, "/x"), null)
  })
})

describe("canGoBack", () => {
  it("needs history behind", () => {
    assert.equal(Model.canGoBack(Model.newTab("/a")), false)
    assert.equal(Model.canGoBack(Model.navigateTab(Model.newTab("/a"), "/b")), true)
    assert.equal(Model.canGoBack(null), false)
  })
})

describe("canGoForward", () => {
  it("needs history ahead", () => {
    const tab = Model.navigateTab(Model.newTab("/a"), "/b")
    assert.equal(Model.canGoForward(tab), false)
    assert.equal(Model.canGoForward(Model.tabBack(tab)), true)
    assert.equal(Model.canGoForward(null), false)
  })
})

describe("tabBack", () => {
  it("steps back, or stays at the start", () => {
    const tab = Model.navigateTab(Model.newTab("/a", "grid"), "/b")
    assert.deepEqual(Model.tabBack(tab), { path: "/a", view: "grid", history: ["/a", "/b"], pos: 0 })
    const start = Model.newTab("/a")
    assert.equal(Model.tabBack(start), start)
  })
})

describe("tabForward", () => {
  it("steps forward, or stays at the end", () => {
    const tab = Model.navigateTab(Model.newTab("/a"), "/b")
    assert.equal(Model.tabForward(Model.tabBack(tab)).path, "/b")
    assert.equal(Model.tabForward(tab), tab)
  })
})

describe("withView", () => {
  it("switches the view and keeps the history", () => {
    const tab = Model.navigateTab(Model.newTab("/a"), "/b")
    const grid = Model.withView(tab, "grid")
    assert.equal(grid.view, "grid")
    assert.deepEqual(grid.history, tab.history)
    assert.equal(Model.withView(tab, "nope").view, "list")
  })
})

describe("nextView", () => {
  it("cycles list, grid, columns", () => {
    assert.equal(Model.nextView("list"), "grid")
    assert.equal(Model.nextView("columns"), "list")
    assert.equal(Model.nextView("bogus"), "list")
  })
})

describe("wrapIndex", () => {
  it("wraps both ways", () => {
    assert.equal(Model.wrapIndex(3, 3), 0)
    assert.equal(Model.wrapIndex(-1, 3), 2)
    assert.equal(Model.wrapIndex(5, 0), 0)
  })
})

describe("addTab", () => {
  it("opens right after the active tab", () => {
    const tabs = ["/a", "/b", "/c"].map((p) => Model.newTab(p))
    const result = Model.addTab(tabs, 0, Model.newTab("/x"))
    assert.deepEqual(result.tabs.map((t) => t.path), ["/a", "/x", "/b", "/c"])
    assert.equal(result.active, 1)
  })

  it("refuses past MAX_TABS", () => {
    const tabs = Array.from({ length: Model.MAX_TABS }, (_, i) => Model.newTab(`/t${i}`))
    const result = Model.addTab(tabs, 3, Model.newTab("/x"))
    assert.equal(result.tabs, tabs)
    assert.equal(result.active, 3)
  })
})

describe("closeTab", () => {
  const tabs = ["/a", "/b", "/c"].map((p) => Model.newTab(p))

  it("keeps the active tab on screen, or its neighbour when it closes", () => {
    assert.deepEqual(Model.closeTab(tabs, 0, 2), { tabs: [tabs[1], tabs[2]], active: 1 })
    assert.deepEqual(Model.closeTab(tabs, 2, 2).active, 1)
    assert.deepEqual(Model.closeTab(tabs, 1, 1).active, 1)
    assert.deepEqual(Model.closeTab(tabs, 2, 0).active, 0)
  })

  it("keeps the last tab and ignores bad indexes", () => {
    const one = [Model.newTab("/a")]
    assert.equal(Model.closeTab(one, 0, 0).tabs, one)
    assert.equal(Model.closeTab(tabs, 9, 0).tabs, tabs)
    assert.equal(Model.closeTab(tabs, -1, 0).tabs, tabs)
  })
})

describe("retargetTabs", () => {
  const tabs = [Model.newTab(`${HOME}/Downloads/fonts`, "grid"), Model.newTab(`${HOME}/Music`), Model.newTab(`${HOME}/Downloads`)]

  it("carries tabs along with a moved or renamed folder", () => {
    const moved = Model.retargetTabs(tabs, `${HOME}/Downloads`, `${HOME}/Inbox`)
    assert.deepEqual(moved.map((t) => t.path), [`${HOME}/Inbox/fonts`, `${HOME}/Music`, `${HOME}/Inbox`])
    assert.equal(moved[0].view, "grid")
    assert.deepEqual(moved[0].history, [`${HOME}/Inbox/fonts`])
  })

  it("sends tabs to the parent of a folder that went away", () => {
    assert.deepEqual(Model.retargetTabs(tabs, `${HOME}/Downloads/fonts`, "").map((t) => t.path), [`${HOME}/Downloads`, `${HOME}/Music`, `${HOME}/Downloads`])
    assert.deepEqual(Model.retargetTabs([Model.newTab("/srv")], "/srv", "").map((t) => t.path), ["/"])
  })

  it("sends every tab on an ejected drive to one place", () => {
    const drive = [Model.newTab("/run/media/joamag/T7/Backups")]
    assert.deepEqual(Model.retargetTabs(drive, "/run/media/joamag/T7", HOME, true).map((t) => t.path), [HOME])
  })

  it("returns the same list when nothing moves", () => {
    assert.equal(Model.retargetTabs(tabs, "/etc", "/srv"), tabs)
    assert.equal(Model.retargetTabs(tabs, Model.TRASH, "/srv"), tabs)
  })
})

describe("extensionOf", () => {
  it("lower-cases the last extension and ignores dot files", () => {
    assert.equal(Model.extensionOf("a.TAR.GZ"), "gz")
    assert.equal(Model.extensionOf(".bashrc"), "")
    assert.equal(Model.extensionOf("trailing."), "")
    assert.equal(Model.extensionOf("plain"), "")
  })
})

describe("kindOf", () => {
  it("groups files by extension", () => {
    assert.equal(Model.kindOf("x", true), "dir")
    assert.equal(Model.kindOf("a.jpg", false), "image")
    assert.equal(Model.kindOf("a.mkv", false), "video")
    assert.equal(Model.kindOf("a.qml", false), "code")
    assert.equal(Model.kindOf("a.woff2", false), "font")
    assert.equal(Model.kindOf("a.weird", false), "file")
  })
})

describe("typeLabel", () => {
  it("names folders, known text types, images by format and the rest by kind", () => {
    assert.equal(Model.typeLabel(entry("a", { dir: true })), "Folder")
    assert.equal(Model.typeLabel(entry("notes.md")), "Markdown")
    assert.equal(Model.typeLabel(entry("shot.png")), "PNG image")
    assert.equal(Model.typeLabel(entry("talk.mkv")), "Video")
    assert.equal(Model.typeLabel(entry("blob")), "File")
    assert.equal(Model.typeLabel(null), "")
  })
})

describe("typeFor", () => {
  it("names a type from its extension and kind", () => {
    assert.equal(Model.typeFor("md", "text"), "Markdown")
    assert.equal(Model.typeFor("webp", "image"), "WEBP image")
    assert.equal(Model.typeFor("", "image"), "Image")
    assert.equal(Model.typeFor("iso", "disc"), "Disk image")
  })
})

describe("kindIcon", () => {
  it("falls back to the plain file glyph", () => {
    assert.equal(Model.kindIcon("dir"), Model.KIND_ICONS.dir)
    assert.equal(Model.kindIcon("unknown"), Model.KIND_ICONS.file)
  })
})

describe("isImage", () => {
  it("is true for formats Qt decodes", () => {
    assert.equal(Model.isImage(entry("a.WebP")), true)
    assert.equal(Model.isImage(entry("a.heic")), false)
    assert.equal(Model.isImage(entry("a.png", { dir: true })), false)
    assert.equal(Model.isImage(null), false)
  })
})

describe("isTextual", () => {
  it("previews small text, code and extensionless files", () => {
    assert.equal(Model.isTextual(entry("a.md", { size: 100 })), true)
    assert.equal(Model.isTextual(entry("a.qml", { size: 100 })), true)
    assert.equal(Model.isTextual(entry("Makefile", { size: 100 })), true)
    assert.equal(Model.isTextual(entry("a.md", { size: 300000 })), false)
    assert.equal(Model.isTextual(entry("a.bin")), false)
    assert.equal(Model.isTextual(entry("docs", { dir: true })), false)
    assert.equal(Model.isTextual(null), false)
  })
})

describe("previewKind", () => {
  it("shows pictures and PDF pages itself", () => {
    assert.equal(Model.previewKind(entry("a.png")), "image")
    assert.equal(Model.previewKind(entry("a.PDF")), "pdf")
  })

  it("shows text, asks a thumbnailer for media and documents, and nothing else", () => {
    assert.equal(Model.previewKind(entry("a.md", { size: 10 })), "text")
    for (const name of ["a.mp4", "a.flac", "a.docx", "a.ods", "a.pptx", "a.ttf", "a.heic"]) assert.equal(Model.previewKind(entry(name)), "thumbnail", name)
    assert.equal(Model.previewKind(entry("a.zip")), "none")
    assert.equal(Model.previewKind(entry("d", { dir: true })), "dir")
    assert.equal(Model.previewKind(Model.makeEntry({ path: "" })), "none")
    assert.equal(Model.previewKind(null), "none")
  })
})

describe("thumbnailKey", () => {
  it("changes with the file's date and the size asked for", () => {
    const a = entry("a.mp4", { modified: 5 })
    assert.equal(Model.thumbnailKey(a, 256), `${HOME}/Downloads/a.mp4|5|256`)
    assert.notEqual(Model.thumbnailKey(a, 512), Model.thumbnailKey(a, 256))
    assert.equal(Model.thumbnailKey(null, 256), "")
  })
})

describe("previewText", () => {
  it("keeps the first lines of text", () => {
    assert.equal(Model.previewText("a\nb\tc\nd\n", 2), "a\nb\tc")
    assert.equal(Model.previewText("", 3), "")
    assert.equal(Model.previewText(null, 3), "")
  })

  it("gives up on binary content", () => {
    assert.equal(Model.previewText("\u007fELF\u0002\u0001\u0000", 5), null)
    assert.equal(Model.previewText("caf\uFFFD", 5), null)
    // ANSI colours in a log are still text.
    assert.equal(Model.previewText("\u001b[31mred\u001b[0m", 5), "\u001b[31mred\u001b[0m")
  })
})

describe("makeEntry", () => {
  it("fills name, kind, type, hidden and the sort keys from the path", () => {
    const e = Model.makeEntry({ path: "/x/.Notes 2.md", size: "12", modified: 5 })
    assert.deepEqual(e, {
      name: ".Notes 2.md", path: "/x/.Notes 2.md", dir: false, size: 12, modified: 5, hidden: true, kind: "text", type: "Markdown",
      lower: ".notes 2.md", key: ".notes 0000000000000002.md", origin: "", trashName: "",
    })
    assert.equal(Model.makeEntry({ path: "/x/plain" }).key, "plain")
  })

  it("leaves folders without a size", () => {
    const e = Model.makeEntry({ path: "/x/d.zip", dir: true, size: 4096, origin: "/o", trashName: "d.2" })
    assert.ok(Number.isNaN(e.size))
    assert.equal(e.kind, "dir")
    assert.equal(e.type, "Folder")
    assert.equal(e.origin, "/o")
    assert.equal(e.trashName, "d.2")
    assert.equal(Model.makeEntry({}).path, "")
  })
})

describe("parseTime", () => {
  it("reads epoch seconds", () => {
    assert.equal(Model.parseTime("1700000000.75"), 1700000000750)
    assert.equal(Model.parseTime(12), 12000)
  })

  it("reads UTC dates with a Z and local dates without", () => {
    assert.equal(Model.parseTime("2026-11-20T10:00:00.5Z"), Date.UTC(2026, 10, 20, 10, 0, 0, 500))
    assert.equal(Model.parseTime("2026-11-20T10:00:00.802543Z"), Date.UTC(2026, 10, 20, 10, 0, 0, 802))
    assert.equal(Model.parseTime(" 2026-11-24T10:00:00 "), new Date(2026, 10, 24, 10).getTime())
  })

  it("is NaN for anything else", () => {
    assert.ok(Number.isNaN(Model.parseTime("nope")))
    assert.ok(Number.isNaN(Model.parseTime("2026-11-24")))
    assert.ok(Number.isNaN(Model.parseTime("")))
    assert.ok(Number.isNaN(Model.parseTime(null)))
    assert.ok(Number.isNaN(Model.parseTime(undefined)))
  })
})

describe("parseEntries", () => {
  it("reads entry lines with either kind of time", () => {
    const raw = [
      "entry\tf\t120\t1700000000\t/home/joamag/a.txt\t\t",
      "entry\td\t\t1700000001.75\t/home/joamag/dir",
      "entry\tf\t9\tnope\t/home/joamag/Trash/files/b.2.txt\t/home/joamag/Documents/b.txt\tb.2.txt",
      "entry\tf\t3\t2026-11-22T10:00:00Z\t/home/joamag/c.txt",
      "entry\tf\t1\t1\t",
      "junk",
      "",
    ].join("\n")
    const list = Model.parseEntries(raw)
    assert.equal(list.length, 4)
    assert.equal(list[0].modified, 1700000000000)
    assert.equal(list[0].size, 120)
    assert.equal(list[1].dir, true)
    assert.equal(list[1].modified, 1700000001750)
    assert.equal(list[2].name, "b.txt")
    assert.equal(list[2].trashName, "b.2.txt")
    assert.equal(list[2].origin, "/home/joamag/Documents/b.txt")
    assert.ok(Number.isNaN(list[2].modified))
    assert.equal(list[3].modified, Date.UTC(2026, 10, 22, 10))
    assert.deepEqual(Model.parseEntries(""), [])
  })
})

describe("padNumber", () => {
  it("pads to a fixed width so string order is numeric order", () => {
    assert.equal(Model.padNumber(12), "0000000000000012")
    assert.equal(Model.padNumber(2.9), "0000000000000002")
    assert.equal(Model.padNumber(-3), "0000000000000000")
    assert.ok(Model.padNumber(9) < Model.padNumber(10))
    assert.equal(Model.padNumber(1e17), "100000000000000000")
  })
})

describe("naturalKey", () => {
  it("lower-cases and pads every run of digits", () => {
    assert.equal(Model.naturalKey("File2.TXT"), "file0000000000000002.txt")
    assert.ok(Model.naturalKey("file2") < Model.naturalKey("file10"))
    assert.equal(Model.naturalKey("a007"), Model.naturalKey("a7"))
    assert.equal(Model.naturalKey(null), "")
  })
})

describe("normalizeSortKey", () => {
  it("accepts the four columns", () => {
    assert.equal(Model.normalizeSortKey("size"), "size")
    assert.equal(Model.normalizeSortKey("colour"), "name")
  })
})

describe("defaultDescending", () => {
  it("puts newest and largest first", () => {
    assert.equal(Model.defaultDescending("modified"), true)
    assert.equal(Model.defaultDescending("size"), true)
    assert.equal(Model.defaultDescending("name"), false)
  })
})

describe("nextSort", () => {
  it("flips the current column and starts others in their natural order", () => {
    assert.deepEqual(Model.nextSort("name", false, "name"), { key: "name", descending: true })
    assert.deepEqual(Model.nextSort("name", true, "modified"), { key: "modified", descending: true })
    assert.deepEqual(Model.nextSort("size", true, "type"), { key: "type", descending: false })
  })
})

describe("cycleSortKey", () => {
  it("walks the columns", () => {
    assert.equal(Model.cycleSortKey("name"), "modified")
    assert.equal(Model.cycleSortKey("type"), "name")
    assert.equal(Model.cycleSortKey("bogus"), "name")
  })
})

describe("sortString", () => {
  it("leads with the column, then the natural and the raw name", () => {
    const e = entry("File2.txt", { size: 41, modified: 7 })
    assert.equal(Model.sortString(e, "name"), "\u0001file0000000000000002.txt\u0001File2.txt")
    assert.equal(Model.sortString(e, "modified"), "0000000000000007\u0001file0000000000000002.txt\u0001File2.txt")
    assert.equal(Model.sortString(e, "size"), "0000000000000042\u0001file0000000000000002.txt\u0001File2.txt")
    assert.equal(Model.sortString(e, "type"), "plain text\u0001file0000000000000002.txt\u0001File2.txt")
  })

  it("puts unknown sizes and dates first", () => {
    const dir = entry("d", { dir: true })
    assert.ok(Model.sortString(dir, "size") < Model.sortString(entry("e", { size: 0 }), "size"))
    assert.ok(Model.sortString(dir, "modified").startsWith("0000000000000000"))
  })
})

describe("sortEntries", () => {
  it("sorts by name, naturally, folders first either way", () => {
    assert.deepEqual(Model.sortEntries(LISTING, "name", false).map((e) => e.name), ["alpha", "Zeta", ".hidden", "file2.txt", "file10.txt", "photo.PNG"])
    assert.deepEqual(Model.sortEntries(LISTING, "name", true).map((e) => e.name), ["Zeta", "alpha", "photo.PNG", "file10.txt", "file2.txt", ".hidden"])
  })

  it("sorts by date, size and type, ties by name", () => {
    assert.deepEqual(Model.sortEntries(LISTING, "modified", false).map((e) => e.name), ["alpha", "Zeta", "file2.txt", "file10.txt", ".hidden", "photo.PNG"])
    assert.deepEqual(Model.sortEntries(LISTING, "modified", true).map((e) => e.name), ["Zeta", "alpha", "photo.PNG", ".hidden", "file10.txt", "file2.txt"])
    assert.deepEqual(Model.sortEntries(LISTING, "size", true).map((e) => e.name), ["Zeta", "alpha", "file2.txt", "photo.PNG", "file10.txt", ".hidden"])
    // File, Plain text, PNG image.
    assert.deepEqual(Model.sortEntries(LISTING, "type", false).map((e) => e.name), ["alpha", "Zeta", ".hidden", "file2.txt", "file10.txt", "photo.PNG"])
  })

  it("keeps names that differ only in case or zeros in a fixed order", () => {
    const list = [entry("b"), entry("a01"), entry("B"), entry("a1")]
    assert.deepEqual(Model.sortEntries(list, "name", false).map((e) => e.name), ["a01", "a1", "B", "b"])
  })

  it("leaves the input alone and accepts nothing", () => {
    const copy = LISTING.slice()
    Model.sortEntries(LISTING, "bogus", false)
    assert.deepEqual(LISTING, copy)
    assert.deepEqual(Model.sortEntries(null, "name", false), [])
  })
})

describe("filterEntries", () => {
  it("matches part of the name, case-insensitively", () => {
    assert.deepEqual(Model.filterEntries(LISTING, "FILE", false).map((e) => e.name), ["file10.txt", "file2.txt"])
  })

  it("hides dot files unless they are shown", () => {
    assert.equal(Model.filterEntries(LISTING, "", false).length, 5)
    assert.equal(Model.filterEntries(LISTING, "", true).length, 6)
    assert.deepEqual(Model.filterEntries(null, "x", true), [])
  })
})

describe("formatSize", () => {
  it("counts in decimal units", () => {
    assert.equal(Model.formatSize(1), "1 byte")
    assert.equal(Model.formatSize(999), "999 bytes")
    assert.equal(Model.formatSize(1000), "1.0 kB")
    assert.equal(Model.formatSize(412000), "412 kB")
    assert.equal(Model.formatSize(2100000000), "2.1 GB")
    assert.equal(Model.formatSize(999999), "1.0 MB")
    assert.equal(Model.formatSize(5e18), "5000 PB")
  })

  it("prints nothing for unknown sizes", () => {
    assert.equal(Model.formatSize(NaN), "")
    assert.equal(Model.formatSize(-1), "")
    assert.equal(Model.formatSize(""), "")
  })
})

describe("pad2", () => {
  it("pads single digits", () => {
    assert.equal(Model.pad2(7), "07")
    assert.equal(Model.pad2(12), "12")
  })
})

describe("formatDate", () => {
  const now = new Date(2026, 10, 24, 13, 58).getTime()

  it("shows the time today, Yesterday, the day this year and the year before", () => {
    assert.equal(Model.formatDate(new Date(2026, 10, 24, 9, 5).getTime(), now), "09:05")
    assert.equal(Model.formatDate(new Date(2026, 10, 23, 23, 59).getTime(), now), "Yesterday")
    assert.equal(Model.formatDate(new Date(2026, 0, 3).getTime(), now), "3 Jan")
    assert.equal(Model.formatDate(new Date(2025, 11, 31).getTime(), now), "31 Dec 2025")
  })

  it("prints nothing for unknown dates", () => {
    assert.equal(Model.formatDate(NaN, now), "")
    assert.equal(Model.formatDate(0, now), "")
    assert.notEqual(Model.formatDate(Date.now(), undefined), "")
  })
})

describe("formatFullDate", () => {
  it("spells out day, month, year and time", () => {
    assert.equal(Model.formatFullDate(new Date(2026, 10, 24, 13, 8).getTime()), "24 Nov 2026, 13:08")
    assert.equal(Model.formatFullDate(NaN), "")
  })
})

describe("plural", () => {
  it("adds an s, or the given plural", () => {
    assert.equal(Model.plural(1, "item"), "1 item")
    assert.equal(Model.plural(2, "item"), "2 items")
    assert.equal(Model.plural(0, "copy", "copies"), "0 copies")
  })
})

describe("itemsLabel", () => {
  it("names one item or counts several", () => {
    assert.equal(Model.itemsLabel(1, "a.txt"), "a.txt")
    assert.equal(Model.itemsLabel(3, "a.txt"), "3 items")
    assert.equal(Model.itemsLabel(1, null), "")
  })
})

describe("indexOfPath", () => {
  it("finds an entry by path", () => {
    assert.equal(Model.indexOfPath(LISTING, `${HOME}/Downloads/alpha`), 1)
    assert.equal(Model.indexOfPath(LISTING, "/x"), -1)
    assert.equal(Model.indexOfPath(null, "/x"), -1)
  })
})

describe("clampIndex", () => {
  it("keeps an index in range", () => {
    assert.equal(Model.clampIndex(9, 3), 2)
    assert.equal(Model.clampIndex(-2, 3), 0)
    assert.equal(Model.clampIndex(4, 0), 0)
  })
})

describe("toggleSelected", () => {
  it("adds and removes without touching the input", () => {
    const sel = ["/a"]
    assert.deepEqual(Model.toggleSelected(sel, "/b"), ["/a", "/b"])
    assert.deepEqual(Model.toggleSelected(sel, "/a"), [])
    assert.deepEqual(sel, ["/a"])
    assert.deepEqual(Model.toggleSelected(null, "/a"), ["/a"])
  })
})

describe("rangePaths", () => {
  it("takes everything between anchor and cursor, either way round", () => {
    assert.deepEqual(Model.rangePaths(LISTING, 3, 1).map(Model.baseName), ["alpha", "file10.txt", "file2.txt"])
    assert.deepEqual(Model.rangePaths(LISTING, 4, 99).map(Model.baseName), ["photo.PNG", ".hidden"])
    assert.deepEqual(Model.rangePaths([], 0, 1), [])
  })
})

describe("pickedEntries", () => {
  it("returns the selection in list order", () => {
    const sel = [LISTING[3].path, LISTING[0].path]
    assert.deepEqual(Model.pickedEntries(LISTING, sel, 5).map((e) => e.name), ["Zeta", "file2.txt"])
  })

  it("falls back to the cursor entry, or nothing", () => {
    assert.deepEqual(Model.pickedEntries(LISTING, [], 2).map((e) => e.name), ["file10.txt"])
    assert.deepEqual(Model.pickedEntries(LISTING, ["/gone"], -1), [])
    assert.deepEqual(Model.pickedEntries(null, null, 0), [])
  })
})

describe("keepSelected", () => {
  it("drops paths that are no longer listed", () => {
    assert.deepEqual(Model.keepSelected([LISTING[0].path, "/gone"], LISTING), [LISTING[0].path])
    assert.deepEqual(Model.keepSelected(null, LISTING), [])
  })
})

describe("wheelRows", () => {
  it("turns a notch into the wheel step, up positive", () => {
    assert.deepEqual(Model.wheelRows(0, 120, 3), { rows: 3, carry: 0 })
    assert.deepEqual(Model.wheelRows(0, -240, 3), { rows: -6, carry: 0 })
    assert.deepEqual(Model.wheelRows(0, 120, 1), { rows: 1, carry: 0 })
  })

  it("adds a touchpad's small deltas up to whole rows", () => {
    let step = Model.wheelRows(0, -15, 3)
    assert.deepEqual(step, { rows: 0, carry: -15 })
    step = Model.wheelRows(step.carry, -30, 3)
    assert.deepEqual(step, { rows: -1, carry: -5 })
    // Turning back spends what was carried first.
    assert.deepEqual(Model.wheelRows(-5, 10, 3), { rows: 0, carry: 5 })
  })

  it("treats a missing step or delta as nothing", () => {
    assert.deepEqual(Model.wheelRows(undefined, null, 0), { rows: 0, carry: 0 })
    assert.deepEqual(Model.wheelRows(0, 120, 0), { rows: 1, carry: 0 })
  })
})

describe("steppedScroll", () => {
  it("moves by whole rows and lands on a row edge", () => {
    assert.equal(Model.steppedScroll(0, 3, 26, 2600, 260), 78)
    assert.equal(Model.steppedScroll(80, 3, 26, 2600, 260), 156)
    assert.equal(Model.steppedScroll(78, -1, 26, 2600, 260), 52)
  })

  it("stays inside the content", () => {
    assert.equal(Model.steppedScroll(2300, 10, 26, 2600, 260), 2340)
    assert.equal(Model.steppedScroll(26, -5, 26, 2600, 260), 0)
    assert.equal(Model.steppedScroll(0, 3, 26, 100, 260), 0)
  })

  it("leaves the offset alone without a row size", () => {
    assert.equal(Model.steppedScroll(40, 3, 0, 2600, 260), 40)
  })
})

describe("uniqueName", () => {
  it("returns a free name unchanged", () => {
    assert.equal(Model.uniqueName(["b.txt"], "a.txt", false), "a.txt")
    assert.equal(Model.uniqueName(null, "a.txt", false), "a.txt")
  })

  it("adds (copy) before the extension, then numbers", () => {
    assert.equal(Model.uniqueName(["a.txt"], "a.txt", false), "a (copy).txt")
    assert.equal(Model.uniqueName(["a.txt", "a (copy).txt", "a (copy 2).txt"], "a.txt", false), "a (copy 3).txt")
  })

  it("keeps folders and dot files whole", () => {
    assert.equal(Model.uniqueName(["my.dir"], "my.dir", true), "my.dir (copy)")
    assert.equal(Model.uniqueName([".bashrc"], ".bashrc", false), ".bashrc (copy)")
  })
})

describe("planTransfer", () => {
  const dest = `${HOME}/Documents`
  const names = ["report.pdf", "notes"]

  it("flags the names already taken", () => {
    const plan = Model.planTransfer([`${HOME}/Downloads/report.pdf`, `${HOME}/Downloads/new.txt`], dest, "copy", names, {})
    assert.equal(plan.error, "")
    assert.deepEqual(plan.jobs.map((j) => [j.name, j.conflict, j.decision]), [["report.pdf", true, ""], ["new.txt", false, "new"]])
  })

  it("flags two sources that share a name", () => {
    const plan = Model.planTransfer(["/a/x.txt", "/b/x.txt"], dest, "copy", [], {})
    assert.deepEqual(plan.jobs.map((j) => j.conflict), [false, true])
  })

  it("copies next to the original under a (copy) name and skips moves in place", () => {
    const copy = Model.planTransfer([`${dest}/report.pdf`, `${dest}/notes`], dest, "copy", names, { [`${dest}/notes`]: true })
    assert.deepEqual(copy.jobs.map((j) => [j.name, j.conflict, j.dir]), [["report (copy).pdf", false, false], ["notes (copy)", false, true]])
    assert.deepEqual(Model.planTransfer([`${dest}/report.pdf`], dest, "move", names, {}).jobs, [])
  })

  it("refuses to put a folder inside itself", () => {
    const plan = Model.planTransfer([`${HOME}/Downloads/new.txt`, HOME], `${HOME}/Documents`, "move", [], null)
    assert.equal(plan.error, "Cannot put joamag inside itself")
    assert.deepEqual(plan.jobs, [])
    assert.deepEqual(Model.planTransfer(null, dest, "copy", null, null), { error: "", jobs: [] })
  })
})

describe("conflictIndex", () => {
  it("finds the next unanswered conflict", () => {
    const jobs = [{ conflict: false, decision: "new" }, { conflict: true, decision: "skip" }, { conflict: true, decision: "" }]
    assert.equal(Model.conflictIndex(jobs), 2)
    assert.equal(Model.conflictIndex([]), -1)
    assert.equal(Model.conflictIndex(null), -1)
  })
})

describe("decideConflict", () => {
  const jobs = [
    { source: "/a/1", name: "1", dir: false, conflict: true, decision: "" },
    { source: "/a/2", name: "2", dir: false, conflict: false, decision: "new" },
    { source: "/a/3", name: "3", dir: false, conflict: true, decision: "" },
  ]

  it("answers one conflict", () => {
    const next = Model.decideConflict(jobs, 0, "skip", false)
    assert.deepEqual(next.map((j) => j.decision), ["skip", "new", ""])
    assert.equal(jobs[0].decision, "")
  })

  it("answers the rest too", () => {
    assert.deepEqual(Model.decideConflict(jobs, 0, "replace", true).map((j) => j.decision), ["replace", "new", "replace"])
  })
})

describe("transferArgs", () => {
  it("lists source, target and policy, skipping skipped and unanswered jobs", () => {
    const jobs = [
      { source: "/a/x.txt", name: "x.txt", dir: false, conflict: true, decision: "keep" },
      { source: "/b/x.txt", name: "x.txt", dir: false, conflict: true, decision: "keep" },
      { source: "/a/y", name: "y", dir: true, conflict: true, decision: "replace" },
      { source: "/a/z", name: "z", dir: false, conflict: true, decision: "skip" },
      { source: "/a/w", name: "w", dir: false, conflict: false, decision: "new" },
      { source: "/a/v", name: "v", dir: false, conflict: true, decision: "" },
    ]
    assert.deepEqual(Model.transferArgs(jobs, "/d", ["x.txt", "y", "z"]), [
      "/a/x.txt", "/d/x (copy).txt", "new",
      "/b/x.txt", "/d/x (copy 2).txt", "new",
      "/a/y", "/d/y", "replace",
      "/a/w", "/d/w", "new",
    ])
    assert.deepEqual(Model.transferArgs(null, "/d", null), [])
  })
})

describe("transferLabel", () => {
  it("says what goes where", () => {
    assert.equal(Model.transferLabel("copy", 1, "big.iso", "Downloads"), "Copying big.iso to Downloads")
    assert.equal(Model.transferLabel("move", 3, "a", "T7"), "Moving 3 items to T7")
  })
})

describe("parseNames", () => {
  it("reads name lines, tabs in names included", () => {
    assert.deepEqual(Model.parseNames("name\ta.txt\nname\tb\tc\nname\t\nerror\tx\n"), ["a.txt", "b\tc"])
    assert.deepEqual(Model.parseNames(null), [])
  })
})

describe("parseApps", () => {
  it("puts the default first, then the rest by name", () => {
    const raw = "app\tnvim.desktop\tNeovim\t0\napp\tobsidian.desktop\tObsidian\t1\napp\tcode.desktop\t\t0\napp\t\tNothing\t0\n"
    assert.deepEqual(Model.parseApps(raw), [
      { id: "obsidian.desktop", name: "Obsidian", isDefault: true },
      { id: "code.desktop", name: "code.desktop", isDefault: false },
      { id: "nvim.desktop", name: "Neovim", isDefault: false },
    ])
    assert.deepEqual(Model.parseApps(""), [])
  })
})

describe("parseThumbnail", () => {
  it("reads the picture path, tabs included", () => {
    assert.equal(Model.parseThumbnail("thumbnail\t/c/a\tb.png\n"), "/c/a\tb.png")
    assert.equal(Model.parseThumbnail("error\tno preview for video/mp4\n"), "")
    assert.equal(Model.parseThumbnail("thumbnail\t\n"), "")
    assert.equal(Model.parseThumbnail(null), "")
  })
})

describe("parseFree", () => {
  it("reads free and total bytes", () => {
    assert.deepEqual(Model.parseFree("free\t100\t400\n"), { avail: 100, size: 400 })
    const none = Model.parseFree("")
    assert.ok(Number.isNaN(none.avail))
  })
})

describe("parseResult", () => {
  it("collects every kind of line", () => {
    const raw = [
      "total\t2048", "progress\t1024", "done\t/a\t/b", "error\tdisk\tfull", "trashed\tx.2\t/h/x", "trashed\t\t/m/y",
      "restored\tx.2\t/h/x", "created\t/h/New folder", "mounted\t/run/media/u/T7", "cancelled", "unknown\tline", "",
    ].join("\n")
    const r = Model.parseResult(raw)
    assert.equal(r.total, 2048)
    assert.equal(r.progress, 1024)
    assert.deepEqual(r.done, [{ from: "/a", to: "/b" }])
    assert.deepEqual(r.errors, ["disk\tfull"])
    assert.deepEqual(r.trashed, [{ name: "x.2", path: "/h/x" }, { name: "", path: "/m/y" }])
    assert.deepEqual(r.restored, [{ name: "x.2", path: "/h/x" }])
    assert.deepEqual(r.created, ["/h/New folder"])
    assert.equal(r.mounted, "/run/media/u/T7")
    assert.equal(r.cancelled, true)
  })

  it("starts empty", () => {
    const r = Model.parseResult("done\ncreated\ntrashed\nrestored\nmounted")
    assert.deepEqual(r.done, [{ from: "", to: "" }])
    assert.deepEqual(r.created, [""])
    assert.equal(r.mounted, "")
    assert.ok(Number.isNaN(Model.parseResult("").total))
  })
})

describe("statusText", () => {
  it("counts items, the selection and its size", () => {
    assert.equal(Model.statusText(LISTING, [], false, ""), "6 items")
    assert.equal(Model.statusText(LISTING, [LISTING[2].path, LISTING[3].path, LISTING[0].path], false, ""), "6 items · 3 selected, 310 bytes")
    assert.equal(Model.statusText(LISTING.slice(0, 1), [LISTING[0].path], true, "~/Downloads"), "1 item found below ~/Downloads · 1 selected")
    assert.equal(Model.statusText(null, null, false, ""), "0 items")
  })
})

describe("emptyText", () => {
  it("explains why nothing is listed", () => {
    assert.equal(Model.emptyText("/x", "iso", false, "~"), "Nothing named “iso” here")
    assert.equal(Model.emptyText("/x", "iso", true, "~/x"), "Nothing named “iso” below ~/x")
    assert.equal(Model.emptyText(Model.TRASH, "", false, ""), "Trash is empty")
    assert.equal(Model.emptyText(Model.RECENT, "", false, ""), "Nothing opened lately")
    assert.equal(Model.emptyText("/x", "", false, ""), "This folder is empty")
  })
})

describe("tooltip", () => {
  it("names the folder and counts tabs", () => {
    assert.equal(Model.tooltip([Model.newTab(HOME)], 0, "Home"), "Files · Home")
    assert.equal(Model.tooltip([Model.newTab(HOME), Model.newTab("/")], 1, "System"), "Files · System · 2 tabs")
    assert.equal(Model.tooltip([], 0, ""), "Files")
  })
})

describe("hints", () => {
  it("picks the hint line for the mode", () => {
    assert.equal(Model.hints("rename"), Model.HINTS.rename)
    assert.equal(Model.hints("trash")[1].label, "restore")
    assert.equal(Model.hints("whatever"), Model.HINTS.browse)
  })
})

describe("itemMenu", () => {
  it("offers restore and delete for a trash item", () => {
    assert.deepEqual(Model.itemMenu({ trashName: "a.2" }, 1, false, false).map((i) => i.id), ["restore", "purge"])
  })

  it("offers folder actions for a folder", () => {
    const menu = Model.itemMenu(entry("d", { dir: true }), 1, true, true)
    assert.deepEqual(menu.map((i) => i.id), ["open", "opentab", "copy", "cut", "pasteinto", "rename", "bookmark", "trash", "purge"])
    assert.equal(menu.find((i) => i.id === "bookmark").label, "Remove bookmark")
    assert.equal(menu.find((i) => i.id === "pasteinto").disabled, false)
  })

  it("offers Open with for a file and greys rename for several", () => {
    const menu = Model.itemMenu(entry("a.txt"), 2, false, false)
    assert.deepEqual(menu.map((i) => i.id), ["open", "openwith", "copy", "cut", "rename", "trash", "purge"])
    assert.equal(menu.find((i) => i.id === "rename").disabled, true)
    assert.deepEqual(Model.itemMenu(null, 1, false, false), [])
  })
})

describe("folderMenu", () => {
  it("offers new, paste, the sort columns, bookmark and Nautilus for a folder", () => {
    const menu = Model.folderMenu(HOME, false, true, "size", false)
    assert.deepEqual(menu.map((i) => i.id), ["newfolder", "newfile", "paste", "selectall", "hidden", "sort:name", "sort:modified", "sort:size", "sort:type", "bookmark", "nautilus"])
    assert.equal(menu.find((i) => i.id === "paste").disabled, true)
    assert.equal(menu.find((i) => i.id === "hidden").label, "Hide hidden files")
    assert.equal(menu.find((i) => i.id === "hidden").icon, Model.GLYPHS.hiddenHidden)
    assert.equal(Model.folderMenu(HOME, false, false, "name", false).find((i) => i.id === "hidden").icon, Model.GLYPHS.hiddenShown)
    assert.match(menu.find((i) => i.id === "sort:size").label, /✓$/)
    assert.equal(Model.folderMenu(HOME, true, false, "name", true).find((i) => i.id === "bookmark").label, "Remove bookmark")
  })

  it("keeps Recent to selection and view, and the Trash to emptying", () => {
    assert.deepEqual(Model.folderMenu(Model.RECENT, true, false, "name", false).map((i) => i.id), ["selectall", "hidden", "sort:name", "sort:modified", "sort:size", "sort:type"])
    assert.deepEqual(Model.folderMenu(Model.TRASH, true, false, "name", false).map((i) => i.id), ["emptytrash"])
  })
})

describe("files.sh", () => {
  // A scratch home with the standard folders, a data dir, a config dir and
  // stand-ins for the commands that would touch the real machine. gio does
  // what the script asks of it on the scratch files (trash, restore) and
  // logs every call; FAKE_GIO_FAIL makes it refuse.
  function setup(t) {
    const dir = tmpdir(t)
    const home = path.join(dir, "home")
    const data = path.join(home, ".local", "share")
    const config = path.join(home, ".config")
    const bin = path.join(dir, "bin")
    for (const d of [home, data, config, bin, path.join(home, "Downloads"), path.join(home, "Music")]) fs.mkdirSync(d, { recursive: true })
    fakeCommand(bin, "xdg-user-dir", 'case "$1" in DOWNLOAD) echo "$HOME/Downloads/" ;; MUSIC) echo "$HOME/Music" ;; *) echo "$HOME/" ;; esac')
    fakeCommand(bin, "df", `
case "$*" in
  "-PB1 /") printf 'Filesystem 1-blocks Used Available Capacity Mounted\\n/dev/mapper/root 1000 400 600 40%% /\\n' ;;
  "-PB1 /run/media/u/T7") printf 'Filesystem 1-blocks Used Available Capacity Mounted\\n/dev/sdb1 2000 500 1500 25%% /run/media/u/T7\\n' ;;
  "-PB1 "*) printf 'Filesystem 1-blocks Used Available Capacity Mounted\\nx 50 20 30 40%% /x\\n' ;;
esac`)
    fakeCommand(bin, "findmnt", 'echo "/dev/mapper/root[/@]"')
    fakeCommand(bin, "lsblk", `
case "$*" in
  "-P -o PATH,PKNAME,RM,HOTPLUG") printf '%s\\n' 'PATH="/dev/sda" PKNAME="" RM="0" HOTPLUG="0"' 'PATH="/dev/sda1" PKNAME="sda" RM="0" HOTPLUG="0"' 'PATH="/dev/sda2" PKNAME="sda" RM="0" HOTPLUG="0"' 'PATH="/dev/sdb" PKNAME="" RM="0" HOTPLUG="1"' 'PATH="/dev/sdb1" PKNAME="sdb" RM="0" HOTPLUG="0"' 'PATH="/dev/sdb2" PKNAME="sdb" RM="0" HOTPLUG="0"' 'PATH="/dev/mapper/root" PKNAME="sda2" RM="0" HOTPLUG="0"' ;;
  "-P -b -o PATH,FSTYPE,LABEL,MOUNTPOINTS,SIZE") printf '%s\\n' 'PATH="/dev/sda" FSTYPE="" LABEL="" MOUNTPOINTS="" SIZE="900"' 'PATH="/dev/sda1" FSTYPE="vfat" LABEL="" MOUNTPOINTS="/boot" SIZE="10"' 'PATH="/dev/sda2" FSTYPE="crypto_LUKS" LABEL="" MOUNTPOINTS="" SIZE="890"' 'PATH="/dev/mapper/root" FSTYPE="btrfs" LABEL="" MOUNTPOINTS="/\\x0a/home" SIZE="890"' 'PATH="/dev/sdb1" FSTYPE="exfat" LABEL="T7" MOUNTPOINTS="/run/media/u/T7\\x0a/mnt/t7" SIZE="2000"' 'PATH="/dev/sdb2" FSTYPE="ext4" LABEL="Spare" MOUNTPOINTS="" SIZE="300"' ;;
  *) exit 2 ;;
esac`)
    fakeCommand(bin, "gio", `
printf '%s\\n' "$*" >> "$FAKE_LOG"
[[ -n \${FAKE_GIO_FAIL:-} ]] && { echo "gio: refused" >&2; exit 1; }
trash="$XDG_DATA_HOME/Trash"
case "$1" in
  trash)
    shift
    if [[ $1 == --restore ]]; then
      name=\${2#trash:///}; name=\${name//%20/ }
      orig=$(sed -n 's/^Path=//p' "$trash/info/$name.trashinfo"); orig=\${orig//%20/ }
      mkdir -p "$(dirname "$orig")"; mv "$trash/files/$name" "$orig"; rm "$trash/info/$name.trashinfo"
    elif [[ $1 == --empty ]]; then
      rm -rf "$trash/files" "$trash/info"
    else
      [[ $1 == -- ]] && shift
      mkdir -p "$trash/files" "$trash/info"
      name=$(basename "$1"); n=1; base=$name
      while [[ -e $trash/info/$name.trashinfo ]]; do n=$((n + 1)); name="$base.$n"; done
      mv "$1" "$trash/files/$name"
      printf '[Trash Info]\\nPath=%s\\nDeletionDate=2026-11-24T10:00:00\\n' "\${1// /%20}" > "$trash/info/$name.trashinfo"
    fi ;;
  info) [[ -e \${@: -1} ]] && echo "  standard::content-type: text/markdown" ;;
  mime) printf 'Default application for “text/markdown”: obsidian.desktop\\nRegistered applications:\\n\\tobsidian.desktop\\n\\tnvim.desktop\\n\\tghost.desktop\\n\\tobsidian.desktop\\nRecommended applications:\\n\\tnvim.desktop\\n' ;;
  launch) ;;
  mount) if [[ $2 == -d ]]; then echo "Mounted $3 at /run/media/u/STICK"; fi ;;
esac`)
    const apps = path.join(data, "applications")
    fs.mkdirSync(apps)
    fs.writeFileSync(path.join(apps, "obsidian.desktop"), "[Desktop Entry]\nName=Obsidian\nName[pt]=Obsidiana\n[Desktop Action new]\nName=New vault\n")
    fs.writeFileSync(path.join(apps, "nvim.desktop"), "[Desktop Entry]\nExec=nvim\n")
    const env = { HOME: home, XDG_DATA_HOME: data, XDG_CONFIG_HOME: config, XDG_DATA_DIRS: path.join(dir, "none"), FAKE_LOG: path.join(dir, "gio.log"), TMPDIR: dir }
    const run = (args, extra = {}) => runScript("joamag.files", "files.sh", args, { bin, env: { ...env, ...extra } })
    const log = () => (fs.existsSync(env.FAKE_LOG) ? fs.readFileSync(env.FAKE_LOG, "utf8").trim().split("\n") : [])
    return { dir, home, data, config, bin, env, run, log }
  }

  function write(file, content = "") {
    fs.mkdirSync(path.dirname(file), { recursive: true })
    fs.writeFileSync(file, content)
  }

  it("lists places, bookmarks, drives and the trash count", (t) => {
    const s = setup(t)
    write(path.join(s.config, "gtk-3.0", "bookmarks"), `file://${s.home}/Music%20Box Music box\nfile://${s.home}/plain\nsftp://server/x Remote\n`)
    write(path.join(s.data, "Trash", "info", "a.trashinfo"), "")
    write(path.join(s.data, "Trash", "info", "b.trashinfo"), "")
    const parsed = Model.parsePlaces(s.run(["places"]).stdout)
    // Desktop is unset (xdg-user-dir answers home) and has no folder, so it is left out.
    assert.deepEqual(parsed.places.map((p) => [p.key, p.path]), [["home", s.home], ["downloads", `${s.home}/Downloads`], ["music", `${s.home}/Music`]])
    assert.deepEqual(parsed.bookmarks, [{ path: `${s.home}/Music Box`, label: "Music box" }, { path: `${s.home}/plain`, label: "plain" }])
    assert.deepEqual(parsed.drives.map((d) => [d.mount, d.device, d.name, d.size, d.avail, d.removable]), [
      ["/", "/dev/mapper/root", "System", 1000, 600, false],
      ["/run/media/u/T7", "/dev/sdb1", "T7", 2000, 1500, true],
      ["", "/dev/sdb2", "Spare", 300, NaN, true],
    ])
    assert.equal(parsed.trashCount, 2)
  })

  it("reports free space for a folder", (t) => {
    const s = setup(t)
    assert.deepEqual(Model.parseFree(s.run(["free", s.home]).stdout), { avail: 30, size: 50 })
  })

  it("lists recent files newest first, skipping the ones that are gone", (t) => {
    const s = setup(t)
    write(path.join(s.home, "a b.txt"), "x")
    write(path.join(s.home, "R&D.md"), "xy")
    fs.mkdirSync(path.join(s.home, "proj"))
    write(path.join(s.data, "recently-used.xbel"), [
      "<xbel>",
      `  <bookmark href="file://${s.home}/a%20b.txt" added="2026-11-20T10:00:00Z" modified="2026-11-20T10:00:00.5Z" visited="x">`,
      `  <bookmark href="file://${s.home}/gone.txt" added="2026-11-23T10:00:00Z" modified="2026-11-23T10:00:00Z" visited="x">`,
      `  <bookmark href="file://${s.home}/R&amp;D.md" added="2026-11-22T10:00:00Z" modified="2026-11-22T10:00:00Z" visited="x">`,
      `  <bookmark href="file://${s.home}/proj" added="2026-11-21T10:00:00Z" modified="2026-11-21T10:00:00Z" visited="x">`,
      `  <bookmark href="file://${s.home}/a%20b.txt" added="2026-11-01T10:00:00Z" modified="2026-11-01T10:00:00Z" visited="x">`,
      '  <bookmark href="https://example.com" added="2026-11-24T10:00:00Z" modified="2026-11-24T10:00:00Z" visited="x">',
      "</xbel>",
    ].join("\n"))
    const list = Model.parseEntries(s.run(["recent"]).stdout)
    // a b.txt is listed twice; its newest use counts.
    assert.deepEqual(list.map((e) => [e.name, e.dir]), [["R&D.md", false], ["proj", true], ["a b.txt", false]])
    assert.equal(list[2].modified, Date.UTC(2026, 10, 20, 10, 0, 0, 500))
    assert.equal(list[0].size, 2)
    assert.equal(list[0].modified, Date.UTC(2026, 10, 22, 10))
  })

  it("lists nothing recent without the bookmarks file, and stops at the limit", (t) => {
    const s = setup(t)
    assert.equal(s.run(["recent"]).stdout, "")
    const lines = ["<xbel>"]
    for (let i = 0; i < 45; i++) {
      write(path.join(s.home, `f${i}`), "")
      lines.push(`  <bookmark href="file://${s.home}/f${i}" added="x" modified="2026-11-${String(10 + (i % 15)).padStart(2, "0")}T10:00:00Z" visited="x">`)
    }
    write(path.join(s.data, "recently-used.xbel"), lines.join("\n"))
    assert.equal(Model.parseEntries(s.run(["recent"]).stdout).length, 40)
  })

  it("lists the trash with where each item came from", (t) => {
    const s = setup(t)
    const trash = path.join(s.data, "Trash")
    write(path.join(trash, "files", "report.pdf"), "12345")
    write(path.join(trash, "info", "report.pdf.trashinfo"), `[Trash Info]\nPath=${s.home}/Documents/report%20final.pdf\nDeletionDate=2026-11-24T10:00:00\n`)
    fs.mkdirSync(path.join(trash, "files", "old"), { recursive: true })
    write(path.join(trash, "info", "old.trashinfo"), `[Trash Info]\nPath=${s.home}/old\nDeletionDate=2026-11-20T08:30:00\n`)
    write(path.join(trash, "info", "orphan.trashinfo"), "[Trash Info]\nPath=/x\n")
    const list = Model.sortEntries(Model.parseEntries(s.run(["trashed"]).stdout), "name", false)
    assert.deepEqual(list.map((e) => [e.name, e.trashName, e.origin, e.dir]), [
      ["old", "old", `${s.home}/old`, true],
      ["report final.pdf", "report.pdf", `${s.home}/Documents/report final.pdf`, false],
    ])
    assert.equal(list[1].size, 5)
    assert.equal(list[1].modified, new Date(2026, 10, 24, 10).getTime())
    assert.equal(list[1].path, path.join(trash, "files", "report.pdf"))
  })

  it("lists an empty trash when there is none", (t) => {
    assert.equal(setup(t).run(["trashed"]).stdout, "")
  })

  it("searches below a folder by name, hidden files only on request", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Downloads", "Invoice-1.pdf"), "x")
    write(path.join(s.home, "Downloads", "deep", "more", "old invoice.txt"), "")
    write(path.join(s.home, ".cache", "invoice.tmp"), "")
    write(path.join(s.home, "Downloads", "[x]invoice*.md"), "")
    const names = (args) => Model.parseEntries(s.run(["search", ...args]).stdout).map((e) => e.name).sort()
    assert.deepEqual(names([s.home, "INVOICE"]), ["Invoice-1.pdf", "[x]invoice*.md", "old invoice.txt"])
    assert.deepEqual(names([s.home, "invoice", "all"]), ["Invoice-1.pdf", "[x]invoice*.md", "invoice.tmp", "old invoice.txt"])
    // Wildcards in the query are taken literally.
    assert.deepEqual(names([s.home, "e*."]), ["[x]invoice*.md"])
    assert.deepEqual(names([s.home, "[x]"]), ["[x]invoice*.md"])
    assert.ok(Model.parseEntries(s.run(["search", s.home, "deep"]).stdout)[0].dir)
  })

  it("searches nothing for an empty query and refuses a missing folder", (t) => {
    const s = setup(t)
    assert.equal(s.run(["search", s.home, ""]).stdout, "")
    assert.equal(s.run(["search", path.join(s.home, "nope"), "x"]).stdout, `error\tno folder at ${s.home}/nope\n`)
    assert.equal(s.run(["search"]).status, 1)
  })

  it("lists the names in a folder", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Music", "a.mp3"))
    write(path.join(s.home, "Music", ".dot"))
    assert.deepEqual(Model.parseNames(s.run(["names", path.join(s.home, "Music")]).stdout).sort(), [".dot", "a.mp3"])
    assert.equal(s.run(["names", path.join(s.home, "none")]).stdout, `error\tno folder at ${s.home}/none\n`)
    assert.equal(s.run(["names"]).status, 1)
  })

  it("lists the apps that open a file, the default first", (t) => {
    const s = setup(t)
    write(path.join(s.home, "notes.md"))
    assert.deepEqual(Model.parseApps(s.run(["apps", path.join(s.home, "notes.md")]).stdout), [
      { id: "obsidian.desktop", name: "Obsidian", isDefault: true },
      { id: "nvim.desktop", name: "nvim.desktop", isDefault: false },
    ])
  })

  it("refuses apps for a missing or unknown file", (t) => {
    const s = setup(t)
    assert.equal(s.run(["apps", path.join(s.home, "none")]).stdout, `error\tno file at ${s.home}/none\n`)
    write(path.join(s.home, "odd"))
    assert.equal(s.run(["apps", path.join(s.home, "odd")], { FAKE_GIO_FAIL: "1" }).stdout, "error\tcould not tell the type of odd\n")
    assert.equal(s.run(["apps"]).status, 1)
  })

  it("launches an app with its desktop file", (t) => {
    const s = setup(t)
    assert.equal(s.run(["launch", "obsidian.desktop", "/a b", "/c"]).stdout, "")
    assert.deepEqual(s.log(), [`launch ${s.data}/applications/obsidian.desktop /a b /c`])
    assert.equal(s.run(["launch", "ghost.desktop", "/a"]).stdout, "error\tno app named ghost.desktop\n")
    assert.equal(s.run(["launch", "nvim.desktop", "/a"], { FAKE_GIO_FAIL: "1" }).stdout, "error\tgio: refused\n")
    assert.equal(s.run(["launch"]).status, 1)
  })

  it("makes a thumbnail with the registered thumbnailer and keeps it", (t) => {
    const s = setup(t)
    const thumbs = path.join(s.data, "thumbnailers")
    fs.mkdirSync(thumbs)
    fs.writeFileSync(path.join(thumbs, "other.thumbnailer"), "[Thumbnailer Entry]\nExec=never %i %o\nMimeType=image/x-other;\n")
    fs.writeFileSync(path.join(thumbs, "fake.thumbnailer"), "[Thumbnailer Entry]\nExec=fakethumb --size=%s -s %s %u %i %o 100%%\nMimeType=text/plain;text/markdown;\n")
    fakeCommand(s.bin, "fakethumb", 'printf "%s\\n" "$*" >> "$FAKE_LOG"; printf PNG > "${@: -2:1}"')
    const file = path.join(s.home, "R&D notes.md")
    write(file, "x")
    const cache = path.join(s.dir, "cache")
    const first = s.run(["thumbnail", file, "256"], { XDG_CACHE_HOME: cache })
    const made = Model.parseThumbnail(first.stdout)
    assert.match(made, new RegExp(`^${cache}/joamag-files/thumbnails/[0-9a-f]{32}-\\d+-256\\.png$`))
    assert.equal(fs.readFileSync(made, "utf8"), "PNG")
    // Each placeholder is one argument, the & and the space in the name kept.
    const call = s.log().find((l) => l.startsWith("--size"))
    const tmp = `${path.dirname(made)}/.${path.basename(made).split("-")[0]}.`
    assert.ok(call.startsWith(`--size=256 -s 256 file://${s.home}/R%26D%20notes.md ${file} ${tmp}`), call)
    assert.ok(call.endsWith(".png 100%"), call)
    // Asked again, the cached picture comes back without running anything.
    const before = s.log().length
    assert.equal(Model.parseThumbnail(s.run(["thumbnail", file, "256"], { XDG_CACHE_HOME: cache }).stdout), made)
    assert.equal(s.log().length, before)
    // A new version of the file replaces the old picture.
    fs.utimesSync(file, new Date(2030, 0, 1), new Date(2030, 0, 1))
    const newer = Model.parseThumbnail(s.run(["thumbnail", file, "256"], { XDG_CACHE_HOME: cache }).stdout)
    assert.notEqual(newer, made)
    assert.ok(!fs.existsSync(made))
  })

  it("says when there is no thumbnail to make", (t) => {
    const s = setup(t)
    const thumbs = path.join(s.data, "thumbnailers")
    fs.mkdirSync(thumbs)
    fs.writeFileSync(path.join(thumbs, "broken.thumbnailer"), "[Thumbnailer Entry]\nExec=brokenthumb %i %o\nMimeType=text/markdown;\n")
    fakeCommand(s.bin, "brokenthumb", 'echo "brokenthumb: cannot decode" >&2; exit 1')
    const file = path.join(s.home, "a.md")
    write(file, "x")
    const env = { XDG_CACHE_HOME: path.join(s.dir, "cache") }
    assert.equal(s.run(["thumbnail", file, "256"], env).stdout, "error\tno preview: brokenthumb: cannot decode\n")
    fs.rmSync(path.join(thumbs, "broken.thumbnailer"))
    assert.equal(s.run(["thumbnail", file, "256"], env).stdout, "error\tno preview for text/markdown\n")
    assert.equal(s.run(["thumbnail", file, "256"], { ...env, FAKE_GIO_FAIL: "1" }).stdout, "error\tcould not tell the type of a.md\n")
    assert.equal(s.run(["thumbnail", file, "big"], env).stdout, "error\tbad size big\n")
    assert.equal(s.run(["thumbnail", path.join(s.home, "none"), "256"], env).stdout, `error\tno file at ${s.home}/none\n`)
    assert.equal(s.run(["thumbnail"], env).status, 1)
  })

  it("copies files and folders with the total and progress", (t) => {
    const s = setup(t)
    const src = path.join(s.home, "Downloads")
    write(path.join(src, "a.txt"), "hello")
    write(path.join(src, "dir", "inner.txt"), "world!")
    const dest = path.join(s.home, "Music")
    const r = Model.parseResult(s.run(["transfer", "copy", `${src}/a.txt`, `${dest}/a.txt`, "new", `${src}/dir`, `${dest}/dir`, "new"]).stdout)
    assert.deepEqual(r.errors, [])
    assert.deepEqual(r.done, [{ from: `${src}/a.txt`, to: `${dest}/a.txt` }, { from: `${src}/dir`, to: `${dest}/dir` }])
    assert.ok(r.total > 0)
    assert.equal(r.progress, r.total)
    assert.equal(fs.readFileSync(path.join(dest, "dir", "inner.txt"), "utf8"), "world!")
    assert.ok(fs.existsSync(path.join(src, "a.txt")))
  })

  it("moves files within a filesystem without measuring them", (t) => {
    const s = setup(t)
    const src = path.join(s.home, "Downloads", "m.txt")
    write(src, "x")
    const r = Model.parseResult(s.run(["transfer", "move", src, path.join(s.home, "Music", "m.txt"), "new"]).stdout)
    assert.equal(r.total, 0)
    assert.ok(Number.isNaN(r.progress))
    assert.equal(r.done.length, 1)
    assert.ok(!fs.existsSync(src))
    assert.ok(fs.existsSync(path.join(s.home, "Music", "m.txt")))
  })

  it("replaces a taken name by trashing the old file first", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Downloads", "r.txt"), "new")
    write(path.join(s.home, "Music", "r.txt"), "old")
    const r = Model.parseResult(s.run(["transfer", "copy", `${s.home}/Downloads/r.txt`, `${s.home}/Music/r.txt`, "replace"]).stdout)
    assert.equal(r.done.length, 1)
    assert.equal(fs.readFileSync(path.join(s.home, "Music", "r.txt"), "utf8"), "new")
    assert.equal(fs.readFileSync(path.join(s.data, "Trash", "files", "r.txt"), "utf8"), "old")
  })

  it("reports each item that cannot go and carries on", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Downloads", "k.txt"), "k")
    write(path.join(s.home, "Music", "k.txt"), "taken")
    write(path.join(s.home, "Downloads", "ok.txt"), "ok")
    write(path.join(s.home, "Music", "rep.txt"), "old")
    write(path.join(s.home, "Downloads", "rep.txt"), "new")
    const d = `${s.home}/Downloads`
    const out = s.run(["transfer", "copy",
      `${d}/gone.txt`, `${s.home}/Music/gone.txt`, "new",
      `${d}/k.txt`, `${s.home}/Music/k.txt`, "new",
      d, `${d}/inside`, "new",
      `${d}/ok.txt`, `${s.home}/nowhere/ok.txt`, "new",
      `${d}/rep.txt`, `${s.home}/Music/rep.txt`, "replace",
      `${d}/ok.txt`, `${s.home}/Music/ok.txt`, "new",
    ], { FAKE_GIO_FAIL: "1" }).stdout
    const r = Model.parseResult(out)
    assert.deepEqual(r.errors, ["gone.txt is gone", "k.txt already exists", "cannot put Downloads inside itself", `no folder at ${s.home}/nowhere`, "gio: refused"])
    assert.deepEqual(r.done.map((x) => Model.baseName(x.to)), ["ok.txt"])
    assert.equal(fs.readFileSync(path.join(s.home, "Music", "k.txt"), "utf8"), "taken")
  })

  it("reports a copy that fails", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Downloads", "f.txt"), "x")
    fakeCommand(s.bin, "cp", 'echo "cp: no space left" >&2; exit 1')
    const r = Model.parseResult(s.run(["transfer", "copy", `${s.home}/Downloads/f.txt`, `${s.home}/Music/f.txt`, "new"]).stdout)
    assert.deepEqual(r.errors, ["cp: no space left"])
    assert.deepEqual(r.done, [])
  })

  it("refuses a bad transfer", (t) => {
    const s = setup(t)
    assert.equal(s.run(["transfer", "link", "/a", "/b", "new"]).stdout, "error\tunknown transfer mode link\n")
    assert.equal(s.run(["transfer", "copy", "/a", "/b"]).stdout, "error\tnothing to transfer\n")
    assert.equal(s.run(["transfer"]).stdout, "error\tunknown transfer mode \n")
  })

  it("cancels a copy and removes what it wrote", async (t) => {
    const s = setup(t)
    write(path.join(s.home, "Downloads", "big.iso"), "x".repeat(4096))
    // A cp that writes part of the file, then stalls.
    fakeCommand(s.bin, "cp", 'head -c 100 "$3" > "$4"; exec sleep 30')
    const child = spawn(path.join(pluginDir("joamag.files"), "files.sh"), ["transfer", "copy", `${s.home}/Downloads/big.iso`, `${s.home}/Music/big.iso`, "new"], {
      env: { ...s.env, PATH: [s.bin, "/usr/bin", "/bin"].join(":"), LANG: "C" },
    })
    let stdout = ""
    const progressed = new Promise((resolve) => child.stdout.on("data", (chunk) => {
      stdout += chunk
      if (stdout.includes("progress\t")) resolve()
    }))
    const closed = new Promise((resolve) => child.on("close", resolve))
    await progressed
    child.kill("SIGTERM")
    await closed
    const r = Model.parseResult(stdout)
    assert.equal(r.cancelled, true)
    assert.equal(r.total, 4096)
    assert.ok(!fs.existsSync(path.join(s.home, "Music", "big.iso")))
    assert.ok(fs.existsSync(path.join(s.home, "Downloads", "big.iso")))
  })

  it("renames and refuses taken or bad names", (t) => {
    const s = setup(t)
    const file = path.join(s.home, "Music", "a.txt")
    write(file)
    write(path.join(s.home, "Music", "b.txt"))
    assert.equal(s.run(["rename", file, "c.txt"]).stdout, `done\t${file}\t${s.home}/Music/c.txt\n`)
    const c = path.join(s.home, "Music", "c.txt")
    assert.equal(s.run(["rename", c, "c.txt"]).stdout, "")
    assert.equal(s.run(["rename", c, "b.txt"]).stdout, "error\tb.txt already exists here\n")
    assert.equal(s.run(["rename", c, "  "]).stdout, "error\ta name cannot be empty\n")
    assert.equal(s.run(["rename", c, "x/y"]).stdout, "error\ta name cannot contain /\n")
    assert.equal(s.run(["rename", c, ".."]).stdout, "error\t.. is not a valid name\n")
    assert.equal(s.run(["rename", file, "d.txt"]).stdout, `error\tno file at ${file}\n`)
    assert.equal(s.run(["rename"]).status, 1)
  })

  it("creates folders and files", (t) => {
    const s = setup(t)
    const music = path.join(s.home, "Music")
    assert.equal(s.run(["mkdir", music, "New folder"]).stdout, `created\t${music}/New folder\n`)
    assert.ok(fs.statSync(path.join(music, "New folder")).isDirectory())
    assert.equal(s.run(["touch", music, "New file"]).stdout, `created\t${music}/New file\n`)
    assert.ok(fs.statSync(path.join(music, "New file")).isFile())
    assert.equal(s.run(["touch", music, "New file"]).stdout, "error\tNew file already exists here\n")
    assert.equal(s.run(["mkdir", music, ""]).stdout, "error\ta name cannot be empty\n")
    assert.equal(s.run(["mkdir", path.join(s.home, "none"), "x"]).stdout, `error\tno folder at ${s.home}/none\n`)
    assert.equal(s.run(["mkdir"]).status, 1)
  })

  it("trashes files and names their trash entries for undo", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Music", "song one.mp3"), "a")
    write(path.join(s.home, "Downloads", "song one.mp3"), "b")
    const r = Model.parseResult(s.run(["trash", `${s.home}/Music/song one.mp3`, `${s.home}/Downloads/song one.mp3`]).stdout)
    assert.deepEqual(r.trashed, [
      { name: "song one.mp3", path: `${s.home}/Music/song one.mp3` },
      { name: "song one.mp3.2", path: `${s.home}/Downloads/song one.mp3` },
    ])
    assert.ok(!fs.existsSync(path.join(s.home, "Music", "song one.mp3")))
  })

  it("reports a file gio cannot trash", (t) => {
    const s = setup(t)
    assert.equal(s.run(["trash", "/nope"], { FAKE_GIO_FAIL: "1" }).stdout, "error\tgio: refused\n")
    assert.equal(s.run(["trash"]).stdout, "error\tnothing to move to the trash\n")
  })

  it("restores items, under a (copy) name when the old one is taken", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Music", "a.txt"), "first")
    write(path.join(s.home, "Music", "b.txt"), "second")
    s.run(["trash", `${s.home}/Music/a.txt`, `${s.home}/Music/b.txt`])
    write(path.join(s.home, "Music", "b.txt"), "newer")
    const r = Model.parseResult(s.run(["restore", "a.txt", "b.txt", "zzz"]).stdout)
    assert.deepEqual(r.restored, [{ name: "a.txt", path: `${s.home}/Music/a.txt` }, { name: "b.txt", path: `${s.home}/Music/b (copy).txt` }])
    assert.deepEqual(r.errors, ["zzz is not in the trash"])
    assert.equal(fs.readFileSync(path.join(s.home, "Music", "b (copy).txt"), "utf8"), "second")
    assert.equal(fs.readFileSync(path.join(s.home, "Music", "b.txt"), "utf8"), "newer")
    assert.ok(!fs.existsSync(path.join(s.data, "Trash", "info", "b.txt.trashinfo")))
    assert.equal(s.run(["restore"]).stdout, "error\tnothing to restore\n")
  })

  it("restores a folder under its whole name and reports gio failures", (t) => {
    const s = setup(t)
    fs.mkdirSync(path.join(s.home, "Music", "v1.0"))
    write(path.join(s.home, "Music", "x.txt"))
    s.run(["trash", `${s.home}/Music/v1.0`, `${s.home}/Music/x.txt`])
    fs.mkdirSync(path.join(s.home, "Music", "v1.0"))
    fs.mkdirSync(path.join(s.home, "Music", "v1.0 (copy)"))
    assert.equal(Model.parseResult(s.run(["restore", "v1.0"]).stdout).restored[0].path, `${s.home}/Music/v1.0 (copy 2)`)
    assert.equal(s.run(["restore", "x.txt"], { FAKE_GIO_FAIL: "1" }).stdout, "error\tgio: refused\n")
  })

  it("deletes trash items for good", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Music", "p.txt"))
    s.run(["trash", `${s.home}/Music/p.txt`])
    assert.equal(s.run(["purge", "p.txt", "../etc", ""]).stdout, "error\t../etc is not in the trash\nerror\t is not in the trash\n")
    assert.ok(!fs.existsSync(path.join(s.data, "Trash", "files", "p.txt")))
    assert.ok(!fs.existsSync(path.join(s.data, "Trash", "info", "p.txt.trashinfo")))
    assert.equal(s.run(["purge"]).stdout, "error\tnothing to delete\n")
  })

  it("deletes files for good but never home or the root", (t) => {
    const s = setup(t)
    write(path.join(s.home, "Music", "d", "x"))
    assert.equal(s.run(["delete", path.join(s.home, "Music", "d"), "/", s.home]).stdout, `error\trefusing to delete /\nerror\trefusing to delete ${s.home}\n`)
    assert.ok(!fs.existsSync(path.join(s.home, "Music", "d")))
    assert.ok(fs.existsSync(s.home))
    assert.equal(s.run(["delete"]).stdout, "error\tnothing to delete\n")
  })

  it("empties the trash", (t) => {
    const s = setup(t)
    assert.equal(s.run(["empty-trash"]).stdout, "")
    assert.equal(s.run(["empty-trash"], { FAKE_GIO_FAIL: "1" }).stdout, "error\tgio: refused\n")
    assert.deepEqual(s.log(), ["trash --empty", "trash --empty"])
  })

  it("mounts and ejects drives", (t) => {
    const s = setup(t)
    assert.equal(s.run(["mount", "/dev/sdc1"]).stdout, "mounted\t/run/media/u/STICK\n")
    assert.equal(s.run(["eject", "/run/media/u/STICK"]).stdout, "")
    assert.equal(s.run(["mount", "/dev/sdc1"], { FAKE_GIO_FAIL: "1" }).stdout, "error\tgio: refused\n")
    assert.equal(s.run(["eject", "/x"], { FAKE_GIO_FAIL: "1" }).stdout, "error\tgio: refused\n")
    assert.deepEqual(s.log().slice(0, 2), ["mount -d /dev/sdc1", "mount -e /run/media/u/STICK"])
    assert.equal(s.run(["mount"]).status, 1)
    assert.equal(s.run(["eject"]).status, 1)
  })

  it("adds and removes bookmarks Nautilus shares", (t) => {
    const s = setup(t)
    const file = path.join(s.config, "gtk-3.0", "bookmarks")
    const box = path.join(s.home, "Music Box")
    fs.mkdirSync(box)
    assert.equal(s.run(["bookmark", box]).stdout, "")
    assert.equal(s.run(["bookmark", box]).stdout, "")
    assert.equal(fs.readFileSync(file, "utf8"), `file://${s.home}/Music%20Box\n`)
    fs.appendFileSync(file, `file://${s.home}/Downloads Downloads\nsftp://server/x Remote`)
    assert.equal(s.run(["unbookmark", box]).stdout, "")
    assert.equal(fs.readFileSync(file, "utf8"), `file://${s.home}/Downloads Downloads\nsftp://server/x Remote\n`)
    assert.equal(s.run(["unbookmark", path.join(s.home, "Downloads")]).stdout, "")
    s.run(["unbookmark", "sftp-only"])
    assert.equal(s.run(["bookmark", path.join(s.home, "nope")]).stdout, `error\tno folder at ${s.home}/nope\n`)
    assert.equal(s.run(["bookmark"]).status, 1)
  })

  it("unbookmarks down to an empty file, and does nothing without one", (t) => {
    const s = setup(t)
    assert.equal(s.run(["unbookmark", s.home]).stdout, "")
    const file = path.join(s.config, "gtk-3.0", "bookmarks")
    s.run(["bookmark", s.home])
    s.run(["unbookmark", s.home])
    assert.equal(fs.readFileSync(file, "utf8"), "")
  })

  it("rejects bad invocations", (t) => {
    const s = setup(t)
    assert.equal(s.run(["bogus"]).status, 1)
    assert.equal(s.run([]).status, 1)
    assert.equal(s.run(["free"]).status, 1)
  })
})
