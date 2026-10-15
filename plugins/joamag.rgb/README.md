# joamag.rgb

RGB lighting control for the Omarchy bar, through OpenRGB: a palette icon, dimmed while every light is off, and a popup that lists each device OpenRGB can light, such as the case's NZXT Smart Device V2 and the graphics card. Every device gets a switch, the animations its controller offers, a row of colours with a field for any other, and a brightness slider, plus a speed slider while an animation runs. What you set is remembered and put back when the shell starts, since the hardware forgets its colours on a power cycle.

## Interactions

- Left click on the bar icon: open the popup. Arrow keys or `j`/`k` move over the devices and the footer actions, Enter switches the device under the cursor on or off, `h`/`l` change its brightness, Esc closes, Tab switches to the neighbouring panel.
- Middle click on the bar icon: look for devices again.
- Right click on the bar icon: turn every light off, or back on when they are all off.
- `1`-`9`: paint the device under the cursor (or the first device, with the cursor elsewhere) white, red, orange, yellow, green, cyan, blue, purple or pink.
- `c`: focus that device's colour field. `ff8000`, `#ff8000` or `#f80` followed by Enter set it; Esc gives the keys back.
- `[` / `]`: that device's previous or next animation, `Solid` included.
- `a`: all off, or all on. `r`: look for devices again.

A device is driven in its own single-colour mode, `Static`, `Fixed` or `Direct` in that order of preference, and switched off through its `Off` mode, or painted black when it has none. Brightness scales the colour, which works the same on every device whatever its controller offers. A device with no single-colour mode is listed dimmed and left running its effect.

## Animations

Every other mode a device offers is an animation, listed under it with `Solid` first: on an NZXT hub `Fading`, `Spectrum Cycle`, `Marquee`, `Breathing`, `Candle`, `Super Rainbow` and the rest, on a graphics card whatever its controller has, such as `Cycle` and `Strobe`. An animation runs in the device's colour, scaled by the brightness, and at the speed set on its slider, a percentage of the controller's own range. Rainbow animations bring their own colours and take neither the colour nor the brightness; one that takes several colours gets the one colour, which every NZXT animation accepts.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `devices` | `""` | Devices to show, comma separated: a device is listed when its name contains one of the words or its type is one (`"nzxt, gpu"`); empty lists every device OpenRGB finds |
| `restoreOnStart` | `true` | Put the remembered colours back when the shell starts, and on any device that shows up later |

The popup writes what it sets onto the same entry, one object per device keyed by its name, so it can be edited by hand too:

```json
{ "id": "joamag.rgb", "lights": { "NZXT Smart Device V2": { "on": true, "color": "FF0000", "brightness": 80, "effect": "Breathing", "speed": 50 } } }
```

`color` is the colour at full brightness, `effect` the animation by its OpenRGB name (`""` for a solid colour) and `speed` its speed in percent. A device that has never been set from the widget has no entry and is left as it is.

## IPC

```
omarchy-shell joamag.rgb toggle
omarchy-shell joamag.rgb refresh
omarchy-shell joamag.rgb on
omarchy-shell joamag.rgb off
omarchy-shell joamag.rgb version
```

## Setup

```bash
sudo pacman -S openrgb
sudo systemctl enable --now openrgb
```

The service runs OpenRGB's SDK server, which the widget's calls talk to, so a change lands in a moment. Without it every call detects every device again, which takes a few seconds, and reaches the hardware only once the udev rules the package ships are loaded, after a reboot. Not every graphics card has an OpenRGB controller; one OpenRGB does not detect simply does not show up.

## Data source

`rgb.sh` lists the devices with `openrgb --list-devices`, keeping each one's index, name, type and modes, and applies a change with `openrgb --device INDEX --mode MODE --color RRGGBB`, adding `--speed PERCENT` for an animation. OpenRGB reports a mode it does not know, or a number of colours a mode does not take, on its output and still exits 0, so the script checks what it printed as well as its exit status.
