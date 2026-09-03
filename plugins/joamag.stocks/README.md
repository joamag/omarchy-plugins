# joamag.stocks

Market watchlist for the Omarchy bar. One index or stock sits in the bar with its daily change; the popup shows a chart for the selected symbol with 1D / 5D / 1M / 6M / 1Y ranges, and a watchlist where every row carries a sparkline, the price and the daily move. Defaults: S&P 500, NASDAQ Composite, Dow Jones, AMD, Intel, NVIDIA, Apple and Microsoft.

Data comes from Yahoo Finance's public chart endpoint through `curl` and `jq`. No API key, no account, nothing stored. Yahoo is unofficial and occasionally rate limits; the widget keeps the last good values when a refresh fails.

## Interactions

- Left click on the bar: open the popup. Right click: pin the next watchlist symbol to the bar. Scroll: walk the watchlist. Middle click: refresh.
- In the popup, arrow keys or `j`/`k` move over the watchlist and footer actions, `h`/`l` (or left/right) change the chart range, Enter selects the row for the big chart, `o` opens the selected symbol on Yahoo Finance, `p` pins it to the bar, Esc closes.
- Click a row to chart it, right click a row to open it in the browser.

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
omarchy-shell joamag.stocks version
```
