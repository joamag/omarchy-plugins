// Tests for joamag.isabella: Model.js in declaration order, then isabella.sh
// against an in-process stand-in for the Isabella API.

const { describe, it, before, after } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const http = require("node:http")
const path = require("node:path")
const { loadModel, runJsonAsync, runScriptAsync, tmpdir } = require("./helpers")

const Model = loadModel("joamag.isabella")

// A day payload shaped like backend/app.py's day_payload.
function row(id, name, minutes, extra = {}) {
  return { id, name, minutes, over_budget: false, checked: false, cancelled: false, notes: null, playbook: null, from: null, subtasks: [], ...extra }
}

const DAY = {
  day: "2026-09-03",
  title: "Tasks for 2026-09-03 (Thursday)",
  banners: [],
  budget: { hours: 8, minutes: 480, estimated: 240 },
  sections: [
    { name: "Overdue", rows: [row(8, "Iron clothes", 60, { from: "2026-09-02" }), row(7, "Change bed sheets", 20, { from: "2026-09-01", notes: "Use the white linen set", checked: true })] },
    { name: "Kitchen", rows: [row(1, "Sweep and mop the kitchen floor", 15), row(2, "Wipe down counters", 10, { cancelled: true }), row(3, "Clean the oven", 60, { over_budget: true, subtasks: [{ id: 31, name: "Racks", minutes: 20, checked: true, notes: null }, { id: 32, name: "Door glass", minutes: 10, checked: false, notes: "Use the scraper" }] })] },
    { name: "Scheduled", rows: [row(4, "Make the beds", 10, { checked: true })] },
  ],
  editable: true,
  delayable: true,
  cancellable: true,
  adhoc_candidates: [],
  prev_day: "2026-09-02",
  next_day: "2026-09-04",
}
const OK = { state: "ok", url: "https://isabella.example.com", day: DAY }
const EMPTY = { state: "ok", url: "u", day: { ...DAY, sections: [], budget: { hours: 8, minutes: 480, estimated: 0 } } }

describe("parseResult", () => {
  it("accepts an envelope with a state and rejects anything else", () => {
    assert.equal(Model.parseResult(JSON.stringify(OK)).state, "ok")
    assert.deepEqual(Model.parseResult("nope"), { state: "error", error: "Isabella returned no data" })
    assert.deepEqual(Model.parseResult('{"day":{}}'), { state: "error", error: "Isabella returned no data" })
  })
})

describe("hasDay", () => {
  it("needs a day with sections", () => {
    assert.equal(Model.hasDay(OK), true)
    assert.equal(Model.hasDay({ state: "unreachable", day: null }), false)
    assert.equal(Model.hasDay({ state: "ok", day: { sections: "x" } }), false)
    assert.equal(Model.hasDay(null), false)
  })
})

describe("isOk", () => {
  it("requires the ok state and a day", () => {
    assert.equal(Model.isOk(OK), true)
    assert.equal(Model.isOk({ state: "unreachable", day: DAY }), false)
    assert.equal(Model.isOk({ state: "ok" }), false)
  })
})

describe("tasks", () => {
  it("flattens sections into task rows carrying their section", () => {
    const tasks = Model.tasks(OK)
    assert.deepEqual(tasks.map((t) => t.id), [8, 7, 1, 2, 3, 4])
    assert.equal(tasks[0].section, "Overdue")
    assert.equal(tasks[0].from, "2026-09-02")
    assert.equal(tasks[1].notes, "Use the white linen set")
    assert.equal(tasks[4].subtasks.length, 2)
    assert.equal(tasks[4].key, "task:3")
    assert.deepEqual(Model.tasks(null), [])
  })
})

describe("counts", () => {
  it("separates pending, done, cancelled and overdue work", () => {
    assert.deepEqual(Model.counts(OK), { total: 5, done: 2, pending: 3, cancelled: 1, overdue: 1, pendingMinutes: 135 })
    assert.deepEqual(Model.counts(null), { total: 0, done: 0, pending: 0, cancelled: 0, overdue: 0, pendingMinutes: 0 })
  })
})

describe("status", () => {
  it("ranks cancelled over done over overdue over pending", () => {
    const [overdue, doneOverdue, pending, cancelled] = Model.tasks(OK)
    assert.equal(Model.status(overdue), "overdue")
    assert.equal(Model.status(doneOverdue), "done")
    assert.equal(Model.status(pending), "pending")
    assert.equal(Model.status(cancelled), "cancelled")
    assert.equal(Model.status(null), "pending")
  })
})

describe("glyph", () => {
  it("maps each status to its checkbox glyph", () => {
    const [overdue, done, pending, cancelled] = Model.tasks(OK)
    assert.equal(Model.glyph(overdue), Model.GLYPHS.overdue)
    assert.equal(Model.glyph(done), Model.GLYPHS.done)
    assert.equal(Model.glyph(pending), Model.GLYPHS.pending)
    assert.equal(Model.glyph(cancelled), Model.GLYPHS.cancelled)
  })
})

describe("subtaskGlyph", () => {
  it("follows the subtask, or the parent's cancellation", () => {
    assert.equal(Model.subtaskGlyph({ checked: true }, { cancelled: false }), Model.GLYPHS.done)
    assert.equal(Model.subtaskGlyph({ checked: false }, { cancelled: false }), Model.GLYPHS.pending)
    assert.equal(Model.subtaskGlyph({ checked: true }, { cancelled: true }), Model.GLYPHS.cancelled)
    assert.equal(Model.subtaskGlyph(null, null), Model.GLYPHS.pending)
  })
})

describe("visibleRows", () => {
  const rows = Model.visibleRows(OK)

  it("puts pending work first with overdue on top, then done and cancelled", () => {
    const shape = rows.map((r) => (Model.isHeader(r) ? `[${r.title} ${r.count}]` : `${r.kind}:${r.id}`))
    assert.deepEqual(shape, ["[TO DO 3]", "task:8", "task:1", "task:3", "subtask:31", "subtask:32", "[DONE 3]", "task:7", "task:4", "task:2"])
  })

  it("gives subtasks their parent and the parent's cancellation", () => {
    const sub = rows.find((r) => r.kind === "subtask" && r.id === 32)
    assert.equal(sub.parent.id, 3)
    assert.equal(sub.key, "sub:32")
    assert.equal(sub.notes, "Use the scraper")
    assert.equal(sub.cancelled, false)
  })

  it("is empty without a day", () => {
    assert.deepEqual(Model.visibleRows({ state: "error" }), [])
    assert.deepEqual(Model.visibleRows(EMPTY), [])
  })
})

describe("isHeader", () => {
  it("recognises header markers only", () => {
    assert.equal(Model.isHeader({ header: true }), true)
    assert.equal(Model.isHeader({ kind: "task" }), false)
    assert.equal(Model.isHeader(undefined), false)
  })
})

describe("nextRowIndex", () => {
  it("skips headers in both directions and wraps", () => {
    const rows = Model.visibleRows(OK)
    assert.equal(Model.nextRowIndex(rows, 5, 1), 7)
    assert.equal(Model.nextRowIndex(rows, 7, -1), 5)
    assert.equal(Model.nextRowIndex(rows, rows.length - 1, 1), 1)
    assert.equal(Model.nextRowIndex([{ header: true }], 0, 1), -1)
    assert.equal(Model.nextRowIndex(null, 0, 1), -1)
  })
})

describe("firstRowIndex", () => {
  it("lands on the first task", () => {
    assert.equal(Model.firstRowIndex(Model.visibleRows(OK)), 1)
    assert.equal(Model.firstRowIndex([]), -1)
  })
})

describe("formatMinutes", () => {
  it("prints minutes, whole hours or both", () => {
    assert.equal(Model.formatMinutes(45), "45m")
    assert.equal(Model.formatMinutes(120), "2h")
    assert.equal(Model.formatMinutes(135), "2h 15m")
    assert.equal(Model.formatMinutes(-3), "0m")
    assert.equal(Model.formatMinutes("x"), "0m")
  })
})

describe("budgetLine", () => {
  it("compares the estimate with the daily budget", () => {
    assert.equal(Model.budgetLine(OK), "4h of 8h budget")
    assert.equal(Model.budgetLine({ state: "ok", day: { sections: [] } }), "")
    assert.equal(Model.budgetLine(null), "")
  })
})

describe("parseDay", () => {
  it("parses ISO days as local dates and rejects other text", () => {
    const d = Model.parseDay("2026-09-03")
    assert.deepEqual([d.getFullYear(), d.getMonth(), d.getDate()], [2026, 8, 3])
    assert.equal(Model.parseDay("03/09/2026"), null)
    assert.equal(Model.parseDay(null), null)
  })
})

describe("todayIso", () => {
  it("formats the local date", () => {
    const d = new Date()
    const expected = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
    assert.equal(Model.todayIso(), expected)
  })
})

describe("dayLabel", () => {
  it("names today, tomorrow and yesterday, else the weekday and date", () => {
    const shift = (days) => {
      const d = Model.parseDay(Model.todayIso())
      d.setDate(d.getDate() + days)
      return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
    }
    assert.match(Model.dayLabel(shift(0)), /^Today · [A-Z][a-z]+day \d+ [A-Z][a-z]{2}$/)
    assert.match(Model.dayLabel(shift(1)), /^Tomorrow · /)
    assert.match(Model.dayLabel(shift(-1)), /^Yesterday · /)
    assert.match(Model.dayLabel(shift(3)), /^[A-Z][a-z]+day \d+ [A-Z][a-z]{2}$/)
    assert.match(Model.dayLabel(shift(-10)), /^[A-Z][a-z]+day \d+ [A-Z][a-z]{2}$/)
    assert.equal(Model.dayLabel("junk"), "junk")
  })
})

describe("shortDay", () => {
  it("prints day and month", () => {
    assert.equal(Model.shortDay("2026-09-03"), "3 Sep")
    assert.equal(Model.shortDay("junk"), "junk")
  })
})

describe("rowDetail", () => {
  it("combines carryover, area, steps, budget, cancellation and notes", () => {
    const rows = Model.visibleRows(OK)
    const byKey = Object.fromEntries(rows.filter((r) => !Model.isHeader(r)).map((r) => [r.key, r]))
    assert.equal(Model.rowDetail(byKey["task:8"]), "since 2 Sep")
    assert.equal(Model.rowDetail(byKey["task:7"]), "since 1 Sep · Use the white linen set")
    assert.equal(Model.rowDetail(byKey["task:3"]), "Kitchen · 1/2 steps · over budget")
    assert.equal(Model.rowDetail(byKey["task:2"]), "Kitchen · cancelled today")
    assert.equal(Model.rowDetail(byKey["task:4"]), "")
    assert.equal(Model.rowDetail(byKey["sub:32"]), "Use the scraper")
    assert.equal(Model.rowDetail(rows[0]), "")
    assert.equal(Model.rowDetail(null), "")
  })
})

describe("barText", () => {
  it("shows both counts, one of them, or the icon alone", () => {
    assert.equal(Model.barText(OK, "both", false), `${Model.ICON} 3 󰄬2`)
    assert.equal(Model.barText(OK, "pending", false), `${Model.ICON} 3`)
    assert.equal(Model.barText(OK, "done", false), `${Model.ICON} 2/5`)
    assert.equal(Model.barText(OK, "none", false), Model.ICON)
    assert.equal(Model.barText(OK, "both", true), Model.ICON)
    assert.equal(Model.barText(EMPTY, "both", false), Model.ICON)
    assert.equal(Model.barText({ state: "unreachable", day: DAY }, "both", false), Model.ICON)
  })
})

describe("tooltip", () => {
  it("describes the failing states and the counts", () => {
    assert.equal(Model.tooltip(null), "Isabella")
    assert.equal(Model.tooltip({ state: "unconfigured" }), "Isabella: credentials missing")
    assert.equal(Model.tooltip({ state: "unauthorized" }), "Isabella: login refused")
    assert.equal(Model.tooltip({ state: "unreachable", day: DAY }), "Isabella unreachable · showing cached tasks")
    assert.equal(Model.tooltip({ state: "unreachable", day: null }), "Isabella unreachable")
    assert.equal(Model.tooltip({ state: "error", error: "boom" }), "Isabella: boom")
    assert.equal(Model.tooltip({ state: "error" }), "Isabella: request failed")
    assert.equal(Model.tooltip(OK), "Isabella · 3 pending · 2 done · 1 overdue")
    assert.equal(Model.tooltip(EMPTY), "Isabella · nothing scheduled")
  })
})

describe("stateTitle", () => {
  it("names every state", () => {
    assert.equal(Model.stateTitle({ state: "unconfigured" }), "Isabella is not configured")
    assert.equal(Model.stateTitle({ state: "unauthorized" }), "Isabella refused the login")
    assert.equal(Model.stateTitle({ state: "unreachable" }), "Isabella is unreachable")
    assert.equal(Model.stateTitle({ state: "error" }), "Isabella request failed")
    assert.equal(Model.stateTitle(null), "Loading Isabella")
  })
})

describe("stateDetail", () => {
  it("points at the form and the file, listing what is missing", () => {
    assert.equal(Model.stateDetail({ state: "unconfigured", file: "/x/isabella.env", missing: ["ISABELLA_PASSWORD"] }), "Sign in below, or fill in /x/isabella.env with ISABELLA_URL, ISABELLA_USERNAME and ISABELLA_PASSWORD (missing: ISABELLA_PASSWORD).")
    assert.match(Model.stateDetail({ state: "unconfigured", missing: [] }), /~\/.config\/omarchy\/isabella.env with .*PASSWORD\.$/)
    assert.match(Model.stateDetail({ state: "unauthorized" }), /Sign in again/)
    assert.equal(Model.stateDetail({ state: "unreachable", error: "curl: (7) failed", day: DAY }), "curl: (7) failed. Showing the last checklist that was fetched.")
    assert.equal(Model.stateDetail({ state: "unreachable", day: null }), "No response")
    assert.equal(Model.stateDetail({ state: "error", error: "boom" }), "boom")
    assert.equal(Model.stateDetail({ state: "error" }), "")
    assert.equal(Model.stateDetail(null), "")
  })
})

describe("needsCredentials", () => {
  it("is true for the two credential states", () => {
    assert.equal(Model.needsCredentials({ state: "unconfigured" }), true)
    assert.equal(Model.needsCredentials({ state: "unauthorized" }), true)
    assert.equal(Model.needsCredentials(OK), false)
    assert.equal(Model.needsCredentials(null), false)
  })
})

describe("prefill", () => {
  it("uses what the script reported, else the fallback URL", () => {
    assert.deepEqual(Model.prefill({ state: "unconfigured", url: "https://x", username: "admin" }, "https://f"), { url: "https://x", username: "admin" })
    assert.deepEqual(Model.prefill({ state: "unconfigured" }, "https://f"), { url: "https://f", username: "" })
    assert.deepEqual(Model.prefill(null, undefined), { url: "", username: "" })
  })
})

describe("heroStatus", () => {
  it("summarises the day, flags overdue and cached data", () => {
    assert.equal(Model.heroStatus(null), "LOADING")
    assert.equal(Model.heroStatus({ state: "unauthorized" }), "UNAUTHORIZED")
    assert.equal(Model.heroStatus(OK), "3 LEFT · 2h 15m · 1 OVERDUE")
    assert.equal(Model.heroStatus(EMPTY), "NOTHING SCHEDULED")
    assert.equal(Model.heroStatus({ state: "ok", url: "u", day: { ...DAY, sections: [{ name: "Scheduled", rows: [row(4, "Make the beds", 10, { checked: true })] }] } }), "ALL DONE")
    assert.equal(Model.heroStatus({ state: "unreachable", day: DAY }), "3 LEFT · 2h 15m · 1 OVERDUE · CACHED")
  })
})

describe("isabella.sh", () => {
  // The stand-in server: cookie sessions, a day view driven by the calls it
  // received, and the failure modes the script has to survive.
  const server = { calls: [], logins: [], tokens: new Set(), done: new Set(), cancelled: new Set(), password: "good", nextToken: 1 }
  let base = ""

  function payload(day) {
    const rows = [row(1, "Sweep the floor", 15), row(2, "Wipe counters", 10), row(3, "Clean the oven", 60, { subtasks: [{ id: 31, name: "Racks", minutes: 20, checked: false, notes: null }] })]
    for (const r of rows) {
      r.checked = server.done.has(r.id)
      r.cancelled = server.cancelled.has(r.id)
    }
    return { ...DAY, day, sections: [{ name: "Scheduled", rows }], editable: day <= Model.todayIso() }
  }

  function authorized(req) {
    const match = /session=([^;]+)/.exec(req.headers.cookie || "")
    return match && server.tokens.has(match[1])
  }

  function respond(res, status, body) {
    res.writeHead(status, { "Content-Type": "application/json" })
    res.end(JSON.stringify(body))
  }

  before(async () => {
    const instance = http.createServer((req, res) => {
      let raw = ""
      req.on("data", (chunk) => { raw += chunk })
      req.on("end", () => {
        const body = raw ? JSON.parse(raw) : {}
        const url = new URL(req.url, "http://localhost")
        server.calls.push({ method: req.method, path: url.pathname, body })
        if (req.method === "POST" && url.pathname === "/api/auth/login") {
          server.logins.push(body)
          if (body.password !== server.password) return respond(res, 401, { detail: "Invalid credentials." })
          const token = `tok-${server.nextToken++}`
          server.tokens.add(token)
          res.writeHead(200, { "Content-Type": "application/json", "Set-Cookie": `session=${token}; Path=/; HttpOnly; SameSite=lax` })
          return res.end(JSON.stringify({ id: 1, username: body.username, role: "admin" }))
        }
        if (!authorized(req)) return respond(res, 401, { detail: "Not authenticated." })
        const dayMatch = /^\/api\/day\/([^/]+)(?:\/(\w+))?$/.exec(url.pathname)
        if (!dayMatch) return respond(res, 404, { detail: "Not found." })
        const [, day, action] = dayMatch
        if (day === "9999-99-99") return respond(res, 400, { detail: "Invalid day." })
        if (action === "toggle" && body.task === 999) return respond(res, 500, { detail: "boom" })
        if (action === "toggle" && body.task !== undefined) server.done.has(body.task) ? server.done.delete(body.task) : server.done.add(body.task)
        if (action === "cancel") server.cancelled.has(body.task) ? server.cancelled.delete(body.task) : server.cancelled.add(body.task)
        return respond(res, 200, payload(day))
      })
    })
    await new Promise((resolve) => instance.listen(0, "127.0.0.1", resolve))
    base = `http://127.0.0.1:${instance.address().port}`
    server.instance = instance
  })

  after(() => new Promise((resolve) => server.instance.close(resolve)))

  // A credentials file plus an isolated cache directory for one test.
  function setup(t, lines = [`ISABELLA_URL=${base}/`, "ISABELLA_USERNAME=admin", "ISABELLA_PASSWORD=good"]) {
    const dir = tmpdir(t)
    const envFile = path.join(dir, "isabella.env")
    if (lines !== null) fs.writeFileSync(envFile, lines.join("\n") + "\n")
    const env = { ISABELLA_ENV: envFile, XDG_CACHE_HOME: path.join(dir, "cache") }
    return { dir, envFile, env, run: (args, extra = {}) => runJsonAsync("joamag.isabella", "isabella.sh", args, { env: { ...env, ...extra } }) }
  }

  it("reports what is missing from the credentials file", async (t) => {
    const missing = setup(t, null)
    const [none] = (await missing.run(["day"])).json
    assert.equal(none.state, "unconfigured")
    assert.deepEqual(none.missing, ["ISABELLA_URL", "ISABELLA_USERNAME", "ISABELLA_PASSWORD"])
    assert.equal(none.file, missing.envFile)
    const partial = setup(t, ["ISABELLA_URL=https://isabella.example.com", "ISABELLA_USERNAME=admin"])
    const [some] = (await partial.run(["day"])).json
    assert.deepEqual(some.missing, ["ISABELLA_PASSWORD"])
    assert.equal(some.url, "https://isabella.example.com")
    assert.equal(some.username, "admin")
  })

  it("logs in, fetches today by default and caches the day", async (t) => {
    const s = setup(t)
    server.calls.length = 0
    const [result] = (await s.run(["day"])).json
    assert.equal(result.state, "ok")
    assert.equal(result.url, base)
    assert.equal(result.day.day, Model.todayIso())
    assert.deepEqual(server.calls.map((c) => c.path), [`/api/day/${Model.todayIso()}`, "/api/auth/login", `/api/day/${Model.todayIso()}`])
    assert.ok(fs.existsSync(path.join(s.env.XDG_CACHE_HOME, "omarchy/isabella/cookies")))
    assert.equal((fs.statSync(path.join(s.env.XDG_CACHE_HOME, "omarchy/isabella/cookies")).mode & 0o777), 0o600)
    assert.ok(fs.existsSync(path.join(s.env.XDG_CACHE_HOME, `omarchy/isabella/day-${Model.todayIso()}.json`)))
    server.calls.length = 0
    assert.equal((await s.run(["day", "2026-09-04"])).json[0].day.day, "2026-09-04")
    assert.deepEqual(server.calls.map((c) => c.path), ["/api/day/2026-09-04"])
  })

  it("parses comments, quotes and a password containing a hash", async (t) => {
    const s = setup(t, ["# the house", `ISABELLA_URL = "${base}" `, "ISABELLA_USERNAME='admin'", "ISABELLA_PASSWORD=good"])
    server.password = 'p#ss "word"'
    fs.appendFileSync(s.envFile, "")
    fs.writeFileSync(s.envFile, ["# the house", `ISABELLA_URL = "${base}" `, "ISABELLA_USERNAME='admin'", 'ISABELLA_PASSWORD=p#ss "word"'].join("\n") + "\n")
    server.logins.length = 0
    const [result] = (await s.run(["day"])).json
    server.password = "good"
    assert.equal(result.state, "ok")
    assert.deepEqual(server.logins, [{ username: "admin", password: 'p#ss "word"' }])
  })

  it("sends the task and subtask actions the API expects", async (t) => {
    const s = setup(t)
    const today = Model.todayIso()
    // Log in first so the recorded calls are the actions alone.
    assert.equal((await s.run(["day"])).json[0].state, "ok")
    server.calls.length = 0
    assert.equal((await s.run(["toggle", today, "1"])).json[0].day.sections[0].rows[0].checked, true)
    assert.equal((await s.run(["toggle", today, "1"])).json[0].day.sections[0].rows[0].checked, false)
    assert.equal((await s.run(["subtoggle", today, "31"])).json[0].state, "ok")
    assert.equal((await s.run(["cancel", today, "2"])).json[0].day.sections[0].rows[1].cancelled, true)
    assert.equal((await s.run(["cancel", today, "2"])).json[0].day.sections[0].rows[1].cancelled, false)
    assert.equal((await s.run(["delay", today, "3"])).json[0].state, "ok")
    const actions = server.calls.filter((c) => c.method === "POST" && c.path !== "/api/auth/login").map((c) => [c.path.split("/").pop(), c.body])
    assert.deepEqual(actions, [["toggle", { task: 1 }], ["toggle", { task: 1 }], ["toggle", { subtask: 31 }], ["cancel", { task: 2 }], ["cancel", { task: 2 }], ["delay", { task: 3 }]])
  })

  it("logs in again when the session has expired", async (t) => {
    const s = setup(t)
    assert.equal((await s.run(["day"])).json[0].state, "ok")
    server.tokens.clear()
    server.calls.length = 0
    assert.equal((await s.run(["day"])).json[0].state, "ok")
    assert.deepEqual(server.calls.map((c) => c.path), [`/api/day/${Model.todayIso()}`, "/api/auth/login", `/api/day/${Model.todayIso()}`])
  })

  it("reports unauthorized with the prefill when the login is refused", async (t) => {
    const s = setup(t, [`ISABELLA_URL=${base}`, "ISABELLA_USERNAME=admin", "ISABELLA_PASSWORD=wrong"])
    assert.deepEqual((await s.run(["day"])).json, [{ state: "unauthorized", url: base, username: "admin" }])
  })

  it("passes HTTP errors through with their detail", async (t) => {
    const s = setup(t)
    assert.deepEqual((await s.run(["day", "9999-99-99"])).json, [{ state: "error", error: "HTTP 400: Invalid day." }])
    assert.deepEqual((await s.run(["toggle", Model.todayIso(), "999"])).json, [{ state: "error", error: "HTTP 500: boom" }])
  })

  it("reports unreachable, with the cached day when there is one", async (t) => {
    const s = setup(t)
    assert.equal((await s.run(["day"])).json[0].state, "ok")
    fs.writeFileSync(s.envFile, ["ISABELLA_URL=http://127.0.0.1:9", "ISABELLA_USERNAME=admin", "ISABELLA_PASSWORD=good"].join("\n"))
    const [cached] = (await s.run(["day"])).json
    assert.equal(cached.state, "unreachable")
    assert.match(cached.error, /curl: \(7\)/)
    assert.equal(cached.day.day, Model.todayIso())
    const [fresh] = (await s.run(["day", "2030-01-01"])).json
    assert.equal(fresh.state, "unreachable")
    assert.equal(fresh.day, null)
  })

  it("writes the credentials file from the form and lands on today", async (t) => {
    const s = setup(t, null)
    server.calls.length = 0
    const [result] = (await s.run(["configure"], { ISABELLA_SET_URL: `${base}/`, ISABELLA_SET_USERNAME: "admin", ISABELLA_SET_PASSWORD: "good" })).json
    assert.equal(result.state, "ok")
    assert.equal(result.day.day, Model.todayIso())
    assert.equal(fs.readFileSync(s.envFile, "utf8"), `ISABELLA_URL=${base}\nISABELLA_USERNAME=admin\nISABELLA_PASSWORD=good\n`)
    assert.equal(fs.statSync(s.envFile).mode & 0o777, 0o600)
    assert.equal(server.calls.filter((c) => c.path === "/api/auth/login").length, 1)
  })

  it("refuses an incomplete form and reports a refused password after saving", async (t) => {
    const s = setup(t, null)
    assert.deepEqual((await s.run(["configure"], { ISABELLA_SET_URL: base })).json, [{ state: "error", error: "URL, username and password are all required" }])
    assert.equal(fs.existsSync(s.envFile), false)
    const [refused] = (await s.run(["configure"], { ISABELLA_SET_URL: base, ISABELLA_SET_USERNAME: "admin", ISABELLA_SET_PASSWORD: "wrong" })).json
    assert.deepEqual(refused, { state: "unauthorized", url: base, username: "admin" })
    assert.match(fs.readFileSync(s.envFile, "utf8"), /ISABELLA_PASSWORD=wrong/)
  })

  it("answers the login command and rejects bad invocations", async (t) => {
    const s = setup(t)
    assert.deepEqual((await s.run(["login"])).json, [{ state: "ok", url: base }])
    const bad = setup(t, [`ISABELLA_URL=${base}`, "ISABELLA_USERNAME=admin", "ISABELLA_PASSWORD=wrong"])
    assert.deepEqual((await bad.run(["login"])).json, [{ state: "unauthorized", url: base, username: "admin" }])
    assert.equal((await runScriptAsync("joamag.isabella", "isabella.sh", ["bogus"], { env: s.env })).status, 1)
    assert.equal((await runScriptAsync("joamag.isabella", "isabella.sh", ["toggle"], { env: s.env })).status, 1)
    assert.equal((await runScriptAsync("joamag.isabella", "isabella.sh", ["toggle", Model.todayIso()], { env: s.env })).status, 1)
  })
})
