# joamag.isabella

Today's [Isabella](https://github.com/joamag/isabella) checklist in the Omarchy bar: pending and done counts, and a popup that lists the day's tasks with pending work first (overdue at the very top) and done or cancelled tasks after. Tick, cancel or delay straight from the popup, and step to other days to see what is coming.

## Interactions

- Left click on the bar: open the popup. Middle click: refresh. Right click: open Isabella in the browser.
- Click a row or press Enter to tick or untick it (subtasks tick individually and sync their parent). Right click or `c` cancels the task for the day (again to lift the cancellation), `d` delays it to tomorrow.
- `h` / `l` (or left/right) step to the previous or next day, `t` returns to today. Future days are read-only, as in the app.
- `j` / `k` move over rows, `r` refreshes, `o` opens the browser, Esc closes, Tab switches to the neighbouring panel.

## Setup

Credentials live outside the repository and outside `shell.json`, in `~/.config/omarchy/isabella.env` (owner-only permissions):

```
ISABELLA_URL=https://isabella.example.com
ISABELLA_USERNAME=admin
ISABELLA_PASSWORD=...
```

A `member` account is enough to view and tick. The widget logs in through `/api/auth/login`, keeps the session cookie in `~/.cache/omarchy/isabella/` and logs in again when it expires. The last fetched day is cached there too, so the popup still shows the checklist when the server is unreachable (marked CACHED).

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `300` | Refresh cadence; the popup refreshes on open when its data is older than a minute |
| `barMode` | `"both"` | `both` (pending 󰄬done), `pending`, `done` (done/total) or `none` (icon only) |
| `hideOnRestDays` | `false` | Hide the widget on days with nothing scheduled |

## IPC

```
omarchy-shell joamag.isabella toggle
omarchy-shell joamag.isabella refresh
omarchy-shell joamag.isabella version
```

## Data source

`isabella.sh` wraps `curl` around the app's REST API: `GET /api/day/{day}` for the view and `POST /api/day/{day}/toggle|cancel|delay` for actions, each answering with the refreshed day so the popup never needs a second round trip.
