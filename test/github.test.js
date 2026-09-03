// Tests for joamag.github: Model.js in declaration order, then radar.sh.

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { loadModel, FIXTURES, runJson, runScript, tmpdir, fakeCommand } = require("./helpers")

const Model = loadModel("joamag.github")

const HOUR = 3600 * 1000
const iso = (msAgo) => new Date(Date.now() - msAgo).toISOString()

const PASSING = { kind: "pull", repo: "hivesolutions/netius", number: 127, title: "fix: stop following a link", url: "https://github.com/hivesolutions/netius/pull/127", author: "joamag", updatedAt: iso(HOUR), draft: false, ci: "SUCCESS", review: "" }
const FAILING = { kind: "pull", repo: "joamag/boytacean", number: 9, title: "feat: audio", url: "u", author: "joamag", updatedAt: iso(2 * HOUR), draft: false, ci: "FAILURE", review: "" }
const CHANGES = { kind: "pull", repo: "joamag/isabella", number: 8, title: "feat: digest", url: "u", author: "joamag", updatedAt: iso(26 * HOUR), draft: false, ci: "SUCCESS", review: "CHANGES_REQUESTED" }
const APPROVED = { kind: "pull", repo: "joamag/isabella", number: 7, title: "feat: playbooks", url: "u", author: "joamag", updatedAt: iso(40 * 86400 * 1000), draft: false, ci: "PENDING", review: "APPROVED" }
const DRAFT = { kind: "pull", repo: "hivesolutions/omni-facet", number: 3, title: "wip", url: "u", author: "joamag", updatedAt: iso(400 * 86400 * 1000), draft: true, ci: "FAILURE", review: "" }
const PLAIN = { kind: "pull", repo: "acme/api", number: 1, title: "no checks", url: "u", author: "someone", updatedAt: iso(30 * 1000), draft: false, ci: "", review: "REVIEW_REQUIRED" }
const ISSUE = { kind: "issue", repo: "hivesolutions/viriatum", number: 77, title: "Close the listing gaps", url: "u", author: "joamag", updatedAt: iso(HOUR) }
const NOTIFICATION = { kind: "notification", id: "101", repo: "hivesolutions/netius", title: "Add retry", type: "PullRequest", reason: "review_requested", url: "u", updatedAt: iso(HOUR) }

const SNAPSHOT = {
  state: "ok", login: "joamag", fetchedAt: Math.floor(Date.now() / 1000) - 120,
  reviews: { total: 1, items: [PLAIN] },
  pulls: { total: 32, items: [PASSING, FAILING, CHANGES, APPROVED, DRAFT] },
  issues: { total: 161, items: [ISSUE] },
  notifications: { total: 3, items: [NOTIFICATION] },
}
const QUIET = { state: "ok", login: "joamag", fetchedAt: 1, reviews: { total: 0, items: [] }, pulls: { total: 2, items: [PASSING] }, issues: { total: 0, items: [] }, notifications: { total: 0, items: [] } }
const ALL = { showReviews: true, showPulls: true, showIssues: true, showNotifications: true }

describe("parseSnapshot", () => {
  it("accepts an envelope with a state and rejects anything else", () => {
    assert.equal(Model.parseSnapshot(JSON.stringify(SNAPSHOT)).login, "joamag")
    assert.deepEqual(Model.parseSnapshot("garbage"), { state: "error", error: "GitHub returned no data" })
    assert.deepEqual(Model.parseSnapshot('{"login":"x"}'), { state: "error", error: "GitHub returned no data" })
  })
})

describe("isOk", () => {
  it("requires the ok state", () => {
    assert.equal(Model.isOk(SNAPSHOT), true)
    assert.equal(Model.isOk({ state: "error" }), false)
    assert.equal(Model.isOk(null), false)
  })
})

describe("section", () => {
  it("normalises totals and items, empty when missing", () => {
    assert.equal(Model.section(SNAPSHOT, "pulls").total, 32)
    assert.deepEqual(Model.section(SNAPSHOT, "nothing"), { total: 0, items: [] })
    assert.deepEqual(Model.section({ state: "ok", pulls: { total: "x" } }, "pulls"), { total: 0, items: [] })
    assert.deepEqual(Model.section(null, "pulls"), { total: 0, items: [] })
  })
})

describe("ciFailed", () => {
  it("covers FAILURE and ERROR", () => {
    assert.equal(Model.ciFailed(FAILING), true)
    assert.equal(Model.ciFailed({ ci: "error" }), true)
    assert.equal(Model.ciFailed(PASSING), false)
    assert.equal(Model.ciFailed(null), false)
  })
})

describe("ciPending", () => {
  it("covers PENDING and EXPECTED", () => {
    assert.equal(Model.ciPending(APPROVED), true)
    assert.equal(Model.ciPending({ ci: "EXPECTED" }), true)
    assert.equal(Model.ciPending(PASSING), false)
  })
})

describe("changesRequested", () => {
  it("reads the review decision", () => {
    assert.equal(Model.changesRequested(CHANGES), true)
    assert.equal(Model.changesRequested(PASSING), false)
  })
})

describe("failingPulls", () => {
  it("counts red checks and requested changes, ignoring drafts", () => {
    assert.equal(Model.failingPulls(SNAPSHOT), 2)
    assert.equal(Model.failingPulls(QUIET), 0)
    assert.equal(Model.failingPulls(null), 0)
  })
})

describe("attentionCount", () => {
  it("sums reviews, failing PRs and notifications, never issues", () => {
    assert.equal(Model.attentionCount(SNAPSHOT, ALL), 6)
    assert.equal(Model.attentionCount(SNAPSHOT, { ...ALL, showReviews: false }), 5)
    assert.equal(Model.attentionCount(SNAPSHOT, { ...ALL, showPulls: false }), 4)
    assert.equal(Model.attentionCount(SNAPSHOT, { ...ALL, showNotifications: false }), 3)
    assert.equal(Model.attentionCount(SNAPSHOT, null), 6)
    assert.equal(Model.attentionCount({ state: "error" }, ALL), 0)
  })
})

describe("hasFailures", () => {
  it("is true while any own PR needs work", () => {
    assert.equal(Model.hasFailures(SNAPSHOT), true)
    assert.equal(Model.hasFailures(QUIET), false)
  })
})

describe("barText", () => {
  it("adds the count only when something needs attention", () => {
    assert.equal(Model.barText(SNAPSHOT, ALL, false), `${Model.ICON} 6`)
    assert.equal(Model.barText(QUIET, ALL, false), Model.ICON)
    assert.equal(Model.barText(SNAPSHOT, ALL, true), Model.ICON)
    assert.equal(Model.barText({ state: "error" }, ALL, false), Model.ICON)
  })
})

describe("tooltip", () => {
  it("describes the failing states", () => {
    assert.equal(Model.tooltip(null, ALL), "GitHub")
    assert.equal(Model.tooltip({ state: "missing" }, ALL), "GitHub CLI (gh) is not installed")
    assert.equal(Model.tooltip({ state: "unauthenticated" }, ALL), "GitHub: run gh auth login")
    assert.equal(Model.tooltip({ state: "error", error: "boom" }, ALL), "GitHub: boom")
    assert.equal(Model.tooltip({ state: "error" }, ALL), "GitHub: request failed")
  })

  it("summarises the counts", () => {
    assert.equal(Model.tooltip(SNAPSHOT, ALL), "GitHub · 1 to review · 2 PRs need work · 32 open PRs · 3 unread")
    assert.equal(Model.tooltip(QUIET, ALL), "GitHub · 2 open PRs")
    assert.equal(Model.tooltip({ ...QUIET, pulls: { total: 1, items: [FAILING] } }, ALL), "GitHub · 1 PR need work · 1 open PR")
  })
})

describe("stateTitle", () => {
  it("names every state", () => {
    assert.equal(Model.stateTitle({ state: "missing" }), "GitHub CLI is not installed")
    assert.equal(Model.stateTitle({ state: "unauthenticated" }), "GitHub CLI is not signed in")
    assert.equal(Model.stateTitle({ state: "error" }), "GitHub request failed")
    assert.equal(Model.stateTitle(null), "Loading GitHub")
  })
})

describe("stateDetail", () => {
  it("explains every state", () => {
    assert.match(Model.stateDetail({ state: "missing" }), /pacman -S github-cli/)
    assert.match(Model.stateDetail({ state: "unauthenticated" }), /never stores a token/)
    assert.equal(Model.stateDetail({ state: "error", error: "boom" }), "boom")
    assert.equal(Model.stateDetail({ state: "error" }), "")
    assert.equal(Model.stateDetail(null), "")
  })
})

describe("heroStatus", () => {
  it("lists what needs attention or reports quiet", () => {
    assert.equal(Model.heroStatus(null, ALL), "LOADING")
    assert.equal(Model.heroStatus({ state: "error" }, ALL), "ERROR")
    assert.equal(Model.heroStatus(SNAPSHOT, ALL), "1 TO REVIEW · 2 NEED WORK · 3 UNREAD")
    assert.equal(Model.heroStatus(QUIET, ALL), "ALL QUIET")
  })
})

describe("rowGlyph", () => {
  it("ranks PR states draft, failed, changes, approved, pending, passed, plain", () => {
    assert.equal(Model.rowGlyph(DRAFT), "󰏫")
    assert.equal(Model.rowGlyph(FAILING), "󰅙")
    assert.equal(Model.rowGlyph(CHANGES), "󰕒")
    assert.equal(Model.rowGlyph(APPROVED), "󰄬")
    assert.equal(Model.rowGlyph({ kind: "pull", ci: "PENDING" }), "󰔛")
    assert.equal(Model.rowGlyph(PASSING), "󰗠")
    assert.equal(Model.rowGlyph(PLAIN), "󰘭")
  })

  it("picks a glyph per issue or notification subject", () => {
    assert.equal(Model.rowGlyph(ISSUE), "󰀦")
    assert.equal(Model.rowGlyph(NOTIFICATION), "󰘭")
    for (const [type, glyph] of [["Issue", "󰀦"], ["Release", "󰓹"], ["Discussion", "󰭹"], ["Commit", "󰜘"], ["CheckSuite", "󰙨"], ["Other", "󰂚"]]) {
      assert.equal(Model.rowGlyph({ kind: "notification", type }), glyph, type)
    }
    assert.equal(Model.rowGlyph(null), "")
  })
})

describe("rowTone", () => {
  it("maps rows to palette roles", () => {
    assert.equal(Model.rowTone(DRAFT), "muted")
    assert.equal(Model.rowTone(FAILING), "urgent")
    assert.equal(Model.rowTone(CHANGES), "urgent")
    assert.equal(Model.rowTone(APPROVED), "accent")
    assert.equal(Model.rowTone({ kind: "pull", ci: "PENDING" }), "muted")
    assert.equal(Model.rowTone(PASSING), "normal")
    assert.equal(Model.rowTone(NOTIFICATION), "urgent")
    assert.equal(Model.rowTone({ kind: "notification", reason: "mention" }), "accent")
    assert.equal(Model.rowTone({ kind: "notification", reason: "subscribed" }), "normal")
    assert.equal(Model.rowTone(ISSUE), "normal")
    assert.equal(Model.rowTone(null), "normal")
  })
})

describe("rowStatus", () => {
  it("describes PR checks and review, notification reasons, nothing for issues", () => {
    assert.equal(Model.rowStatus(PASSING), "checks passed")
    assert.equal(Model.rowStatus(FAILING), "checks failed")
    assert.equal(Model.rowStatus(CHANGES), "checks passed · changes requested")
    assert.equal(Model.rowStatus(APPROVED), "checks running · approved")
    assert.equal(Model.rowStatus(DRAFT), "draft · checks failed")
    assert.equal(Model.rowStatus(PLAIN), "review required")
    assert.equal(Model.rowStatus(NOTIFICATION), "review requested")
    assert.equal(Model.rowStatus(ISSUE), "")
    assert.equal(Model.rowStatus(null), "")
  })
})

describe("reasonLabel", () => {
  it("translates GitHub reasons and falls back to spaced words", () => {
    assert.equal(Model.reasonLabel("mention"), "mentioned you")
    assert.equal(Model.reasonLabel("ci_activity"), "workflow run")
    assert.equal(Model.reasonLabel("security_alert"), "security alert")
    assert.equal(Model.reasonLabel("manual_something"), "manual something")
    assert.equal(Model.reasonLabel(undefined), "")
  })
})

describe("repoLabel", () => {
  it("drops the owner for the viewer's own repositories", () => {
    assert.equal(Model.repoLabel(FAILING, "joamag"), "boytacean")
    assert.equal(Model.repoLabel(PASSING, "joamag"), "hivesolutions/netius")
    assert.equal(Model.repoLabel(FAILING, ""), "joamag/boytacean")
    assert.equal(Model.repoLabel(null, "joamag"), "")
  })
})

describe("rowTitle", () => {
  it("appends the number when there is one", () => {
    assert.equal(Model.rowTitle(FAILING, "joamag"), "boytacean#9")
    assert.equal(Model.rowTitle(NOTIFICATION, "joamag"), "hivesolutions/netius")
    assert.equal(Model.rowTitle(null, "joamag"), "")
  })
})

describe("formatAge", () => {
  it("scales from now to years and clamps the future", () => {
    assert.equal(Model.formatAge(iso(30 * 1000)), "now")
    assert.equal(Model.formatAge(iso(5 * 60 * 1000)), "5m")
    assert.equal(Model.formatAge(iso(HOUR)), "1h")
    assert.equal(Model.formatAge(iso(26 * HOUR)), "1d")
    assert.equal(Model.formatAge(iso(40 * 86400 * 1000)), "1mo")
    assert.equal(Model.formatAge(iso(400 * 86400 * 1000)), "1y")
    assert.equal(Model.formatAge(iso(-HOUR)), "now")
    assert.equal(Model.formatAge("not a date"), "")
  })
})

describe("formatFetched", () => {
  it("phrases the refresh age", () => {
    assert.equal(Model.formatFetched(Math.floor(Date.now() / 1000)), "updated just now")
    assert.equal(Model.formatFetched(Math.floor(Date.now() / 1000) - 120), "updated 2m ago")
    assert.equal(Model.formatFetched(0), "")
    assert.equal(Model.formatFetched("x"), "")
  })
})

describe("visibleRows", () => {
  it("flattens the enabled non-empty sections with headers", () => {
    const rows = Model.visibleRows(SNAPSHOT, ALL)
    assert.deepEqual(rows.filter(Model.isHeader).map((h) => [h.key, h.total, h.shown]), [["reviews", 1, 1], ["pulls", 32, 5], ["issues", 161, 1], ["notifications", 3, 1]])
    assert.equal(rows.length, 4 + 8)
  })

  it("respects disabled sections and skips empty ones", () => {
    const rows = Model.visibleRows(SNAPSHOT, { ...ALL, showIssues: false, showPulls: false })
    assert.deepEqual(rows.filter(Model.isHeader).map((h) => h.key), ["reviews", "notifications"])
    assert.deepEqual(Model.visibleRows(QUIET, ALL).filter(Model.isHeader).map((h) => h.key), ["pulls"])
    assert.deepEqual(Model.visibleRows({ state: "error" }, ALL), [])
  })
})

describe("isHeader", () => {
  it("recognises header markers only", () => {
    assert.equal(Model.isHeader({ header: true }), true)
    assert.equal(Model.isHeader(PASSING), false)
    assert.equal(Model.isHeader(null), false)
  })
})

describe("nextRowIndex", () => {
  it("skips headers in both directions and wraps", () => {
    const rows = Model.visibleRows(SNAPSHOT, ALL)
    assert.equal(Model.nextRowIndex(rows, 1, 1), 3)
    assert.equal(Model.nextRowIndex(rows, 3, -1), 1)
    assert.equal(Model.nextRowIndex(rows, rows.length - 1, 1), 1)
    assert.equal(Model.nextRowIndex([{ header: true }], 0, 1), -1)
    assert.equal(Model.nextRowIndex([], 0, 1), -1)
  })
})

describe("firstRowIndex", () => {
  it("lands on the first non-header row", () => {
    assert.equal(Model.firstRowIndex(Model.visibleRows(SNAPSHOT, ALL)), 1)
    assert.equal(Model.firstRowIndex([]), -1)
  })
})

describe("radar.sh", () => {
  // A gh stand-in: auth status from FAKE_GH_AUTH, GraphQL and notifications
  // from fixtures or the failure asked for, PUT calls logged.
  function fakeGh(dir) {
    fakeCommand(dir, "gh", `
[[ -n \${FAKE_LOG:-} ]] && printf '%s\\n' "$*" >> "$FAKE_LOG"
case "$1 $2" in
  "auth status") [[ \${FAKE_GH_AUTH:-ok} == ok ]] ;;
  "api graphql")
    case "\${FAKE_GH_GRAPHQL:-ok}" in
      fail) echo "gh: HTTP 502 Bad Gateway" >&2; exit 1 ;;
      errors) echo '{"errors":[{"message":"Something went wrong"}]}' ;;
      *) cat "${FIXTURES}/github-graphql.json" ;;
    esac ;;
  "api -X") exit 0 ;;
  api*) [[ \${FAKE_GH_NOTIF:-ok} == ok ]] || exit 1; cat "${FIXTURES}/github-notifications.json" ;;
  *) exit 2 ;;
esac`)
    return dir
  }

  it("reports missing when no gh can be found", (t) => {
    const dir = tmpdir(t)
    const result = runJson("joamag.github", "radar.sh", [], { bin: dir, env: { HOME: dir } })
    if (fs.existsSync("/usr/bin/gh")) t.skip("/usr/bin/gh exists on this machine")
    else assert.deepEqual(result.json, [{ state: "missing" }])
  })

  it("reports unauthenticated when gh has no session", (t) => {
    const dir = fakeGh(tmpdir(t))
    assert.deepEqual(runJson("joamag.github", "radar.sh", [], { bin: dir, env: { HOME: dir, FAKE_GH_AUTH: "no" } }).json, [{ state: "unauthenticated" }])
  })

  it("condenses the GraphQL and notifications answers", (t) => {
    const dir = fakeGh(tmpdir(t))
    const log = path.join(dir, "gh.log")
    const [snapshot] = runJson("joamag.github", "radar.sh", ["2"], { bin: dir, env: { HOME: dir, FAKE_LOG: log } }).json
    assert.equal(snapshot.state, "ok")
    assert.equal(snapshot.login, "joamag")
    assert.ok(Number.isInteger(snapshot.fetchedAt))
    assert.equal(snapshot.pulls.total, 33)
    assert.ok(snapshot.pulls.items.length > 0)
    const pull = snapshot.pulls.items[0]
    assert.deepEqual(Object.keys(pull).sort(), ["author", "ci", "draft", "kind", "number", "repo", "review", "title", "updatedAt", "url"])
    assert.equal(pull.kind, "pull")
    assert.match(pull.repo, /\//)
    assert.equal(snapshot.issues.items[0].kind, "issue")
    // Unread only, capped at the row count, API URLs turned into browser URLs.
    assert.equal(snapshot.notifications.total, 4)
    assert.equal(snapshot.notifications.items.length, 2)
    assert.equal(snapshot.notifications.items[0].url, "https://github.com/hivesolutions/netius/pull/128")
    assert.equal(snapshot.notifications.items[1].url, "https://github.com/joamag/boytacean/commit/abc123")
    assert.match(fs.readFileSync(log, "utf8"), /-F n=2/)
  })

  it("falls back to the repository page for a notification without a subject URL", (t) => {
    const dir = fakeGh(tmpdir(t))
    const [snapshot] = runJson("joamag.github", "radar.sh", ["5"], { bin: dir, env: { HOME: dir } }).json
    const release = snapshot.notifications.items.find((n) => n.type === "Release")
    assert.equal(release.url, "https://github.com/joamag/omarchy-plugins")
    assert.equal(snapshot.notifications.items.some((n) => n.title === "Already read"), false)
  })

  it("keeps the PR data when the notifications call fails", (t) => {
    const dir = fakeGh(tmpdir(t))
    const [snapshot] = runJson("joamag.github", "radar.sh", [], { bin: dir, env: { HOME: dir, FAKE_GH_NOTIF: "fail" } }).json
    assert.equal(snapshot.state, "ok")
    assert.deepEqual(snapshot.notifications, { total: 0, items: [] })
  })

  it("surfaces GraphQL failures with their message", (t) => {
    const dir = fakeGh(tmpdir(t))
    assert.deepEqual(runJson("joamag.github", "radar.sh", [], { bin: dir, env: { HOME: dir, FAKE_GH_GRAPHQL: "fail" } }).json, [{ state: "error", error: "gh: HTTP 502 Bad Gateway " }])
    assert.deepEqual(runJson("joamag.github", "radar.sh", [], { bin: dir, env: { HOME: dir, FAKE_GH_GRAPHQL: "errors" } }).json, [{ state: "error", error: "Something went wrong" }])
  })

  it("marks notifications read through the API and validates the row count", (t) => {
    const dir = fakeGh(tmpdir(t))
    const log = path.join(dir, "gh.log")
    assert.equal(runScript("joamag.github", "radar.sh", ["mark-read"], { bin: dir, env: { HOME: dir, FAKE_LOG: log } }).status, 0)
    assert.match(fs.readFileSync(log, "utf8"), /api -X PUT notifications -F read=true --silent/)
    const [snapshot] = runJson("joamag.github", "radar.sh", ["lots"], { bin: dir, env: { HOME: dir, FAKE_LOG: log } }).json
    assert.equal(snapshot.state, "ok")
    assert.match(fs.readFileSync(log, "utf8"), /-F n=5/)
  })
})
