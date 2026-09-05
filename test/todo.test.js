// Tests for joamag.todo: Model.js in declaration order, then todo.sh against
// a scratch todo.txt.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawn } = require("node:child_process")
const { loadModel, runScript, tmpdir } = require("./helpers")
const mcp = require("../plugins/joamag.todo/mcp.js")

const Model = loadModel("joamag.todo")

const TODAY = "2026-09-05"

// A listing the way todo.sh emits it: two pending tasks with priorities, a
// plain one, and two done ones ticked on different days.
const RAW = [
  "file\t/home/joamag/.local/share/omarchy/todo.txt",
  "task\t1\t0\t\t2026-09-01\t\tBuy milk +groceries @errands",
  "task\t2\t0\tA\t2026-09-05\t\tCall the bank @phone +admin",
  "task\t3\t1\tB\t2026-09-02\t2026-09-03\tRenew the domain +admin",
  "task\t4\t0\tB\t\t\tWrite the report due:2026-09-10",
  "task\t5\t1\t\t\t2026-09-05\tWater the plants",
  "task\tshort",
  "",
].join("\n")

const snapshot = Model.parseSnapshot(RAW)
const [bank, report, milk, plants, domain] = snapshot.tasks
const empty = Model.parseSnapshot("file\t/x/todo.txt\n")

describe("num", () => {
  it("parses numeric strings and rejects the rest", () => {
    assert.equal(Model.num("3"), 3)
    assert.ok(Number.isNaN(Model.num("")))
    assert.ok(Number.isNaN(Model.num("abc")))
  })
})

describe("parseSnapshot", () => {
  it("reads the file line, every task field and the tags", () => {
    assert.equal(snapshot.file, "/home/joamag/.local/share/omarchy/todo.txt")
    assert.equal(snapshot.error, "")
    assert.equal(snapshot.tasks.length, 5)
    assert.deepEqual(bank, {
      kind: "task", key: "task:2", line: 2, done: false, priority: "A", created: "2026-09-05", completed: "",
      text: "Call the bank @phone +admin", title: "Call the bank", projects: ["admin"], contexts: ["phone"],
    })
    assert.equal(domain.done, true)
    assert.equal(domain.completed, "2026-09-03")
  })

  it("orders pending by priority then line, and done newest first", () => {
    assert.deepEqual(snapshot.tasks.map((t) => t.line), [2, 4, 1, 5, 3])
  })

  it("carries an error line and survives junk", () => {
    assert.equal(Model.parseSnapshot("error\tline 2 has changed").error, "line 2 has changed")
    assert.deepEqual(Model.parseSnapshot("").tasks, [])
    assert.deepEqual(Model.parseSnapshot(null).tasks, [])
    assert.equal(Model.parseSnapshot("task\ta\tb").tasks.length, 0)
  })

  it("keeps a tab inside a task text", () => {
    const parsed = Model.parseSnapshot("task\t1\t0\t\t\t\tone\ttwo")
    assert.equal(parsed.tasks[0].text, "one\ttwo")
  })
})

describe("tags", () => {
  it("collects +projects and @contexts once each", () => {
    assert.deepEqual(Model.tags("Fix +web bug @laptop +web @laptop @home"), { projects: ["web"], contexts: ["laptop", "home"] })
    assert.deepEqual(Model.tags("nothing here"), { projects: [], contexts: [] })
    assert.deepEqual(Model.tags("+ @ lone signs"), { projects: [], contexts: [] })
    assert.deepEqual(Model.tags(""), { projects: [], contexts: [] })
  })
})

describe("stripTags", () => {
  it("drops tags and key:value pairs and tidies the spaces", () => {
    assert.equal(Model.stripTags("Call the bank @phone +admin"), "Call the bank")
    assert.equal(Model.stripTags("Write the report due:2026-09-10"), "Write the report")
    assert.equal(Model.stripTags("Meet at 10:30 tomorrow"), "Meet at 10:30 tomorrow")
    assert.equal(Model.stripTags("  spaced   out  "), "spaced out")
    assert.equal(Model.stripTags(""), "")
  })
})

describe("priorityRank", () => {
  it("ranks A first and no priority last", () => {
    assert.equal(Model.priorityRank("A"), 1)
    assert.equal(Model.priorityRank("C"), 3)
    assert.ok(Model.priorityRank("Z") < Model.priorityRank(""))
  })
})

describe("compareTasks", () => {
  it("puts pending before done, priorities in order, then file order", () => {
    assert.ok(Model.compareTasks(bank, domain) < 0)
    assert.ok(Model.compareTasks(domain, bank) > 0)
    assert.ok(Model.compareTasks(bank, report) < 0)
    assert.ok(Model.compareTasks(report, milk) < 0)
    assert.equal(Model.compareTasks(milk, milk), 0)
  })

  it("orders done tasks by completion date, newest first, then line", () => {
    assert.ok(Model.compareTasks(plants, domain) < 0)
    const sameDay = { done: true, completed: "2026-09-05", line: 9 }
    assert.ok(Model.compareTasks(sameDay, plants) < 0)
  })
})

describe("isLoaded", () => {
  it("needs a tasks array", () => {
    assert.equal(Model.isLoaded(snapshot), true)
    assert.equal(Model.isLoaded({ file: "" }), false)
    assert.equal(Model.isLoaded(null), false)
  })
})

describe("counts", () => {
  it("counts pending, done and priority A", () => {
    assert.deepEqual(Model.counts(snapshot), { pending: 3, done: 2, urgent: 1 })
    assert.deepEqual(Model.counts(empty), { pending: 0, done: 0, urgent: 0 })
    assert.deepEqual(Model.counts(null), { pending: 0, done: 0, urgent: 0 })
  })
})

describe("glyph", () => {
  it("is a ticked box for done and an empty one otherwise", () => {
    assert.equal(Model.glyph(domain), Model.GLYPHS.done)
    assert.equal(Model.glyph(milk), Model.GLYPHS.pending)
    assert.equal(Model.glyph(null), Model.GLYPHS.pending)
  })
})

describe("priorityTone", () => {
  it("colours A urgent, B accent, and nothing once done", () => {
    assert.equal(Model.priorityTone(bank), "urgent")
    assert.equal(Model.priorityTone(report), "accent")
    assert.equal(Model.priorityTone(milk), "normal")
    assert.equal(Model.priorityTone(domain), "normal")
    assert.equal(Model.priorityTone(null), "normal")
  })
})

describe("nextPriority", () => {
  it("cycles none, A, B, C, none and drops an outsider to none", () => {
    assert.equal(Model.nextPriority(""), "A")
    assert.equal(Model.nextPriority("A"), "B")
    assert.equal(Model.nextPriority("C"), "")
    assert.equal(Model.nextPriority("D"), "")
    assert.equal(Model.nextPriority(undefined), "A")
  })
})

describe("parseDay", () => {
  it("reads an ISO day and rejects anything else", () => {
    assert.equal(Model.parseDay("2026-09-05").getDate(), 5)
    assert.equal(Model.parseDay("05/09/2026"), null)
    assert.equal(Model.parseDay(""), null)
  })
})

describe("todayIso", () => {
  it("is today as an ISO day", () => {
    assert.match(Model.todayIso(), /^\d{4}-\d{2}-\d{2}$/)
    assert.equal(Model.parseDay(Model.todayIso()).getDate(), new Date().getDate())
  })
})

describe("formatAge", () => {
  it("names today and yesterday, counts days and weeks, then shows the date", () => {
    assert.equal(Model.formatAge("2026-09-05", TODAY), "today")
    assert.equal(Model.formatAge("2026-09-04", TODAY), "yesterday")
    assert.equal(Model.formatAge("2026-09-01", TODAY), "4d")
    assert.equal(Model.formatAge("2026-08-15", TODAY), "3w")
    assert.equal(Model.formatAge("2026-06-01", TODAY), "1 Jun")
    assert.equal(Model.formatAge("2026-09-09", TODAY), "today")
    assert.equal(Model.formatAge("", TODAY), "")
  })
})

describe("taskDetail", () => {
  it("lists tags, then the age or the tick", () => {
    assert.equal(Model.taskDetail(milk, TODAY), "+groceries · @errands · added 4d")
    assert.equal(Model.taskDetail(bank, TODAY), "+admin · @phone")
    assert.equal(Model.taskDetail(domain, TODAY), "+admin · done 2d")
    assert.equal(Model.taskDetail(plants, TODAY), "done today")
    assert.equal(Model.taskDetail({ done: true, projects: [], contexts: [], completed: "" }, TODAY), "done")
    assert.equal(Model.taskDetail(null), "")
  })
})

describe("barText", () => {
  it("shows the count left, or the icon alone", () => {
    assert.equal(Model.barText(snapshot, "pending", false), `${Model.ICON} 3`)
    assert.equal(Model.barText(snapshot, "none", false), Model.ICON)
    assert.equal(Model.barText(snapshot, "pending", true), Model.ICON)
    assert.equal(Model.barText(empty, "pending", false), Model.ICON)
    assert.equal(Model.barText(null, "pending", false), Model.ICON)
  })
})

describe("tooltip", () => {
  it("summarises the counts or the failure", () => {
    assert.equal(Model.tooltip(snapshot), "To do · 3 to do · 1 urgent · 2 done")
    assert.equal(Model.tooltip(Model.parseSnapshot("task\t1\t0\t\t\t\tOne")), "To do · 1 to do")
    assert.equal(Model.tooltip(empty), "To do · nothing yet")
    assert.equal(Model.tooltip(Model.parseSnapshot("error\tboom")), "To do: boom")
    assert.equal(Model.tooltip(null), "To do")
  })
})

describe("heroStatus", () => {
  it("counts what is left and flags the urgent ones", () => {
    assert.equal(Model.heroStatus(snapshot), "3 LEFT · 1 URGENT")
    assert.equal(Model.heroStatus(Model.parseSnapshot("task\t1\t1\t\t\t2026-09-05\tOne")), "ALL DONE")
    assert.equal(Model.heroStatus(empty), "NOTHING YET")
    assert.equal(Model.heroStatus(null), "LOADING")
  })
})

describe("visibleRows", () => {
  it("puts what is left under TO DO and the latest ticks under DONE", () => {
    const rows = Model.visibleRows(snapshot, 5)
    assert.deepEqual(rows.map((r) => r.header ? `${r.title} ${r.count}` : r.line), ["TO DO 3", 2, 4, 1, "DONE 2", 5, 3])
  })

  it("caps the done group and says so in the header", () => {
    const rows = Model.visibleRows(snapshot, 1)
    const header = rows.find((r) => r.header && r.key === "done")
    assert.equal(header.shown, 1)
    assert.equal(header.count, 2)
    assert.deepEqual(rows.filter((r) => !r.header && r.done).map((r) => r.line), [5])
    assert.equal(Model.visibleRows(snapshot, 0).some((r) => r.header && r.key === "done"), false)
    assert.equal(Model.visibleRows(snapshot, "abc").filter((r) => r.done).length, 2)
  })

  it("is empty without tasks", () => {
    assert.deepEqual(Model.visibleRows(empty, 5), [])
    assert.deepEqual(Model.visibleRows(null, 5), [])
  })
})

describe("isHeader", () => {
  it("only marks header rows", () => {
    assert.equal(Model.isHeader({ header: true }), true)
    assert.equal(Model.isHeader(milk), false)
    assert.equal(Model.isHeader(null), false)
  })
})

describe("nextRowIndex", () => {
  it("walks over headers and wraps", () => {
    const rows = Model.visibleRows(snapshot, 5)
    assert.equal(Model.nextRowIndex(rows, 0, 1), 1)
    assert.equal(Model.nextRowIndex(rows, 3, 1), 5)
    assert.equal(Model.nextRowIndex(rows, 1, -1), rows.length - 1)
    assert.equal(Model.nextRowIndex([], 0, 1), -1)
    assert.equal(Model.nextRowIndex([{ header: true }], 0, 1), -1)
  })
})

describe("firstRowIndex", () => {
  it("is the first non-header row", () => {
    assert.equal(Model.firstRowIndex(Model.visibleRows(snapshot, 5)), 1)
    assert.equal(Model.firstRowIndex([]), -1)
  })
})

// todo.sh against a scratch file. `today` is whatever the machine says, so
// the assertions read it back rather than pin it.
describe("todo.sh", () => {
  const today = new Date().toISOString().slice(0, 10)

  function setup(t, lines = null) {
    const dir = tmpdir(t)
    const file = path.join(dir, "todo.txt")
    if (lines !== null) fs.writeFileSync(file, lines.join("\n") + (lines.length ? "\n" : ""))
    const run = (args) => runScript("joamag.todo", "todo.sh", args, { env: { TODO_FILE: file } })
    const list = (args) => Model.parseSnapshot(run(args).stdout)
    const raw = () => fs.readFileSync(file, "utf8")
    return { dir, file, run, list, raw }
  }

  it("creates the file on first use and lists nothing", (t) => {
    const { file, run } = setup(t)
    const result = run(["list"])
    assert.equal(result.status, 0)
    assert.equal(result.stdout, `file\t${file}\n`)
    assert.equal(fs.existsSync(file), true)
    assert.equal(fs.readFileSync(file, "utf8"), "")
  })

  it("parses every shape a todo.txt line comes in", (t) => {
    const { list } = setup(t, [
      "x 2026-09-03 2026-09-02 Renew the domain +admin pri:B",
      "x 2026-09-05 Water the plants",
      "x Bare done line",
      "(A) 2026-09-05 Call the bank @phone",
      "(B) No date",
      "2026-09-01 Date only",
      "Plain",
      "",
      "   ",
      "x 2026-09-04 pri:C Tag in front",
      "tab\there",
    ])
    const tasks = list(["list"]).tasks.sort((a, b) => a.line - b.line)
    assert.deepEqual(tasks.map((x) => [x.line, x.done, x.priority, x.created, x.completed, x.text]), [
      [1, true, "B", "2026-09-02", "2026-09-03", "Renew the domain +admin"],
      [2, true, "", "", "2026-09-05", "Water the plants"],
      [3, true, "", "", "", "Bare done line"],
      [4, false, "A", "2026-09-05", "", "Call the bank @phone"],
      [5, false, "B", "", "", "No date"],
      [6, false, "", "2026-09-01", "", "Date only"],
      [7, false, "", "", "", "Plain"],
      [10, true, "C", "", "2026-09-04", "Tag in front"],
      [11, false, "", "", "", "tab here"],
    ])
  })

  it("adds a task dated today, keeping a typed priority in front", (t) => {
    const { list, raw } = setup(t, [])
    assert.equal(list(["add", "  Buy milk +groceries  "]).tasks[0].text, "Buy milk +groceries")
    list(["add", "(A) Call the bank @phone"])
    assert.equal(raw(), `${today} Buy milk +groceries\n(A) ${today} Call the bank @phone\n`)
  })

  it("signs a task with --by and never twice", (t) => {
    const { list, raw, run } = setup(t, [])
    assert.equal(list(["add", "--by", "claude", "Review the PR +omarchy"]).tasks[0].contexts.join(), "claude")
    list(["add", "--by", "claude", "Already signed @claude"])
    list(["add", "--by", "c l/a;u de", "Odd name"])
    assert.equal(raw(), `${today} Review the PR +omarchy @claude\n${today} Already signed @claude\n${today} Odd name @claude\n`)
    assert.equal(run(["add", "--by", "", "No name"]).stdout, "error\t--by needs a name\n")
    assert.equal(run(["add", "--by", "claude"]).stdout, "error\tnothing to add\n")
  })

  it("refuses to add nothing", (t) => {
    const { run, raw } = setup(t, [])
    assert.equal(run(["add", "   "]).stdout, "error\tnothing to add\n")
    assert.equal(raw(), "")
  })

  it("ticks a task the todo.txt way and unticks it back exactly", (t) => {
    const { list, raw } = setup(t, ["(A) 2026-09-01 Call the bank @phone", "Plain"])
    const ticked = list(["toggle", "1", "Call the bank @phone"]).tasks.find((x) => x.line === 1)
    assert.equal(raw().split("\n")[0], `x ${today} 2026-09-01 Call the bank @phone pri:A`)
    assert.equal(ticked.done, true)
    assert.equal(ticked.priority, "A")
    assert.equal(ticked.completed, today)
    list(["toggle", "1", "Call the bank @phone"])
    assert.equal(raw(), "(A) 2026-09-01 Call the bank @phone\nPlain\n")
    list(["toggle", "2", "Plain"])
    assert.equal(raw().split("\n")[1], `x ${today} Plain`)
  })

  it("refuses an edit to a line that no longer says what the popup thinks", (t) => {
    const { run, raw } = setup(t, ["Buy milk", "Call the bank"])
    const before = raw()
    assert.equal(run(["toggle", "1", "Call the bank"]).stdout, "error\tline 1 has changed; the list was refreshed\n")
    assert.equal(run(["toggle", "3", "Anything"]).stdout, "error\tline 3 is gone; the list was refreshed\n")
    assert.equal(run(["toggle", "zero", "Buy milk"]).stdout, "error\tline number required\n")
    assert.equal(run(["toggle", "0", "Buy milk"]).stdout, "error\tline number required\n")
    assert.equal(raw(), before)
  })

  it("deletes exactly the named line", (t) => {
    const { list, raw } = setup(t, ["One", "Two", "Three"])
    const tasks = list(["remove", "2", "Two"]).tasks.map((x) => x.text)
    assert.deepEqual(tasks, ["One", "Three"])
    assert.equal(raw(), "One\nThree\n")
  })

  it("sets, changes and clears a priority, on done lines too", (t) => {
    const { list, raw, run } = setup(t, ["2026-09-01 Plain", "x 2026-09-03 Done thing"])
    list(["priority", "1", "Plain", "B"])
    assert.equal(raw().split("\n")[0], "(B) 2026-09-01 Plain")
    list(["priority", "1", "Plain", "A"])
    assert.equal(raw().split("\n")[0], "(A) 2026-09-01 Plain")
    list(["priority", "1", "Plain", "-"])
    assert.equal(raw().split("\n")[0], "2026-09-01 Plain")
    list(["priority", "2", "Done thing", "C"])
    assert.equal(raw().split("\n")[1], "x 2026-09-03 Done thing pri:C")
    assert.equal(list(["list"]).tasks.find((x) => x.line === 2).priority, "C")
    list(["priority", "2", "Done thing", "-"])
    assert.equal(raw().split("\n")[1], "x 2026-09-03 Done thing")
    assert.equal(run(["priority", "1", "Plain", "urgent"]).stdout, "error\tpriority must be a letter or -\n")
  })

  it("archives the ticked tasks into done.txt and keeps the rest", (t) => {
    const { dir, list, raw } = setup(t, ["x 2026-09-03 Old", "Keep me", "x 2026-09-05 Newer"])
    assert.deepEqual(list(["archive"]).tasks.map((x) => x.text), ["Keep me"])
    assert.equal(raw(), "Keep me\n")
    assert.equal(fs.readFileSync(path.join(dir, "done.txt"), "utf8"), "x 2026-09-03 Old\nx 2026-09-05 Newer\n")
    list(["toggle", "1", "Keep me"])
    list(["archive"])
    assert.equal(fs.readFileSync(path.join(dir, "done.txt"), "utf8"), `x 2026-09-03 Old\nx 2026-09-05 Newer\nx ${today} Keep me\n`)
    assert.equal(raw(), "")
  })

  it("leaves no lock or temporary file behind", (t) => {
    const { dir, list } = setup(t, ["One"])
    list(["add", "Two"])
    list(["toggle", "1", "One"])
    list(["archive"])
    assert.deepEqual(fs.readdirSync(dir).sort(), ["done.txt", "todo.txt"])
  })

  it("rejects a bad invocation", (t) => {
    const { run } = setup(t, [])
    const result = run(["bogus"])
    assert.equal(result.status, 1)
    assert.match(result.stderr, /Usage: todo.sh/)
  })
})

// The MCP server, in process for the handlers and over stdio for the
// transport, against a scratch todo.txt each time.
describe("mcp.js", () => {
  function scratch(t, lines = []) {
    const dir = tmpdir(t)
    const file = path.join(dir, "todo.txt")
    fs.writeFileSync(file, lines.join("\n") + (lines.length ? "\n" : ""))
    const previous = { file: process.env.TODO_FILE, author: process.env.TODO_AUTHOR }
    process.env.TODO_FILE = file
    delete process.env.TODO_AUTHOR
    t.after(() => {
      if (previous.file === undefined) delete process.env.TODO_FILE; else process.env.TODO_FILE = previous.file
      if (previous.author === undefined) delete process.env.TODO_AUTHOR; else process.env.TODO_AUTHOR = previous.author
    })
    return { file, raw: () => fs.readFileSync(file, "utf8") }
  }

  const call = (name, args) => mcp.handle({ jsonrpc: "2.0", id: 9, method: "tools/call", params: { name, arguments: args } }).result

  it("initialises with the client's protocol version, or its own", () => {
    const reply = mcp.handle({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {} } })
    assert.equal(reply.id, 1)
    assert.equal(reply.result.protocolVersion, "2024-11-05")
    assert.deepEqual(reply.result.capabilities, { tools: {} })
    assert.equal(reply.result.serverInfo.name, "joamag-todo")
    assert.equal(mcp.handle({ jsonrpc: "2.0", id: 2, method: "initialize" }).result.protocolVersion, mcp.PROTOCOL)
  })

  it("answers ping, ignores notifications and rejects the rest", () => {
    assert.deepEqual(mcp.handle({ jsonrpc: "2.0", id: 3, method: "ping" }).result, {})
    assert.equal(mcp.handle({ jsonrpc: "2.0", method: "notifications/initialized" }), null)
    assert.equal(mcp.handle({ jsonrpc: "2.0", id: 4, method: "resources/list" }).error.code, -32601)
    assert.equal(mcp.handle({ id: 5, method: "ping" }).error.code, -32600)
    assert.equal(mcp.handle(null).error.code, -32600)
  })

  it("lists three tools with the arguments they need", () => {
    const tools = mcp.handle({ jsonrpc: "2.0", id: 6, method: "tools/list" }).result.tools
    assert.deepEqual(tools.map((tool) => tool.name), ["todo_add", "todo_list", "todo_complete"])
    assert.deepEqual(tools[0].inputSchema.required, ["text"])
    assert.deepEqual(tools[2].inputSchema.required, ["line", "text"])
    assert.match(tools[0].description, /@claude/)
  })

  it("adds a task signed as claude, with a priority when asked", (t) => {
    const { raw } = scratch(t)
    const reply = call("todo_add", { text: "Renew the domain +admin", priority: "b" })
    assert.equal(reply.isError, false)
    assert.match(reply.content[0].text, /^Added on line 1: Renew the domain \+admin @claude/)
    assert.match(raw(), /^\(B\) \d{4}-\d{2}-\d{2} Renew the domain \+admin @claude\n$/)
  })

  it("signs as whoever the call or the environment says", (t) => {
    const { raw } = scratch(t)
    call("todo_add", { text: "From a colleague", by: "codex" })
    process.env.TODO_AUTHOR = "assistant"
    call("todo_add", { text: "From the environment" })
    call("todo_add", { text: "Left alone @assistant" })
    assert.deepEqual(raw().split("\n").filter(Boolean).map((l) => l.replace(/^\S+ /, "")), ["From a colleague @codex", "From the environment @assistant", "Left alone @assistant"])
  })

  it("refuses a bad add without touching the file", (t) => {
    const { raw } = scratch(t)
    assert.equal(call("todo_add", { text: "  " }).isError, true)
    assert.equal(call("todo_add", { text: "x", priority: "urgent" }).isError, true)
    assert.equal(call("todo_add", {}).isError, true)
    assert.equal(raw(), "")
  })

  it("lists the tasks with their line numbers, or says the list is empty", (t) => {
    scratch(t, ["(A) 2026-09-01 Call the bank @phone", "Plain", "x 2026-09-03 Done thing"])
    const listing = call("todo_list", {}).content[0].text
    assert.equal(listing, "TO DO (2)\n  [ ] (A) Call the bank  @phone  (line 1)\n  [ ] Plain  (line 2)\nDONE (1)\n  [x] Done thing  (line 3)")
    scratch(t)
    assert.equal(call("todo_list", {}).content[0].text, "The list is empty.")
  })

  it("ticks a task by line and text, the title without tags being enough", (t) => {
    const { raw } = scratch(t, ["Call the bank @phone +admin", "Plain"])
    const reply = call("todo_complete", { line: 1, text: "Call the bank" })
    assert.equal(reply.isError, false)
    assert.match(raw().split("\n")[0], /^x \d{4}-\d{2}-\d{2} Call the bank @phone \+admin$/)
    assert.match(reply.content[0].text, /^Done: Call the bank @phone \+admin/)
  })

  it("refuses to tick the wrong line, a done line or a bad line", (t) => {
    const { raw } = scratch(t, ["One", "x 2026-09-03 Two"])
    const before = raw()
    assert.match(call("todo_complete", { line: 1, text: "Something else" }).content[0].text, /line 1 has changed/)
    assert.match(call("todo_complete", { line: 2, text: "Two" }).content[0].text, /already done/)
    assert.equal(call("todo_complete", { line: 0, text: "One" }).isError, true)
    assert.equal(call("todo_complete", { line: "one", text: "One" }).isError, true)
    assert.equal(call("todo_complete", { line: 1.5, text: "One" }).isError, true)
    assert.equal(call("todo_complete", { line: 1, text: "" }).isError, true)
    assert.equal(call("todo_complete", { line: 9, text: "One" }).isError, true)
    assert.equal(raw(), before)
  })

  it("takes the line number as a numeric string, as a model may hand it back", (t) => {
    const { raw } = scratch(t, ["One"])
    assert.equal(call("todo_complete", { line: "1", text: "One" }).isError, false)
    assert.match(raw(), /^x /)
  })

  it("names an unknown tool as an error", () => {
    assert.equal(call("todo_delete", {}).isError, true)
  })

  it("speaks newline-delimited JSON-RPC over stdio", async (t) => {
    const { file } = scratch(t)
    const child = spawn(process.execPath, [path.join(__dirname, "..", "plugins", "joamag.todo", "mcp.js")], { env: { ...process.env, TODO_FILE: file }, stdio: ["pipe", "pipe", "inherit"] })
    t.after(() => child.kill())
    let out = ""
    child.stdout.on("data", (chunk) => { out += chunk })
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: mcp.PROTOCOL } }) + "\n")
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n")
    child.stdin.write("this is not json\n")
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "todo_add", arguments: { text: "Over the wire" } } }) + "\n")
    child.stdin.end()
    await new Promise((resolve) => child.on("close", resolve))
    const replies = out.trim().split("\n").map((line) => JSON.parse(line))
    assert.deepEqual(replies.map((r) => r.id), [1, null, 2])
    assert.equal(replies[1].error.code, -32700)
    assert.equal(replies[2].result.isError, false)
    assert.match(fs.readFileSync(file, "utf8"), /Over the wire @claude\n$/)
  })
})
