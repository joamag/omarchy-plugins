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
