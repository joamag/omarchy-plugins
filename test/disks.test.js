// Tests for joamag.disks: Model.js in declaration order, then disks.sh
// against df, lsblk, du, findmnt, udisksctl and gio stand-ins.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadModel, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.disks")

// A snapshot the way disks.sh emits it: root, boot, a USB stick, an unmounted
// partition on the stick, trash and cache figures.
const RAW = [
  "mount\t/run/media/joamag/STICK\t/dev/sda1\tvfat\t30000000\t12000000\t18000000\t40\tSTICK\t1\t/dev/sda",
  "mount\t/boot\t/dev/sdc1\tvfat\t2093040\t423592\t1669448\t21\t\t0\t/dev/sdc",
  "mount\t/\t/dev/mapper/root\tbtrfs\t247943168\t103908520\t141796392\t43\t\t0\t/dev/sdc",
  "mount\t/run/media/joamag/OMARCHY\t/dev/sdb1\tiso9660\t6058174\t6058174\t0\t100\tOMARCHY\t1\t/dev/sdb",
  "mount\tshort\trow",
  "volume\t/dev/sda2\tARCHISO_EFI\tvfat\t23M\t/dev/sda",
  "volume\ttoo\tshort",
  "trash_kb\t8476",
  "trash_items\t10",
  "pkgcache_kb\t2111924",
  "pkgcache_files\t171",
  "",
].join("\n")

const snapshot = Model.parseSnapshot(RAW)
const byTarget = Object.fromEntries(snapshot.mounts.map((m) => [m.target, m]))

describe("num", () => {
  it("parses numbers and keeps missing values unknown", () => {
    assert.equal(Model.num("42"), 42)
    assert.ok(Number.isNaN(Model.num("")))
    assert.ok(Number.isNaN(Model.num(null)))
    assert.ok(Number.isNaN(Model.num("x")))
  })
})

describe("parseSnapshot", () => {
  it("reads mounts with numeric sizes and the removable flag", () => {
    assert.equal(snapshot.mounts.length, 4)
    const root = byTarget["/"]
    assert.equal(root.sizeKb, 247943168)
    assert.equal(root.pct, 43)
    assert.equal(root.removable, false)
    assert.equal(root.disk, "/dev/sdc")
    assert.equal(byTarget["/run/media/joamag/STICK"].removable, true)
    assert.equal(byTarget["/run/media/joamag/STICK"].label, "STICK")
    assert.equal(root.key, "mount:/")
  })

  it("reads volumes and the cleanup figures, skipping short rows", () => {
    assert.deepEqual(snapshot.volumes, [{ kind: "volume", key: "volume:/dev/sda2", path: "/dev/sda2", label: "ARCHISO_EFI", fstype: "vfat", size: "23M", disk: "/dev/sda" }])
    assert.equal(snapshot.trashKb, 8476)
    assert.equal(snapshot.trashItems, 10)
    assert.equal(snapshot.cacheKb, 2111924)
    assert.equal(snapshot.cacheFiles, 171)
  })

  it("leaves unknown figures as NaN on empty input", () => {
    const empty = Model.parseSnapshot("")
    assert.deepEqual(empty.mounts, [])
    assert.deepEqual(empty.volumes, [])
    assert.ok(Number.isNaN(empty.trashKb))
    assert.ok(Number.isNaN(empty.cacheFiles))
  })
})

describe("compareMounts", () => {
  it("orders root, fixed disks by path, then removable media", () => {
    assert.deepEqual(snapshot.mounts.map((m) => m.target), ["/", "/boot", "/run/media/joamag/OMARCHY", "/run/media/joamag/STICK"])
    assert.equal(Model.compareMounts(byTarget["/boot"], byTarget["/boot"]), 0)
  })
})

describe("isLoaded", () => {
  it("needs a snapshot with a mounts array", () => {
    assert.equal(Model.isLoaded(snapshot), true)
    assert.equal(Model.isLoaded({ mounts: "x" }), false)
    assert.equal(Model.isLoaded(null), false)
  })
})

describe("mountName", () => {
  it("uses the label, Root for /, or the last path segment", () => {
    assert.equal(Model.mountName(byTarget["/run/media/joamag/STICK"]), "STICK")
    assert.equal(Model.mountName(byTarget["/"]), "Root")
    assert.equal(Model.mountName(byTarget["/boot"]), "boot")
    assert.equal(Model.mountName({ target: "/mnt/data/" }), "/mnt/data/")
    assert.equal(Model.mountName(null), "")
  })
})

describe("volumeName", () => {
  it("uses the label or the device name", () => {
    assert.equal(Model.volumeName(snapshot.volumes[0]), "ARCHISO_EFI")
    assert.equal(Model.volumeName({ path: "/dev/sdd1" }), "sdd1")
    assert.equal(Model.volumeName(null), "")
  })
})

describe("rootMount", () => {
  it("finds / or falls back to the first mount", () => {
    assert.equal(Model.rootMount(snapshot).target, "/")
    assert.equal(Model.rootMount({ mounts: [byTarget["/boot"]], volumes: [] }).target, "/boot")
    assert.equal(Model.rootMount({ mounts: [], volumes: [] }), null)
    assert.equal(Model.rootMount(null), null)
  })
})

describe("removableCount", () => {
  it("counts removable mounts", () => {
    assert.equal(Model.removableCount(snapshot), 2)
    assert.equal(Model.removableCount(null), 0)
  })
})

describe("overThreshold", () => {
  it("lists mounts at or above the limit, ignoring read-only media", () => {
    assert.deepEqual(Model.overThreshold(snapshot, 90).map((m) => m.target), [])
    assert.deepEqual(Model.overThreshold(snapshot, 40).map((m) => m.target), ["/", "/run/media/joamag/STICK"])
    assert.deepEqual(Model.overThreshold(snapshot, "nonsense").map((m) => m.target), [])
    assert.deepEqual(Model.overThreshold(null, 90), [])
  })
})

describe("formatKb", () => {
  it("scales from KB to TB", () => {
    assert.equal(Model.formatKb(512), "512 KB")
    assert.equal(Model.formatKb(2048), "2 MB")
    assert.equal(Model.formatKb(1.5 * 1024 * 1024), "1.5 GB")
    assert.equal(Model.formatKb(236.5 * 1024 * 1024), "237 GB")
    assert.equal(Model.formatKb(1.8 * 1024 * 1024 * 1024), "1.80 TB")
    assert.equal(Model.formatKb(""), "—")
  })
})

describe("formatPercent", () => {
  it("rounds and refuses negatives", () => {
    assert.equal(Model.formatPercent(42.6), "43%")
    assert.equal(Model.formatPercent(-1), "—")
    assert.equal(Model.formatPercent(NaN), "—")
  })
})

describe("mountDetail", () => {
  it("joins target, filesystem, usage and the removable marker", () => {
    assert.equal(Model.mountDetail(byTarget["/"]), "/ · btrfs · 99.1 GB of 236 GB")
    assert.equal(Model.mountDetail(byTarget["/run/media/joamag/STICK"]), "/run/media/joamag/STICK · vfat · 11.4 GB of 28.6 GB · removable")
    assert.equal(Model.mountDetail({ target: "/x", sizeKb: 1024, usedKb: 512 }), "/x · 512 KB of 1 MB")
    assert.equal(Model.mountDetail(null), "")
  })
})

describe("volumeDetail", () => {
  it("describes an unmounted partition", () => {
    assert.equal(Model.volumeDetail(snapshot.volumes[0]), "/dev/sda2 · vfat · 23M · not mounted")
    assert.equal(Model.volumeDetail({ path: "/dev/sdd1" }), "/dev/sdd1 · not mounted")
    assert.equal(Model.volumeDetail(null), "")
  })
})

describe("trashDetail", () => {
  it("reports size and count, empty, or unknown", () => {
    assert.equal(Model.trashDetail(snapshot), "8 MB · 10 items")
    assert.equal(Model.trashDetail({ mounts: [], volumes: [], trashKb: 4, trashItems: 1 }), "4 KB · 1 item")
    assert.equal(Model.trashDetail({ mounts: [], volumes: [], trashKb: 0, trashItems: 0 }), "empty")
    assert.equal(Model.trashDetail({ mounts: [], volumes: [], trashItems: NaN }), "—")
    assert.equal(Model.trashDetail(null), "—")
  })
})

describe("cacheDetail", () => {
  it("reports size and package count when known", () => {
    assert.equal(Model.cacheDetail(snapshot), "2.0 GB · 171 packages")
    assert.equal(Model.cacheDetail({ mounts: [], volumes: [], cacheKb: 2048, cacheFiles: 1 }), "2 MB · 1 package")
    assert.equal(Model.cacheDetail({ mounts: [], volumes: [], cacheKb: 2048, cacheFiles: NaN }), "2 MB")
    assert.equal(Model.cacheDetail({ mounts: [], volumes: [], cacheKb: NaN }), "—")
  })
})

describe("barText", () => {
  it("shows the root filesystem the way the mode asks", () => {
    assert.equal(Model.barText(snapshot, "percent", false), `${Model.ICON} 43%`)
    assert.equal(Model.barText(snapshot, "free", false), `${Model.ICON} 135 GB`)
    assert.equal(Model.barText(snapshot, "used", false), `${Model.ICON} 99.1 GB`)
    assert.equal(Model.barText(snapshot, "none", false), Model.ICON)
    assert.equal(Model.barText(snapshot, "percent", true), Model.ICON)
    assert.equal(Model.barText(null, "percent", false), Model.ICON)
  })
})

describe("tooltip", () => {
  it("summarises free space, other mounts and hot mounts", () => {
    assert.equal(Model.tooltip(snapshot, 90), "Disks · Root 135 GB free · 3 other mounts")
    assert.equal(Model.tooltip(snapshot, 40), "Disks · Root 135 GB free · 3 other mounts · 2 over 40%")
    assert.equal(Model.tooltip({ mounts: [byTarget["/"]], volumes: [] }, 90), "Disks · Root 135 GB free")
    assert.equal(Model.tooltip({ mounts: [byTarget["/"], byTarget["/boot"]], volumes: [] }, 90), "Disks · Root 135 GB free · 1 other mount")
    assert.equal(Model.tooltip(null, 90), "Disks")
  })
})

describe("heroStatus", () => {
  it("counts mounts, removable media and hot mounts", () => {
    assert.equal(Model.heroStatus(snapshot, 90), "4 MOUNTS · 3 REMOVABLE")
    assert.equal(Model.heroStatus(snapshot, 40), "4 MOUNTS · 3 REMOVABLE · 2 OVER 40%")
    assert.equal(Model.heroStatus({ mounts: [byTarget["/"]], volumes: [] }, 90), "1 MOUNT")
    assert.equal(Model.heroStatus(null, 90), "LOADING")
  })
})

describe("visibleRows", () => {
  it("groups mounts, volumes and the two cleanup rows under headers", () => {
    const shape = Model.visibleRows(snapshot).map((r) => (Model.isHeader(r) ? `[${r.title} ${r.count}]` : r.key))
    assert.deepEqual(shape, ["[MOUNTS 4]", "mount:/", "mount:/boot", "mount:/run/media/joamag/OMARCHY", "mount:/run/media/joamag/STICK", "[NOT MOUNTED 1]", "volume:/dev/sda2", "[CLEANUP 2]", "trash", "cache"])
  })

  it("skips empty groups and returns nothing before the first snapshot", () => {
    const shape = Model.visibleRows({ mounts: [], volumes: [] }).map((r) => r.key)
    assert.deepEqual(shape, ["cleanup", "trash", "cache"])
    assert.deepEqual(Model.visibleRows(null), [])
  })
})

describe("isHeader", () => {
  it("recognises header markers only", () => {
    assert.equal(Model.isHeader({ header: true }), true)
    assert.equal(Model.isHeader(byTarget["/"]), false)
    assert.equal(Model.isHeader(null), false)
  })
})

describe("nextRowIndex", () => {
  it("skips headers in both directions and wraps", () => {
    const rows = Model.visibleRows(snapshot)
    assert.equal(Model.nextRowIndex(rows, 4, 1), 6)
    assert.equal(Model.nextRowIndex(rows, 6, -1), 4)
    assert.equal(Model.nextRowIndex(rows, rows.length - 1, 1), 1)
    assert.equal(Model.nextRowIndex([{ header: true }], 0, 1), -1)
    assert.equal(Model.nextRowIndex([], 0, 1), -1)
  })
})

describe("firstRowIndex", () => {
  it("lands on the first non-header row", () => {
    assert.equal(Model.firstRowIndex(Model.visibleRows(snapshot)), 1)
    assert.equal(Model.firstRowIndex([]), -1)
  })
})

describe("disks.sh", () => {
  const DF = [
    "Filesystem       Type    1024-blocks      Used Available Capacity Mounted on",
    "/dev/mapper/root btrfs     247943168 103908520 141796392      43% /",
    "/dev/mapper/root btrfs     247943168 103908520 141796392      43% /var/cache/pacman/pkg",
    "/dev/mapper/root btrfs     247943168 103908520 141796392      43% /home",
    "/dev/sdc1        vfat        2093040    423592   1669448      21% /boot",
    "/dev/sda1        iso9660     6058174   6058174         0     100% /run/media/joamag/OMARCHY_202608",
    "/dev/sdd1        ext4       30000000  12000000  18000000      40% /mnt/backup",
  ].join("\\n")
  // Devices: sda is a removable stick with a mounted ISO partition and an
  // unmounted EFI partition; sdc is a USB system disk the kernel does not
  // flag removable (root lives on its LUKS partition); sdd is a fixed disk.
  const FLAGS = [
    'PATH="/dev/sda" PKNAME="" RM="1" TYPE="disk"',
    'PATH="/dev/sda1" PKNAME="sda" RM="1" TYPE="part"',
    'PATH="/dev/sda2" PKNAME="sda" RM="1" TYPE="part"',
    'PATH="/dev/sdc" PKNAME="" RM="0" TYPE="disk"',
    'PATH="/dev/sdc1" PKNAME="sdc" RM="0" TYPE="part"',
    'PATH="/dev/sdc2" PKNAME="sdc" RM="0" TYPE="part"',
    'PATH="/dev/mapper/root" PKNAME="sdc2" RM="0" TYPE="crypt"',
    'PATH="/dev/sdd" PKNAME="" RM="0" TYPE="disk"',
    'PATH="/dev/sdd1" PKNAME="sdd" RM="0" TYPE="part"',
  ].join("\\n")
  const VOLUMES = [
    'PATH="/dev/sda1" TYPE="part" FSTYPE="iso9660" LABEL="OMARCHY_202608" MOUNTPOINTS="/run/media/joamag/OMARCHY_202608" SIZE="5.8G"',
    'PATH="/dev/sda2" TYPE="part" FSTYPE="vfat" LABEL="ARCHISO_EFI" MOUNTPOINTS="" SIZE="23M"',
    'PATH="/dev/sdc2" TYPE="part" FSTYPE="crypto_LUKS" LABEL="" MOUNTPOINTS="" SIZE="236.5G"',
    'PATH="/dev/sdd1" TYPE="part" FSTYPE="ext4" LABEL="" MOUNTPOINTS="/mnt/backup" SIZE="30G"',
    'PATH="/dev/sdd" TYPE="disk" FSTYPE="" LABEL="" MOUNTPOINTS="" SIZE="30G"',
  ].join("\\n")

  // Stand-ins for every external command the script touches. udisksctl and
  // gio log their arguments; FAKE_UDISKS_FAIL makes udisksctl refuse.
  function fakes(t) {
    const dir = tmpdir(t)
    fakeCommand(dir, "df", `printf '%b\\n' "${DF}"`)
    fakeCommand(dir, "lsblk", `
case "$*" in
  "-P -o PATH,PKNAME,RM,TYPE") printf '%b\\n' '${FLAGS}' ;;
  "-P -o PATH,TYPE,FSTYPE,LABEL,MOUNTPOINTS,SIZE") printf '%b\\n' '${VOLUMES}' ;;
  "-nro LABEL /dev/sda1") echo OMARCHY_202608 ;;
  "-nro LABEL "*) echo ;;
  "-nro PATH,MOUNTPOINT /dev/sda") printf '/dev/sda \\n/dev/sda1 /run/media/joamag/OMARCHY_202608\\n/dev/sda2 \\n' ;;
  *) exit 2 ;;
esac`)
    fakeCommand(dir, "du", 'case "$2" in *Trash*) printf "8476\\t%s\\n" "$2" ;; *) printf "2111924\\t%s\\n" "$2" ;; esac')
    fakeCommand(dir, "findmnt", 'case "$*" in *"/run/media/joamag/OMARCHY_202608") echo "/dev/sda1" ;; *) exit 1 ;; esac')
    fakeCommand(dir, "udisksctl", `printf '%s\\n' "$*" >> "$FAKE_LOG"; if [[ -n \${FAKE_UDISKS_FAIL:-} ]]; then echo "Error unmounting: device is busy" >&2; exit 1; fi`)
    fakeCommand(dir, "gio", `printf '%s\\n' "$*" >> "$FAKE_LOG"`)
    // A trash with three entries and a cache with two packages plus a signature.
    const data = path.join(dir, "data")
    fs.mkdirSync(path.join(data, "Trash", "files"), { recursive: true })
    for (const name of ["a.txt", "b.txt", "dir"]) fs.writeFileSync(path.join(data, "Trash", "files", name), "")
    const cache = path.join(dir, "cache")
    fs.mkdirSync(cache)
    for (const name of ["linux-7.1.9.arch1-2-x86_64.pkg.tar.zst", "linux-7.1.9.arch1-2-x86_64.pkg.tar.zst.sig", "jq-1.7-1-x86_64.pkg.tar.zst"]) fs.writeFileSync(path.join(cache, name), "")
    const env = { XDG_DATA_HOME: data, OMARCHY_PKG_CACHE: cache, FAKE_LOG: path.join(dir, "actions.log"), TMPDIR: dir }
    return { dir, env, log: () => (fs.existsSync(env.FAKE_LOG) ? fs.readFileSync(env.FAKE_LOG, "utf8").trim().split("\n") : []) }
  }

  it("collapses btrfs subvolumes, flags removable media and lists unmounted volumes", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.disks", "disks.sh", [], { bin: f.dir, env: f.env })
    assert.equal(result.status, 0)
    const parsed = Model.parseSnapshot(result.stdout)
    assert.deepEqual(parsed.mounts.map((m) => m.target), ["/", "/boot", "/mnt/backup", "/run/media/joamag/OMARCHY_202608"])
    const root = parsed.mounts.find((m) => m.target === "/")
    assert.equal(root.usedKb, 103908520)
    assert.equal(root.removable, false)
    assert.equal(root.disk, "/dev/sdc")
    const stick = parsed.mounts.find((m) => m.target.startsWith("/run/media"))
    assert.equal(stick.removable, true)
    assert.equal(stick.label, "OMARCHY_202608")
    assert.equal(stick.disk, "/dev/sda")
    // A fixed disk under /mnt is not removable even though it sits in a media path.
    assert.equal(parsed.mounts.find((m) => m.target === "/mnt/backup").removable, false)
    // Only the removable, unmounted, filesystem-bearing partition is a volume.
    assert.deepEqual(parsed.volumes.map((v) => v.path), ["/dev/sda2"])
    assert.equal(parsed.volumes[0].disk, "/dev/sda")
    assert.equal(parsed.trashKb, 8476)
    assert.equal(parsed.trashItems, 3)
    assert.equal(parsed.cacheKb, 2111924)
    assert.equal(parsed.cacheFiles, 2)
  })

  it("reports an empty trash and no cache figures when the directories are missing", (t) => {
    const f = fakes(t)
    const parsed = Model.parseSnapshot(runScript("joamag.disks", "disks.sh", [], { bin: f.dir, env: { ...f.env, XDG_DATA_HOME: path.join(f.dir, "nowhere"), OMARCHY_PKG_CACHE: path.join(f.dir, "nocache") } }).stdout)
    assert.equal(parsed.trashKb, 0)
    assert.equal(parsed.trashItems, 0)
    assert.ok(Number.isNaN(parsed.cacheKb))
  })

  it("unmounts through udisks and reports failures", (t) => {
    const f = fakes(t)
    const ok = runScript("joamag.disks", "disks.sh", ["unmount", "/run/media/joamag/OMARCHY_202608"], { bin: f.dir, env: f.env })
    assert.equal(ok.status, 0)
    assert.equal(ok.stdout, "")
    assert.deepEqual(f.log(), ["unmount -b /dev/sda1 --no-user-interaction"])
    const nothing = runScript("joamag.disks", "disks.sh", ["unmount", "/mnt/none"], { bin: f.dir, env: f.env })
    assert.equal(nothing.stdout, "error\tnothing is mounted at /mnt/none\n")
    const busy = runScript("joamag.disks", "disks.sh", ["unmount", "/run/media/joamag/OMARCHY_202608"], { bin: f.dir, env: { ...f.env, FAKE_UDISKS_FAIL: "1" } })
    assert.equal(busy.stdout, "error\tError unmounting: device is busy \n")
  })

  it("ejects a disk by unmounting its partitions first", (t) => {
    const f = fakes(t)
    const result = runScript("joamag.disks", "disks.sh", ["eject", "/dev/sda"], { bin: f.dir, env: f.env })
    assert.equal(result.stdout, "")
    assert.deepEqual(f.log(), ["unmount -b /dev/sda1 --no-user-interaction", "power-off -b /dev/sda --no-user-interaction"])
    const failed = runScript("joamag.disks", "disks.sh", ["eject", "/dev/sda"], { bin: f.dir, env: { ...f.env, FAKE_UDISKS_FAIL: "1" } })
    assert.equal(failed.stdout, "error\tcould not unmount /dev/sda1\n")
  })

  it("mounts a volume and empties the trash", (t) => {
    const f = fakes(t)
    assert.equal(runScript("joamag.disks", "disks.sh", ["mount", "/dev/sda2"], { bin: f.dir, env: f.env }).stdout, "")
    assert.equal(runScript("joamag.disks", "disks.sh", ["empty-trash"], { bin: f.dir, env: f.env }).stdout, "")
    assert.deepEqual(f.log(), ["mount -b /dev/sda2 --no-user-interaction", "trash --empty"])
    const refused = runScript("joamag.disks", "disks.sh", ["mount", "/dev/sda2"], { bin: f.dir, env: { ...f.env, FAKE_UDISKS_FAIL: "1" } })
    assert.match(refused.stdout, /^error\tError unmounting: device is busy/)
  })

  it("rejects bad invocations", (t) => {
    const f = fakes(t)
    assert.equal(runScript("joamag.disks", "disks.sh", ["bogus"], { bin: f.dir, env: f.env }).status, 1)
    assert.equal(runScript("joamag.disks", "disks.sh", ["unmount"], { bin: f.dir, env: f.env }).status, 1)
    assert.equal(runScript("joamag.disks", "disks.sh", ["eject"], { bin: f.dir, env: f.env }).status, 1)
    assert.equal(runScript("joamag.disks", "disks.sh", ["mount"], { bin: f.dir, env: f.env }).status, 1)
  })
})
