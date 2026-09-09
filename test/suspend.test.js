// Tests for joamag.suspend: Model.js in declaration order, then suspend.sh
// against a systemctl stand-in and a scratch state directory.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadModel, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.suspend")

const CONFIG = {
  version: 1,
  plugins: [
    { id: "joamag.docker" },
    null,
    "joamag.stocks",
    { id: "joamag.suspend", timeoutSec: 600, dryRun: true },
  ],
}

describe("DEFAULT_TIMEOUT_SECONDS", () => {
  it("is thirty minutes", () => {
    assert.equal(Model.DEFAULT_TIMEOUT_SECONDS, 1800)
  })
})

describe("pluginEntry", () => {
  it("finds the service entry among other plugin kinds", () => {
    assert.deepEqual(Model.pluginEntry(CONFIG, "joamag.suspend"), { id: "joamag.suspend", timeoutSec: 600, dryRun: true })
  })

  it("finds the entry in the bar layout when the widget is enabled, and prefers it", () => {
    const bar = { bar: { layout: { left: [], center: [null, "x"], right: [{ id: "omarchy.clock" }, { id: "joamag.suspend", timeoutSec: 900 }] } } }
    assert.deepEqual(Model.pluginEntry(bar, "joamag.suspend"), { id: "joamag.suspend", timeoutSec: 900 })
    const both = { ...bar, plugins: CONFIG.plugins }
    assert.equal(Model.pluginEntry(both, "joamag.suspend").timeoutSec, 900)
    assert.equal(Model.pluginEntry({ bar: { layout: "nope" }, plugins: CONFIG.plugins }, "joamag.suspend").timeoutSec, 600)
  })

  it("is null without a config, a plugins array or a matching id", () => {
    assert.equal(Model.pluginEntry(null, "joamag.suspend"), null)
    assert.equal(Model.pluginEntry({ plugins: "nope" }, "joamag.suspend"), null)
    assert.equal(Model.pluginEntry({ plugins: [] }, "joamag.suspend"), null)
    assert.equal(Model.pluginEntry(CONFIG, "joamag.missing"), null)
  })
})

describe("timeoutSeconds", () => {
  it("falls back without an entry or a value", () => {
    assert.equal(Model.timeoutSeconds(null, 1800), 1800)
    assert.equal(Model.timeoutSeconds({ id: "joamag.suspend" }, 1800), 1800)
    assert.equal(Model.timeoutSeconds({ timeoutSec: "" }, 1800), 1800)
  })

  it("reads whole seconds from numbers and numeric strings", () => {
    assert.equal(Model.timeoutSeconds({ timeoutSec: 600 }, 1800), 600)
    assert.equal(Model.timeoutSeconds({ timeoutSec: "900" }, 1800), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: 90.9 }, 1800), 90)
  })

  it("lets zero disarm and rejects negatives and garbage", () => {
    assert.equal(Model.timeoutSeconds({ timeoutSec: 0 }, 1800), 0)
    assert.equal(Model.timeoutSeconds({ timeoutSec: -5 }, 1800), 1800)
    assert.equal(Model.timeoutSeconds({ timeoutSec: "soon" }, 1800), 1800)
    assert.equal(Model.timeoutSeconds({ timeoutSec: Infinity }, 1800), 1800)
  })
})

describe("dryRun", () => {
  it("is only on for true or the string true", () => {
    assert.equal(Model.dryRun(null), false)
    assert.equal(Model.dryRun({}), false)
    assert.equal(Model.dryRun({ dryRun: true }), true)
    assert.equal(Model.dryRun({ dryRun: "true" }), true)
    assert.equal(Model.dryRun({ dryRun: 1 }), false)
    assert.equal(Model.dryRun({ dryRun: "yes" }), false)
  })
})

describe("parseResult", () => {
  it("splits a verdict line from suspend.sh", () => {
    assert.deepEqual(Model.parseResult("suspend\tidle\n", "", 0), { verdict: "suspend", reason: "idle" })
    assert.deepEqual(Model.parseResult("\nskip\tstay-awake\n", "", 0), { verdict: "skip", reason: "stay-awake" })
    assert.deepEqual(Model.parseResult("error\tsystemctl not found\n", "", 1), { verdict: "error", reason: "systemctl not found" })
  })

  it("turns anything else into an error with the first stderr line", () => {
    assert.deepEqual(Model.parseResult("", "bash: boom\nmore", 127), { verdict: "error", reason: "bash: boom" })
    assert.deepEqual(Model.parseResult("garbage\n", "", 2), { verdict: "error", reason: "suspend.sh exited 2" })
    assert.deepEqual(Model.parseResult("weird\tverdict", null, 0), { verdict: "error", reason: "suspend.sh exited 0" })
  })
})

describe("describeTimeout", () => {
  it("prefers hours, then minutes, then seconds", () => {
    assert.equal(Model.describeTimeout(0), "off")
    assert.equal(Model.describeTimeout(-1), "off")
    assert.equal(Model.describeTimeout(7200), "2 h")
    assert.equal(Model.describeTimeout(1800), "30 min")
    assert.equal(Model.describeTimeout(90), "90 s")
  })
})

describe("PRESETS", () => {
  it("offers the five choices the popup shows, never last", () => {
    assert.deepEqual(Model.PRESETS.map((p) => p.seconds), [900, 1800, 3600, 10800, 0])
    assert.equal(Model.PRESETS[4].label, "Never")
  })
})

describe("presetIndex", () => {
  it("finds a preset by its seconds and calls anything else custom", () => {
    assert.equal(Model.presetIndex(1800), 1)
    assert.equal(Model.presetIndex("3600"), 2)
    assert.equal(Model.presetIndex(0), 4)
    assert.equal(Model.presetIndex(2700), -1)
    assert.equal(Model.presetIndex(NaN), -1)
  })
})

describe("parseDuration", () => {
  it("reads minutes by default and the usual units", () => {
    assert.equal(Model.parseDuration("45"), 2700)
    assert.equal(Model.parseDuration("45m"), 2700)
    assert.equal(Model.parseDuration("45 min"), 2700)
    assert.equal(Model.parseDuration("1h"), 3600)
    assert.equal(Model.parseDuration("1.5 h"), 5400)
    assert.equal(Model.parseDuration("1,5h"), 5400)
    assert.equal(Model.parseDuration("2h30"), 9000)
    assert.equal(Model.parseDuration("2 hours 15 min"), 8100)
    assert.equal(Model.parseDuration("90s"), 90)
    assert.equal(Model.parseDuration(" 20 "), 1200)
  })

  it("switches off for zero and its words", () => {
    assert.equal(Model.parseDuration("0"), 0)
    assert.equal(Model.parseDuration("off"), 0)
    assert.equal(Model.parseDuration("Never"), 0)
    assert.equal(Model.parseDuration("none"), 0)
  })

  it("keeps a timeout between a minute and a day", () => {
    assert.equal(Model.parseDuration("30 sec"), 60)
    assert.equal(Model.parseDuration("48h"), 86400)
    assert.equal(Model.parseDuration("0.1"), 60)
  })

  it("rejects anything it cannot read", () => {
    for (const bad of ["", "   ", "abc", "-5", "1h2h", "5 days", "h", null, undefined]) {
      assert.ok(Number.isNaN(Model.parseDuration(bad)), `expected NaN for ${JSON.stringify(bad)}`)
    }
  })
})

describe("detectionSeconds", () => {
  it("keeps the detection window short enough that nothing pre-empts it", () => {
    // The screensaver is the first thing that would reset the compositor's
    // idle clock, and it is never configured below a minute in practice.
    assert.equal(Model.detectionSeconds(1800), 60)
    assert.equal(Model.detectionSeconds(3600), 60)
    assert.equal(Model.detectionSeconds(90), 60)
  })

  it("never asks for a longer window than the timeout itself", () => {
    assert.equal(Model.detectionSeconds(30), 30)
    assert.equal(Model.detectionSeconds(5), 5)
    assert.equal(Model.detectionSeconds(90.9), 60)
  })

  it("floors the window and falls back for a value that is not a timeout", () => {
    assert.equal(Model.detectionSeconds(1), Model.DETECTION_FLOOR_SECONDS)
    assert.equal(Model.detectionSeconds(0), 60)
    assert.equal(Model.detectionSeconds(-5), 60)
    assert.equal(Model.detectionSeconds("soon"), 60)
    assert.equal(Model.detectionSeconds(undefined), 60)
  })
})

describe("awaySeconds", () => {
  const now = 1_800_000_000_000

  it("counts whole seconds since the absence began", () => {
    assert.equal(Model.awaySeconds(now - 90_000, now), 90)
    assert.equal(Model.awaySeconds(now - 1_500, now), 1)
    assert.equal(Model.awaySeconds(now, now), 0)
  })

  it("is zero when nobody is away, or the clock disagrees", () => {
    assert.equal(Model.awaySeconds(0, now), 0)
    assert.equal(Model.awaySeconds(-1, now), 0)
    assert.equal(Model.awaySeconds(now + 5_000, now), 0)
    assert.equal(Model.awaySeconds("x", now), 0)
    assert.equal(Model.awaySeconds(now, "x"), 0)
  })
})

describe("mayAttempt", () => {
  const now = 1_800_000_000_000

  it("allows the first attempt of an absence", () => {
    assert.equal(Model.mayAttempt(false, 0, now), true)
    assert.equal(Model.mayAttempt(false, now + 1000, now), true)
  })

  it("holds off after an attempt until the retry falls due", () => {
    assert.equal(Model.mayAttempt(true, 0, now), false)
    assert.equal(Model.mayAttempt(true, now + 1000, now), false)
    assert.equal(Model.mayAttempt(true, now, now), true)
    assert.equal(Model.mayAttempt(true, now - 1000, now), true)
  })

  it("never retries on a nonsense retry time", () => {
    assert.equal(Model.mayAttempt(true, -1, now), false)
    assert.equal(Model.mayAttempt(true, "soon", now), false)
    assert.equal(Model.mayAttempt(true, now - 1000, "x"), false)
  })
})

describe("isDue", () => {
  const now = 1_800_000_000_000

  it("is due once the absence has lasted the whole timeout", () => {
    assert.equal(Model.isDue(now - 1_800_000, now, 1800), true)
    assert.equal(Model.isDue(now - 1_799_000, now, 1800), false)
    assert.equal(Model.isDue(now - 60_000, now, 60), true)
  })

  it("is never due while disarmed or with nobody away", () => {
    assert.equal(Model.isDue(now - 1_800_000, now, 0), false)
    assert.equal(Model.isDue(now - 1_800_000, now, -1), false)
    assert.equal(Model.isDue(0, now, 1800), false)
    assert.equal(Model.isDue(now - 1_800_000, now, "soon"), false)
  })
})

describe("shortTimeout", () => {
  it("is what fits in a bar", () => {
    assert.equal(Model.shortTimeout(0), "off")
    assert.equal(Model.shortTimeout(-1), "off")
    assert.equal(Model.shortTimeout(45), "45s")
    assert.equal(Model.shortTimeout(900), "15m")
    assert.equal(Model.shortTimeout(3600), "1h")
    assert.equal(Model.shortTimeout(5400), "1h 30m")
    assert.equal(Model.shortTimeout(10800), "3h")
    assert.equal(Model.shortTimeout("1800"), "30m")
  })
})

describe("barIcon", () => {
  it("is the sleeping face, crossed out when off", () => {
    assert.equal(Model.barIcon(true), Model.ICON_ARMED)
    assert.equal(Model.barIcon(false), Model.ICON_OFF)
    assert.notEqual(Model.ICON_ARMED, Model.ICON_OFF)
  })

  it("is crossed out while stay awake holds the machine", () => {
    assert.equal(Model.barIcon(true, true), Model.ICON_OFF)
    assert.equal(Model.barIcon(true, false), Model.ICON_ARMED)
    assert.equal(Model.barIcon(false, true), Model.ICON_OFF)
  })
})

describe("barText", () => {
  it("adds the timeout only when armed, wanted and horizontal", () => {
    assert.equal(Model.barText(true, 1800, true, false), `${Model.ICON_ARMED} 30m`)
    assert.equal(Model.barText(true, 1800, false, false), Model.ICON_ARMED)
    assert.equal(Model.barText(true, 1800, true, true), Model.ICON_ARMED)
    assert.equal(Model.barText(false, 0, true, false), Model.ICON_OFF)
  })

  it("drops the timeout while stay awake holds the machine", () => {
    assert.equal(Model.barText(true, 1800, true, false, true), Model.ICON_OFF)
    assert.equal(Model.barText(true, 1800, true, false, false), `${Model.ICON_ARMED} 30m`)
  })
})

describe("verdictLabel", () => {
  it("puts the last outcome into words", () => {
    assert.equal(Model.verdictLabel("suspend", "idle"), "last time it slept")
    assert.equal(Model.verdictLabel("skip", "stay-awake"), "skipped, stay awake is on")
    assert.equal(Model.verdictLabel("skip", "suspend-off"), "skipped, suspend is off in the menu")
    assert.equal(Model.verdictLabel("skip", "inhibited"), "skipped, something is holding sleep")
    assert.equal(Model.verdictLabel("skip", "other-users"), "skipped, another user is logged in")
    assert.equal(Model.verdictLabel("skip", "odd"), "skipped, odd")
    assert.equal(Model.verdictLabel("skip", ""), "skipped")
    assert.equal(Model.verdictLabel("error", "boom"), "failed: boom")
    assert.equal(Model.verdictLabel("error", ""), "failed")
    assert.equal(Model.verdictLabel("", ""), "")
  })
})

describe("heroStatus", () => {
  it("says when it sleeps, or that it never will, and what is holding it", () => {
    assert.equal(Model.heroStatus(true, 1800, false, false), "SLEEPS AFTER 30 MIN")
    assert.equal(Model.heroStatus(true, 3600, true, false), "SLEEPS AFTER 1 H · IDLE NOW")
    assert.equal(Model.heroStatus(true, 1800, true, true), "SLEEPS AFTER 30 MIN · STAY AWAKE ON")
    assert.equal(Model.heroStatus(false, 0, true, false), "NEVER SLEEPS")
  })
})

describe("tooltip", () => {
  it("summarises the timeout and the last outcome", () => {
    assert.equal(Model.tooltip(true, 1800, "", ""), "Suspend · Sleeps after 30 min idle")
    assert.equal(Model.tooltip(true, 900, "skip", "inhibited"), "Suspend · Sleeps after 15 min idle · skipped, something is holding sleep")
    assert.equal(Model.tooltip(false, 0, "suspend", "idle"), "Suspend · Auto sleep is off · last time it slept")
  })

  it("says when stay awake is what is holding the machine", () => {
    assert.equal(Model.tooltip(true, 1800, "", "", true), "Suspend · Held awake by stay awake")
    assert.equal(Model.tooltip(false, 0, "", "", true), "Suspend · Auto sleep is off")
  })
})

// suspend.sh with a scratch OMARCHY_STATE_DIR and a systemctl stand-in that
// records its arguments to $FAKE_LOG.
describe("suspend.sh", () => {
  function setup(t, { stayAwake = false, suspendOff = false, systemctl = "exit 0" } = {}) {
    const dir = tmpdir(t)
    const state = path.join(dir, "state")
    fs.mkdirSync(path.join(state, "indicators"), { recursive: true })
    fs.mkdirSync(path.join(state, "toggles"), { recursive: true })
    if (stayAwake) fs.writeFileSync(path.join(state, "indicators", "stay-awake"), "")
    if (suspendOff) fs.writeFileSync(path.join(state, "toggles", "suspend-off"), "")
    const bin = path.join(dir, "bin")
    fs.mkdirSync(bin)
    const log = path.join(dir, "systemctl.log")
    fakeCommand(bin, "systemctl", `echo "$*" >> "$FAKE_LOG"\n${systemctl}`)
    const run = (args = []) => runScript("joamag.suspend", "suspend.sh", args, { bin, env: { OMARCHY_STATE_DIR: state, FAKE_LOG: log } })
    const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean) : [])
    return { run, calls }
  }

  it("suspends through systemctl with the inhibitor check on", (t) => {
    const { run, calls } = setup(t)
    const result = run()
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "suspend\tidle\n")
    assert.deepEqual(calls(), ["suspend --check-inhibitors=yes"])
  })

  it("skips while Stay Awake is on and never calls systemctl", (t) => {
    const { run, calls } = setup(t, { stayAwake: true })
    const result = run()
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "skip\tstay-awake\n")
    assert.deepEqual(calls(), [])
  })

  it("skips while suspend is toggled off in the system menu", (t) => {
    const { run, calls } = setup(t, { suspendOff: true })
    assert.equal(run().stdout, "skip\tsuspend-off\n")
    assert.deepEqual(calls(), [])
  })

  it("decides without acting in dry-run mode", (t) => {
    const { run, calls } = setup(t)
    const result = run(["--dry-run"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "suspend\tidle\n")
    assert.deepEqual(calls(), [])
  })

  it("reports a block inhibitor as a skip", (t) => {
    const { run } = setup(t, { systemctl: `echo 'Operation inhibited by "Backup" (PID 4242 "borg", user joamag), reason is "Nightly backup".' >&2; exit 1` })
    const result = run()
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "skip\tinhibited\n")
  })

  it("reports other logged-in users as a skip", (t) => {
    const { run } = setup(t, { systemctl: "echo 'User guest is logged in on seat1.' >&2; exit 1" })
    assert.equal(run().stdout, "skip\tother-users\n")
  })

  it("surfaces any other systemctl failure as an error", (t) => {
    const { run } = setup(t, { systemctl: "echo 'Failed to suspend system via logind: Access denied' >&2; exit 1" })
    const result = run()
    assert.equal(result.status, 1)
    assert.equal(result.stdout, "error\tFailed to suspend system via logind: Access denied\n")
  })

  it("describes a silent systemctl failure by its exit status", (t) => {
    const { run } = setup(t, { systemctl: "exit 3" })
    const result = run()
    assert.equal(result.status, 1)
    assert.equal(result.stdout, "error\tsystemctl suspend exited 3\n")
  })

  it("errors when systemctl is not on PATH", (t) => {
    const dir = tmpdir(t)
    const result = runScript("joamag.suspend", "suspend.sh", [], { path: dir, env: { OMARCHY_STATE_DIR: path.join(dir, "state") } })
    assert.equal(result.status, 1)
    assert.equal(result.stdout, "error\tsystemctl not found\n")
  })
})
