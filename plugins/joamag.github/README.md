# joamag.github

GitHub radar for the Omarchy bar: the number of things that need you (review requests, your pull requests with failed checks or requested changes, unread notifications), and a popup listing review requests, your open pull requests with CI and review state, issues assigned to you and unread notifications. Everything opens in the browser with a click.

It reuses the `gh` CLI session, so there is no token to configure: if `gh auth status` works, the widget works.

## Interactions

- Left click on the bar: open the popup. Middle click: refresh. Right click: open github.com/notifications.
- Arrow keys or `j`/`k` move over rows and footer actions, Enter opens the row in the browser, `y` copies its URL, `r` refreshes, `m` marks every notification as read, Esc closes, Tab switches to the neighbouring panel.
- Click a row to open it, right click to copy its URL.

## What the glyphs mean

| Glyph | Pull request |
|---|---|
| 󰗠 | checks passed |
| 󰅙 | checks failed (counts as attention) |
| 󰕒 | changes requested (counts as attention) |
| 󰄬 | approved |
| 󰔛 | checks running |
| 󰏫 | draft |

Issues show 󰀦; notifications show a glyph for their subject (PR, issue, release, discussion, commit, workflow).

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `180` | Refresh cadence (one GraphQL and one REST request each) |
| `maxRows` | `5` | Rows fetched per section; the header shows the full total |
| `showReviews` | `true` | Review requests section and its share of the bar count |
| `showPulls` | `true` | My pull requests section and failing PRs in the bar count |
| `showIssues` | `true` | Assigned issues section (never part of the bar count) |
| `showNotifications` | `true` | Unread notifications section and its share of the bar count |
| `hideWhenQuiet` | `false` | Hide the widget while the attention count is zero |

## IPC

```
omarchy-shell joamag.github toggle
omarchy-shell joamag.github refresh
omarchy-shell joamag.github markRead
omarchy-shell joamag.github version
```

## Data source

`radar.sh` runs one GraphQL query (three searches: `review-requested:@me`, `author:@me`, `assignee:@me`) and one `GET /notifications`, in parallel, and condenses the answer to a single JSON object. Marking notifications read is `PUT /notifications`.
