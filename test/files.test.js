// Tests for joamag.files: Model.js in declaration order, then files.sh in a
// scratch home against xdg-user-dir, lsblk, df, findmnt and gio stand-ins.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawn } = require("node:child_process")
const { loadModel, pluginDir, fixturePath, runScript, runScriptAsync, tmpdir, fakeCommand } = require("./helpers")

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

// An archive as bsdtar lists it in the C locale: a zip that never lists
// its folders, a symlink, a hard link, a member older than six months and
// one dated in the last six months.
const ZIP = "/home/joamag/Downloads/docs.zip"
const LISTING_NOW = new Date(2026, 10, 24, 12, 0).getTime()
const ARCHIVE_LISTING = [
  "-rw-r--r--  0 1000   1000        3 Nov 24 10:05 docs/a b.txt",
  "-rw-r--r--  0 1000   1000     2048 Mar  3  2024 docs/sub/c.md",
  "drwxr-xr-x  0 1000   1000        0 Nov 20 09:00 docs/empty/",
  "-rw-r--r--  0 1000   1000        4 Dec 30 23:00 ./readme.txt",
  "lrwxrwxrwx  0 1000   1000        0 Nov 24 10:05 link -> readme.txt",
  "hrw-r--r--  0 1000   1000        0 Nov 24 10:05 hard link to readme.txt",
  "drwxr-xr-x  0 1000   1000        0 Nov 24 10:05 ./",
  "bsdtar: Damaged archive",
  "",
].join("\n")
const members = Model.parseArchiveListing(ARCHIVE_LISTING, LISTING_NOW)

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
  it("passes a folder inside an archive through", () => {
    assert.equal(Model.expandPath(Model.archiveLocation(ZIP, "docs"), HOME, "/"), `archive:${ZIP}::/docs`)
  })

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
  it("knows Recent, the Trash and folders inside archives", () => {
    assert.equal(Model.isVirtual(Model.RECENT), true)
    assert.equal(Model.isVirtual(Model.TRASH), true)
    assert.equal(Model.isVirtual(Model.archiveLocation(ZIP, "")), true)
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

  it("climbs inside an archive, then out to its folder", () => {
    assert.equal(Model.parentPath(Model.archiveLocation(ZIP, "docs/sub")), Model.archiveLocation(ZIP, "docs"))
    assert.equal(Model.parentPath(Model.archiveLocation(ZIP, "docs")), Model.archiveLocation(ZIP, ""))
    assert.equal(Model.parentPath(Model.archiveLocation(ZIP, "")), `${HOME}/Downloads`)
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

  it("writes the folder inside an archive after the archive", () => {
    assert.equal(Model.prettyPath(Model.archiveLocation(ZIP, "docs/sub"), HOME), "~/Downloads/docs.zip › docs/sub")
    assert.equal(Model.prettyPath(Model.archiveLocation(ZIP, ""), HOME), "~/Downloads/docs.zip")
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

describe("dragData", () => {
  it("carries the files as a URI list and the paths as text", () => {
    assert.deepEqual(Model.dragData(["/a b", "/c"]), { "text/uri-list": "file:///a%20b\r\nfile:///c\r\n", "text/plain": "/a b\n/c" })
    assert.deepEqual(Model.dragData(null), { "text/uri-list": "", "text/plain": "" })
  })
})

describe("isArchiveName", () => {
  it("knows the suffixes bsdtar reads, ignoring case", () => {
    for (const name of ["a.zip", "a.TAR.GZ", "a.tgz", "a.tar.zst", "a.7z", "a.rar", "a.iso", "a.jar"]) assert.equal(Model.isArchiveName(name), true, name)
    assert.equal(Model.isArchiveName("a.gz"), false)
    assert.equal(Model.isArchiveName(".zip"), false)
    assert.equal(Model.isArchiveName(null), false)
  })
})

describe("isArchive", () => {
  it("is a file with an archive name, not a folder or a trash item", () => {
    assert.equal(Model.isArchive(entry("a.zip")), true)
    assert.equal(Model.isArchive(entry("a.zip", { dir: true })), false)
    assert.equal(Model.isArchive({ name: "a.zip", trashName: "a.zip" }), false)
    assert.equal(Model.isArchive(null), false)
  })
})

describe("archiveLocation", () => {
  it("joins the archive and the folder inside it", () => {
    assert.equal(Model.archiveLocation(ZIP, "/docs/sub/"), `archive:${ZIP}::/docs/sub`)
    assert.equal(Model.archiveLocation(ZIP, ""), `archive:${ZIP}::/`)
    assert.equal(Model.archiveLocation(ZIP), `archive:${ZIP}::/`)
  })
})

describe("isArchiveLocation", () => {
  it("recognises the prefix", () => {
    assert.equal(Model.isArchiveLocation(Model.archiveLocation(ZIP, "")), true)
    assert.equal(Model.isArchiveLocation(ZIP), false)
    assert.equal(Model.isArchiveLocation(null), false)
  })
})

describe("splitArchive", () => {
  it("parts the archive from the folder inside it", () => {
    assert.deepEqual(Model.splitArchive(Model.archiveLocation(ZIP, "docs/sub")), { archive: ZIP, inner: "docs/sub" })
    assert.deepEqual(Model.splitArchive(`archive:${ZIP}`), { archive: ZIP, inner: "" })
    assert.equal(Model.splitArchive(ZIP), null)
  })
})

describe("archiveStem", () => {
  it("drops the archive suffix", () => {
    assert.equal(Model.archiveStem("photos.tar.gz"), "photos")
    assert.equal(Model.archiveStem("Report.ZIP"), "Report")
    assert.equal(Model.archiveStem("notes.txt"), "notes.txt")
    assert.equal(Model.archiveStem(null), "")
  })
})

describe("parseArchiveListing", () => {
  it("reads members with sizes and dates", () => {
    const byInner = Object.fromEntries(members.map((m) => [m.inner, m]))
    assert.equal(byInner["docs/a b.txt"].size, 3)
    assert.equal(byInner["docs/a b.txt"].modified, new Date(2026, 10, 24, 10, 5).getTime())
    assert.equal(byInner["docs/sub/c.md"].modified, new Date(2024, 2, 3).getTime())
    // A time on a date after today is from last year.
    assert.equal(byInner["readme.txt"].modified, new Date(2025, 11, 30, 23, 0).getTime())
    assert.equal(byInner["docs/empty"].dir, true)
  })

  it("makes up folders a zip leaves out and names links by themselves", () => {
    assert.deepEqual(members.map((m) => m.inner), ["docs", "docs/a b.txt", "docs/sub", "docs/sub/c.md", "docs/empty", "readme.txt", "link", "hard"])
    assert.equal(members[0].dir, true)
    assert.ok(Number.isNaN(members[0].size))
  })

  it("starts empty", () => {
    assert.deepEqual(Model.parseArchiveListing("", LISTING_NOW), [])
    assert.ok(Model.parseArchiveListing("-rw-r--r--  0 a b 1 Jan  1 10:00 x", undefined).length === 1)
  })
})

describe("archiveEntries", () => {
  it("lists one folder of the archive", () => {
    assert.deepEqual(Model.archiveEntries(members, ZIP, "").map((e) => [e.name, e.dir]), [["docs", true], ["readme.txt", false], ["link", false], ["hard", false]])
    const docs = Model.archiveEntries(members, ZIP, "docs")
    assert.deepEqual(docs.map((e) => e.name), ["a b.txt", "sub", "empty"])
    assert.equal(docs[0].path, Model.archiveLocation(ZIP, "docs/a b.txt"))
    assert.equal(docs[0].size, 3)
    assert.deepEqual(Model.archiveEntries(members, ZIP, "nowhere"), [])
    assert.deepEqual(Model.archiveEntries(null, ZIP, ""), [])
  })
})

describe("archiveSummary", () => {
  it("counts files, folders and the unpacked size, with the first names", () => {
    assert.deepEqual(Model.archiveSummary(members, 3), { files: 5, dirs: 3, bytes: 2055, names: ["docs/", "docs/a b.txt", "docs/sub/"], more: 5 })
    assert.deepEqual(Model.archiveSummary(null, 3), { files: 0, dirs: 0, bytes: 0, names: [], more: 0 })
  })
})

describe("extractTarget", () => {
  it("unpacks a single top folder as itself", () => {
    const single = Model.parseArchiveListing("-rw-r--r-- 0 a b 1 Jan  1  2024 proj/a.txt\n-rw-r--r-- 0 a b 1 Jan  1  2024 proj/b.txt", LISTING_NOW)
    assert.deepEqual(Model.extractTarget(single, "proj-1.0.tar.gz", []), { name: "proj", strip: 1 })
    assert.deepEqual(Model.extractTarget(single, "proj-1.0.tar.gz", ["proj"]), { name: "proj (copy)", strip: 1 })
  })

  it("unpacks anything else into a folder named after the archive", () => {
    assert.deepEqual(Model.extractTarget(members, "docs.zip", []), { name: "docs", strip: 0 })
    assert.deepEqual(Model.extractTarget(members, "docs.zip", ["docs"]), { name: "docs (copy)", strip: 0 })
    const lone = Model.parseArchiveListing("-rw-r--r-- 0 a b 1 Jan  1  2024 only.txt", LISTING_NOW)
    assert.deepEqual(Model.extractTarget(lone, "only.zip", []), { name: "only", strip: 0 })
    assert.deepEqual(Model.extractTarget([], ".zip", []), { name: ".zip", strip: 0 })
    assert.deepEqual(Model.extractTarget(null, "", []), { name: "Archive", strip: 0 })
  })
})

describe("stripCount", () => {
  it("counts the folders above the members copied out", () => {
    assert.equal(Model.stripCount(""), 0)
    assert.equal(Model.stripCount("docs"), 1)
    assert.equal(Model.stripCount("docs/sub"), 2)
  })
})

describe("withoutMembers", () => {
  it("drops the copies of one archive's members and keeps the rest", () => {
    const extracted = {
      [Model.archiveLocation("/d/photos.zip", "a.jpg")]: "/cache/1/a.jpg",
      [Model.archiveLocation("/d/photos.zip", "trip/b.jpg")]: "/cache/1/trip/b.jpg",
      [Model.archiveLocation("/d/photos.zip.old", "a.jpg")]: "/cache/2/a.jpg",
      [Model.archiveLocation("/e/docs.tar", "c.md")]: "/cache/3/c.md",
    }
    assert.deepEqual(Model.withoutMembers(extracted, "/d/photos.zip"), {
      [Model.archiveLocation("/d/photos.zip.old", "a.jpg")]: "/cache/2/a.jpg",
      [Model.archiveLocation("/e/docs.tar", "c.md")]: "/cache/3/c.md",
    })
    // The map itself is left as it was, for the bindings to see a new one.
    assert.equal(Object.keys(extracted).length, 4)
  })

  it("keeps everything for another archive, and copes with nothing held", () => {
    const extracted = { [Model.archiveLocation("/e/docs.tar", "c.md")]: "/cache/3/c.md", "/not/a/member": "/x" }
    assert.deepEqual(Model.withoutMembers(extracted, "/d/photos.zip"), extracted)
    assert.deepEqual(Model.withoutMembers(null, "/d/photos.zip"), {})
  })
})

describe("compressName", () => {
  it("offers a free .zip named after the item, or Archive for several", () => {
    assert.equal(Model.compressName([entry("notes.md")], []), "notes.zip")
    assert.equal(Model.compressName([entry("photos", { dir: true })], ["photos.zip"]), "photos (copy).zip")
    assert.equal(Model.compressName([entry("a"), entry("b")], []), "Archive.zip")
    assert.equal(Model.compressName([entry("old.tar.gz")], []), "old.zip")
    assert.equal(Model.compressName(null, null), "Archive.zip")
  })
})

describe("canCompressTo", () => {
  it("needs a suffix bsdtar can write", () => {
    for (const name of ["a.zip", "a.7z", "a.tar", "a.TAR.GZ", "a.tar.zst"]) assert.equal(Model.canCompressTo(name), true, name)
    assert.equal(Model.canCompressTo("a.rar"), false)
    assert.equal(Model.canCompressTo("zip"), false)
    assert.equal(Model.canCompressTo(null), false)
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
    assert.equal(Model.placeLabel(Model.archiveLocation(ZIP, ""), HOME, [], []), "docs.zip")
    assert.equal(Model.placeLabel(Model.archiveLocation(ZIP, "docs/sub"), HOME, [], []), "sub")
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
    assert.equal(Model.placeIcon(Model.archiveLocation(ZIP, "docs"), HOME, [], []), Model.KIND_ICONS.archive)
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

  it("goes through the archive into its folders", () => {
    assert.deepEqual(Model.crumbs(Model.archiveLocation(ZIP, "docs/sub"), HOME, []), [
      { label: "Home", path: HOME },
      { label: "Downloads", path: `${HOME}/Downloads` },
      { label: "docs.zip", path: Model.archiveLocation(ZIP, "") },
      { label: "docs", path: Model.archiveLocation(ZIP, "docs") },
      { label: "sub", path: Model.archiveLocation(ZIP, "docs/sub") },
    ])
    assert.equal(Model.crumbs(`archive:/a.zip::/`, HOME, [])[0].path, "/")
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

describe("addVisited", () => {
  it("keeps folders newest first, each once, up to the cap", () => {
    assert.deepEqual(Model.addVisited([], "/a", 3), ["/a"])
    assert.deepEqual(Model.addVisited(["/a", "/b", "/c"], "/b", 3), ["/b", "/a", "/c"])
    assert.deepEqual(Model.addVisited(["/a", "/b", "/c"], "/d", 3), ["/d", "/a", "/b"])
    assert.equal(Model.addVisited(Array.from({ length: 60 }, (_, i) => `/f${i}`), "/new").length, Model.VISITED_MAX)
  })

  it("leaves out Recent, the Trash and folders inside archives", () => {
    assert.deepEqual(Model.addVisited(["/a"], Model.RECENT, 3), ["/a"])
    assert.deepEqual(Model.addVisited(["/a"], Model.TRASH, 3), ["/a"])
    assert.deepEqual(Model.addVisited(["/a"], Model.archiveLocation(ZIP, "docs"), 3), ["/a"])
  })

  it("cleans up what settings hand back", () => {
    assert.deepEqual(Model.addVisited(["/a", 7, null, "/b"], "", 5), ["/a", "/b"])
    assert.deepEqual(Model.addVisited("nope", "", 5), [])
    assert.deepEqual(Model.addVisited(undefined, "/a"), ["/a"])
  })
})

describe("jumpCandidates", () => {
  const tabs = [Model.newTab(HOME), Model.newTab(`${HOME}/Downloads`), Model.newTab("/etc")]
  const recent = [
    Model.makeEntry({ path: "/srv/www", dir: true }),
    Model.makeEntry({ path: "/srv/notes/todo.txt" }),
  ]

  it("lists other tabs, opened, recent, bookmarks, places then drives, each once", () => {
    const list = Model.jumpCandidates(tabs, 0, ["/opt/tools", "/etc"], recent, places.bookmarks, places.places, places.drives, HOME)
    assert.deepEqual(list.map((c) => `${c.source}:${c.path}`), [
      `tab:${HOME}/Downloads`, "tab:/etc",
      "visited:/opt/tools",
      "recent:/srv/www", "recent:/srv/notes",
      `bookmark:${HOME}/repo.private`, `bookmark:${HOME}/Documents/Finance 2026`,
      `place:${HOME}`, `place:${HOME}/Pictures`,
      "drive:/", "drive:/run/media/joamag/T7", "drive:/mnt/data",
    ])
  })

  it("names and marks each folder", () => {
    const list = Model.jumpCandidates(tabs, 0, [], [], places.bookmarks, places.places, places.drives, HOME)
    assert.deepEqual(list[0], { path: `${HOME}/Downloads`, source: "tab", label: "Downloads", icon: Model.PLACE_ICONS.downloads, tabIndex: 1 })
    const bookmark = list.find((c) => c.source === "bookmark")
    assert.equal(bookmark.label, "repo")
    assert.equal(bookmark.icon, Model.GLYPHS.bookmark)
    assert.equal(bookmark.tabIndex, -1)
    assert.equal(list.find((c) => c.path === "/run/media/joamag/T7").label, "T7")
  })

  it("is empty with nothing to offer", () => {
    assert.deepEqual(Model.jumpCandidates(null, 0, null, null, null, null, null, HOME), [])
    // The only tab is the one on screen.
    assert.deepEqual(Model.jumpCandidates([Model.newTab(HOME)], 0, [], [], [], [], [], HOME), [])
  })
})

describe("fuzzyScore", () => {
  it("is 0 for nothing typed and -1 when the letters do not all fit in order", () => {
    assert.equal(Model.fuzzyScore("", "/etc"), 0)
    assert.equal(Model.fuzzyScore("xyz", "~/Downloads"), -1)
    assert.equal(Model.fuzzyScore("sd", "~/Downloads"), -1)
    assert.equal(Model.fuzzyScore("a", ""), -1)
  })

  it("ranks word starts and runs above scattered letters", () => {
    assert.ok(Model.fuzzyScore("dl", "~/Downloads") > 0)
    assert.ok(Model.fuzzyScore("down", "~/Downloads") > Model.fuzzyScore("dwns", "~/Downloads"))
    assert.ok(Model.fuzzyScore("rp", "~/repo.private") > Model.fuzzyScore("rp", "~/xrxxxxp"))
    assert.ok(Model.fuzzyScore("pic", "~/Pictures") > Model.fuzzyScore("pic", "~/topics"))
  })

  it("takes the best place to start, not the first", () => {
    // The D and o of Documents come first, but down-notes fits as a run.
    assert.equal(Model.fuzzyScore("down", "~/Documents/down-notes"), Model.fuzzyScore("down", "~/xxxxxxxxx/down-notes"))
    assert.ok(Model.fuzzyScore("down", "~/Documents/down-notes") > Model.fuzzyScore("down", "~/Documents/dxoxwxn"))
  })

  it("ignores case and skips spaces in what is typed", () => {
    assert.equal(Model.fuzzyScore("DOWN", "~/Downloads"), Model.fuzzyScore("down", "~/Downloads"))
    assert.equal(Model.fuzzyScore("fin 26", "~/Documents/Finance 2026"), Model.fuzzyScore("fin26", "~/Documents/Finance 2026"))
    assert.equal(Model.fuzzyScore("   ", "/etc"), 0)
  })
})

describe("jumpMatches", () => {
  const candidates = Model.jumpCandidates([], 0, ["/srv/www", `${HOME}/Documents/down-notes`], [], places.bookmarks, places.places, places.drives, HOME)

  it("keeps the order and the limit with nothing typed", () => {
    assert.deepEqual(Model.jumpMatches(candidates, "", HOME, 2).map((c) => c.path), ["/srv/www", `${HOME}/Documents/down-notes`])
    assert.equal(Model.jumpMatches(candidates, "  ", HOME).length, candidates.length)
    assert.deepEqual(Model.jumpMatches(null, "a", HOME), [])
  })

  it("puts the best fit first and drops what does not fit", () => {
    // Both fit as a run at a word start; the shorter way in wins.
    assert.deepEqual(Model.jumpMatches(candidates, "down", HOME).map((c) => c.path), [`${HOME}/Downloads`, `${HOME}/Documents/down-notes`])
    // A run in the folder's own name beats letters spread over the path.
    const spread = [{ path: "/p/i/c/x", label: "x" }, { path: "/srv/pics", label: "pics" }]
    assert.deepEqual(Model.jumpMatches(spread, "pic", HOME).map((c) => c.path), ["/srv/pics", "/p/i/c/x"])
    assert.deepEqual(Model.jumpMatches(candidates, "qqq", HOME), [])
    assert.equal(Model.jumpMatches(candidates, "t7", HOME)[0].path, "/run/media/joamag/T7")
  })

  it("finds a folder by its label when the path does not fit", () => {
    const renamed = [{ path: "/srv/x1", label: "Projects", source: "bookmark" }, { path: "/srv/x2", label: "Other", source: "bookmark" }]
    assert.deepEqual(Model.jumpMatches(renamed, "proj", HOME).map((c) => c.path), ["/srv/x1"])
  })

  it("keeps the candidates' order on a tie and stops at the limit", () => {
    const twins = [{ path: "/a/same", label: "same" }, { path: "/b/same", label: "same" }, { path: "/c/same", label: "same" }]
    assert.deepEqual(Model.jumpMatches(twins, "same", HOME).map((c) => c.path), ["/a/same", "/b/same", "/c/same"])
    assert.equal(Model.jumpMatches(twins, "same", HOME, 2).length, 2)
  })
})

describe("looksLikePath", () => {
  it("accepts absolute and home paths only", () => {
    assert.equal(Model.looksLikePath("/etc"), true)
    assert.equal(Model.looksLikePath("  /etc "), true)
    assert.equal(Model.looksLikePath("~"), true)
    assert.equal(Model.looksLikePath("~/Music"), true)
    assert.equal(Model.looksLikePath("~other"), false)
    assert.equal(Model.looksLikePath("docs"), false)
    assert.equal(Model.looksLikePath(""), false)
    assert.equal(Model.looksLikePath(null), false)
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

describe("walkable", () => {
  it("reads an archive as the folder it opens as", () => {
    assert.equal(Model.walkable(`${HOME}/Downloads`), `${HOME}/Downloads`)
    assert.equal(Model.walkable(Model.archiveLocation(ZIP, "")), ZIP)
    assert.equal(Model.walkable(Model.archiveLocation(ZIP, "docs/sub")), `${ZIP}/docs/sub`)
    assert.equal(Model.walkable(Model.TRASH), Model.TRASH)
    assert.equal(Model.walkable(null), "")
  })
})

describe("moveDirection", () => {
  it("goes back out to a folder it was in, and on everywhere else", () => {
    assert.equal(Model.moveDirection(HOME, `${HOME}/Downloads`), 1)
    assert.equal(Model.moveDirection(`${HOME}/Downloads/a`, HOME), -1)
    assert.equal(Model.moveDirection(HOME, "/"), -1)
    assert.equal(Model.moveDirection(`${HOME}/Music`, `${HOME}/Downloads`), 1)
    assert.equal(Model.moveDirection(HOME, HOME), 1)
    // An archive is a folder: in from where it sits, out back to it.
    assert.equal(Model.moveDirection(`${HOME}/Downloads`, Model.archiveLocation(ZIP, "")), 1)
    assert.equal(Model.moveDirection(Model.archiveLocation(ZIP, "docs"), Model.archiveLocation(ZIP, "")), -1)
    assert.equal(Model.moveDirection(Model.archiveLocation(ZIP, "docs"), `${HOME}/Downloads`), -1)
    // Recent and the Trash are inside nothing.
    assert.equal(Model.moveDirection(Model.TRASH, HOME), 1)
    assert.equal(Model.moveDirection(HOME, Model.RECENT), 1)
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

describe("dragIcon", () => {
  it("names the icon theme's picture for the kind", () => {
    assert.equal(Model.dragIcon(entry("d", { dir: true })), "folder")
    assert.equal(Model.dragIcon(entry("a.png")), "image-x-generic")
    assert.equal(Model.dragIcon(entry("a.zip")), "package-x-generic")
    assert.equal(Model.dragIcon(entry("a.weird")), "text-x-generic")
    assert.equal(Model.dragIcon(null), "text-x-generic")
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
    assert.equal(Model.previewKind(entry("a.zip")), "archive")
    assert.equal(Model.previewKind(entry("a.iso")), "archive")
    assert.equal(Model.previewKind(entry("a.bin")), "none")
    assert.equal(Model.previewKind(entry("d", { dir: true })), "dir")
    assert.equal(Model.previewKind(Model.makeEntry({ path: "" })), "none")
    assert.equal(Model.previewKind(null), "none")
  })
})

describe("lookKind", () => {
  it("plays video and music on disk", () => {
    assert.equal(Model.lookKind(entry("a.mp4")), "video")
    assert.equal(Model.lookKind(entry("a.flac")), "audio")
  })

  it("shows the rest the way the pane does", () => {
    assert.equal(Model.lookKind(entry("a.png")), "image")
    assert.equal(Model.lookKind(entry("a.docx")), "thumbnail")
    assert.equal(Model.lookKind(entry("a.zip")), "archive")
    assert.equal(Model.lookKind(entry("d", { dir: true })), "dir")
    assert.equal(Model.lookKind(null), "none")
  })

  it("does not take media out of an archive to play it", () => {
    assert.equal(Model.lookKind(Model.makeEntry({ path: Model.archiveLocation(ZIP, "clip.mp4") })), "thumbnail")
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

  it("reads 8192 characters unless given more", () => {
    const long = Array.from({ length: 2000 }, (_, i) => `line ${i}`).join("\n")
    assert.equal(Model.previewText(long, 5000), long.slice(0, 8192))
    assert.equal(Model.previewText(long, 5000, 1e6), long)
    assert.equal(Model.previewText(long, 10, 1e6).split("\n").length, 10)
  })

  it("gives up on binary content", () => {
    assert.equal(Model.previewText("\u007fELF\u0002\u0001\u0000", 5), null)
    assert.equal(Model.previewText("caf\uFFFD", 5), null)
    // ANSI colours in a log are still text.
    assert.equal(Model.previewText("\u001b[31mred\u001b[0m", 5), "\u001b[31mred\u001b[0m")
    // Only the start is looked at for binary, however much is read.
    assert.equal(Model.previewText("text\n" + "a".repeat(9000) + "\u0000", 5, 1e6), "text\n" + "a".repeat(9000) + "\u0000")
  })
})

describe("previewActions", () => {
  it("offers to open a file or pick its app", () => {
    assert.deepEqual(Model.previewActions(entry("a.png")).map((a) => a.id), ["open", "openwith"])
  })

  it("offers a new tab for a folder, browsing and extracting for an archive", () => {
    assert.deepEqual(Model.previewActions(entry("d", { dir: true })).map((a) => a.id), ["open", "opentab"])
    assert.deepEqual(Model.previewActions(entry("a.zip")).map((a) => a.label), ["Browse", "Extract here"])
  })

  it("offers copying out inside an archive and restoring in the Trash", () => {
    assert.deepEqual(Model.previewActions(Model.makeEntry({ path: Model.archiveLocation(ZIP, "a.txt") })).map((a) => a.id), ["open", "copy"])
    assert.deepEqual(Model.previewActions(Model.makeEntry({ path: "/t/a", trashName: "a" })).map((a) => a.id), ["restore", "purge"])
    assert.deepEqual(Model.previewActions(null), [])
  })
})

describe("previewFacts", () => {
  const modified = new Date(2026, 10, 24, 9, 14).getTime()

  it("lists a file's kind, size, date and folder", () => {
    assert.deepEqual(Model.previewFacts(entry("a.pdf", { size: 184000, modified }), HOME, { pages: 3 }), [
      ["Kind", "PDF document"], ["Size", "184 kB"], ["Pages", "3"], ["Modified", "24 Nov 2026, 09:14"], ["Where", "~/Downloads"],
    ])
    assert.deepEqual(Model.previewFacts(entry("a.mp4", { size: 1000 }), HOME, { length: "2:34" }).map((r) => r[0]), ["Kind", "Size", "Length", "Where"])
  })

  it("counts a folder's items when known", () => {
    assert.deepEqual(Model.previewFacts(entry("d", { dir: true }), HOME, { items: 1 })[1], ["Contains", "1 item"])
    assert.deepEqual(Model.previewFacts(entry("d", { dir: true }), HOME).map((r) => r[0]), ["Kind", "Where"])
  })

  it("says where a trashed file came from", () => {
    const trashed = Model.makeEntry({ path: "/t/a.txt", trashName: "a.txt", origin: `${HOME}/Documents/a.txt`, size: 5, modified })
    assert.deepEqual(Model.previewFacts(trashed, HOME).slice(2), [["Deleted", "24 Nov 2026, 09:14"], ["From", "~/Documents"]])
    assert.deepEqual(Model.previewFacts(null, HOME), [])
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

describe("sameListing", () => {
  it("matches the same rows by path, kind, size and date", () => {
    const a = [entry("one.txt", { size: 1, modified: 10 }), entry("dir", { dir: true, modified: 20 })]
    const copy = a.map((e) => Model.makeEntry({ path: e.path, dir: e.dir, size: e.size, modified: e.modified }))
    assert.equal(Model.sameListing(a, a), true)
    assert.equal(Model.sameListing(a, copy), true)
    assert.equal(Model.sameListing([], []), true)
  })

  it("tells changed, reordered or missing rows apart", () => {
    const a = [entry("one.txt", { size: 1, modified: 10 }), entry("two.txt", { size: 2, modified: 10 })]
    assert.equal(Model.sameListing(a, [a[1], a[0]]), false)
    assert.equal(Model.sameListing(a, [a[0]]), false)
    assert.equal(Model.sameListing(a, [a[0], entry("two.txt", { size: 3, modified: 10 })]), false)
    assert.equal(Model.sameListing(a, [a[0], entry("two.txt", { size: 2, modified: 11 })]), false)
    assert.equal(Model.sameListing(a, [a[0], entry("two.txt", { dir: true, modified: 10 })]), false)
    assert.equal(Model.sameListing(a, null), false)
    assert.equal(Model.sameListing(undefined, a), false)
  })
})

describe("settleMoves", () => {
  const rows = (...names) => names.map((n) => entry(n))
  const at = (n) => `${HOME}/Downloads/${n}`

  it("says how far each entry moved and which ones are new", () => {
    // b went away and e came at the end: c and d move up a place.
    const moves = Model.settleMoves(rows("a", "b", "c", "d"), rows("a", "c", "d", "e"))
    assert.deepEqual(moves.shifts, { [at("c")]: 1, [at("d")]: 1 })
    assert.deepEqual(moves.arrived, { [at("e")]: true })
    // A new one at the top pushes the rest down.
    assert.deepEqual(Model.settleMoves(rows("b", "c"), rows("a", "b", "c")), { shifts: { [at("b")]: -1, [at("c")]: -1 }, arrived: { [at("a")]: true } })
    // Names that are also an object's own words are paths like any other.
    assert.deepEqual(Model.settleMoves([{ path: "constructor" }], [{ path: "toString" }, { path: "constructor" }]), { shifts: { constructor: -1 }, arrived: { toString: true } })
  })

  it("leaves alone a listing where nothing came or went, or too much did", () => {
    // The same files, even sorted anew, change nothing.
    assert.equal(Model.settleMoves(rows("a", "b"), rows("a", "b")), null)
    assert.equal(Model.settleMoves(rows("a", "b"), rows("b", "a")), null)
    assert.equal(Model.settleMoves(null, undefined), null)
    const many = Array.from({ length: 30 }, (_, i) => `f${i}`)
    assert.equal(Model.settleMoves(rows(...many), []), null)
    assert.notEqual(Model.settleMoves(rows(...many), rows(...many.slice(Model.SETTLE_MAX))), null)
    assert.equal(Model.settleMoves(rows(...many), rows(...many.slice(Model.SETTLE_MAX + 1))), null)
    assert.equal(Model.settleMoves(rows("a"), rows("a", "b", "c"), 1), null)
  })
})

describe("rememberListing", () => {
  it("keeps listings by path, the newest last, up to the cap", () => {
    let cache = {}
    for (let i = 0; i < 5; i++) cache = Model.rememberListing(cache, `/f${i}`, [i], 3)
    assert.deepEqual(Object.keys(cache), ["/f2", "/f3", "/f4"])
    // Seen again, a folder moves to the newest end with its new listing.
    cache = Model.rememberListing(cache, "/f2", [22], 3)
    assert.deepEqual(Object.keys(cache), ["/f3", "/f4", "/f2"])
    assert.deepEqual(cache["/f2"], [22])
    assert.equal(Object.keys(Model.rememberListing({}, "/a", [])).length, 1)
  })

  it("leaves the old cache as it was", () => {
    const old = { "/a": [1] }
    const next = Model.rememberListing(old, "/b", [2])
    assert.deepEqual(old, { "/a": [1] })
    assert.deepEqual(Object.keys(next), ["/a", "/b"])
    assert.equal(Object.keys(Model.rememberListing(null, "/a", [1])).length, 1)
  })

  it("drops a folder too big to keep, or with no path or listing", () => {
    const big = new Array(Model.LISTING_CACHE_BIG + 1).fill(0)
    assert.deepEqual(Object.keys(Model.rememberListing({ "/a": [1], "/big": [2] }, "/big", big)), ["/a"])
    assert.deepEqual(Object.keys(Model.rememberListing({ "/a": [1] }, "", [1])), ["/a"])
    assert.deepEqual(Object.keys(Model.rememberListing({ "/a": [1] }, "/b", null)), ["/a"])
    // Not kept, it still makes room only for what is kept.
    const full = { "/a": [1], "/b": [2], "/c": [3] }
    assert.deepEqual(Object.keys(Model.rememberListing(full, "/big", big, 3)), ["/a", "/b", "/c"])
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

describe("formatDuration", () => {
  it("shows minutes and seconds, and hours past an hour", () => {
    assert.equal(Model.formatDuration(154000), "2:34")
    assert.equal(Model.formatDuration(9999), "0:09")
    assert.equal(Model.formatDuration(3723000), "1:02:03")
  })

  it("starts at zero for nothing known", () => {
    assert.equal(Model.formatDuration(NaN), "0:00")
    assert.equal(Model.formatDuration(-5), "0:00")
    assert.equal(Model.formatDuration(undefined), "0:00")
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

describe("typeAheadIndex", () => {
  const names = ["alpha", "apple", "banana", "Berry", "cherry"].map((n) => entry(n))

  it("moves to the next name after the cursor with the first letter, wrapping", () => {
    assert.equal(Model.typeAheadIndex(names, "a", 0), 1)
    assert.equal(Model.typeAheadIndex(names, "a", 1), 0)
    assert.equal(Model.typeAheadIndex(names, "c", 0), 4)
    assert.equal(Model.typeAheadIndex(names, "B", 4), 2)
  })

  it("keeps the name under the cursor while more letters still fit it", () => {
    assert.equal(Model.typeAheadIndex(names, "ap", 1), 1)
    assert.equal(Model.typeAheadIndex(names, "be", 2), 3)
    assert.equal(Model.typeAheadIndex(names, "ch", 0), 4)
  })

  it("steps through the names a letter starts when it is typed over and over", () => {
    assert.equal(Model.typeAheadIndex(names, "aa", 0), 1)
    assert.equal(Model.typeAheadIndex(names, "bbb", 2), 3)
  })

  it("finds nothing for a start no name has", () => {
    assert.equal(Model.typeAheadIndex(names, "zz", 0), -1)
    assert.equal(Model.typeAheadIndex(names, "", 0), -1)
    assert.equal(Model.typeAheadIndex([], "a", 0), -1)
    assert.equal(Model.typeAheadIndex(null, "a", 0), -1)
    // A cursor past the end starts from the last name.
    assert.equal(Model.typeAheadIndex(names, "a", 99), 0)
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

describe("columnWidth", () => {
  it("keeps a whole width inside the range", () => {
    assert.equal(Model.columnWidth(250), 250)
    assert.equal(Model.columnWidth(200.6), 201)
    assert.equal(Model.columnWidth("300"), 300)
    assert.equal(Model.columnWidth(10), Model.COLUMN_MIN)
    assert.equal(Model.columnWidth(5000), Model.COLUMN_MAX)
  })

  it("falls back to the default for anything that is not a number", () => {
    assert.equal(Model.columnWidth(undefined), Model.COLUMN_WIDTH)
    assert.equal(Model.columnWidth("wide"), Model.COLUMN_WIDTH)
    assert.equal(Model.columnWidth(Infinity), Model.COLUMN_WIDTH)
  })
})

describe("longestNames", () => {
  it("picks the longest names, longest first", () => {
    const list = [entry("a"), entry("abcd.txt"), entry("ab"), entry("abcdef")]
    assert.deepEqual(Model.longestNames(list, 2), ["abcd.txt", "abcdef"])
    assert.equal(Model.longestNames(list).length, 4)
    assert.equal(Model.longestNames(Array.from({ length: 20 }, (_, i) => entry(`f${i}`))).length, 8)
    assert.deepEqual(Model.longestNames(null, 3), [])
  })
})

describe("paneWidth", () => {
  it("keeps a whole width inside the range", () => {
    assert.equal(Model.paneWidth(250, 100, 300, 200), 250)
    assert.equal(Model.paneWidth(200.6, 100, 300, 200), 201)
    assert.equal(Model.paneWidth("150", 100, 300, 200), 150)
    assert.equal(Model.paneWidth(10, 100, 300, 200), 100)
    assert.equal(Model.paneWidth(5000, 100, 300, 200), 300)
  })

  it("falls back for anything that is not a number", () => {
    assert.equal(Model.paneWidth(undefined, 100, 300, 200), 200)
    assert.equal(Model.paneWidth("wide", 100, 300, 200), 200)
    assert.equal(Model.paneWidth(-Infinity, 100, 300, 200), 200)
  })
})

describe("sidebarWidth", () => {
  it("keeps the sidebar between its bounds, its default when unset", () => {
    assert.equal(Model.sidebarWidth(260), 260)
    assert.equal(Model.sidebarWidth(40), Model.SIDEBAR_MIN)
    assert.equal(Model.sidebarWidth(900), Model.SIDEBAR_MAX)
    assert.equal(Model.sidebarWidth(undefined), Model.SIDEBAR_WIDTH)
  })
})

describe("previewWidth", () => {
  it("keeps the preview between its bounds, the popup's or the window's default when unset", () => {
    assert.equal(Model.previewWidth(320), 320)
    assert.equal(Model.previewWidth(20), Model.PREVIEW_MIN)
    assert.equal(Model.previewWidth(2000), Model.PREVIEW_MAX)
    assert.equal(Model.previewWidth(undefined), Model.PREVIEW_WIDTH)
    assert.equal(Model.previewWidth("x", Model.PREVIEW_WINDOW_WIDTH), Model.PREVIEW_WINDOW_WIDTH)
  })
})

describe("revealOffset", () => {
  it("does not move when the span is in view", () => {
    assert.equal(Model.revealOffset(100, 150, 400, 600, 400), 100)
    assert.equal(Model.revealOffset(0, 0, 400, 600, 400), 0)
  })

  it("moves only as far as the span needs", () => {
    // The end past the right edge: just enough to show it.
    assert.equal(Model.revealOffset(0, 380, 570, 600, 400), 170)
    // The start past the left edge: back to it.
    assert.equal(Model.revealOffset(300, 190, 380, 600, 400), 190)
  })

  it("shows the start when the span is wider than the view", () => {
    assert.equal(Model.revealOffset(0, 380, 1000, 1200, 400), 380)
  })

  it("never goes past the last offset nor below zero", () => {
    // Scrolled further than the strip now goes, after it shrank.
    assert.equal(Model.revealOffset(500, 0, 190, 200, 400), 0)
    assert.equal(Model.revealOffset(500, 250, 400, 200, 400), 200)
    assert.equal(Model.revealOffset(-20, 0, 100, 0, 400), 0)
  })
})

describe("slotOffset", () => {
  it("says where a tile was, in tiles across and rows down", () => {
    // Four across: the tile now first in the second row was second in it.
    assert.deepEqual(Model.slotOffset(4, 1, 4), { x: 1, y: 0 })
    // Last in the first row now, it was first in the second.
    assert.deepEqual(Model.slotOffset(3, 1, 4), { x: -3, y: 1 })
    // Pushed on by a new tile before it.
    assert.deepEqual(Model.slotOffset(4, -1, 4), { x: 3, y: -1 })
    assert.deepEqual(Model.slotOffset(2, 0, 4), { x: 0, y: 0 })
    assert.deepEqual(Model.slotOffset(2, undefined, 4), { x: 0, y: 0 })
    // A grid is a column wide at least.
    assert.deepEqual(Model.slotOffset(2, 1, 0), { x: 0, y: 1 })
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

describe("parseClipboard", () => {
  it("reads the files and whether they were cut", () => {
    assert.deepEqual(Model.parseClipboard("clipboard\tcut\nfile\t/a b\nfile\t/c\td\nfile\t\n"), { state: "files", mode: "cut", paths: ["/a b", "/c\td"] })
    assert.deepEqual(Model.parseClipboard("clipboard\tcopy\nfile\t/a\n"), { state: "files", mode: "copy", paths: ["/a"] })
  })

  it("tells text from a missing wl-paste", () => {
    assert.deepEqual(Model.parseClipboard("clipboard\tempty\n"), { state: "empty", mode: "copy", paths: [] })
    assert.deepEqual(Model.parseClipboard("clipboard\tcopy\n"), { state: "empty", mode: "copy", paths: [] })
    assert.deepEqual(Model.parseClipboard("clipboard\tunavailable\n"), { state: "unavailable", mode: "copy", paths: [] })
    assert.deepEqual(Model.parseClipboard(null), { state: "empty", mode: "copy", paths: [] })
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
    assert.equal(Model.hints("archive")[4].label, "copy out")
    assert.equal(Model.hints("prompt")[0].key, "Enter")
    assert.equal(Model.hints("jump")[3].key, "Ctrl+Enter")
    assert.equal(Model.hints("find")[0].label, "the start of a name")
    assert.equal(Model.hints("whatever"), Model.HINTS.browse)
  })
})

describe("lookHints", () => {
  it("adds pages, playing and the app picker by what is shown", () => {
    const keys = (kind) => Model.lookHints(kind).map((h) => h.key)
    assert.deepEqual(keys("image"), ["j/k", "Space Esc", "Enter", "o"])
    assert.deepEqual(keys("pdf"), ["j/k", "Space Esc", "Enter", "< >", "o"])
    assert.deepEqual(keys("audio"), ["j/k", "Space Esc", "Enter", "p", "o"])
    assert.deepEqual(keys("dir"), ["j/k", "Space Esc", "Enter"])
  })
})

describe("menuPosition", () => {
  it("opens at the pointer where it fits", () => {
    assert.deepEqual(Model.menuPosition(100, 50, 200, 120, 700, 500, false), { x: 100, y: 50 })
  })

  it("turns to the other side of the pointer near the right and the bottom", () => {
    assert.deepEqual(Model.menuPosition(650, 450, 200, 120, 700, 500, false), { x: 450, y: 330 })
  })

  it("hangs from a header button by its right edge", () => {
    assert.deepEqual(Model.menuPosition(690, 40, 200, 300, 700, 500, true), { x: 490, y: 40 })
  })

  it("stays inside an area too small for it", () => {
    assert.deepEqual(Model.menuPosition(30, 20, 200, 300, 150, 250, false), { x: 0, y: 0 })
    assert.deepEqual(Model.menuPosition(100, 20, 200, 120, 700, 500, true), { x: 0, y: 20 })
  })
})

describe("itemMenu", () => {
  it("offers restore and delete for a trash item", () => {
    assert.deepEqual(Model.itemMenu({ trashName: "a.2" }, 1, false, false).map((i) => i.id), ["restore", "purge"])
  })

  it("offers folder actions for a folder", () => {
    const menu = Model.itemMenu(entry("d", { dir: true }), 1, true, true)
    assert.deepEqual(menu.map((i) => i.id), ["open", "opentab", "compress", "copy", "cut", "copypath", "pasteinto", "rename", "bookmark", "trash", "purge"])
    assert.equal(menu.find((i) => i.id === "bookmark").label, "Remove bookmark")
    assert.equal(menu.find((i) => i.id === "pasteinto").disabled, false)
  })

  it("offers Open with for a file and greys rename for several", () => {
    const menu = Model.itemMenu(entry("a.txt"), 2, false, false)
    assert.deepEqual(menu.map((i) => i.id), ["open", "openwith", "compress", "copy", "cut", "copypath", "rename", "trash", "purge"])
    assert.equal(menu.find((i) => i.id === "rename").disabled, true)
    assert.deepEqual(Model.itemMenu(null, 1, false, false), [])
  })

  it("opens an archive as a folder and offers to extract it", () => {
    const menu = Model.itemMenu(entry("docs.zip"), 1, false, false)
    assert.deepEqual(menu.map((i) => i.id), ["open", "openwith", "extracthere", "extractto", "compress", "copy", "cut", "copypath", "rename", "trash", "purge"])
    assert.equal(menu[0].label, "Open as a folder")
  })

  it("keeps what is inside an archive to opening, copying out and extracting", () => {
    assert.deepEqual(Model.itemMenu(Model.makeEntry({ path: Model.archiveLocation(ZIP, "docs/a.txt") }), 1, false, false).map((i) => i.id), ["open", "openwith", "copy", "extractto"])
    assert.deepEqual(Model.itemMenu(Model.makeEntry({ path: Model.archiveLocation(ZIP, "docs"), dir: true }), 1, false, false).map((i) => i.id), ["open", "copy", "extractto"])
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

  it("offers to extract the whole archive from inside it", () => {
    assert.deepEqual(Model.folderMenu(Model.archiveLocation(ZIP, "docs"), true, false, "name", false).map((i) => i.id), ["extractall", "selectall", "hidden", "sort:name", "sort:modified", "sort:size", "sort:type"])
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
  info) case "\${@: -1}" in *.png) [[ -e \${@: -1} ]] && echo "  standard::content-type: image/png" ;; *) [[ -e \${@: -1} ]] && echo "  standard::content-type: text/markdown" ;; esac ;;
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

  // wl-copy and wl-paste stand-ins holding the clipboard in a file, its
  // types in another, so no test touches the real clipboard.
  function clipboard(s) {
    const clip = path.join(s.dir, "clip")
    fakeCommand(s.bin, "wl-copy", `
if [[ $1 == --clear ]]; then rm -f "$FAKE_CLIP" "$FAKE_CLIP.types"; exit 0; fi
[[ -n \${FAKE_CLIP_FAIL:-} ]] && { echo "wl-copy: no seat" >&2; exit 1; }
cat > "$FAKE_CLIP"; printf '%s\\n' "$2" > "$FAKE_CLIP.types"`)
    fakeCommand(s.bin, "wl-paste", `
case "$1" in
  --list-types) [[ -f $FAKE_CLIP.types ]] || { echo "Nothing is copied" >&2; exit 1; }; cat "$FAKE_CLIP.types" ;;
  --no-newline) cat "$FAKE_CLIP" ;;
esac`)
    const env = { FAKE_CLIP: clip }
    const offer = (types, content) => {
      fs.writeFileSync(`${clip}.types`, types.join("\n") + "\n")
      fs.writeFileSync(clip, content)
    }
    return { clip, env, offer, read: () => fs.readFileSync(clip, "utf8"), types: () => fs.readFileSync(`${clip}.types`, "utf8").trim() }
  }

  // A python3 stand-in in front of clipboard.py: it logs every TYPE=FILE
  // offer with the file's content and exits with FAKE_PY_STATUS.
  function helper(s) {
    fakeCommand(s.bin, "python3", `
for arg in "\${@:2}"; do printf '%s\\t%s\\n' "\${arg%=*}" "$(tr '\\r\\n' '|/' < "\${arg##*=}")" >> "$FAKE_LOG"; done
[[ -n \${FAKE_PY_ERROR:-} ]] && echo "$FAKE_PY_ERROR" >&2
exit \${FAKE_PY_STATUS:-0}`)
  }

  it("offers copied files in every form apps read", (t) => {
    const s = setup(t)
    const c = clipboard(s)
    helper(s)
    const odd = path.join(s.home, "R&D notes.md")
    assert.equal(s.run(["clipboard-set", "cut", odd, `${s.home}/b`], c.env).stdout, "")
    const uri = `file://${s.home}/R%26D%20notes.md`
    const plain = `${odd}/${s.home}/b`
    assert.deepEqual(s.log(), [
      `x-special/gnome-copied-files\tcut/${uri}/file://${s.home}/b`,
      `text/uri-list\t${uri}|/file://${s.home}/b|/`,
      `text/plain;charset=utf-8\t${plain}`,
      `text/plain\t${plain}`,
      `UTF8_STRING\t${plain}`,
      `STRING\t${plain}`,
      `TEXT\t${plain}`,
    ])
    // The payload files were only there for the helper to read.
    assert.deepEqual(fs.readdirSync(s.dir).filter((n) => n.startsWith("files-clipboard.")), [])
  })

  it("offers a picture as a file, never as its pixels", (t) => {
    const s = setup(t)
    const c = clipboard(s)
    helper(s)
    const png = path.join(s.home, "shot.png")
    write(png, "PNGDATA")
    s.run(["clipboard-set", "copy", png], c.env)
    // Nautilus pastes a clipboard picture as a new "Pasted image" before it
    // looks for files, so the name would be lost.
    assert.ok(!s.log().some((l) => l.startsWith("image/")))
    assert.equal(s.log()[0], `x-special/gnome-copied-files\tcopy/file://${png}`)
  })

  it("falls back to wl-copy without the helper, and reports its failures", (t) => {
    const s = setup(t)
    const c = clipboard(s)
    helper(s)
    const odd = path.join(s.home, "R&D notes.md")
    assert.equal(s.run(["clipboard-set", "copy", odd, `${s.home}/b`], { ...c.env, FAKE_PY_STATUS: "2" }).stdout, "")
    assert.equal(c.types(), "x-special/gnome-copied-files")
    assert.equal(c.read(), `copy\nfile://${s.home}/R%26D%20notes.md\nfile://${s.home}/b`)
    assert.deepEqual(Model.parseClipboard(s.run(["clipboard-get"], c.env).stdout), { state: "files", mode: "copy", paths: [odd, `${s.home}/b`] })
    s.run(["clipboard-set", "cut", odd], { ...c.env, FAKE_PY_STATUS: "2" })
    assert.deepEqual(Model.parseClipboard(s.run(["clipboard-get"], c.env).stdout), { state: "files", mode: "cut", paths: [odd] })
    assert.equal(s.run(["clipboard-set", "copy", odd], { ...c.env, FAKE_PY_STATUS: "1", FAKE_PY_ERROR: "clipboard.py: the compositor refused the clipboard" }).stdout, "error\tclipboard.py: the compositor refused the clipboard\n")
  })

  it("offers copied paths as text under every text type", (t) => {
    const s = setup(t)
    const c = clipboard(s)
    helper(s)
    const text = `${s.home}/R&D notes.md\n${s.home}/b`
    assert.equal(s.run(["clipboard-text", text], c.env).stdout, "")
    const plain = `${s.home}/R&D notes.md/${s.home}/b`
    assert.deepEqual(s.log(), [
      `text/plain;charset=utf-8\t${plain}`,
      `text/plain\t${plain}`,
      `UTF8_STRING\t${plain}`,
      `STRING\t${plain}`,
      `TEXT\t${plain}`,
    ])
    assert.deepEqual(fs.readdirSync(s.dir).filter((n) => n.startsWith("files-clipboard.")), [])
    // Text is not files: the widget finds nothing to paste.
    assert.equal(s.run(["clipboard-text", ""], c.env).stdout, "error\tnothing to copy\n")
  })

  it("falls back to wl-copy for text, and reports its failures", (t) => {
    const s = setup(t)
    const c = clipboard(s)
    helper(s)
    assert.equal(s.run(["clipboard-text", "/srv/a b"], { ...c.env, FAKE_PY_STATUS: "2" }).stdout, "")
    assert.equal(c.types(), "text/plain;charset=utf-8")
    assert.equal(c.read(), "/srv/a b")
    assert.equal(s.run(["clipboard-text", "/srv/a"], { ...c.env, FAKE_PY_STATUS: "2", FAKE_CLIP_FAIL: "1" }).stdout, "error\twl-copy: no seat\n")
    assert.equal(s.run(["clipboard-text", "/srv/a"], { ...c.env, FAKE_PY_STATUS: "1", FAKE_PY_ERROR: "clipboard.py: the compositor refused the clipboard" }).stdout, "error\tclipboard.py: the compositor refused the clipboard\n")
  })

  it("reads what Nautilus and other apps copy", (t) => {
    const s = setup(t)
    const c = clipboard(s)
    // Nautilus offers its own type next to text; the file manager type wins.
    c.offer(["text/plain", "x-special/gnome-copied-files"], "cut\r\nfile:///srv/a%20b\r\nfile://localhost/srv/c")
    assert.deepEqual(Model.parseClipboard(s.run(["clipboard-get"], c.env).stdout), { state: "files", mode: "cut", paths: ["/srv/a b", "/srv/c"] })
    // An unknown first line counts as a copy.
    c.offer(["x-special/gnome-copied-files"], "link\nfile:///srv/a")
    assert.equal(Model.parseClipboard(s.run(["clipboard-get"], c.env).stdout).mode, "copy")
    // A plain list of URIs: comments, other schemes and other hosts are skipped.
    c.offer(["text/uri-list"], "# from a browser\r\nfile:///srv/x.pdf\r\nhttps://example.com/y\r\nfile://server/share/z\r\n")
    assert.deepEqual(Model.parseClipboard(s.run(["clipboard-get"], c.env).stdout), { state: "files", mode: "copy", paths: ["/srv/x.pdf"] })
  })

  it("finds no files in text or in an empty clipboard", (t) => {
    const s = setup(t)
    const c = clipboard(s)
    c.offer(["text/plain;charset=utf-8", "text/plain"], "/srv/looks/like/a/path")
    assert.equal(s.run(["clipboard-get"], c.env).stdout, "clipboard\tempty\n")
    assert.equal(s.run(["clipboard-clear"], c.env).stdout, "")
    assert.ok(!fs.existsSync(c.clip))
    assert.equal(s.run(["clipboard-get"], c.env).stdout, "clipboard\tempty\n")
  })

  it("says when the clipboard cannot be used", (t) => {
    const s = setup(t)
    const c = clipboard(s)
    assert.equal(s.run(["clipboard-set", "move", "/a"], c.env).stdout, "error\tunknown clipboard mode move\n")
    assert.equal(s.run(["clipboard-set", "copy"], c.env).stdout, "error\tnothing to copy\n")
    helper(s)
    assert.equal(s.run(["clipboard-set", "copy", "/a"], { ...c.env, FAKE_PY_STATUS: "2", FAKE_CLIP_FAIL: "1" }).stdout, "error\twl-copy: no seat\n")
    // Without wl-clipboard there is only the widget's own clipboard.
    const bare = path.join(s.dir, "bare")
    fs.mkdirSync(bare)
    assert.equal(runScript("joamag.files", "files.sh", ["clipboard-get"], { path: bare, env: s.env }).stdout, "clipboard\tunavailable\n")
    assert.equal(runScript("joamag.files", "files.sh", ["clipboard-set", "copy", "/a"], { path: bare, env: s.env }).stdout, "error\twl-copy is not installed\n")
    assert.equal(runScript("joamag.files", "files.sh", ["clipboard-clear"], { path: bare, env: s.env }).stdout, "error\twl-copy is not installed\n")
  })

  // clipboard.py against the compositor stand-in, over a real socket.
  async function compositor(t, manager) {
    const dir = tmpdir(t)
    const sock = path.join(dir, "wayland-test")
    const child = spawn("python3", [fixturePath("fake_compositor.py"), sock, manager])
    let stdout = ""
    child.stdout.on("data", (chunk) => { stdout += chunk })
    const closed = new Promise((resolve) => child.on("close", () => resolve(stdout)))
    for (let i = 0; i < 100 && !fs.existsSync(sock); i++) await new Promise((r) => setTimeout(r, 20))
    const files = {}
    for (const [name, content] of [["uris", "file:///a%20b\r\n"], ["plain", "/a b"], ["png", "PNG\u0000DATA"]]) {
      files[name] = path.join(dir, name)
      fs.writeFileSync(files[name], content)
    }
    return { dir, sock, files, seen: async () => JSON.parse(await closed) }
  }

  it("owns the clipboard with every format and serves each paste (clipboard.py)", async (t) => {
    const c = await compositor(t, "ext_data_control_manager_v1")
    const run = await runScriptAsync("joamag.files", "clipboard.py", ["--foreground", `text/uri-list=${c.files.uris}`, `text/plain;charset=utf-8=${c.files.plain}`, `image/png=${c.files.png}`], { env: { WAYLAND_DISPLAY: c.sock } })
    assert.equal(run.status, 0, run.stderr)
    assert.deepEqual(await c.seen(), {
      manager: "ext_data_control_manager_v1",
      version: 1,
      offers: ["text/uri-list", "text/plain;charset=utf-8", "image/png"],
      selection: "clipboard",
      data: { "text/uri-list": "file:///a%20b\r\n", "text/plain;charset=utf-8": "/a b", "image/png": "PNG\u0000DATA" },
    })
  })

  it("goes to the background once the clipboard is its own, and can set the primary one", async (t) => {
    const c = await compositor(t, "zwlr_data_control_manager_v1")
    const display = path.basename(c.sock)
    const run = await runScriptAsync("joamag.files", "clipboard.py", ["--primary", `text/plain=${c.files.plain}`], { env: { WAYLAND_DISPLAY: display, XDG_RUNTIME_DIR: c.dir } })
    assert.equal(run.status, 0, run.stderr)
    const seen = await c.seen()
    assert.equal(seen.manager, "zwlr_data_control_manager_v1")
    assert.equal(seen.version, 2)
    assert.equal(seen.selection, "primary")
    assert.deepEqual(seen.data, { "text/plain": "/a b" })
  })

  it("tells the caller to fall back when there is no data-control or no session", async (t) => {
    const c = await compositor(t, "none")
    const run = await runScriptAsync("joamag.files", "clipboard.py", [`text/plain=${c.files.plain}`], { env: { WAYLAND_DISPLAY: c.sock } })
    assert.equal(run.status, 2)
    assert.match(run.stderr, /no data-control protocol/)
    assert.equal((await c.seen()).selection, null)
    const away = await runScriptAsync("joamag.files", "clipboard.py", [`text/plain=${c.files.plain}`], { env: { WAYLAND_DISPLAY: path.join(c.dir, "gone") } })
    assert.equal(away.status, 2)
    const unset = await runScriptAsync("joamag.files", "clipboard.py", [`text/plain=${c.files.plain}`], { env: { WAYLAND_DISPLAY: "wayland-9" } })
    assert.equal(unset.status, 2)
    assert.match(unset.stderr, /no Wayland session/)
  })

  it("refuses arguments it cannot offer", async (t) => {
    const c = await compositor(t, "none")
    assert.equal((await runScriptAsync("joamag.files", "clipboard.py", ["text/plain"], { env: { WAYLAND_DISPLAY: c.sock } })).status, 1)
    assert.equal((await runScriptAsync("joamag.files", "clipboard.py", ["--foreground"], { env: { WAYLAND_DISPLAY: c.sock } })).status, 1)
    // Nothing connected, so the stand-in is let go.
    const free = await runScriptAsync("joamag.files", "clipboard.py", [`text/plain=${c.files.plain}`], { env: { WAYLAND_DISPLAY: c.sock } })
    assert.equal(free.status, 2)
    await c.seen()
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

  // Real archives, made with bsdtar from a small tree: a folder with a
  // subfolder, a file at the top and a name with a glob character.
  function archives(s) {
    const src = path.join(s.dir, "src")
    write(path.join(src, "docs", "a b.txt"), "hello")
    write(path.join(src, "docs", "sub", "c[1].md"), "deep")
    write(path.join(src, "readme.txt"), "top")
    const zip = path.join(s.home, "docs.zip")
    const tgz = path.join(s.home, "docs.tar.gz")
    for (const out of [zip, tgz]) {
      const made = require("node:child_process").spawnSync("bsdtar", ["-a", "-cf", out, "-C", src, "docs", "readme.txt"])
      assert.equal(made.status, 0, String(made.stderr))
    }
    return { src, zip, tgz }
  }

  it("lists an archive's members", (t) => {
    const s = setup(t)
    const a = archives(s)
    for (const archive of [a.zip, a.tgz]) {
      const listed = Model.parseArchiveListing(s.run(["archive-list", archive]).stdout, Date.now())
      assert.deepEqual(listed.map((m) => m.inner).sort(), ["docs", "docs/a b.txt", "docs/sub", "docs/sub/c[1].md", "readme.txt"])
    }
    write(path.join(s.home, "broken.zip"), "not a zip")
    assert.match(s.run(["archive-list", path.join(s.home, "broken.zip")]).stdout, /^error\t/)
    assert.equal(s.run(["archive-list", path.join(s.home, "none.zip")]).stdout, `error\tno archive at ${s.home}/none.zip\n`)
    assert.equal(s.run(["archive-list"]).status, 1)
  })

  it("takes one member out into the cache, once", (t) => {
    const s = setup(t)
    const a = archives(s)
    const env = { XDG_CACHE_HOME: path.join(s.dir, "cache") }
    const out = s.run(["archive-file", a.zip, "docs/sub/c[1].md"], env).stdout
    assert.match(out, /^extracted\t.+\/joamag-files\/archives\/[0-9a-f]{32}\/docs\/sub\/c\[1\]\.md\n$/)
    const copy = out.trim().split("\t")[1]
    assert.equal(fs.readFileSync(copy, "utf8"), "deep")
    // Taken again, the copy is reused rather than extracted over.
    fs.writeFileSync(copy, "kept")
    assert.equal(s.run(["archive-file", a.zip, "docs/sub/c[1].md"], env).stdout, out)
    assert.equal(fs.readFileSync(copy, "utf8"), "kept")
    assert.match(s.run(["archive-file", a.zip, "nothing.txt"], env).stdout, /^error\t/)
    assert.equal(s.run(["archive-file", a.zip, "../escape"], env).stdout, "error\tbad member ../escape\n")
    assert.equal(s.run(["archive-file", a.zip, "/abs"], env).stdout, "error\tbad member /abs\n")
    assert.equal(s.run(["archive-file", path.join(s.home, "none.zip"), "x"], env).stdout, `error\tno archive at ${s.home}/none.zip\n`)
  })

  it("extracts an archive with its progress, and a folder of it without the folders above", (t) => {
    const s = setup(t)
    const a = archives(s)
    const all = path.join(s.home, "all")
    const r = Model.parseResult(s.run(["extract", a.tgz, all, "0"]).stdout)
    assert.equal(r.total, 12)
    assert.equal(r.progress, 12)
    assert.deepEqual(r.done, [{ from: a.tgz, to: all }])
    assert.equal(fs.readFileSync(path.join(all, "docs", "sub", "c[1].md"), "utf8"), "deep")
    const part = path.join(s.home, "part")
    Model.parseResult(s.run(["extract", a.zip, part, "1", "docs/sub", "docs/a b.txt"]).stdout)
    assert.deepEqual(fs.readdirSync(part).sort(), ["a b.txt", "sub"])
    assert.equal(fs.readFileSync(path.join(part, "sub", "c[1].md"), "utf8"), "deep")
  })

  it("keeps files already where it extracts, and reports what fails", (t) => {
    const s = setup(t)
    const a = archives(s)
    const into = path.join(s.home, "into")
    write(path.join(into, "readme.txt"), "mine")
    Model.parseResult(s.run(["extract", a.zip, into, "0"]).stdout)
    assert.equal(fs.readFileSync(path.join(into, "readme.txt"), "utf8"), "mine")
    assert.equal(fs.readFileSync(path.join(into, "docs", "a b.txt"), "utf8"), "hello")
    write(path.join(s.home, "bad.zip"), "nope")
    assert.match(s.run(["extract", path.join(s.home, "bad.zip"), path.join(s.home, "x"), "0"]).stdout, /error\t/)
    assert.equal(s.run(["extract", path.join(s.home, "none.zip"), into, "0"]).stdout, `error\tno archive at ${s.home}/none.zip\n`)
    assert.equal(s.run(["extract", a.zip, into, "x"]).stdout, "error\tbad strip x\n")
    assert.equal(s.run(["extract", a.zip, into]).stdout, "error\textract needs an archive, a destination and a strip count\n")
  })

  it("cancels an extraction and removes the folder it made", async (t) => {
    const s = setup(t)
    const a = archives(s)
    // A bsdtar whose extraction stalls after writing a file.
    fakeCommand(s.bin, "bsdtar", 'if [[ $1 == -xkf ]]; then mkdir -p "$4"; echo x > "$4/partial"; exec sleep 30; fi; exec /usr/bin/bsdtar "$@"')
    const dest = path.join(s.home, "made")
    const child = spawn(path.join(pluginDir("joamag.files"), "files.sh"), ["extract", a.zip, dest, "0"], { env: { ...s.env, PATH: [s.bin, "/usr/bin", "/bin"].join(":"), LANG: "C" } })
    let stdout = ""
    const progressed = new Promise((resolve) => child.stdout.on("data", (chunk) => {
      stdout += chunk
      if (stdout.includes("progress\t")) resolve()
    }))
    const closed = new Promise((resolve) => child.on("close", resolve))
    await progressed
    child.kill("SIGTERM")
    await closed
    assert.equal(Model.parseResult(stdout).cancelled, true)
    assert.ok(!fs.existsSync(dest))
  })

  it("compresses into the format its name asks for", (t) => {
    const s = setup(t)
    const a = archives(s)
    const zip = path.join(s.home, "out.zip")
    assert.equal(s.run(["compress", zip, path.join(a.src, "docs"), path.join(a.src, "readme.txt")]).stdout, `total\t0\ncreated\t${zip}\n`)
    const listed = Model.parseArchiveListing(s.run(["archive-list", zip]).stdout, Date.now())
    assert.deepEqual(listed.map((m) => m.inner).sort(), ["docs", "docs/a b.txt", "docs/sub", "docs/sub/c[1].md", "readme.txt"])
    const tgz = path.join(s.home, "out.tar.gz")
    write(path.join(s.home, "-dash.txt"), "d")
    s.run(["compress", tgz, path.join(s.home, "-dash.txt")])
    assert.match(require("node:child_process").execFileSync("file", ["-b", tgz]).toString(), /gzip/)
    assert.deepEqual(fs.readdirSync(s.home).filter((n) => n.startsWith(".partial")), [])
  })

  it("refuses a taken name, a missing file or folder, and nothing to pack", (t) => {
    const s = setup(t)
    const a = archives(s)
    assert.equal(s.run(["compress", a.zip, path.join(a.src, "readme.txt")]).stdout, "error\tdocs.zip already exists\n")
    assert.equal(s.run(["compress", path.join(s.home, "n.zip"), path.join(s.home, "gone")]).stdout, "error\tgone is gone\n")
    assert.equal(s.run(["compress", path.join(s.home, "nowhere", "n.zip"), path.join(a.src, "readme.txt")]).stdout, `error\tno folder at ${s.home}/nowhere\n`)
    assert.equal(s.run(["compress", path.join(s.home, "n.zip")]).stdout, "error\tnothing to compress\n")
    fakeCommand(s.bin, "bsdtar", 'echo "bsdtar: disk full" >&2; exit 1')
    assert.equal(s.run(["compress", path.join(s.home, "n.zip"), path.join(a.src, "readme.txt")]).stdout, "total\t0\nerror\tbsdtar: disk full\n")
    assert.ok(!fs.existsSync(path.join(s.home, "n.zip")))
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

  // Stand-ins for what the default file manager touches: the shell's IPC
  // (FAKE_SHELL_STATUS makes it unreachable); xdg-mime, which reads the
  // folder default from the user's mimeapps.list, else the system's (the
  // FAKE_MIME file), and writes it to the user's; Hyprland, the D-Bus
  // reload, and starting, finding (FAKE_RUNNING) and stopping the
  // FileManager1 service. All of them log.
  function manager(s) {
    const mime = path.join(s.dir, "mime")
    fakeCommand(s.bin, "omarchy-shell", 'printf "shell %s\\n" "$*" >> "$FAKE_LOG"; exit ${FAKE_SHELL_STATUS:-0}')
    fakeCommand(s.bin, "omarchy-cmd-terminal-cwd", 'echo "$FAKE_CWD"')
    fakeCommand(s.bin, "xdg-mime", `
list="$XDG_CONFIG_HOME/mimeapps.list"
case "$1" in
  query)
    line=$(grep -m 1 '^inode/directory=' "$list" 2>/dev/null)
    if [[ -n $line ]]; then echo "\${line#*=}"; else cat "$FAKE_MIME" 2>/dev/null; fi ;;
  default)
    [[ -n \${FAKE_MIME_FAIL:-} ]] && { echo "xdg-mime: cannot write" >&2; exit 1; }
    if [[ -f $list ]]; then kept=$(grep -v '^inode/directory=' "$list"); else kept="[Default Applications]"; fi
    printf '%s\\ninode/directory=%s\\n' "$kept" "$2" > "$list"
    printf 'xdg-mime %s\\n' "$*" >> "$FAKE_LOG" ;;
esac`)
    for (const name of ["hyprctl", "gdbus", "setsid", "pkill"]) fakeCommand(s.bin, name, `printf '${name} %s\\n' "$*" >> "$FAKE_LOG"`)
    fakeCommand(s.bin, "pgrep", 'printf "pgrep %s\\n" "$*" >> "$FAKE_LOG"; [[ -n ${FAKE_RUNNING:-} ]]')
    const apps = path.join(s.data, "applications")
    const installed = (id) => fs.writeFileSync(path.join(apps, id), `[Desktop Entry]\nName=${id}\nMimeType=inode/directory;\n`)
    const files = {
      app: path.join(apps, "joamag-files.desktop"),
      dbus: path.join(s.data, "dbus-1", "services", "org.freedesktop.FileManager1.service"),
      bindings: path.join(s.config, "hypr", "bindings.lua"),
      previous: path.join(s.home, ".local", "state", "joamag-files", "previous-file-manager"),
      previousService: path.join(s.home, ".local", "state", "joamag-files", "previous-file-manager.service"),
      mimeapps: path.join(s.config, "mimeapps.list"),
    }
    // The service's whole command line, as files.sh looks for it.
    const service = `(.*/)?python3 ${pluginDir("joamag.files").replace(/[\][\\.*^$+?(){}|]/g, "\\$&")}/filemanager1\\.py`
    return { mime, files, installed, service, env: { FAKE_MIME: mime, FAKE_CWD: path.join(s.home, "Music"), XDG_STATE_HOME: path.join(s.home, ".local", "state") } }
  }

  it("shows folders, files and file URIs from other apps in the widget", (t) => {
    const s = setup(t)
    const m = manager(s)
    const report = path.join(s.home, "Downloads", "Q4 report.pdf")
    write(report, "%PDF")
    for (const args of [["open", path.join(s.home, "Downloads")], ["open", `file://${s.home}/Down%20loads/R%26D`], ["open", `file://localhost${s.home}/Music`], ["open", report], ["open", "Music"], ["reveal", path.join(s.home, "Music")], ["open"], ["open-cwd"]]) {
      assert.equal(s.run(args, m.env).stdout, "")
    }
    assert.deepEqual(s.log(), [
      `shell joamag.files go ${s.home}/Downloads`,
      `shell joamag.files go ${s.home}/Down loads/R&D`,
      `shell joamag.files go ${s.home}/Music`,
      // A file shows in its folder, picked.
      `shell joamag.files reveal ${report}`,
      // A relative path is taken from where it was asked.
      `shell joamag.files go ${process.cwd()}/Music`,
      `shell joamag.files reveal ${s.home}/Music`,
      "shell joamag.files summon",
      `shell joamag.files go ${s.home}/Music`,
    ])
  })

  it("hands folders to the previous file manager without the widget, and remote ones always", (t) => {
    const s = setup(t)
    const m = manager(s)
    const apps = path.join(s.data, "applications")
    const gone = { ...m.env, FAKE_SHELL_STATUS: "1" }
    assert.equal(s.run(["open", "/srv"], gone).stdout, "error\tno other file manager to open /srv\n")
    assert.equal(s.run(["open"], gone).stdout, "error\tno other file manager\n")
    m.installed("org.gnome.Nautilus.desktop")
    s.run(["open", "/srv"], gone)
    m.installed("folio.desktop")
    s.run(["reveal", "/srv/notes.md"], gone)
    s.run(["open"], gone)
    // The one that was the default before goes first.
    write(m.files.previous, "nvim.desktop\n")
    s.run(["open", "sftp://server/srv"], m.env)
    assert.deepEqual(s.log(), [
      "shell joamag.files go /srv",
      "shell joamag.files summon",
      "shell joamag.files go /srv",
      `launch ${apps}/org.gnome.Nautilus.desktop /srv`,
      "shell joamag.files reveal /srv/notes.md",
      `launch ${apps}/folio.desktop /srv/notes.md`,
      "shell joamag.files summon",
      `launch ${apps}/folio.desktop`,
      `launch ${apps}/nvim.desktop sftp://server/srv`,
    ])
  })

  it("quotes a plugin folder with a space for the desktop file and Hyprland", (t) => {
    const s = setup(t)
    const m = manager(s)
    const here = path.join(s.dir, "my plugins", "joamag.files")
    fs.mkdirSync(here, { recursive: true })
    fs.copyFileSync(path.join(pluginDir("joamag.files"), "files.sh"), path.join(here, "files.sh"))
    fs.chmodSync(path.join(here, "files.sh"), 0o755)
    const result = require("node:child_process").spawnSync(path.join(here, "files.sh"), ["default", "on"], { env: { ...s.env, ...m.env, PATH: `${s.bin}:/usr/bin:/bin`, LANG: "C" } })
    assert.equal(String(result.stdout), "")
    assert.ok(fs.readFileSync(m.files.app, "utf8").includes(`Exec="${here}/files.sh" open %U\n`))
    // Escaped for the shell Hyprland runs it in, then again for Lua.
    const shell = here.replace(/ /g, "\\\\ ")
    assert.ok(fs.readFileSync(m.files.bindings, "utf8").includes(`o.rebind("SUPER + SHIFT + F", "File manager", "${shell}/files.sh open")\n`))
  })

  it("finds and stops the FileManager1 service, never an editor on its script", async (t) => {
    const s = setup(t)
    const m = manager(s)
    // The real pgrep and pkill, on a copy of the plugin whose service sleeps.
    for (const name of ["pgrep", "pkill"]) fs.rmSync(path.join(s.bin, name))
    const here = path.join(s.dir, "plugin")
    fs.mkdirSync(here)
    fs.copyFileSync(path.join(pluginDir("joamag.files"), "files.sh"), path.join(here, "files.sh"))
    fs.chmodSync(path.join(here, "files.sh"), 0o755)
    const script = path.join(here, "filemanager1.py")
    fs.writeFileSync(script, "import time\ntime.sleep(30)\n")
    const run = (mode) => require("node:child_process").spawnSync(path.join(here, "files.sh"), ["default", mode], { env: { ...s.env, ...m.env, PATH: `${s.bin}:/usr/bin:/bin`, LANG: "C" } })
    const ended = (child) => new Promise((resolve) => child.on("exit", (code, signal) => resolve(signal)))
    const editor = spawn("tail", ["-f", script])
    t.after(() => editor.kill())
    await new Promise((resolve) => setTimeout(resolve, 100))
    // Only the editor names the script: the service is not running yet.
    run("on")
    assert.deepEqual(s.log().filter((l) => l.startsWith("setsid")), [`setsid -f ${script}`])
    const service = spawn("python3", [script])
    t.after(() => service.kill())
    await new Promise((resolve) => setTimeout(resolve, 100))
    fs.writeFileSync(s.env.FAKE_LOG, "")
    run("on")
    assert.deepEqual(s.log().filter((l) => l.startsWith("setsid")), [])
    const stopped = ended(service)
    run("off")
    assert.equal(await stopped, "SIGTERM")
    assert.equal(editor.exitCode, null)
    assert.equal(editor.signalCode, null)
  })

  it("makes the widget the default file manager, and hands everything back", (t) => {
    const s = setup(t)
    const m = manager(s)
    const here = pluginDir("joamag.files")
    m.installed("org.gnome.Nautilus.desktop")
    // Nautilus is the system's default; the user's list holds other types.
    fs.writeFileSync(m.mime, "org.gnome.Nautilus.desktop")
    const types = "[Default Applications]\ntext/html=chrome.desktop\n"
    write(m.files.mimeapps, types)
    const mine = "-- My keys\no.bind(\"SUPER + W\", \"Close\", \"close-window\")\n"
    write(m.files.bindings, mine)
    assert.equal(s.run(["default", "on"], m.env).stdout, "")
    assert.equal(fs.readFileSync(m.files.mimeapps, "utf8"), types + "inode/directory=joamag-files.desktop\n")
    assert.equal(fs.readFileSync(m.files.previous, "utf8"), "org.gnome.Nautilus.desktop\n")
    const app = fs.readFileSync(m.files.app, "utf8")
    assert.match(app, /^\[Desktop Entry\]\n/)
    assert.ok(app.includes(`Exec=${here}/files.sh open %U\n`))
    assert.ok(app.includes("MimeType=inode/directory;\nNoDisplay=true\n"))
    assert.equal(fs.readFileSync(m.files.dbus, "utf8"), `[D-BUS Service]\nName=org.freedesktop.FileManager1\nExec=${here}/filemanager1.py\n`)
    assert.equal(fs.readFileSync(m.files.bindings, "utf8"), mine + [
      "",
      "-- joamag.files: the file manager keys open the Files widget (its Default file manager setting adds and removes these lines)",
      `o.rebind("SUPER + SHIFT + F", "File manager", "${here}/files.sh open")`,
      `o.rebind("SUPER + ALT + SHIFT + F", "File manager (cwd)", "${here}/files.sh open-cwd")`,
      "-- joamag.files: end",
      "",
    ].join("\n"))
    assert.deepEqual(s.log(), [
      "xdg-mime default joamag-files.desktop inode/directory",
      "gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ReloadConfig",
      "hyprctl reload",
      `pgrep -f -x -- ${m.service}`,
      `setsid -f ${here}/filemanager1.py`,
    ])

    // Again, at the next start: nothing to change, the service running.
    fs.writeFileSync(s.env.FAKE_LOG, "")
    s.run(["default", "on"], { ...m.env, FAKE_RUNNING: "1" })
    assert.deepEqual(s.log(), [`pgrep -f -x -- ${m.service}`])
    assert.equal(fs.readFileSync(m.files.previous, "utf8"), "org.gnome.Nautilus.desktop\n")

    // Off: every file as it was, the system's default showing through.
    fs.writeFileSync(s.env.FAKE_LOG, "")
    assert.equal(s.run(["default", "off"], m.env).stdout, "")
    assert.equal(fs.readFileSync(m.files.mimeapps, "utf8"), types)
    assert.equal(fs.readFileSync(m.files.bindings, "utf8"), mine)
    for (const file of [m.files.app, m.files.dbus, m.files.previous]) assert.ok(!fs.existsSync(file), file)
    assert.deepEqual(s.log(), [
      "gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ReloadConfig",
      "hyprctl reload",
      `pkill -f -x -- ${m.service}`,
    ])

    // Off again changes nothing.
    fs.writeFileSync(s.env.FAKE_LOG, "")
    s.run(["default", "off"], m.env)
    assert.deepEqual(s.log(), [`pkill -f -x -- ${m.service}`])
  })

  it("sets back the user's own pick, or one still installed, and never touches a default it did not set", (t) => {
    const s = setup(t)
    const m = manager(s)
    const here = pluginDir("joamag.files")
    for (const id of ["org.gnome.Nautilus.desktop", "thunar.desktop"]) m.installed(id)
    fs.writeFileSync(m.mime, "org.gnome.Nautilus.desktop")
    // Off at every start, for someone who never turned it on: their pick stays.
    write(m.files.mimeapps, "[Default Applications]\ninode/directory=thunar.desktop\n")
    s.run(["default", "off"], m.env)
    assert.equal(fs.readFileSync(m.files.mimeapps, "utf8"), "[Default Applications]\ninode/directory=thunar.desktop\n")
    assert.ok(!s.log().some((l) => l.startsWith("xdg-mime")))
    // Their own pick comes back when the widget lets go.
    s.run(["default", "on"], m.env)
    s.run(["default", "off"], m.env)
    assert.equal(fs.readFileSync(m.files.mimeapps, "utf8"), "[Default Applications]\ninode/directory=thunar.desktop\n")
    // Thunar went away meanwhile, Omarchy's Files is the system's default
    // now: that one shows through, nothing is written.
    s.run(["default", "on"], m.env)
    fs.rmSync(path.join(s.data, "applications", "thunar.desktop"))
    m.installed("folio.desktop")
    fs.writeFileSync(m.mime, "folio.desktop")
    fs.writeFileSync(s.env.FAKE_LOG, "")
    s.run(["default", "off"], m.env)
    assert.equal(fs.readFileSync(m.files.mimeapps, "utf8"), "[Default Applications]\n")
    assert.deepEqual(s.log(), ["gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ReloadConfig", "hyprctl reload", `pkill -f -x -- ${m.service}`])
  })

  it("sets the user's own D-Bus service aside, and puts it back", (t) => {
    const s = setup(t)
    const m = manager(s)
    const here = pluginDir("joamag.files")
    const theirs = "[D-BUS Service]\nName=org.freedesktop.FileManager1\nExec=/usr/bin/flea --dbus\n"
    write(m.files.dbus, theirs)
    s.run(["default", "on"], m.env)
    assert.equal(fs.readFileSync(m.files.dbus, "utf8"), `[D-BUS Service]\nName=org.freedesktop.FileManager1\nExec=${here}/filemanager1.py\n`)
    assert.equal(fs.readFileSync(m.files.previousService, "utf8"), theirs)
    // Again, at the next start: the one set aside stays as it was.
    s.run(["default", "on"], m.env)
    assert.equal(fs.readFileSync(m.files.previousService, "utf8"), theirs)
    fs.writeFileSync(s.env.FAKE_LOG, "")
    s.run(["default", "off"], m.env)
    assert.equal(fs.readFileSync(m.files.dbus, "utf8"), theirs)
    assert.ok(!fs.existsSync(path.dirname(m.files.previousService)))
    assert.ok(s.log().includes("gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ReloadConfig"))
  })

  it("keeps another file manager's D-Bus service, minds missing bindings, and reports xdg-mime", (t) => {
    const s = setup(t)
    const m = manager(s)
    const here = pluginDir("joamag.files")
    m.installed("org.gnome.Nautilus.desktop")
    // No bindings yet, and the folder default already the widget's.
    write(m.files.mimeapps, "[Default Applications]\ninode/directory=joamag-files.desktop\n")
    s.run(["default", "on"], m.env)
    assert.ok(!fs.existsSync(m.files.previous))
    assert.equal(fs.readFileSync(m.files.bindings, "utf8").split("\n")[0], "-- joamag.files: the file manager keys open the Files widget (its Default file manager setting adds and removes these lines)")
    assert.ok(!s.log().some((l) => l.startsWith("xdg-mime")))
    // Another file manager took the D-Bus service meanwhile.
    write(m.files.dbus, "[D-BUS Service]\nName=org.freedesktop.FileManager1\nExec=/usr/bin/flea --dbus\n")
    fs.writeFileSync(s.env.FAKE_LOG, "")
    s.run(["default", "off"], m.env)
    assert.ok(fs.existsSync(m.files.dbus))
    assert.equal(fs.readFileSync(m.files.bindings, "utf8"), "\n")
    // Nothing was the default before, not even the system's: Nautilus, installed, is.
    assert.equal(fs.readFileSync(m.files.mimeapps, "utf8"), "[Default Applications]\ninode/directory=org.gnome.Nautilus.desktop\n")
    assert.deepEqual(s.log(), ["xdg-mime default org.gnome.Nautilus.desktop inode/directory", "hyprctl reload", `pkill -f -x -- ${m.service}`])
    // Without bindings, off leaves them alone.
    fs.rmSync(m.files.bindings)
    s.run(["default", "off"], m.env)
    assert.ok(!fs.existsSync(m.files.bindings))
    assert.equal(s.run(["default", "on"], { ...m.env, FAKE_MIME_FAIL: "1" }).stdout, "error\txdg-mime: cannot write\n")
  })

  it("rejects bad invocations", (t) => {
    const s = setup(t)
    assert.equal(s.run(["bogus"]).status, 1)
    assert.equal(s.run([]).status, 1)
    assert.equal(s.run(["free"]).status, 1)
    assert.equal(s.run(["reveal"]).status, 1)
    assert.equal(s.run(["default"]).stdout, "error\tdefault takes on or off\n")
  })
})

// filemanager1.py on a bus of its own that starts no services, so only what
// the test runs owns names: another file manager holding the name first,
// then the widget's service waiting in line behind it.
describe("filemanager1.py", () => {
  const { spawnSync } = require("node:child_process")
  const ready = spawnSync("sh", ["-c", "command -v dbus-run-session && command -v gdbus && python3 -c 'from gi.repository import Gio'"]).status === 0

  const CONFIG = `<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
`

  // Holds the name, then lets go; the widget's service must wait, then take
  // the calls. Each call is one files.sh run, logged by a stand-in.
  const DRIVER = String.raw`
set -u
dir=$1
trap 'kill $(jobs -p) 2>/dev/null' EXIT
bus() { gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method "org.freedesktop.DBus.$1" org.freedesktop.FileManager1 2>/dev/null; }
show() { gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 --method "org.freedesktop.FileManager1.$1" "$2" "" >/dev/null 2>&1; }
until_true() { for _ in $(seq 200); do "$@" && return 0; sleep 0.025; done; return 1; }
python3 -c 'from gi.repository import Gio, GLib; Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.FileManager1", Gio.BusNameOwnerFlags.NONE, None, None, None); GLib.MainLoop().run()' &
holder=$!
until_true eval '[[ $(bus NameHasOwner) == "(true,)" ]]' || exit 1
first=$(bus GetNameOwner)
"$dir/filemanager1.py" &
service=$!
sleep 0.3
show ShowFolders "['file:///held']"
kill "$holder"
until_true eval 'owner=$(bus GetNameOwner); [[ -n $owner && $owner != "$first" ]]' || exit 1
show ShowItems "['file:///home/u/a%20b.txt', 'file:///home/u/c']"
show ShowFolders "['file:///home/u']"
show ShowItemProperties "[]"
until_true eval '[[ $(wc -l < "$dir/log" 2>/dev/null) == 2 ]]' || exit 1
`

  it("waits for the name, then hands folders and items to files.sh", (t) => {
    if (!ready) {
      t.skip("needs dbus-run-session, gdbus and PyGObject")
      return
    }
    const dir = tmpdir(t)
    fs.copyFileSync(path.join(pluginDir("joamag.files"), "filemanager1.py"), path.join(dir, "filemanager1.py"))
    fs.chmodSync(path.join(dir, "filemanager1.py"), 0o755)
    fakeCommand(dir, "files.sh", `printf '%s\\n' "$*" >> "${dir}/log"`)
    fs.writeFileSync(path.join(dir, "bus.conf"), CONFIG)
    fs.writeFileSync(path.join(dir, "driver.sh"), DRIVER)
    const result = spawnSync("dbus-run-session", [`--config-file=${path.join(dir, "bus.conf")}`, "--", "bash", path.join(dir, "driver.sh"), dir], { timeout: 20000 })
    assert.equal(result.status, 0, String(result.stderr))
    // Nothing while the other one held the name; the first of each call
    // after; nothing for an empty list.
    assert.deepEqual(fs.readFileSync(path.join(dir, "log"), "utf8").trim().split("\n"), [
      "reveal file:///home/u/a%20b.txt",
      "open file:///home/u",
    ])
  })
})
