// Tests for joamag.screenoff: Model.js in declaration order, then screenoff.sh
// against stand-ins for the Omarchy commands and a scratch state directory.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { loadModel, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.screenoff")

const CONFIG = {
  version: 1,
  bar: { layout: { left: [], center: [], right: [{ id: "joamag.screenoff", timeoutSec: 60 }] } },
  plugins: [
    { id: "joamag.suspend" },
    null,
    "joamag.stocks",
    { id: "joamag.screenoff", timeoutSec: 600, dryRun: true },
  ],
}

describe("DEFAULT_TIMEOUT_SECONDS", () => {
  it("is fifteen minutes", () => {
    assert.equal(Model.DEFAULT_TIMEOUT_SECONDS, 900)
  })
})

describe("MAX_TIMEOUT_SECONDS", () => {
  it("is a day", () => {
    assert.equal(Model.MAX_TIMEOUT_SECONDS, 86400)
  })
})

describe("FORCED_SETTLE_SECONDS", () => {
  it("is a second, enough to let go of the mouse", () => {
    assert.equal(Model.FORCED_SETTLE_SECONDS, 1)
  })
})

describe("parseConfig", () => {
  it("reads shell.json as the shell writes it", () => {
    assert.deepEqual(Model.parseConfig(JSON.stringify(CONFIG, null, 2) + "\n"), CONFIG)
  })

  it("is null for a file that is missing, empty or still being written", () => {
    assert.equal(Model.parseConfig(undefined), null)
    assert.equal(Model.parseConfig(""), null)
    assert.equal(Model.parseConfig("  \n"), null)
    assert.equal(Model.parseConfig('{ "version": 1, "plugins": ['), null)
  })

  it("is null for JSON that is not an object", () => {
    assert.equal(Model.parseConfig("null"), null)
    assert.equal(Model.parseConfig("42"), null)
    assert.equal(Model.parseConfig('"shell"'), null)
    assert.equal(Model.parseConfig("[]"), null)
  })
})

describe("pluginEntry", () => {
  it("finds the service entry among other plugins, never the bar layout", () => {
    assert.deepEqual(Model.pluginEntry(CONFIG, "joamag.screenoff"), { id: "joamag.screenoff", timeoutSec: 600, dryRun: true })
  })

  it("is null without a config, a plugins array or a matching id", () => {
    assert.equal(Model.pluginEntry(null, "joamag.screenoff"), null)
    assert.equal(Model.pluginEntry("nope", "joamag.screenoff"), null)
    assert.equal(Model.pluginEntry({ plugins: "nope" }, "joamag.screenoff"), null)
    assert.equal(Model.pluginEntry({ plugins: [] }, "joamag.screenoff"), null)
    assert.equal(Model.pluginEntry({ plugins: [{ timeoutSec: 60 }] }, "joamag.screenoff"), null)
    assert.equal(Model.pluginEntry(CONFIG, "joamag.missing"), null)
  })
})

describe("timeoutSeconds", () => {
  it("falls back without an entry or a value", () => {
    assert.equal(Model.timeoutSeconds(null, 900), 900)
    assert.equal(Model.timeoutSeconds({ id: "joamag.screenoff" }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: null }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: "" }, 900), 900)
  })

  it("reads whole seconds from numbers and numeric strings", () => {
    assert.equal(Model.timeoutSeconds({ timeoutSec: 600 }, 900), 600)
    assert.equal(Model.timeoutSeconds({ timeoutSec: "1800" }, 900), 1800)
    assert.equal(Model.timeoutSeconds({ timeoutSec: 90.9 }, 900), 90)
  })

  it("lets zero disarm and rejects negatives and garbage", () => {
    assert.equal(Model.timeoutSeconds({ timeoutSec: 0 }, 900), 0)
    assert.equal(Model.timeoutSeconds({ timeoutSec: -5 }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: "soon" }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: Infinity }, 900), 900)
  })

  it("waits a day at the most", () => {
    assert.equal(Model.timeoutSeconds({ timeoutSec: 86400 }, 900), 86400)
    assert.equal(Model.timeoutSeconds({ timeoutSec: 604800 }, 900), 86400)
  })

  it("takes only a number or the text of one for a timeout", () => {
    // Number() reads true as one second and a blank string or an empty list
    // as zero, which would blank at once or disarm without a word.
    assert.equal(Model.timeoutSeconds({ timeoutSec: true }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: false }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: [] }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: [30] }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: {} }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: "   " }, 900), 900)
    assert.equal(Model.timeoutSeconds({ timeoutSec: " 600 " }, 900), 600)
    assert.equal(Model.timeoutSeconds({ timeoutSec: "0" }, 900), 0)
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

describe("respectInhibitors", () => {
  it("is only off for false or the string false", () => {
    assert.equal(Model.respectInhibitors(null), true)
    assert.equal(Model.respectInhibitors({}), true)
    assert.equal(Model.respectInhibitors({ respectInhibitors: false }), false)
    assert.equal(Model.respectInhibitors({ respectInhibitors: "false" }), false)
    assert.equal(Model.respectInhibitors({ respectInhibitors: true }), true)
    assert.equal(Model.respectInhibitors({ respectInhibitors: 0 }), true)
    assert.equal(Model.respectInhibitors({ respectInhibitors: "no" }), true)
    assert.equal(Model.respectInhibitors({ respectInhibitors: null }), true)
  })
})

describe("parseStayAwake", () => {
  const ON = '{"enabled":false,"stayAwake":true,"idle":false,"inIdleCycle":false,"screensaver":150,"lock":300}'
  const OFF = '{"enabled":true,"stayAwake":false,"idle":false,"inIdleCycle":false,"screensaver":150,"lock":300}'

  it("reads Stay Awake out of the idle service's answer", () => {
    assert.deepEqual(Model.parseStayAwake(`${ON}\n`), { known: true, stayAwake: true, screensaverCycle: false })
    assert.deepEqual(Model.parseStayAwake(`\n  ${OFF}  \n`), { known: true, stayAwake: false, screensaverCycle: false })
  })

  it("takes it for off when the answer does not say it is on", () => {
    assert.deepEqual(Model.parseStayAwake('{"idle":false}'), { known: true, stayAwake: false, screensaverCycle: false })
    assert.deepEqual(Model.parseStayAwake('{"stayAwake":"true"}'), { known: true, stayAwake: false, screensaverCycle: false })
    assert.deepEqual(Model.parseStayAwake('{"stayAwake":1}'), { known: true, stayAwake: false, screensaverCycle: false })
  })

  it("reads an idle cycle that has started the screensaver", () => {
    const CYCLE = '{"enabled":true,"stayAwake":false,"idle":true,"inIdleCycle":true,"screensaverStarted":true,"screensaverWindows":1}'
    assert.deepEqual(Model.parseStayAwake(CYCLE), { known: true, stayAwake: false, screensaverCycle: true })
  })

  it("does not take a cycle that has not reached the screensaver, or a screensaver outside one, for it", () => {
    assert.equal(Model.parseStayAwake('{"inIdleCycle":true,"screensaverStarted":false}').screensaverCycle, false)
    assert.equal(Model.parseStayAwake('{"inIdleCycle":false,"screensaverStarted":true}').screensaverCycle, false)
    assert.equal(Model.parseStayAwake('{"inIdleCycle":"true","screensaverStarted":1}').screensaverCycle, false)
  })

  it("knows nothing when the answer is missing or unreadable", () => {
    assert.deepEqual(Model.parseStayAwake(""), { known: false, stayAwake: false, screensaverCycle: false })
    assert.equal(Model.parseStayAwake("Target not found").known, false)
    assert.equal(Model.parseStayAwake("null\n[true]\ntrue").known, false)
    assert.equal(Model.parseStayAwake(undefined).known, false)
  })

  it("ignores a torn line but keeps the whole one beside it", () => {
    assert.deepEqual(Model.parseStayAwake(`{"stayAwake":tr\n${ON}`), { known: true, stayAwake: true, screensaverCycle: false })
    assert.deepEqual(Model.parseStayAwake('{"stayAwake":tr'), { known: false, stayAwake: false, screensaverCycle: false })
    assert.equal(Model.parseStayAwake('{"inIdleCycle":true,"screensaverStarted":tr').screensaverCycle, false)
  })
})

describe("nextAction", () => {
  it("turns the displays off once the user is idle while it is watching", () => {
    assert.equal(Model.nextAction(true, true, false), "off")
  })

  it("turns them back on when the user returns", () => {
    assert.equal(Model.nextAction(true, false, true), "on")
  })

  it("turns them back on when it stops watching, idle or not", () => {
    assert.equal(Model.nextAction(false, true, true), "on")
    assert.equal(Model.nextAction(false, false, true), "on")
  })

  it("does nothing when the displays are already what they should be", () => {
    assert.equal(Model.nextAction(true, true, true), "")
    assert.equal(Model.nextAction(true, false, false), "")
    assert.equal(Model.nextAction(false, true, false), "")
    assert.equal(Model.nextAction(false, false, false), "")
    assert.equal(Model.nextAction(undefined, undefined, undefined), "")
  })

  it("turns the displays off for a screen off asked for by hand, watching or not", () => {
    assert.equal(Model.nextAction(false, false, false, true), "off")
    assert.equal(Model.nextAction(true, false, false, true), "off")
  })

  it("keeps them off while the hands stay away, even once it stops watching", () => {
    assert.equal(Model.nextAction(false, false, true, true), "")
    assert.equal(Model.nextAction(false, true, true, true), "")
  })

  it("turns them back on when the user returns from a screen off asked for by hand", () => {
    assert.equal(Model.nextAction(false, false, true, false), "on")
  })

  it("keeps a timed blank while the user is still away, with or without one asked for", () => {
    assert.equal(Model.nextAction(true, true, true, false), "")
    assert.equal(Model.nextAction(true, true, false, false), "off")
  })
})

describe("scriptAction", () => {
  it("turns the displays off after the timeout, or on request whatever the last blank was", () => {
    assert.equal(Model.scriptAction(true, false, ""), "off")
    assert.equal(Model.scriptAction(true, true, ""), "now")
    assert.equal(Model.scriptAction(true, true, "displays"), "now")
  })

  it("brings the keyboard backlight back with the displays unless the blank left it alone", () => {
    assert.equal(Model.scriptAction(false, false, "idle"), "on")
    assert.equal(Model.scriptAction(false, false, "forced"), "on")
    assert.equal(Model.scriptAction(false, false, "displays"), "displays-on")
    assert.equal(Model.scriptAction(false, true, "displays"), "displays-on")
  })

  it("takes a state it was never told about for a timed blank and a full wake", () => {
    assert.equal(Model.scriptAction(undefined, undefined, undefined), "on")
    assert.equal(Model.scriptAction(true, undefined, undefined), "off")
  })
})

describe("runsDry", () => {
  it("goes by the setting when the displays are turned off", () => {
    assert.equal(Model.runsDry("off", false, false), false)
    assert.equal(Model.runsDry("off", true, false), true)
    assert.equal(Model.runsDry("off", false, true), false)
    assert.equal(Model.runsDry("off", true, true), true)
  })

  it("turns them back on the way they went off, whatever the setting is by then", () => {
    assert.equal(Model.runsDry("on", true, false), false)
    assert.equal(Model.runsDry("on", false, false), false)
    assert.equal(Model.runsDry("on", false, true), true)
    assert.equal(Model.runsDry("on", true, true), true)
  })

  it("goes by the setting for a blank on request, and by the blank for a wake of the displays alone", () => {
    assert.equal(Model.runsDry("now", true, false), true)
    assert.equal(Model.runsDry("now", false, true), false)
    assert.equal(Model.runsDry("displays-on", true, false), false)
    assert.equal(Model.runsDry("displays-on", false, true), true)
  })

  it("takes a setting or a blank it was never told about for a real one", () => {
    assert.equal(Model.runsDry("off", undefined, true), false)
    assert.equal(Model.runsDry("on", true, undefined), false)
    assert.equal(Model.runsDry("on", undefined, undefined), false)
  })
})

describe("parseResult", () => {
  it("splits a verdict line from screenoff.sh", () => {
    assert.deepEqual(Model.parseResult("off\tidle\n", "", 0), { verdict: "off", reason: "idle" })
    assert.deepEqual(Model.parseResult("on\tactivity\n", "", 0), { verdict: "on", reason: "activity" })
    assert.deepEqual(Model.parseResult("skip\tallow-idle\n", "", 0), { verdict: "skip", reason: "allow-idle" })
    assert.deepEqual(Model.parseResult("error\tomarchy-system-wake not found\n", "", 1), { verdict: "error", reason: "omarchy-system-wake not found" })
  })

  it("turns anything else into an error with the first stderr line", () => {
    assert.deepEqual(Model.parseResult("", "\nbash: screenoff.sh: Permission denied\nmore\n", 126), { verdict: "error", reason: "bash: screenoff.sh: Permission denied" })
    assert.deepEqual(Model.parseResult("maybe\tlater\n", "", 0), { verdict: "error", reason: "screenoff.sh exited 0" })
    assert.deepEqual(Model.parseResult("off", "", 2), { verdict: "error", reason: "screenoff.sh exited 2" })
    assert.deepEqual(Model.parseResult(undefined, undefined, 127), { verdict: "error", reason: "screenoff.sh exited 127" })
    assert.deepEqual(Model.parseResult("", "Usage: screenoff.sh off|on [--dry-run]\n", 1), { verdict: "error", reason: "Usage: screenoff.sh off|on [--dry-run]" })
    assert.deepEqual(Model.parseResult("error\t\n", "", 1), { verdict: "error", reason: "screenoff.sh exited 1" })
  })
})

describe("firstLine", () => {
  it("is the first line with anything on it, trimmed", () => {
    assert.equal(Model.firstLine("\n\n  one  \ntwo\n"), "one")
    assert.equal(Model.firstLine("only"), "only")
  })

  it("is empty when there is nothing to read", () => {
    assert.equal(Model.firstLine(""), "")
    assert.equal(Model.firstLine(" \n \n"), "")
    assert.equal(Model.firstLine(null), "")
  })
})

describe("displaysOff", () => {
  it("takes the script's word for it", () => {
    assert.equal(Model.displaysOff("off", false), true)
    assert.equal(Model.displaysOff("on", true), false)
  })

  it("leaves the displays as they were after a skip or an error", () => {
    assert.equal(Model.displaysOff("skip", false), false)
    assert.equal(Model.displaysOff("error", false), false)
    assert.equal(Model.displaysOff("error", true), true)
    assert.equal(Model.displaysOff("", undefined), false)
  })
})

describe("blankReason", () => {
  it("takes the reason of the blank the script reported", () => {
    assert.equal(Model.blankReason("off", "idle", ""), "idle")
    assert.equal(Model.blankReason("off", "forced", "idle"), "forced")
    assert.equal(Model.blankReason("off", "displays", ""), "displays")
  })

  it("forgets it once the displays are back, however they came back", () => {
    assert.equal(Model.blankReason("on", "activity", "forced"), "")
    assert.equal(Model.blankReason("on", "displays", "displays"), "")
  })

  it("leaves it as it was after a skip or an error, so a failed wake is tried again the same way", () => {
    assert.equal(Model.blankReason("skip", "allow-idle", "idle"), "idle")
    assert.equal(Model.blankReason("error", "omarchy-brightness-display on exited 1", "displays"), "displays")
    assert.equal(Model.blankReason("error", "boom", undefined), "")
    assert.equal(Model.blankReason("off", undefined, "idle"), "")
  })
})

describe("blankByHand", () => {
  it("is true for a blank asked for, with or without the keyboard backlight", () => {
    assert.equal(Model.blankByHand("forced"), true)
    assert.equal(Model.blankByHand("displays"), true)
  })

  it("is false for the timed blank and for no blank at all", () => {
    assert.equal(Model.blankByHand("idle"), false)
    assert.equal(Model.blankByHand(""), false)
    assert.equal(Model.blankByHand(undefined), false)
  })
})

describe("describeTimeout", () => {
  it("prefers hours, then minutes, then seconds", () => {
    assert.equal(Model.describeTimeout(3600), "1 h")
    assert.equal(Model.describeTimeout(900), "15 min")
    assert.equal(Model.describeTimeout(5400), "90 min")
    assert.equal(Model.describeTimeout(90), "90 s")
  })

  it("is off when there is no timeout", () => {
    assert.equal(Model.describeTimeout(0), "off")
    assert.equal(Model.describeTimeout(-1), "off")
    assert.equal(Model.describeTimeout(undefined), "off")
  })
})

// screenoff.sh with a scratch OMARCHY_STATE_DIR and stand-ins for the Omarchy
// commands that record how they were called to $FAKE_LOG. A command set to
// null is left out, as on a machine that lacks it, and PATH then holds the
// stand-ins alone so the real one cannot answer in its place and blank the
// displays of whoever is running the tests.
describe("screenoff.sh", () => {
  const COMMANDS = ["omarchy-brightness-keyboard", "omarchy-brightness-display", "omarchy-system-wake", "omarchy-hyprland-monitor-clamshell"]

  function setup(t, { stayAwake = true, ...bodies } = {}) {
    const dir = tmpdir(t)
    const state = path.join(dir, "state")
    fs.mkdirSync(path.join(state, "indicators"), { recursive: true })
    if (stayAwake) fs.writeFileSync(path.join(state, "indicators", "stay-awake"), "")
    const bin = path.join(dir, "bin")
    fs.mkdirSync(bin)
    const log = path.join(dir, "commands.log")
    for (const name of COMMANDS) {
      if (bodies[name] === null) continue
      fakeCommand(bin, name, `echo "${name} $*" >> "$FAKE_LOG"\n${bodies[name] || "exit 0"}`)
    }
    const lacking = COMMANDS.some((name) => bodies[name] === null)
    const run = (args) => runScript("joamag.screenoff", "screenoff.sh", args, { path: lacking ? bin : `${bin}:/usr/bin:/bin`, env: { OMARCHY_STATE_DIR: state, FAKE_LOG: log } })
    const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean) : [])
    return { run, calls }
  }

  it("turns the displays and then the keyboard backlight off", (t) => {
    const { run, calls } = setup(t)
    const result = run(["off"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "off\tidle\n")
    assert.deepEqual(calls(), ["omarchy-brightness-display off", "omarchy-brightness-keyboard off"])
  })

  it("leaves the displays alone once Stay Awake has been switched off", (t) => {
    const { run, calls } = setup(t, { stayAwake: false })
    const result = run(["off"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "skip\tallow-idle\n")
    assert.deepEqual(calls(), [])
  })

  it("turns the displays and the keyboard backlight off on request while Stay Awake is on", (t) => {
    const { run, calls } = setup(t)
    const result = run(["now"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "off\tforced\n")
    assert.deepEqual(calls(), ["omarchy-brightness-display off", "omarchy-brightness-keyboard off"])
  })

  it("turns the displays alone off on request while Stay Awake is off, the keyboard backlight left to the lock", (t) => {
    const { run, calls } = setup(t, { stayAwake: false })
    const result = run(["now"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "off\tdisplays\n")
    assert.deepEqual(calls(), ["omarchy-brightness-display off"])
  })

  it("turns the displays alone off on request on a machine with no state directory", (t) => {
    const dir = tmpdir(t)
    const bin = path.join(dir, "bin")
    fs.mkdirSync(bin)
    for (const name of COMMANDS) fakeCommand(bin, name, "exit 0")
    const result = runScript("joamag.screenoff", "screenoff.sh", ["now"], { bin, env: { OMARCHY_STATE_DIR: path.join(dir, "missing") } })
    assert.equal(result.stdout, "off\tdisplays\n")
  })

  it("takes a machine with no state directory for one that is not held awake", (t) => {
    const dir = tmpdir(t)
    const bin = path.join(dir, "bin")
    fs.mkdirSync(bin)
    for (const name of COMMANDS) fakeCommand(bin, name, `echo "${name} $*" >> "$FAKE_LOG"`)
    const log = path.join(dir, "commands.log")
    const result = runScript("joamag.screenoff", "screenoff.sh", ["off"], { bin, env: { OMARCHY_STATE_DIR: path.join(dir, "missing"), FAKE_LOG: log } })
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "skip\tallow-idle\n")
    assert.equal(fs.existsSync(log), false)
  })

  it("goes by the state under the home directory when no other is named", (t) => {
    const dir = tmpdir(t)
    const bin = path.join(dir, "bin")
    fs.mkdirSync(bin)
    for (const name of COMMANDS) fakeCommand(bin, name, "exit 0")
    const run = () => runScript("joamag.screenoff", "screenoff.sh", ["off"], { bin, env: { HOME: dir } })
    assert.equal(run().stdout, "skip\tallow-idle\n")
    const indicators = path.join(dir, ".local", "state", "omarchy", "indicators")
    fs.mkdirSync(indicators, { recursive: true })
    fs.writeFileSync(path.join(indicators, "stay-awake"), "")
    assert.equal(run().stdout, "off\tidle\n")
  })

  it("decides without acting in dry-run mode", (t) => {
    const { run, calls } = setup(t)
    assert.equal(run(["off", "--dry-run"]).stdout, "off\tidle\n")
    assert.equal(run(["now", "--dry-run"]).stdout, "off\tforced\n")
    assert.equal(run(["on", "--dry-run"]).stdout, "on\tactivity\n")
    assert.equal(run(["displays-on", "--dry-run"]).stdout, "on\tdisplays\n")
    assert.deepEqual(calls(), [])
    const idle = setup(t, { stayAwake: false })
    assert.equal(idle.run(["off", "--dry-run"]).stdout, "skip\tallow-idle\n")
    assert.equal(idle.run(["now", "--dry-run"]).stdout, "off\tdisplays\n")
    assert.deepEqual(idle.calls(), [])
  })

  it("needs none of the commands to decide in dry-run mode", (t) => {
    const { run } = setup(t, { "omarchy-brightness-keyboard": null, "omarchy-brightness-display": null, "omarchy-system-wake": null, "omarchy-hyprland-monitor-clamshell": null })
    assert.equal(run(["off", "--dry-run"]).stdout, "off\tidle\n")
    assert.equal(run(["now", "--dry-run"]).stdout, "off\tforced\n")
    assert.equal(run(["on", "--dry-run"]).stdout, "on\tactivity\n")
    assert.equal(run(["displays-on", "--dry-run"]).stdout, "on\tdisplays\n")
  })

  it("keeps what the commands print out of its one verdict line", (t) => {
    const chatter = "echo 'brightness 0'; echo 'DPMS: ok' >&2; exit 0"
    const { run } = setup(t, { "omarchy-brightness-keyboard": chatter, "omarchy-brightness-display": chatter, "omarchy-system-wake": chatter, "omarchy-hyprland-monitor-clamshell": chatter })
    assert.equal(run(["off"]).stdout, "off\tidle\n")
    assert.equal(run(["on"]).stdout, "on\tactivity\n")
    assert.equal(run(["displays-on"]).stdout, "on\tdisplays\n")
  })

  it("turns the displays off even when the keyboard backlight will not dim", (t) => {
    const { run, calls } = setup(t, { "omarchy-brightness-keyboard": "echo 'no keyboard backlight' >&2; exit 1" })
    assert.equal(run(["off"]).stdout, "off\tidle\n")
    assert.deepEqual(calls(), ["omarchy-brightness-display off", "omarchy-brightness-keyboard off"])
  })

  it("turns the displays off on a machine with no keyboard backlight command", (t) => {
    const { run, calls } = setup(t, { "omarchy-brightness-keyboard": null })
    assert.equal(run(["off"]).stdout, "off\tidle\n")
    assert.deepEqual(calls(), ["omarchy-brightness-display off"])
  })

  it("reports a display command that fails by its first line", (t) => {
    const { run } = setup(t, { "omarchy-brightness-display": "echo; echo 'hyprctl: no socket' >&2; echo more; exit 1" })
    const result = run(["off"])
    assert.equal(result.status, 1)
    assert.equal(result.stdout, "error\thyprctl: no socket\n")
  })

  it("describes a silent failure by its exit status", (t) => {
    const { run } = setup(t, { "omarchy-brightness-display": "exit 3" })
    const result = run(["off"])
    assert.equal(result.status, 1)
    assert.equal(result.stdout, "error\tomarchy-brightness-display off exited 3\n")
  })

  it("errors when the display command is not on PATH", (t) => {
    const { run } = setup(t, { "omarchy-brightness-display": null })
    const result = run(["off"])
    assert.equal(result.status, 1)
    assert.equal(result.stdout, "error\tomarchy-brightness-display not found\n")
  })

  it("leaves the keyboard backlight lit when the displays will not go off", (t) => {
    const failing = setup(t, { "omarchy-brightness-display": "exit 1" })
    assert.equal(failing.run(["off"]).status, 1)
    assert.deepEqual(failing.calls(), ["omarchy-brightness-display off"])
    const missing = setup(t, { "omarchy-brightness-display": null })
    assert.equal(missing.run(["off"]).status, 1)
    assert.deepEqual(missing.calls(), [])
  })

  it("fails a screen off asked for the same way as a timed one", (t) => {
    const failing = setup(t, { stayAwake: false, "omarchy-brightness-display": "echo 'hyprctl: no socket' >&2; exit 1" })
    const result = failing.run(["now"])
    assert.equal(result.status, 1)
    assert.equal(result.stdout, "error\thyprctl: no socket\n")
    assert.deepEqual(failing.calls(), ["omarchy-brightness-display off"])
    const dimless = setup(t, { "omarchy-brightness-keyboard": "exit 1" })
    assert.equal(dimless.run(["now"]).stdout, "off\tforced\n")
  })

  it("wakes the displays, whatever Stay Awake says by then", (t) => {
    for (const stayAwake of [true, false]) {
      const { run, calls } = setup(t, { stayAwake })
      const result = run(["on"])
      assert.equal(result.status, 0)
      assert.equal(result.stdout, "on\tactivity\n")
      assert.deepEqual(calls(), ["omarchy-system-wake"])
    }
  })

  it("reports a wake that fails or cannot be found", (t) => {
    const failing = setup(t, { "omarchy-system-wake": "echo 'wake failed' >&2; exit 1" }).run(["on"])
    assert.equal(failing.status, 1)
    assert.equal(failing.stdout, "error\twake failed\n")
    const missing = setup(t, { "omarchy-system-wake": null }).run(["on"])
    assert.equal(missing.status, 1)
    assert.equal(missing.stdout, "error\tomarchy-system-wake not found\n")
  })

  it("wakes the displays alone, with the clamshell check omarchy-system-wake runs, and never the keyboard backlight", (t) => {
    for (const stayAwake of [true, false]) {
      const { run, calls } = setup(t, { stayAwake })
      const result = run(["displays-on"])
      assert.equal(result.status, 0)
      assert.equal(result.stdout, "on\tdisplays\n")
      assert.deepEqual(calls(), ["omarchy-brightness-display on", "omarchy-hyprland-monitor-clamshell"])
    }
  })

  it("wakes the displays alone even when the clamshell check fails or is missing", (t) => {
    const failing = setup(t, { "omarchy-hyprland-monitor-clamshell": "echo 'no laptop' >&2; exit 1" })
    assert.equal(failing.run(["displays-on"]).stdout, "on\tdisplays\n")
    const missing = setup(t, { "omarchy-hyprland-monitor-clamshell": null })
    assert.equal(missing.run(["displays-on"]).stdout, "on\tdisplays\n")
    assert.deepEqual(missing.calls(), ["omarchy-brightness-display on"])
  })

  it("reports a wake of the displays alone that fails or cannot be found, before the clamshell check", (t) => {
    const failing = setup(t, { "omarchy-brightness-display": "echo 'hyprctl: no socket' >&2; exit 1" })
    const result = failing.run(["displays-on"])
    assert.equal(result.status, 1)
    assert.equal(result.stdout, "error\thyprctl: no socket\n")
    assert.deepEqual(failing.calls(), ["omarchy-brightness-display on"])
    const missing = setup(t, { "omarchy-brightness-display": null }).run(["displays-on"])
    assert.equal(missing.status, 1)
    assert.equal(missing.stdout, "error\tomarchy-brightness-display not found\n")
  })

  it("rejects a bad invocation", (t) => {
    const { run, calls } = setup(t)
    for (const args of [[], ["blank"], ["--dry-run"], ["displays"]]) {
      const result = run(args)
      assert.equal(result.status, 1)
      assert.equal(result.stdout, "")
      assert.match(result.stderr, /Usage: screenoff.sh/)
    }
    assert.deepEqual(calls(), [])
  })
})
