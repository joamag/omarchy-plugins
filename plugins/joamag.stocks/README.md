# joamag.stocks

Market watchlist for the Omarchy bar. One index or stock sits in the bar with its daily change; the popup shows a chart for the selected symbol with 1D / 5D / 1M / 6M / 1Y / 5Y ranges, and a watchlist where every row carries a sparkline, the price and the daily move. A News tab lists the headlines for the charted symbol, or the day's top finance stories. Defaults: S&P 500, NASDAQ Composite, Dow Jones, AMD, Intel, NVIDIA, Apple and Microsoft.

Data comes from Yahoo Finance's public chart endpoint through `curl` and `jq`. No API key, no account, nothing stored. Yahoo is unofficial and occasionally rate limits; the widget keeps the last good values when a refresh fails.

## News

The popup has two tabs, Markets and News; it always opens on Markets, and `n` or a click on the tab switches. News shows one of two feeds, picked with the buttons at its top or `h`/`l`:

- **The charted symbol**: up to ten headlines from Yahoo Finance's search endpoint, the same one the add field uses. Chart another row on Markets and News follows it.
- **Top stories**: CNBC Top News and MarketWatch Top Stories (RSS), merged newest first with duplicates dropped. If one feed is down the other still shows and the status line says which one failed.

Each row is the title, the publisher and how long ago it came out. Click a headline or press Enter on it to open it in the browser. A feed is kept for five minutes; Refresh (or `r`) on the News tab fetches it again. The list scrolls inside the height the Markets view has, so switching tabs never resizes the popup.

### Sources

The Sources button beside the two feeds (or `s`) swaps the headlines for a checklist of publishers: every one in the feed on screen with its headline count, plus every one you have hidden, so it can always be brought back. Switch a publisher off to hide its headlines in every feed (Motley Fool in all symbols' news, CNBC in Top stories); Space or a click toggles the row under the cursor, Show all clears the list, `s` or Esc goes back to the headlines. Everything shows until you hide it, so a new publisher appears on its own. While the filter takes headlines out of the feed on screen the button reads `Sources · 4 hidden`.

Each switch is saved at once as `hiddenSources` on the widget's `shell.json` entry, matched by publisher name ignoring case. It can be edited by hand as a list (`["Motley Fool", "TIKR"]`) or a comma separated string.

## Interactions

- Hover the big chart for a crosshair: the bubble shows time, price and change at that point, and the hero price and change follow the pointer until it leaves the chart.
- Left click on the bar: open the popup. Right click: pin the next watchlist symbol to the bar. Scroll: walk the watchlist. Middle click: refresh.
- In the popup, arrow keys or `j`/`k` move over the watchlist and footer actions, `h`/`l` (or left/right) change the chart range, Enter selects the row for the big chart, `o` opens the selected symbol on Yahoo Finance, `p` pins it to the bar, `a` adds a symbol, `x` asks to remove the cursor row, `J`/`K` reorder, `n` switches between Markets and News, `s` opens the news Sources list, Esc closes (or leaves Sources first).
- Click a row to chart it, right click a row to open it in the browser, drag a row up or down to reorder the watchlist.
- While quotes or a chart are loading, a thin line sweeps between the price and the chart and the Refresh icon turns. Switching range or symbol keeps the previous chart on screen, dimmed, until the new one arrives; rows still waiting for their first quote pulse, and the add field hint turns while a search or check runs. The bar stays still on timed refreshes, and every animation holds still under the shell's reduced motion setting.

## Editing the watchlist

The watchlist is the `symbols` setting on the widget's `shell.json` entry, and the popup edits that same value, so both routes stay in sync:

- **In the popup**: press `a` or the "Add" footer button and start typing. Suggestions from Yahoo Finance search appear under the field as you type (symbol, company, exchange); Up/Down highlights one, Tab completes it into the field, Enter adds the highlighted match or the typed symbol (`TSLA`, `^PSI20`, `BTC-USD`). Typed symbols are checked against Yahoo before they are added, so a typo shows an error instead of a dead row; Esc leaves the field. Hover or move the cursor onto a row and click `✕`, or press `x`, to remove it: a dialog asks first, where Enter removes and Esc or a click outside keeps the symbol (the last symbol cannot be removed). Drag a row up or down to move it: the row follows the pointer, the rows it passes slide out of the way and the release commits the new order. `J` and `K` do the same from the keyboard. Every change is written to `shell.json` immediately.
- **In the file**: edit `symbols` in `~/.config/omarchy/shell.json` as a comma separated string (an array works too). The shell watches the file, so the list updates without a restart.
- **From a script**: `omarchy-shell joamag.stocks addSymbol TSLA` and `omarchy-shell joamag.stocks removeSymbol TSLA`. Scripts are not asked to confirm.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `symbols` | `"^GSPC,^IXIC,^DJI,AMD,INTC,NVDA,AAPL,MSFT"` | Comma separated Yahoo Finance symbols (indices start with `^`) |
| `barSymbol` | `"^GSPC"` | Symbol shown in the bar; right click on the bar cycles and persists it |
| `showPrice` | `false` | Show the last price in the bar |
| `showChange` | `true` | Show the daily change in the bar |
| `range` | `"1d"` | Default chart range: `1d`, `5d`, `1mo`, `6mo`, `1y`, `5y` |
| `refreshIntervalSec` | `60` | Refresh cadence for quotes |
| `hiddenSources` | `[]` | Publishers whose headlines the News tab hides, set from its Sources list |

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
