# joamag.sysmon

System monitor for the Omarchy bar: one headline metric in the bar (CPU by default) and a popup with live meters for CPU, memory, swap, GPU, VRAM and the root disk, the CPU/GPU temperatures, load averages, the busiest processes, and a kernel section with the running release, the day it was built and the uptime.

## Interactions

- Left click: open the popup (arrow keys move between the action buttons, Enter activates, Esc closes, Tab switches to the neighbouring panel).
- Right click: cycle the metric shown in the bar (CPU, memory, temperature, GPU, disk). The choice is written to your `shell.json` entry.
- Middle click: refresh now.
- Scroll: nothing, on purpose.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `barMetric` | `"cpu"` | `cpu`, `memory`, `temperature`, `gpu` or `disk` |
| `showLabel` | `true` | Show the value next to the icon |
| `refreshIntervalSec` | `3` | Bar refresh cadence; the popup refreshes every second while open |
| `processCount` | `6` | Rows in the top processes list (0 hides the section) |

Multiple instances are allowed, so you can show CPU in one slot and memory in another.

## IPC

```
omarchy-shell shell toggle joamag.sysmon
omarchy-shell shell call joamag.sysmon refresh
omarchy-shell shell call joamag.sysmon cycleMetric
```

## Data sources

`stats.sh` reads `/proc/stat`, `/proc/meminfo`, `/proc/loadavg`, `/proc/uptime`, `/sys/class/hwmon` (k10temp, zenpower, coretemp), `nvidia-smi` or the amdgpu sysfs, `df`, `top` and `uname` (the kernel's build timestamp is parsed out of `uname -v`). No daemon, no root.
