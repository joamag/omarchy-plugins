// Shared plumbing for the plugin tests: loading a QML JavaScript library the
// way the shell sees it, running a plugin script under a controlled PATH, and
// a scratch directory per test that is removed afterwards.
//
// Model.js files are `.pragma library` scripts: no module system, every
// top-level function is a global. They are evaluated in a fresh vm context
// with the file path attached so the coverage report attributes the lines to
// the real source file.

const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const vm = require("node:vm")
const { spawn, spawnSync } = require("node:child_process")

const ROOT = path.resolve(__dirname, "..")
const FIXTURES = path.join(__dirname, "fixtures")

function pluginDir(id) {
  return path.join(ROOT, "plugins", id)
}

function loadModel(id) {
  const file = path.join(pluginDir(id), "Model.js")
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library[^\n]*/, "")
  const names = [...source.matchAll(/^(?:function|var) (\w+)/gm)].map((m) => m[1])
  // Wrapped in a function on the very first line so line numbers stay those
  // of the file, and run in this realm so objects the library builds compare
  // equal to literals in the tests.
  const wrapper = `(function () {${source}\nreturn { ${names.join(", ")} }\n})()`
  return new vm.Script(wrapper, { filename: file }).runInThisContext()
}

function fixture(name) {
  return fs.readFileSync(path.join(FIXTURES, name), "utf8")
}

function fixturePath(name) {
  return path.join(FIXTURES, name)
}

// Scratch directory removed when the test finishes.
function tmpdir(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-plugins-"))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  return dir
}

// Writes an executable that stands in for an external command (gh, docker,
// curl, ...) so a script can be driven through every branch offline. The
// body is bash; $FAKE_LOG is set when a log file is requested so the fake
// can record what it was asked.
function fakeCommand(dir, name, body) {
  const file = path.join(dir, name)
  fs.writeFileSync(file, `#!/bin/bash\n${body}\n`, { mode: 0o755 })
  return file
}

// Runs a plugin script with the given arguments. `bin` is prepended to a
// minimal PATH so fakes shadow the real commands while bash, jq, curl, awk
// and friends stay reachable; `path` replaces the PATH entirely for the
// cases where a command has to be absent.
function runScript(id, script, args = [], { bin = null, path: fullPath = null, env = {}, input = null } = {}) {
  const PATH = fullPath !== null ? fullPath : [bin, "/usr/bin", "/bin"].filter(Boolean).join(":")
  const result = spawnSync(path.join(pluginDir(id), script), args, {
    encoding: "utf8",
    input: input === null ? undefined : input,
    env: { HOME: os.homedir(), PATH, LANG: "C", ...env },
  })
  return { status: result.status, stdout: result.stdout, stderr: result.stderr }
}

function withJson(result) {
  const lines = result.stdout.split("\n").filter((line) => line.trim() !== "")
  return { ...result, lines, json: lines.map((line) => JSON.parse(line)) }
}

function runJson(id, script, args, options) {
  return withJson(runScript(id, script, args, options))
}

// Asynchronous twin of runScript for tests that serve the script from an
// in-process HTTP server: a synchronous spawn would block the event loop the
// server needs to answer.
function runScriptAsync(id, script, args = [], { bin = null, path: fullPath = null, env = {} } = {}) {
  const PATH = fullPath !== null ? fullPath : [bin, "/usr/bin", "/bin"].filter(Boolean).join(":")
  return new Promise((resolve, reject) => {
    const child = spawn(path.join(pluginDir(id), script), args, { env: { HOME: os.homedir(), PATH, LANG: "C", ...env } })
    let stdout = ""
    let stderr = ""
    child.stdout.on("data", (chunk) => { stdout += chunk })
    child.stderr.on("data", (chunk) => { stderr += chunk })
    child.on("error", reject)
    child.on("close", (status) => resolve({ status, stdout, stderr }))
  })
}

async function runJsonAsync(id, script, args, options) {
  return withJson(await runScriptAsync(id, script, args, options))
}

module.exports = { ROOT, FIXTURES, pluginDir, loadModel, fixture, fixturePath, tmpdir, fakeCommand, runScript, runJson, runScriptAsync, runJsonAsync }
