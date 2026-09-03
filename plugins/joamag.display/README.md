# joamag.display

Display controls for the Omarchy bar: brightness and contrast for the focused monitor, a true gamma exponent and a colour temperature for the whole session, then the text size, scale and monitor list of the built-in Display widget.

This is a fork of Omarchy's first-party `omarchy.monitor` panel, which already drove brightness over DDC/CI. Contrast, gamma and temperature are the additions, so enable this widget and disable `omarchy.monitor` rather than running both.

## What drives what

| Control | Range | Route | Scope |
|---|---|---|---|
| Brightness | 1-100% | `omarchy-brightness-display`, which picks the backlight, an Apple display or DDC/CI VCP 0x10 | The focused monitor |
| Contrast | 0-100% | DDC/CI VCP 0x12 through `ddcutil` | The focused monitor |
| Gamma | 0.30-2.80, neutral 1.00 | `wl-gammarelay-rs` `Gamma` over D-Bus | Every display |
| Temperature | 2500-6500K, neutral 6500K | `wl-gammarelay-rs` `Temperature` over D-Bus | Every display |

Brightness and contrast are the monitor's own settings: they persist across reboots, live in the panel rather than the session, and cost nothing in signal quality because the panel does the scaling itself.

**Gamma is the same quantity the NVIDIA control panel calls gamma** — a true exponent on the display's transfer curve, with the same 0.30 to 2.80 range and the same 1.00 neutral, so a value carried over from Windows means the same thing here. Above 1.00 the midtones lift and the image washes out; below it they deepen until the shadows crush. Black and white stay put either way, which is what makes it a gamma control rather than a dimmer.

No monitor exposes a gamma VCP, so this has to be the compositor's gamma ramp, and only one client may own that ramp at a time. This widget uses [`wl-gammarelay-rs`](https://github.com/MaxVerevkin/wl-gammarelay-rs), which applies changes live over D-Bus without flicker, and deliberately **not** `hyprsunset`: hyprsunset's `gamma` is a linear 0-100% scale on the ramp, which is a dimmer, not a gamma curve, and it silently reads a value like `1.5` as 1.5%.

The gamma slider runs on a **logarithmic track**, unlike the NVIDIA panel's linear one. Gamma is a ratio, so 0.50 is as far from neutral as 2.00 is, and on a linear track the entire darkening half would sit in the first 28% of travel while the top third moved the picture almost not at all. On a log track neutral lands near the middle, halving and doubling cost the same distance, and every part of the track does something. The numbers are unchanged, so a value from Windows still means the same thing.

Because that one daemon owns the whole ramp, the temperature slider is the night light. Use it instead of `omarchy toggle nightlight`, which drives hyprsunset and would fight this widget for the ramp. The daemon is started on demand and revived by a later refresh if it dies, so nothing needs to be added to autostart.

A control that nothing on the machine can report is left out of the popup entirely: a laptop panel shows brightness but no contrast, and a monitor with DDC/CI switched off in its own menu shows neither.

## Across reboots

Every control comes back where you left it, by two different routes.

Brightness and contrast need nothing: they are the monitor's own settings, kept in its memory, so they survive not just a reboot but unplugging the machine entirely.

Gamma and temperature are session state, and a ramp daemon that has just started is at 1.00 and 6500K no matter what you last chose. So the widget writes them onto its own `shell.json` entry as you change them, and replays them onto the daemon whenever the daemon appears:

```json
{ "id": "joamag.display", "gamma": 1.2, "temperature": 5000 }
```

That covers three cases with one mechanism: at login the shell starts before the daemon does, a daemon that dies mid-session comes back at its defaults, and a `shell.json` edited by hand is honoured on the next restart. A probe runs on its own timer even while the popup is shut - it is one D-Bus round trip and never touches i2c, so it costs nothing to leave running - and gives up after three failed revivals so a machine without the daemon installed is not nagged forever.

## Interactions

- Left click on the bar: open the popup. Scroll on the bar: brightness in `wheelStep` steps, with the usual OSD.
- `j`/`k` (or up/down) move between sections, `h`/`l` (or left/right) move the slider under the cursor, step the text size or walk the scale presets, `r` refreshes, Esc closes, Tab switches to the neighbouring panel. One press moves the knob a fixed distance along its track, so it means the same amount of change wherever the control currently sits.
- Drag a slider with the pointer: the value follows the knob and is written once the drag settles, so a drag does not put one i2c exchange on the bus per pixel.
- Enter on a scale preset applies it; Enter on a display row enables or disables that display.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `showContrast` | `true` | Show the contrast slider when the monitor reports contrast |
| `showGamma` | `true` | Show the gamma slider |
| `showTemperature` | `true` | Show the colour temperature slider |
| `wheelStep` | `5` | Brightness step when scrolling on the bar (percent) |
| `refreshIntervalSec` | `5` | Re-read cadence while the popup is open |

## IPC

```
omarchy-shell joamag.display toggle
omarchy-shell joamag.display refresh
omarchy-shell joamag.display brightness 60
omarchy-shell joamag.display contrast 75
omarchy-shell joamag.display gamma 1.35
omarchy-shell joamag.display temperature 4500
omarchy-shell joamag.display state
omarchy-shell joamag.display version
```

## Data source

`display.sh` answers one snapshot per refresh: the focused monitor and its i2c bus, brightness and contrast in a single `ddcutil getvcp 10 12` exchange, gamma and temperature from `busctl`, and the scale and monitor list from `hyprctl monitors`. The i2c bus of each monitor is cached under `$XDG_RUNTIME_DIR/joamag-display/`, and a monitor that does not answer is remembered for a minute so a refresh does not re-probe every bus.

DDC/CI needs the `i2c-dev` module and read/write on the monitor's `/dev/i2c-*`; on a normal Omarchy install the udev ACL already grants the logged-in user both, so nothing needs root and no group change is required. If contrast never appears, check that the monitor's own on-screen menu has DDC/CI enabled.

## Requirements

`ddcutil` for brightness and contrast, and `wl-gammarelay-rs` (AUR) for gamma and temperature. Without the latter the widget still works, minus those two sliders.
