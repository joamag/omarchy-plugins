# joamag.peripherals

Wireless peripheral batteries for the Omarchy bar: the battery glyph of whichever mouse, keyboard or headset has the least charge, with its level next to it, and a popup listing every device with its charge, whether it is charging and how long it has left. A desktop has no battery widget of its own, and this is the one that tells you the mouse is about to die before it does.

## Interactions

- Left click on the bar icon: open the popup. Arrow keys or `j`/`k` move over the footer actions, Enter activates, Esc closes, Tab switches to the neighbouring panel.
- Middle click on the bar icon: refresh now.
- Right click on the bar icon: open Solaar, when it is installed.

## States

| State | Bar | Popup |
|---|---|---|
| No battery-powered peripheral | widget hidden | - |
| Every device above the threshold | glyph of the emptiest device and its level | Device list |
| A device at or below the threshold, not charging | same, urgent | Device list with that row urgent |

Logitech mice and keyboards on a Unifying or Bolt receiver report their charge as a level rather than a percentage (full, high, normal, low, critical), so that is what the widget shows for them; the number upower attaches to such a device is only used to pick a glyph. Bluetooth devices generally report a real percentage and, while discharging, an estimate of the time left.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `showLevel` | `true` | Show the emptiest device's level next to the glyph |
| `warnPct` | `20` | Charge at or below which a device turns the widget urgent |
| `hideWhenHealthy` | `false` | Hide the widget while no device is low |
| `refreshIntervalSec` | `60` | Fallback refresh cadence; changes are picked up as they happen |

## IPC

```
omarchy-shell joamag.peripherals toggle
omarchy-shell joamag.peripherals refresh
omarchy-shell joamag.peripherals version
```

## Data source

`peripherals.sh` reads one `upower -d` and keeps the devices that are neither the machine's own battery nor its mains, which Omarchy's battery service already owns. The widget also keeps `upower --monitor` running, so a device waking up, going to sleep or being plugged in shows within a second; the refresh interval is only a fallback. Nothing needs root.

upower only knows the devices the kernel drives, and the kernel does not drive every Logitech receiver: on the kernel this was written against, `hid-logitech-dj` claims the Unifying receiver but has no entry for the Bolt receiver (`046d:c548`), so a keyboard paired to a Bolt is invisible to upower. For those the script has a second source, Solaar's own library, which reads the receivers directly the way Solaar does. That read costs about a second per paired slot on a Bolt receiver, so it runs in the background, its result is cached for two minutes under `$XDG_RUNTIME_DIR/joamag-peripherals/`, and each snapshot merges the last reading in, deduplicated by serial against what upower reported. Solaar itself is optional: without it the widget shows what upower sees, and the footer button that opens it does not appear.

Stale pairings slow that read down: a Bolt receiver keeps a slot for every time a device was paired to it, and each one costs the same second whether the device is there or not. Removing the old ones in Solaar makes the reading correspondingly quicker.
