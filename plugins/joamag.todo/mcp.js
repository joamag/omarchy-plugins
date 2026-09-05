#!/usr/bin/env node

// An MCP server for the to-do list, so any LLM client can add to it: three
// tools over stdio, each a thin call into todo.sh, so the file is only ever
// written by the one script. No dependencies: the stdio transport is
// newline-delimited JSON-RPC 2.0, which is small enough to speak by hand.
//
//   node mcp.js                      serve on stdin/stdout
//   TODO_AUTHOR=claude               the @context every added task is signed
//                                    with, unless the call says otherwise
//   TODO_FILE=...                    passed through to todo.sh
//
// Register with Claude Code:  claude mcp add todo -- node /path/to/mcp.js

const fs = require("node:fs")
const path = require("node:path")
const readline = require("node:readline")
const vm = require("node:vm")
const { spawnSync } = require("node:child_process")

const VERSION = "0.1.0"
const PROTOCOL = "2025-06-18"
const SCRIPT = path.join(__dirname, "todo.sh")

// Model.js is a QML `.pragma library`: no module system, every top-level
// function a global. Evaluated the way the tests do it, so the listing is
// parsed and ordered exactly as the popup shows it.
function loadModel() {
  const file = path.join(__dirname, "Model.js")
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library[^\n]*/, "")
  const names = [...source.matchAll(/^(?:function|var) (\w+)/gm)].map((m) => m[1])
  return new vm.Script(`(function () {${source}\nreturn { ${names.join(", ")} }\n})()`, { filename: file }).runInThisContext()
}

const Model = loadModel()

function author() {
  return String(process.env.TODO_AUTHOR || "claude")
}

function runTodo(args) {
  const result = spawnSync(SCRIPT, args, { encoding: "utf8", env: process.env })
  if (result.error) return { error: `could not run todo.sh: ${result.error.message}`, snapshot: null }
  const snapshot = Model.parseSnapshot(result.stdout)
  if (result.status !== 0 && !snapshot.error) snapshot.error = `todo.sh exited ${result.status}`
  return { error: snapshot.error, snapshot }
}

// The listing as text an LLM can act on: one line per task with its line
// number, so todo_complete can name it back.
function describe(snapshot) {
  const rows = Model.visibleRows(snapshot, 1000)
  if (rows.length === 0) return "The list is empty."
  const lines = []
  for (const row of rows) {
    if (Model.isHeader(row)) { lines.push(`${row.title} (${row.count})`); continue }
    const box = row.done ? "[x]" : "[ ]"
    const pri = row.priority ? `(${row.priority}) ` : ""
    const tags = [...row.projects.map((p) => `+${p}`), ...row.contexts.map((c) => `@${c}`)].join(" ")
    lines.push(`  ${box} ${pri}${row.title}${tags ? "  " + tags : ""}  (line ${row.line})`)
  }
  return lines.join("\n")
}

const TOOLS = [
  {
    name: "todo_add",
    description:
      "Add a task to the user's to-do list (the To do widget in their Omarchy bar, a todo.txt file). "
      + "Use it when the user asks to remember something, be reminded later, note a follow-up, or put something on their list. "
      + "Write the task the way the user would, short and in their words. Tags: +project for a project, @context for where or how. "
      + `Every task added here is signed with @${author()} so the user can see who added it.`,
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string", description: "The task, e.g. \"Renew the domain +admin\"" },
        priority: { type: "string", enum: ["A", "B", "C"], description: "A for urgent, B for soon, C for whenever; leave out for none" },
        by: { type: "string", description: `Who is adding it; defaults to ${author()}` },
      },
      required: ["text"],
    },
  },
  {
    name: "todo_list",
    description: "List the user's to-do tasks: what is still to do first, in priority order, then the latest ones ticked, each with its line number.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "todo_complete",
    description:
      "Tick a task as done. Pass the line number and the exact task text as todo_list showed them; "
      + "the tick is refused if the file changed in between, in which case list again.",
    inputSchema: {
      type: "object",
      properties: {
        line: { type: "integer", description: "The line number from todo_list" },
        text: { type: "string", description: "The task text as the file has it, without the [ ] box, priority or line number" },
      },
      required: ["line", "text"],
    },
  },
]

function text(content, isError = false) {
  return { content: [{ type: "text", text: content }], isError }
}

function callTool(name, args) {
  const a = args && typeof args === "object" ? args : {}
  switch (name) {
  case "todo_add": {
    let task = String(a.text || "").trim()
    if (task === "") return text("todo_add needs a task text", true)
    const priority = String(a.priority || "").toUpperCase()
    if (priority !== "" && !/^[A-Z]$/.test(priority)) return text("priority must be a single letter", true)
    if (priority !== "" && !/^\([A-Z]\) /.test(task)) task = `(${priority}) ${task}`
    const by = String(a.by || author()).replace(/[^A-Za-z0-9_.-]/g, "")
    const { error, snapshot } = runTodo(by ? ["add", "--by", by, task] : ["add", task])
    if (error) return text(error, true)
    const added = snapshot.tasks.reduce((best, t) => (!best || t.line > best.line ? t : best), null)
    return text(`Added${added ? ` on line ${added.line}` : ""}: ${added ? added.text : task}\n\n${describe(snapshot)}`)
  }
  case "todo_list": {
    const { error, snapshot } = runTodo(["list"])
    if (error) return text(error, true)
    return text(describe(snapshot))
  }
  case "todo_complete": {
    const line = Number(a.line)
    const taskText = String(a.text || "").trim()
    if (!Number.isInteger(line) || line < 1) return text("line must be a positive integer", true)
    if (taskText === "") return text("text is required", true)
    const before = runTodo(["list"])
    const target = before.snapshot ? before.snapshot.tasks.find((t) => t.line === line) : null
    if (target && target.done) return text(`Line ${line} is already done.`, true)
    // The exact text as the file has it is what the guard compares, but an
    // LLM will often hand back the title without its tags; either is accepted
    // when it names the same task.
    const exact = target && (target.text === taskText || target.title === taskText) ? target.text : taskText
    const { error, snapshot } = runTodo(["toggle", String(line), exact])
    if (error) return text(error, true)
    return text(`Done: ${exact}\n\n${describe(snapshot)}`)
  }
  default:
    return text(`unknown tool ${name}`, true)
  }
}

function response(id, result) {
  return { jsonrpc: "2.0", id, result }
}

function failure(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } }
}

// One JSON-RPC message in, one out; null for a notification, which gets no
// reply.
function handle(message) {
  if (!message || typeof message !== "object" || message.jsonrpc !== "2.0") return failure(null, -32600, "invalid request")
  const { id, method, params } = message
  const isNotification = id === undefined
  switch (method) {
  case "initialize":
    return response(id, {
      protocolVersion: params && typeof params.protocolVersion === "string" ? params.protocolVersion : PROTOCOL,
      capabilities: { tools: {} },
      serverInfo: { name: "joamag-todo", version: VERSION },
    })
  case "ping":
    return response(id, {})
  case "tools/list":
    return response(id, { tools: TOOLS })
  case "tools/call":
    return response(id, callTool(params && params.name, params && params.arguments))
  default:
    if (isNotification) return null
    return failure(id, -32601, `method not found: ${method}`)
  }
}

function serve(input = process.stdin, output = process.stdout) {
  const lines = readline.createInterface({ input, crlfDelay: Infinity })
  lines.on("line", (line) => {
    if (line.trim() === "") return
    let message
    try {
      message = JSON.parse(line)
    } catch (e) {
      output.write(JSON.stringify(failure(null, -32700, "parse error")) + "\n")
      return
    }
    const reply = handle(message)
    if (reply) output.write(JSON.stringify(reply) + "\n")
  })
}

if (require.main === module) serve()

module.exports = { handle, callTool, describe, TOOLS, VERSION, PROTOCOL }
