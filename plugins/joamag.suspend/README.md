# joamag.suspend

Idle suspend for the Omarchy shell. Omarchy's own idle service runs the screensaver and the lock, then leaves the machine on forever; this plugin adds the missing step and suspends after a period of idle, 30 minutes by default. It is a headless service plus a bar widget: the service does the sleeping, the widget sets when.

## The widget

The bar shows a sleeping face, 󰒲, with the timeout next to it while auto sleep is on, and the same face crossed out, 󰒳, dimmed, while it is off. Right click on it flips between the two. The popup has:

- a **SLEEP AFTER** row of presets, 15 min, 30 min, 1 h, 3 h and Never, the current one lit; click one, press `1`-`5`, or move over them with `h`/`l` and press Enter. `n` is Never;
- a field for **any other duration**: `c` focuses it, and `45`, `45m`, `1.5h`, `2h30` or `off` followed by Enter set it;
- what the service knows: whether it is armed, whether the machine counts as idle right now, whether Omarchy's Stay Awake is on, and what happened the last time the timeout was reached;
- **Stay awake** (`w`), which flips Omarchy's own indicator, and **Sleep now** (`s`), which runs the checks below and suspends after a confirming second press.

The widget writes the timeout onto its own entry in `shell.json` and the service reads it from there, live; the change is in force the moment a preset is clicked.

## How it decides

The countdown is the compositor's idle notifier, the same clock the built-in screensaver and lock use, so it starts from the last keyboard, mouse or controller input and is held back by any Wayland idle inhibitor (a video playing, a game). When the timeout is reached `suspend.sh` runs and checks, in order:

| Check | Outcome |
|---|---|
| Stay Awake is on (the bar indicator, `omarchy toggle idle stay-awake`) | skipped, `stay-awake` |
| Suspend is hidden from the system menu (`omarchy toggle suspend`) | skipped, `suspend-off` |
| A systemd block inhibitor holds sleep (an update, a backup, `systemd-inhibit --what=sleep`) | skipped, `inhibited` |
| Another user has a graphical or tty session | skipped, `other-users` |
| Otherwise | `systemctl suspend` |

Delay inhibitors do not block: Omarchy's own sleep monitor uses one to lock the screen before the machine sleeps, so a suspend from this service is always locked. A skipped suspend is not retried until there has been input again followed by another full idle period.

## Settings

Inline on the plugin's entry in `~/.config/omarchy/shell.json`: in the bar layout when the widget is enabled, in `plugins[]` when only the service is.

```json
{ "id": "joamag.suspend", "timeoutSec": 1800 }
```

| Key | Default | Meaning |
|---|---|---|
| `timeoutSec` | `1800` | Seconds of idle before suspending; `0` disarms the service |
| `showLabel` | `true` | Show the timeout next to the bar icon |
| `dryRun` | `false` | Log the decision without calling `systemctl` |

Changes apply live once the shell reloads its config (`omarchy-shell shell reloadConfig` after editing by hand). When the entry exists in both places the bar's wins, since that is the one with a control on it.

## IPC

```
omarchy-shell joamag.suspend status     # armed, idle, timeout, last verdict
omarchy-shell joamag.suspend now        # run the checks and suspend right away
omarchy-shell joamag.suspend version
omarchy-shell joamag.suspend.panel toggle   # the popup (the service owns the plain target)
```

Events are logged with a `joamag.suspend` prefix in the shell log (`qs log -p /usr/share/omarchy/shell`).

## Enabling

```bash
omarchy plugin enable joamag.suspend --section right   # widget and service
omarchy plugin enable joamag.suspend                   # service only, no bar presence
```

One entry enables both kinds; the shell starts the service right away either way.
