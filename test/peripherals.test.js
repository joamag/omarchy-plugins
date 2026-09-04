// Tests for joamag.peripherals: Model.js in declaration order, then
// peripherals.sh driven against a fake upower on PATH.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawn } = require("node:child_process")
const { loadModel, runScript, tmpdir, fakeCommand, fixturePath } = require("./helpers")

const Model = loadModel("joamag.peripherals")

// A snapshot the way peripherals.sh emits it: a coarse Logitech mouse and
// keyboard, a fine bluetooth headset on its charger, and a phone with an
// estimate of the time left.
const RAW = [
  "solaar\t1",
  "device\t/org/freedesktop/UPower/devices/battery_hidpp_battery_0\tmouse\tLogitech MX Master 3\tfully-charged\t100\tfull\t",
  "device\t/org/freedesktop/UPower/devices/battery_hidpp_battery_1\tkeyboard\tMX Keys\tdischarging\t20\tlow\t",
  "device\t/org/freedesktop/UPower/devices/headset_dev_AA\theadset\tWH-1000XM5\tcharging\t45\t\t90",
  "device\t/org/freedesktop/UPower/devices/phone_dev_11\tphone\tPixel 9\tdischarging\t12\tnone\t30",
  "device\tshort",
  "",
].join("\n")

const snapshot = Model.parseSnapshot(RAW)
const [phone, keyboard, headset, mouse] = snapshot.devices
const empty = Model.parseSnapshot("solaar\t0\n")

describe("num", () => {
  it("parses numeric strings and rejects the rest", () => {
    assert.equal(Model.num("45"), 45)
    assert.ok(Number.isNaN(Model.num("abc")))
    assert.ok(Number.isNaN(Model.num(undefined)))
    assert.ok(Number.isNaN(Model.num("")))
  })
})

describe("parseSnapshot", () => {
  it("reads the solaar flag and every device field", () => {
    assert.equal(snapshot.solaar, true)
    assert.equal(empty.solaar, false)
    assert.equal(Model.parseSnapshot("solaar\tyes").solaar, false)
    assert.equal(snapshot.devices.length, 4)
    assert.deepEqual(headset, {
      key: "/org/freedesktop/UPower/devices/headset_dev_AA",
      path: "/org/freedesktop/UPower/devices/headset_dev_AA",
      type: "headset",
      model: "WH-1000XM5",
      state: "charging",
      pct: 45,
      level: "",
      minutes: 90,
    })
  })

  it("orders the emptiest device first", () => {
    assert.deepEqual(snapshot.devices.map((d) => d.model), ["Pixel 9", "MX Keys", "WH-1000XM5", "Logitech MX Master 3"])
  })

  it("leaves a missing estimate unknown rather than zero", () => {
    assert.ok(Number.isNaN(mouse.minutes))
    assert.ok(Number.isNaN(keyboard.minutes))
  })

  it("skips malformed device rows and empty input", () => {
    assert.deepEqual(Model.parseSnapshot(""), { solaar: false, devices: [] })
    assert.deepEqual(Model.parseSnapshot(null), { solaar: false, devices: [] })
    assert.deepEqual(Model.parseSnapshot("device\ta\tb\tc").devices, [])
  })

  it("names a device with no type unknown", () => {
    assert.equal(Model.parseSnapshot("device\t/p\t\tX\t\t\t\t").devices[0].type, "unknown")
  })
})

describe("compareDevices", () => {
  it("puts less charge first and unknown charge last", () => {
    assert.ok(Model.compareDevices(phone, mouse) < 0)
    assert.ok(Model.compareDevices(mouse, phone) > 0)
    const unknown = { model: "A", pct: NaN }
    assert.ok(Model.compareDevices(mouse, unknown) < 0)
    assert.ok(Model.compareDevices(unknown, mouse) > 0)
  })

  it("falls back to the name when the charge ties", () => {
    assert.ok(Model.compareDevices({ model: "Alpha", pct: 50 }, { model: "Beta", pct: 50 }) < 0)
    assert.ok(Model.compareDevices({ model: "Beta", pct: 50 }, { model: "Alpha", pct: 50 }) > 0)
    assert.equal(Model.compareDevices({ model: "Same", pct: 50 }, { model: "Same", pct: 50 }), 0)
  })
})

describe("deviceName", () => {
  it("prefers the model and falls back to the path tail", () => {
    assert.equal(Model.deviceName(mouse), "Logitech MX Master 3")
    assert.equal(Model.deviceName({ path: "/org/freedesktop/UPower/devices/battery_hidpp_battery_0" }), "battery_hidpp_battery_0")
    assert.equal(Model.deviceName({ path: "" }), "")
    assert.equal(Model.deviceName(null), "")
  })
})

describe("typeLabel", () => {
  it("reads the type as words", () => {
    assert.equal(Model.typeLabel({ type: "gaming-input" }), "gaming input")
    assert.equal(Model.typeLabel(mouse), "mouse")
    assert.equal(Model.typeLabel({}), "unknown")
    assert.equal(Model.typeLabel(null), "unknown")
  })
})

describe("isCharging", () => {
  it("counts charging and waiting to charge, nothing else", () => {
    assert.equal(Model.isCharging(headset), true)
    assert.equal(Model.isCharging({ state: "pending-charge" }), true)
    assert.equal(Model.isCharging(mouse), false)
    assert.equal(Model.isCharging(phone), false)
    assert.equal(Model.isCharging(null), false)
  })
})

describe("isCoarse", () => {
  it("is true only for a level word", () => {
    assert.equal(Model.isCoarse(mouse), true)
    assert.equal(Model.isCoarse(keyboard), true)
    assert.equal(Model.isCoarse(headset), false)
    assert.equal(Model.isCoarse(phone), false)
    assert.equal(Model.isCoarse({ level: "unknown" }), false)
    assert.equal(Model.isCoarse(null), false)
  })
})

describe("chargePercent", () => {
  it("uses the percentage for a fine device and the level for a coarse one", () => {
    assert.equal(Model.chargePercent(headset), 45)
    assert.equal(Model.chargePercent(mouse), 100)
    assert.equal(Model.chargePercent(keyboard), 20)
    assert.equal(Model.chargePercent({ level: "critical", pct: 99 }), 5)
    assert.ok(Number.isNaN(Model.chargePercent({ level: "unknown", pct: "" })))
    assert.ok(Number.isNaN(Model.chargePercent(null)))
  })
})

describe("batteryGlyph", () => {
  it("steps through the ten glyphs and clamps the ends", () => {
    assert.equal(Model.batteryGlyph(0, false), Model.BATTERY_ICONS[0])
    assert.equal(Model.batteryGlyph(5, false), Model.BATTERY_ICONS[0])
    assert.equal(Model.batteryGlyph(15, false), Model.BATTERY_ICONS[1])
    assert.equal(Model.batteryGlyph(94, false), Model.BATTERY_ICONS[8])
    assert.equal(Model.batteryGlyph(95, false), Model.BATTERY_ICONS[9])
    assert.equal(Model.batteryGlyph(150, false), Model.BATTERY_ICONS[9])
  })

  it("switches to the charging set and marks an unknown charge", () => {
    assert.equal(Model.batteryGlyph(50, true), Model.CHARGING_ICONS[4])
    assert.equal(Model.batteryGlyph(NaN, false), Model.UNKNOWN_ICON)
    assert.equal(Model.batteryGlyph("x", true), Model.UNKNOWN_ICON)
  })
})

describe("typeIcon", () => {
  it("has a glyph per known type and a fallback", () => {
    assert.equal(Model.typeIcon(mouse), Model.TYPE_ICONS.mouse)
    assert.equal(Model.typeIcon({ type: "tablet" }), Model.ICON)
    assert.equal(Model.typeIcon(null), Model.ICON)
  })
})

describe("lowestDevice", () => {
  it("is the first device after sorting, or null", () => {
    assert.equal(Model.lowestDevice(snapshot), phone)
    assert.equal(Model.lowestDevice(empty), null)
    assert.equal(Model.lowestDevice(null), null)
  })
})

describe("lowDevices", () => {
  it("keeps devices at or below the threshold that are not charging", () => {
    assert.deepEqual(Model.lowDevices(snapshot, 20).map((d) => d.model), ["Pixel 9", "MX Keys"])
    assert.deepEqual(Model.lowDevices(snapshot, 10), [])
    assert.deepEqual(Model.lowDevices(snapshot, 50).map((d) => d.model), ["Pixel 9", "MX Keys"])
  })

  it("defaults the threshold and copes without a snapshot", () => {
    assert.equal(Model.lowDevices(snapshot, "abc").length, 2)
    assert.deepEqual(Model.lowDevices(null, 20), [])
  })

  it("ignores a device whose charge is unknown", () => {
    assert.deepEqual(Model.lowDevices(Model.parseSnapshot("device\t/p\tmouse\tM\tdischarging\t\tunknown\t"), 20), [])
  })
})

describe("chargingCount", () => {
  it("counts the devices on a charger", () => {
    assert.equal(Model.chargingCount(snapshot), 1)
    assert.equal(Model.chargingCount(empty), 0)
    assert.equal(Model.chargingCount(null), 0)
  })
})

describe("formatPercent", () => {
  it("rounds and marks an unknown or negative value", () => {
    assert.equal(Model.formatPercent(44.6), "45%")
    assert.equal(Model.formatPercent(-1), "—")
    assert.equal(Model.formatPercent(NaN), "—")
  })
})

describe("formatMinutes", () => {
  it("writes minutes under an hour and hours above", () => {
    assert.equal(Model.formatMinutes(0), "0m")
    assert.equal(Model.formatMinutes(45), "45m")
    assert.equal(Model.formatMinutes(60), "1h")
    assert.equal(Model.formatMinutes(90), "1h 30m")
    assert.equal(Model.formatMinutes(125.4), "2h 5m")
    assert.equal(Model.formatMinutes(NaN), "0m")
    assert.equal(Model.formatMinutes(-30), "0m")
  })
})

describe("levelLabel", () => {
  it("shows a coarse device's word and a fine device's percentage", () => {
    assert.equal(Model.levelLabel(mouse), "Full")
    assert.equal(Model.levelLabel(keyboard), "Low")
    assert.equal(Model.levelLabel(headset), "45%")
    assert.equal(Model.levelLabel({ level: "unknown", pct: "" }), "—")
    assert.equal(Model.levelLabel(null), "—")
  })
})

describe("stateLabel", () => {
  it("names every upower state and nothing for an unknown one", () => {
    assert.equal(Model.stateLabel({ state: "charging" }), "charging")
    assert.equal(Model.stateLabel({ state: "discharging" }), "discharging")
    assert.equal(Model.stateLabel({ state: "fully-charged" }), "fully charged")
    assert.equal(Model.stateLabel({ state: "pending-charge" }), "waiting to charge")
    assert.equal(Model.stateLabel({ state: "pending-discharge" }), "waiting to discharge")
    assert.equal(Model.stateLabel({ state: "empty" }), "empty")
    assert.equal(Model.stateLabel({ state: "unknown" }), "")
    assert.equal(Model.stateLabel(null), "")
  })
})

describe("deviceDetail", () => {
  it("joins type, state and the time estimate in the right direction", () => {
    assert.equal(Model.deviceDetail(headset), "headset · charging · 1h 30m to full")
    assert.equal(Model.deviceDetail(phone), "phone · discharging · 30m left")
    assert.equal(Model.deviceDetail(mouse), "mouse · fully charged")
    assert.equal(Model.deviceDetail({ type: "gaming-input", state: "unknown", minutes: 0 }), "gaming input")
    assert.equal(Model.deviceDetail(null), "")
  })
})

describe("barText", () => {
  it("shows the emptiest device's glyph, and its level only when wanted and horizontal", () => {
    assert.equal(Model.barText(snapshot, true, false), `${Model.BATTERY_ICONS[0]} 12%`)
    assert.equal(Model.barText(snapshot, false, false), Model.BATTERY_ICONS[0])
    assert.equal(Model.barText(snapshot, true, true), Model.BATTERY_ICONS[0])
    assert.equal(Model.barText(empty, true, false), Model.ICON)
    assert.equal(Model.barText(null, true, false), Model.ICON)
  })

  it("uses the charging glyph and the level word where they apply", () => {
    const charging = Model.parseSnapshot("device\t/p\theadset\tH\tcharging\t45\t\t")
    assert.equal(Model.barText(charging, true, false), `${Model.CHARGING_ICONS[4]} 45%`)
    const coarse = Model.parseSnapshot("device\t/p\tmouse\tM\tdischarging\t20\tlow\t")
    assert.equal(Model.barText(coarse, true, false), `${Model.BATTERY_ICONS[1]} Low`)
  })
})

describe("tooltip", () => {
  it("lists every device and counts the low ones", () => {
    assert.equal(Model.tooltip(snapshot, 20), "Peripherals · Pixel 9 12% · MX Keys Low · WH-1000XM5 45% charging · Logitech MX Master 3 Full · 2 low")
    assert.equal(Model.tooltip(snapshot, 5), "Peripherals · Pixel 9 12% · MX Keys Low · WH-1000XM5 45% charging · Logitech MX Master 3 Full")
    assert.equal(Model.tooltip(empty, 20), "Peripherals · no wireless devices")
    assert.equal(Model.tooltip(null, 20), "Peripherals")
  })
})

describe("heroStatus", () => {
  it("counts devices, low ones and charging ones", () => {
    assert.equal(Model.heroStatus(snapshot, 20), "4 DEVICES · 2 LOW · 1 CHARGING")
    assert.equal(Model.heroStatus(snapshot, 5), "4 DEVICES · 1 CHARGING")
    assert.equal(Model.heroStatus(Model.parseSnapshot("device\t/p\tmouse\tM\tdischarging\t80\t\t"), 20), "1 DEVICE")
    assert.equal(Model.heroStatus(empty, 20), "NO WIRELESS DEVICES")
    assert.equal(Model.heroStatus(null, 20), "SCANNING")
  })
})

describe("peripherals.sh", () => {
  // A PATH holding nothing but what the script needs, so whatever the machine
  // running the tests happens to have installed (Solaar, here) cannot leak
  // into the answers. The script is run with `path`, not `bin`, for that.
  function hermeticBin(t) {
    const dir = tmpdir(t)
    for (const tool of ["awk", "cat", "cut", "date", "flock", "mkdir", "mktemp", "mv", "python3", "rm", "stat", "touch"]) {
      const real = process.env.PATH.split(":").map((d) => path.join(d, tool)).find((f) => fs.existsSync(f))
      fs.symlinkSync(real, path.join(dir, tool))
    }
    return dir
  }

  // A upower stand-in answering `-d` from the fixture; `--monitor` is never
  // reached by the script.
  function fakeUpower(dir, body = `[[ $1 == -d ]] || exit 2; cat "${fixturePath("upower-dump.txt")}"`) {
    fakeCommand(dir, "upower", body)
    return dir
  }

  // Solaar's library is real on this machine, so the default environment
  // points Python at a stand-in that is absent, and a test opts into the
  // fake one with a pairing table of its own.
  function env(dir, extra = {}) {
    // No bytecode caches next to the stand-in library, or they end up in the tree.
    return { XDG_RUNTIME_DIR: dir, PYTHONPATH: fixturePath("no_logitech_receiver"), PYTHONDONTWRITEBYTECODE: "1", ...extra }
  }

  function solaarEnv(dir, receivers, extra = {}) {
    return env(dir, { PYTHONPATH: fixturePath(""), FAKE_SOLAAR: JSON.stringify(receivers), ...extra })
  }

  const run = (dir, args = [], environment = env(dir)) => runScript("joamag.peripherals", "peripherals.sh", args, { path: dir, env: environment })
  const cache = (dir) => path.join(dir, "joamag-peripherals", "solaar.tsv")

  it("keeps the peripherals and drops the machine's own battery, mains and absent devices", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    const result = run(dir)
    assert.equal(result.status, 0)
    const parsed = Model.parseSnapshot(result.stdout)
    assert.deepEqual(parsed.devices.map((d) => d.model), ["Pixel 9", "MX Keys", "WH-1000XM5", "Logitech MX Master 3"])
    assert.ok(!result.stdout.includes("BAT0"))
    assert.ok(!result.stdout.includes("line_power"))
    assert.ok(!result.stdout.includes("DisplayDevice"))
    assert.ok(!result.stdout.includes("Xbox"))
  })

  it("carries the level word and the percentage upower says to ignore", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    const parsed = Model.parseSnapshot(run(dir).stdout)
    const [, keys, , master] = parsed.devices
    assert.equal(master.type, "mouse")
    assert.equal(master.state, "fully-charged")
    assert.equal(master.level, "full")
    assert.equal(master.pct, 100)
    assert.equal(keys.level, "low")
    assert.equal(keys.pct, 20)
  })

  it("converts the time estimates to minutes", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    const parsed = Model.parseSnapshot(run(dir).stdout)
    const [pixel, , sony] = parsed.devices
    assert.equal(sony.minutes, 90)
    assert.equal(pixel.minutes, 30)
    assert.equal(pixel.level, "none")
    assert.equal(pixel.pct, 12)
  })

  it("reports whether Solaar is installed", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    assert.match(run(dir).stdout, /^solaar\t0\n/)
    fakeCommand(dir, "solaar", "exit 0")
    assert.match(run(dir).stdout, /^solaar\t1\n/)
  })

  it("answers with just the Solaar line when upower is absent", (t) => {
    const dir = hermeticBin(t)
    const result = run(dir)
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "solaar\t0\n")
  })

  it("lists no devices when upower fails", (t) => {
    const dir = fakeUpower(hermeticBin(t), "echo 'Cannot connect to daemon' >&2; exit 1")
    const result = run(dir)
    assert.equal(result.stdout, "solaar\t0\n")
    assert.equal(Model.parseSnapshot(result.stdout).devices.length, 0)
  })

  // The pairing table of this very machine: the mouse on a Unifying receiver
  // that upower also sees, and a keyboard on a Bolt receiver it cannot.
  const RECEIVERS = [
    { name: "Unifying Receiver", devices: [
      { name: "MX Master 3 Wireless Mouse", kind: "mouse", serial: "F80F7B68", battery: { level: 100, next_level: 50, status: "DISCHARGING" } },
      { name: "MX Anywhere 3", kind: "mouse", serial: "4E0F978B", online: false },
    ] },
    { name: "Bolt Receiver", devices: [
      { name: "MX KEYS S", kind: "keyboard", serial: "E44AD6CB", online: false },
      { name: "MX Keys S", kind: "keyboard", serial: "E44AD6CB", battery: { level: 75, next_level: null, status: "DISCHARGING" } },
    ] },
  ]

  it("reads the receivers through Solaar's library into the cache", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    assert.equal(run(dir, ["solaar"], solaarEnv(dir, RECEIVERS)).status, 0)
    const lines = fs.readFileSync(cache(dir), "utf8").trim().split("\n")
    assert.deepEqual(lines, [
      "device\tsolaar:F80F7B68\tmouse\tMX Master 3 Wireless Mouse\tdischarging\t100\tfull\t\tF80F7B68",
      "device\tsolaar:E44AD6CB\tkeyboard\tMX Keys S\tdischarging\t75\t\t\tE44AD6CB",
    ])
  })

  it("merges the cache into the snapshot, upower winning a device both report", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    run(dir, ["solaar"], solaarEnv(dir, RECEIVERS))
    const parsed = Model.parseSnapshot(run(dir).stdout)
    assert.deepEqual(parsed.devices.map((d) => [d.model, d.path.startsWith("solaar:") ? "solaar" : "upower"]), [
      ["Pixel 9", "upower"],
      ["MX Keys", "upower"],
      ["WH-1000XM5", "upower"],
      ["MX Keys S", "solaar"],
      ["Logitech MX Master 3", "upower"],
    ])
    const keys = parsed.devices.find((d) => d.model === "MX Keys S")
    assert.equal(keys.type, "keyboard")
    assert.equal(keys.pct, 75)
    assert.equal(keys.state, "discharging")
  })

  it("maps every battery status and level the library can hand back", (t) => {
    const dir = hermeticBin(t)
    const receivers = [{ devices: [
      { name: "A", kind: "mouse", serial: "A1", battery: { level: "FULL", status: "FULL" } },
      { name: "B", kind: "mouse", serial: "B1", battery: { level: "GOOD", status: "RECHARGING" } },
      { name: "C", kind: "mouse", serial: "C1", battery: { level: "LOW", status: "SLOW_RECHARGE" } },
      { name: "D", kind: "mouse", serial: "D1", battery: { level: "CRITICAL", status: "ALMOST_FULL" } },
      { name: "E", kind: "mouse", serial: "E1", battery: { level: "EMPTY", status: "INVALID_BATTERY" } },
      { name: "F", kind: "keyboard", serial: "F1", battery: { level: 50, next_level: 20, status: "DISCHARGING" } },
      { name: "G", kind: "keyboard", serial: "G1", battery: { level: 20, next_level: 5, status: "DISCHARGING" } },
      { name: "H", kind: "keyboard", serial: "H1", battery: { level: 5, next_level: 0, status: "DISCHARGING" } },
      { name: "I", kind: "headset", serial: "I1", battery: { level: 42, next_level: null, status: null } },
    ] }]
    run(dir, ["solaar"], solaarEnv(dir, receivers))
    const rows = fs.readFileSync(cache(dir), "utf8").trim().split("\n").map((l) => l.split("\t"))
    assert.deepEqual(rows.map((r) => [r[3], r[4], r[5], r[6]]), [
      ["A", "fully-charged", "90", "full"],
      ["B", "charging", "50", "normal"],
      ["C", "charging", "20", "low"],
      ["D", "charging", "5", "critical"],
      ["E", "unknown", "0", "critical"],
      ["F", "discharging", "50", "normal"],
      ["G", "discharging", "20", "low"],
      ["H", "discharging", "5", "critical"],
      ["I", "unknown", "42", ""],
    ])
  })

  it("skips what cannot be read: offline devices, no battery, a device that errors, a receiver that will not open", (t) => {
    const dir = hermeticBin(t)
    const receivers = [
      { fail: true, devices: [{ name: "Ghost", kind: "mouse", serial: "G1", battery: { level: 50, status: "DISCHARGING" } }] },
      { devices: [
        { name: "Asleep", kind: "mouse", serial: "S1", online: false, battery: { level: 50, status: "DISCHARGING" } },
        { name: "Mute", kind: "mouse", serial: "M1", battery: null },
        { name: "Flaky", kind: "mouse", serial: "F1", battery: "raise" },
        { name: "Gone", kind: "mouse", serial: "O1", battery: { level: 50, status: "OFFLINE" } },
        { name: "Nameless serial", kind: "mouse", serial: "", battery: { level: 60, next_level: null, status: "DISCHARGING" } },
      ] },
    ]
    run(dir, ["solaar"], solaarEnv(dir, receivers))
    const rows = fs.readFileSync(cache(dir), "utf8").trim().split("\n")
    // Only the last one survives, keyed by its name for want of a serial.
    assert.deepEqual(rows, ["device\tsolaar:NAMELESSSERIAL\tmouse\tNameless serial\tdischarging\t60\t\t\tNAMELESSSERIAL"])
  })

  it("lets only one Solaar reading run at a time", async (t) => {
    const dir = hermeticBin(t)
    fs.mkdirSync(path.join(dir, "joamag-peripherals"))
    // Something else holds the lock, the way a reading still in progress does.
    // flock hands the lock to the sleep it runs, so releasing it means
    // taking down that whole process group, not just flock.
    const holder = spawn("flock", [path.join(dir, "joamag-peripherals", "solaar.lock"), "sleep", "30"], { stdio: "ignore", detached: true })
    const release = () => { try { process.kill(-holder.pid, "SIGTERM") } catch (e) { /* already gone */ } }
    t.after(release)
    await new Promise((resolve) => setTimeout(resolve, 200))
    assert.equal(run(dir, ["solaar"], solaarEnv(dir, RECEIVERS)).status, 0)
    assert.equal(fs.existsSync(cache(dir)), false)
    release()
    await new Promise((resolve) => holder.on("exit", resolve))
    run(dir, ["solaar"], solaarEnv(dir, RECEIVERS))
    assert.equal(fs.readFileSync(cache(dir), "utf8").trim().split("\n").length, 2)
  })

  it("lets only whole device lines through from the cache", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    fs.mkdirSync(path.join(dir, "joamag-peripherals"))
    // A cache torn by two writers: a tail of one line, a line short of a
    // column, and one good device.
    fs.writeFileSync(cache(dir), [
      "100\tfull\t\tF80F7B68",
      "device\tsolaar:X\tmouse\tShort\tdischarging\t50\t\t",
      "device\tsolaar:E44AD6CB\tkeyboard\tMX Keys S\tdischarging\t75\t\t\tE44AD6CB",
      "",
    ].join("\n"))
    const result = run(dir)
    const models = Model.parseSnapshot(result.stdout).devices.map((d) => d.model)
    assert.ok(models.includes("MX Keys S"))
    assert.ok(!models.includes("Short"))
    assert.ok(!/^100\t/m.test(result.stdout))
  })

  it("writes an empty cache when the library is not installed", (t) => {
    const dir = hermeticBin(t)
    assert.equal(run(dir, ["solaar"]).status, 0)
    assert.equal(fs.readFileSync(cache(dir), "utf8"), "")
  })

  it("asks for a fresh reading in the background only when the cache has aged out", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    const log = path.join(dir, "spawn.log")
    fakeCommand(dir, "solaar", "exit 0")
    fakeCommand(dir, "setsid", `printf '%s\\n' "setsid $*" >> "${log}"`)
    // No cache yet: one request, and the marker stops a second snapshot from
    // asking again straight away.
    run(dir, [], env(dir, { OMARCHY_PERIPHERALS_SOLAAR_TTL: "60" }))
    run(dir, [], env(dir, { OMARCHY_PERIPHERALS_SOLAAR_TTL: "60" }))
    const spawned = fs.readFileSync(log, "utf8").trim().split("\n")
    assert.equal(spawned.length, 1)
    assert.match(spawned[0], /peripherals\.sh solaar$/)
    // A fresh cache: no request at all.
    fs.mkdirSync(path.dirname(cache(dir)), { recursive: true })
    fs.writeFileSync(cache(dir), "")
    fs.rmSync(path.join(dir, "joamag-peripherals", "solaar.attempt"))
    run(dir, [], env(dir, { OMARCHY_PERIPHERALS_SOLAAR_TTL: "60" }))
    assert.equal(fs.readFileSync(log, "utf8").trim().split("\n").length, 1)
  })

  it("never asks Solaar for anything when it is not installed", (t) => {
    const dir = fakeUpower(hermeticBin(t))
    const log = path.join(dir, "spawn.log")
    fakeCommand(dir, "setsid", `printf '%s\\n' "setsid $*" >> "${log}"`)
    run(dir, [], env(dir, { OMARCHY_PERIPHERALS_SOLAAR_TTL: "0" }))
    assert.equal(fs.existsSync(log), false)
  })

  it("rejects a bad invocation", (t) => {
    const dir = hermeticBin(t)
    const result = run(dir, ["bogus"])
    assert.equal(result.status, 1)
    assert.match(result.stderr, /Usage: peripherals.sh/)
  })
})
