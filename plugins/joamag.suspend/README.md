# joamag.suspend

Idle suspend for the Omarchy shell. Omarchy's own idle service runs the screensaver and the lock, then leaves the machine on forever; this headless service adds the missing step and suspends after a configurable period of idle, 30 minutes by default.

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

Inline on the service entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "joamag.suspend", "timeoutSec": 1800 }
```

| Key | Default | Meaning |
|---|---|---|
| `timeoutSec` | `1800` | Seconds of idle before suspending; `0` disarms the service |
| `dryRun` | `false` | Log the decision without calling `systemctl` |

Changes apply live once the shell reloads its config (`omarchy-shell shell reloadConfig` after editing by hand).

## IPC

```
omarchy-shell joamag.suspend status     # armed, idle, timeout, last verdict
omarchy-shell joamag.suspend now        # run the checks and suspend right away
omarchy-shell joamag.suspend version
```

Events are logged with a `joamag.suspend` prefix in the shell log (`qs log -p /usr/share/omarchy/shell`).

## Enabling

```bash
omarchy plugin enable joamag.suspend
```

Services have no bar presence, so enabling adds the entry to `plugins[]` and the shell starts it right away.
