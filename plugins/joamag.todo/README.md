# joamag.todo

A to-do list for the Omarchy bar: the number of tasks left next to a checkbox, and a popup that lists what is left first, in priority order, with the latest ticks after it. Tick, add, prioritise, delete and archive from the popup, or just edit the file.

The list is a plain [todo.txt](http://todotxt.org) file, `~/.local/share/omarchy/todo.txt` by default, created the first time the widget runs. One task per line; `x` and a date in front of a done one; `(A)`, `(B)`, `(C)` for a priority; a leading date for when it was added; `+project` and `@context` anywhere. Nothing else is stored, so any todo.txt app or a text editor sees the same list, and the widget notices a change on disk within a beat.

```
(A) 2026-09-05 Call the bank @phone +admin
2026-09-05 Buy milk +groceries @errands
x 2026-09-05 2026-09-04 Renew the domain +admin pri:B
```

## Interactions

- Left click on the bar: open the popup. Middle click: refresh. Right click: open the file in your editor.
- Click a task (or press Enter on it) to tick or untick it. Right click, or `x`, deletes it: the first press arms the row, a second within four seconds deletes.
- `a` (or the Add button) opens a field at the bottom of the list: type a task and press Enter, as many as you like, Esc when done. `(A) Call the bank @phone` sets the priority and tags on the way in.
- `p` cycles a task's priority through none, A, B, C. `A` (shift) archives: every ticked task moves to `done.txt` next to the file, after a confirming second press.
- `j`/`k` move over rows and the footer actions, `r` refreshes, `e` opens the file, Esc closes, Tab switches to the neighbouring panel.

Ticking keeps the todo.txt conventions: `x` and today's date go in front, the creation date stays, and a priority is kept as a `pri:A` tag so unticking restores it. Every edit names the line by number *and* by text, so a line that has changed under the widget (an editor saved meanwhile) is refused with a note rather than overwritten, and the list refreshes.

## Letting an LLM add to the list

Two ways in, both leaving a visible signature on the task.

**MCP server.** `mcp.js` is a zero-dependency MCP server over stdio with three tools: `todo_add`, `todo_list` and `todo_complete`. Every task it adds is signed with an `@claude` context (or whatever `TODO_AUTHOR` says, or the call's `by`), so the popup shows who put it there and the file keeps it.

Give it a launcher on your PATH first: clients started from the desktop (VS Code, a chat app) do not see a shell's PATH, so `node` from mise is not there. A four-line script does it:

```bash
cat > ~/.local/bin/todo-mcp <<'EOF'
#!/bin/bash
server="$HOME/.config/omarchy/plugins/joamag.todo/mcp.js"
node=$(command -v node 2>/dev/null || true); [[ -n $node ]] || node="$HOME/.local/share/mise/shims/node"
exec "$node" "$server" "$@"
EOF
chmod +x ~/.local/bin/todo-mcp
```

Then register it once per client:

```bash
claude mcp add --scope user todo -- ~/.local/bin/todo-mcp     # Claude Code
codex mcp add todo -- ~/.local/bin/todo-mcp                    # Codex
gemini mcp add -s user todo ~/.local/bin/todo-mcp              # Gemini CLI
```

VS Code takes `{"type": "stdio", "command": "~/.local/bin/todo-mcp"}` under `servers` in `~/.config/Code/User/mcp.json`; OpenCode takes `{"type": "local", "command": ["~/.local/bin/todo-mcp"], "enabled": true}` under `mcp` in `~/.config/opencode/opencode.json` (both want the path spelled out, not `~`). Claude Desktop, Cursor and the rest take the same command in their MCP configuration. The tool descriptions say when to reach for them ("remember", "remind me", "follow up", "put on my list"), so a session that has the server uses it without being told. Deleting is deliberately not exposed; `todo_complete` ticks, and only a line whose text still matches.

**Command line.** `todo.sh add --by claude "Renew the domain +admin"` appends the same signature; the IPC `omarchy-shell joamag.todo add` takes plain text.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `file` | `""` | The todo.txt file; empty is `~/.local/share/omarchy/todo.txt` |
| `barMode` | `"pending"` | `pending` shows the count of tasks left, `none` shows the icon alone |
| `hideWhenEmpty` | `false` | Hide the widget while nothing is left to do |
| `doneLimit` | `5` | Done tasks kept visible in the popup, newest first; `0` hides them |
| `refreshIntervalSec` | `60` | Fallback refresh cadence; the file itself is watched |

## IPC

```
omarchy-shell joamag.todo toggle
omarchy-shell joamag.todo refresh
omarchy-shell joamag.todo add "Buy milk +groceries"
omarchy-shell joamag.todo version
```

## Data source

`todo.sh` reads and rewrites the file: `list` for the popup, `add` (with `--by NAME` to sign), `toggle`, `remove`, `priority` and `archive` for the edits, each answering with the fresh listing. `mcp.js` only ever calls it, so the file has one writer. Rewrites take a lock next to the file and replace it whole, so two writers cannot tear it. `TODO_FILE` overrides the path for scripts and tests.
