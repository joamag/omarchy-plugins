# joamag.stocks

Market watchlist for the Omarchy bar. One index or stock sits in the bar with its daily change; the popup shows a chart for the selected symbol with 1D / 5D / 1M / 6M / 1Y ranges, and a watchlist where every row carries a sparkline, the price and the daily move. Defaults: S&P 500, NASDAQ Composite, Dow Jones, AMD, Intel, NVIDIA, Apple and Microsoft.

Data comes from Yahoo Finance's public chart endpoint through `curl` and `jq`. No API key, no account, nothing stored. Yahoo is unofficial and occasionally rate limits; the widget keeps the last good values when a refresh fails.

## Interactions

- Hover the big chart for a crosshair: the bubble shows time, price and change at that point, and the hero price and change follow the pointer until it leaves the chart.
- Left click on the bar: open the popup. Right click: pin the next watchlist symbol to the bar. Scroll: walk the watchlist. Middle click: refresh.
- In the popup, arrow keys or `j`/`k` move over the watchlist and footer actions, `h`/`l` (or left/right) change the chart range, Enter selects the row for the big chart, `o` opens the selected symbol on Yahoo Finance, `p` pins it to the bar, `a` adds a symbol, `x` removes the cursor row, `J`/`K` reorder, Esc closes.
- Click a row to chart it, right click a row to open it in the browser.

## Editing the watchlist

The watchlist is the `symbols` setting on the widget's `shell.json` entry, and the popup edits that same value, so both routes stay in sync:

- **In the popup**: press `a` or the "Add" footer button and start typing. Suggestions from Yahoo Finance search appear under the field as you type (symbol, company, exchange); Up/Down highlights one, Tab completes it into the field, Enter adds the highlighted match or the typed symbol (`TSLA`, `^PSI20`, `BTC-USD`). Typed symbols are checked against Yahoo before they are added, so a typo shows an error instead of a dead row; Esc leaves the field. Hover or move the cursor onto a row and click `✕`, or press `x`, to remove it (the last symbol cannot be removed). `J` and `K` move the cursor row down and up. Every change is written to `shell.json` immediately.
- **In the file**: edit `symbols` in `~/.config/omarchy/shell.json` as a comma separated string (an array works too). The shell watches the file, so the list updates without a restart.
- **From a script**: `omarchy-shell joamag.stocks addSymbol TSLA` and `omarchy-shell joamag.stocks removeSymbol TSLA`.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `symbols` | `"^GSPC,^IXIC,^DJI,AMD,INTC,NVDA,AAPL,MSFT"` | Comma separated Yahoo Finance symbols (indices start with `^`) |
| `barSymbol` | `"^GSPC"` | Symbol shown in the bar; right click on the bar cycles and persists it |
| `showPrice` | `false` | Show the last price in the bar |
| `showChange` | `true` | Show the daily change in the bar |
| `range` | `"1d"` | Default chart range: `1d`, `5d`, `1mo`, `6mo`, `1y` |
| `refreshIntervalSec` | `60` | Refresh cadence for quotes |

Multiple instances are allowed, so two widgets can pin two different symbols.

## IPC

```
omarchy-shell joamag.stocks toggle
omarchy-shell joamag.stocks refresh
omarchy-shell joamag.stocks cycleSymbol
omarchy-shell joamag.stocks addSymbol TSLA
omarchy-shell joamag.stocks removeSymbol TSLA
omarchy-shell joamag.stocks version
```
