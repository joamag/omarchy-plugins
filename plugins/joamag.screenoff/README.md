# joamag.screenoff

Display blanking for a machine that is held awake. Omarchy's Stay Awake, the cup in the bar or `omarchy toggle idle`, works by switching the shell's idle service off altogether. That stops the screensaver and the lock, which is the point, but the lock was also what turned the displays off, so with Stay Awake on the screens show the same picture for as long as the machine is left alone. This plugin adds that one step back: while Stay Awake is on, the displays go off after a period of idle, 15 minutes by default, and any key press or mouse movement turns them back on. Nothing is locked and nothing sleeps.

It is a headless service with no bar presence. With Stay Awake off it does nothing on its own and Omarchy's own screensaver, lock and blanking run as usual; a screen off asked for by hand, from the System menu, works either way.

## How it decides

The countdown is the compositor's idle notifier, the same clock the built-in screensaver and lock use, so it starts from the last keyboard, mouse or controller input and is held back by any Wayland idle inhibitor: a video playing, a game, a call. It only runs while Stay Awake is on, which the service asks the shell's idle service about every five seconds, so the wait is counted from the last input or from when Stay Awake was seen to be on, whichever came later.

When the timeout is reached `screenoff.sh off` runs, checks once more that Stay Awake is still on, and turns the displays off through DPMS with `omarchy-brightness-display off`, after dimming the keyboard backlight where there is one. These are the commands the lock screen blanks with, so the monitors behave exactly as they do behind a locked session. The first input after that runs `screenoff.sh on`, which is `omarchy-system-wake`.

| What happens while the displays are off | Outcome |
|---|---|
| A key is pressed or the mouse moves | displays back on |
| Stay Awake is switched off | displays back on, Omarchy's idle service takes over from there |
| `timeoutSec` is set to `0` | displays back on, the service is disarmed |
| Any other setting is changed | displays back on, the wait starts again under the new setting |

A session that is locked by hand counts as active for as long as it stays locked, so this service stays out of the way and the lock screen blanks the displays itself.

## Screen off now

The displays can also be turned off by hand, Stay Awake or not, with `omarchy-shell joamag.screenoff now` or a "Screen off" row in Omarchy's System menu. Nothing is locked and nothing sleeps. The displays go once the input has stopped for a second, so the click or key press that asked for it does not wake them straight back, and the first key press or mouse movement after that brings them back on. With Stay Awake on, the keyboard backlight goes off and comes back with them, as it does for the timed blank.

With Stay Awake off, Omarchy's own idle cycle keeps running underneath, and the displays stay off through it. Its screensaver moves the cursor when it starts, which reads as input, so input during the blank counts as a return only once the idle service has dropped its cycle too: input it lets the screensaver ride through does not bring the displays back either, and dismissing the screensaver does. Its lock still comes at its usual time and dims the keyboard backlight, saving the level to put back later, so in this case the keyboard backlight is left to it and the displays alone go off and come back.

Plugins never write outside `shell.json`, so the menu row is added by hand to `~/.config/omarchy/extensions/omarchy-menu.jsonc`, inside its outer braces:

```jsonc
"system.screenoff": {"icon":"󰶐","label":"Screen off","when":"omarchy-shell joamag.screenoff status | grep -q forced","action":"omarchy-shell joamag.screenoff now"},
```

The `when` check hides the row until the running service can take it: only a service that answers `now` reports `forced` in its status. The service is kept loaded across plugin reloads, so after updating from an earlier version the row appears once the shell is restarted (`omarchy-restart-shell`). Rows from that file land at the end of the System menu, after Shutdown.

## Settings

Inline on the plugin's entry in `plugins[]` of `~/.config/omarchy/shell.json`.

```json
{ "id": "joamag.screenoff", "timeoutSec": 900 }
```

| Key | Default | Meaning |
|---|---|---|
| `timeoutSec` | `900` | Seconds of idle before the displays go off; `0` disarms the service, a day is the most |
| `respectInhibitors` | `true` | Let a Wayland idle inhibitor (video, game, call) keep the displays on; `false` blanks regardless |
| `dryRun` | `false` | Log the decision without touching the displays |

The service reads the file itself and follows it live, so an edit is in force as soon as it is saved.

## IPC

```
omarchy-shell joamag.screenoff status     # watching, idle, forced, timeout, displays, last verdict
omarchy-shell joamag.screenoff now        # displays off until the next input, Stay Awake or not
omarchy-shell joamag.screenoff version
```

`watching` is true only while Stay Awake is on and a timeout is set. Events are logged with a `joamag.screenoff` prefix in the shell log (`qs log -p /usr/share/omarchy/shell`).

## Enabling

```bash
omarchy plugin enable joamag.screenoff
```

The shell starts the service right away. Because the service is kept loaded across plugin reloads, a change to its code only reaches the shell on a restart (`bin/reload`).
