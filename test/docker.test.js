// Tests for joamag.docker: Model.js in declaration order, then docker.sh.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const net = require("node:net")
const path = require("node:path")
const { loadModel, fixture, fixturePath, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.docker")

const RAW_OK = "state\tok\n" + fixture("docker-ps.tsv").split("\n").filter(Boolean).map((line) => `container\t${line}`).join("\n") + "\n"
const ok = Model.parseSnapshot(RAW_OK)
const byName = Object.fromEntries(ok.containers.map((c) => [c.name, c]))

// Opens a unix socket at `file` so docker.sh sees a "daemon", closed after the test.
function listenSocket(t, file) {
  return new Promise((resolve, reject) => {
    const server = net.createServer()
    server.once("error", reject)
    server.listen(file, () => {
      t.after(() => new Promise((done) => server.close(done)))
      resolve(server)
    })
  })
}

describe("parseSnapshot", () => {
  it("reads the state and the container rows, ports optional", () => {
    assert.equal(ok.state, "ok")
    assert.equal(ok.containers.length, 3)
    assert.equal(byName.api.ports, "0.0.0.0:8080->80/tcp")
    assert.equal(byName.cache.ports, "")
    assert.equal(byName["postgres-db"].id, "abc123def456")
  })

  it("sorts running containers first, then alphabetically", () => {
    assert.deepEqual(ok.containers.map((c) => c.name), ["api", "cache", "postgres-db"])
  })

  it("skips short rows and keeps the error message", () => {
    const parsed = Model.parseSnapshot("state\terror\nerror\tboom\tsplat\ncontainer\tonly\tfour\tfields\n")
    assert.equal(parsed.state, "error")
    assert.equal(parsed.error, "boom\tsplat")
    assert.equal(parsed.containers.length, 0)
  })

  it("falls back to an error with a message when nothing usable arrives", () => {
    assert.deepEqual(Model.parseSnapshot(""), { state: "error", error: "Docker returned no data", containers: [] })
    assert.equal(Model.parseSnapshot("state\t").state, "error")
  })
})

describe("compareContainers", () => {
  it("orders by running state then name", () => {
    assert.ok(Model.compareContainers(byName.api, byName.cache) < 0)
    assert.ok(Model.compareContainers(byName["postgres-db"], byName.cache) > 0)
    assert.equal(Model.compareContainers(byName.api, byName.api), 0)
  })
})

describe("isRunning", () => {
  it("is true only for the running state", () => {
    assert.equal(Model.isRunning(byName.api), true)
    assert.equal(Model.isRunning(byName.cache), false)
    assert.equal(Model.isRunning(null), false)
  })
})

describe("isPaused", () => {
  it("is true only for the paused state", () => {
    assert.equal(Model.isPaused(byName.cache), true)
    assert.equal(Model.isPaused(byName.api), false)
    assert.equal(Model.isPaused(undefined), false)
  })
})

describe("runningCount", () => {
  it("counts running containers", () => {
    assert.equal(Model.runningCount(ok), 1)
    assert.equal(Model.runningCount(null), 0)
  })
})

describe("totalCount", () => {
  it("counts every container", () => {
    assert.equal(Model.totalCount(ok), 3)
    assert.equal(Model.totalCount(null), 0)
  })
})

describe("stateIcon", () => {
  it("maps known states and falls back for unknown ones", () => {
    assert.equal(Model.stateIcon(byName.api), Model.STATE_ICONS.running)
    assert.equal(Model.stateIcon({ state: "weird" }), Model.STATE_ICONS.created)
    assert.equal(Model.stateIcon(null), Model.STATE_ICONS.created)
  })
})

describe("toggleCommand", () => {
  it("stops running, resumes paused and starts everything else", () => {
    assert.equal(Model.toggleCommand(byName.api), "stop")
    assert.equal(Model.toggleCommand(byName.cache), "unpause")
    assert.equal(Model.toggleCommand(byName["postgres-db"]), "start")
  })
})

describe("shortImage", () => {
  it("drops registries, ports and digests but keeps namespaces and tags", () => {
    assert.equal(Model.shortImage("ghcr.io/acme/api@sha256:deadbeef"), "acme/api")
    assert.equal(Model.shortImage("postgres:16"), "postgres:16")
    assert.equal(Model.shortImage("library/nginx"), "library/nginx")
    assert.equal(Model.shortImage("localhost:5000/tools/build:1"), "tools/build:1")
    assert.equal(Model.shortImage(""), "")
  })
})

describe("isOk", () => {
  it("requires the ok state", () => {
    assert.equal(Model.isOk(ok), true)
    assert.equal(Model.isOk(Model.parseSnapshot("state\tdenied")), false)
    assert.equal(Model.isOk(null), false)
  })
})

describe("stateTitle", () => {
  it("names every state", () => {
    assert.equal(Model.stateTitle({ state: "missing" }), "Docker is not installed")
    assert.equal(Model.stateTitle({ state: "stopped" }), "Docker daemon is not running")
    assert.equal(Model.stateTitle({ state: "denied" }), "Docker needs sudo on this account")
    assert.equal(Model.stateTitle({ state: "error" }), "Docker error")
    assert.equal(Model.stateTitle(null), "Checking Docker")
  })
})

describe("stateDetail", () => {
  it("explains every state and echoes error text", () => {
    assert.match(Model.stateDetail({ state: "missing" }), /Install docker/)
    assert.match(Model.stateDetail({ state: "stopped" }), /Start the daemon/)
    assert.match(Model.stateDetail({ state: "denied" }), /sudoless Docker/)
    assert.equal(Model.stateDetail({ state: "error", error: "boom" }), "boom")
    assert.equal(Model.stateDetail({ state: "error" }), "")
    assert.equal(Model.stateDetail(null), "")
  })
})

describe("heroStatus", () => {
  it("summarises counts or the failing state", () => {
    assert.equal(Model.heroStatus(null), "CHECKING")
    assert.equal(Model.heroStatus({ state: "denied", containers: [] }), "DENIED")
    assert.equal(Model.heroStatus(Model.parseSnapshot("state\tok\n")), "NO CONTAINERS")
    assert.equal(Model.heroStatus(ok), "1 RUNNING · 3 TOTAL")
  })
})

describe("barText", () => {
  it("adds the running count only when reachable, horizontal and wanted", () => {
    assert.equal(Model.barText(ok, true, false), `${Model.ICON} 1`)
    assert.equal(Model.barText(ok, false, false), Model.ICON)
    assert.equal(Model.barText(ok, true, true), Model.ICON)
    assert.equal(Model.barText(Model.parseSnapshot("state\tstopped"), true, false), Model.ICON)
  })
})

describe("tooltip", () => {
  it("describes counts or the failing state", () => {
    assert.equal(Model.tooltip(null), "Docker")
    assert.equal(Model.tooltip(Model.parseSnapshot("state\tstopped")), "Docker daemon is not running")
    assert.equal(Model.tooltip(Model.parseSnapshot("state\tok\n")), "Docker · no containers")
    assert.equal(Model.tooltip(ok), "Docker · 1 of 3 running")
  })
})

describe("docker.sh", () => {
  it("reports missing when the docker CLI is absent", (t) => {
    const bin = tmpdir(t)
    const result = runScript("joamag.docker", "docker.sh", [], { path: bin })
    assert.equal(result.status, 0)
    assert.equal(result.stdout, "state\tmissing\n")
  })

  it("reports stopped when there is no socket", (t) => {
    const bin = tmpdir(t)
    fakeCommand(bin, "docker", "exit 99")
    const result = runScript("joamag.docker", "docker.sh", [], { bin, env: { OMARCHY_DOCKER_SOCKET: path.join(bin, "missing.sock") } })
    assert.equal(result.stdout, "state\tstopped\n")
  })

  it("reports denied without running docker when the socket is not writable", async (t) => {
    const dir = tmpdir(t)
    const sock = path.join(dir, "docker.sock")
    await listenSocket(t, sock)
    fs.chmodSync(sock, 0o000)
    fakeCommand(dir, "docker", 'echo "docker must not run" >&2; exit 99')
    const result = runScript("joamag.docker", "docker.sh", [], { bin: dir, env: { OMARCHY_DOCKER_SOCKET: sock } })
    assert.equal(result.stdout, "state\tdenied\n")
    assert.equal(result.stderr, "")
  })

  it("lists containers from docker ps", async (t) => {
    const dir = tmpdir(t)
    const sock = path.join(dir, "docker.sock")
    await listenSocket(t, sock)
    fakeCommand(dir, "docker", `[[ $1 == ps ]] || exit 2; cat "${fixturePath("docker-ps.tsv")}"`)
    const result = runScript("joamag.docker", "docker.sh", [], { bin: dir, env: { OMARCHY_DOCKER_SOCKET: sock } })
    const parsed = Model.parseSnapshot(result.stdout)
    assert.equal(parsed.state, "ok")
    assert.deepEqual(parsed.containers.map((c) => c.name), ["api", "cache", "postgres-db"])
    assert.equal(parsed.containers[0].ports, "0.0.0.0:8080->80/tcp")
  })

  it("classifies docker CLI failures by their message", async (t) => {
    const dir = tmpdir(t)
    const sock = path.join(dir, "docker.sock")
    await listenSocket(t, sock)
    const cases = [
      ["permission denied while trying to connect to the docker API", "denied"],
      ["Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?", "stopped"],
      ["error during connect: something odd", "error"],
    ]
    for (const [message, state] of cases) {
      fakeCommand(dir, "docker", `echo "${message}" >&2; exit 1`)
      const parsed = Model.parseSnapshot(runScript("joamag.docker", "docker.sh", [], { bin: dir, env: { OMARCHY_DOCKER_SOCKET: sock } }).stdout)
      assert.equal(parsed.state, state, message)
      if (state === "error") assert.equal(parsed.error, message)
    }
  })
})
