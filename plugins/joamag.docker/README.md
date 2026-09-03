# joamag.docker

Docker container control for the Omarchy bar: the whale icon with the running container count, and a popup that lists every container with its image and status. Click a row to start or stop it (paused containers resume), right-click to restart. The footer opens lazydocker or refreshes the list.

## Interactions

- Left click on the bar icon: open the popup. Arrow keys or `j`/`k` move over containers and footer actions, Enter activates, Esc closes, Tab switches to the neighbouring panel.
- Middle click on the bar icon: refresh now.
- Right click on the bar icon: open lazydocker (the same target as `SUPER + SHIFT + D`).
- Row left click / Enter: start or stop the container. Row right click: restart it.

## States

The widget adapts to how Docker is set up on the machine:

| State | Bar | Popup |
|---|---|---|
| Docker CLI missing | widget hidden | - |
| Daemon not running | dimmed icon | "Start daemon" button (`systemctl start docker`, authorizes through polkit) |
| Socket not accessible | dimmed icon | Explanation and an "Enable sudoless Docker" button that runs Omarchy's setup flow |
| Reachable | icon + running count | Container list |

Omarchy keeps user accounts out of the `docker` group by default, so on a fresh install the widget shows the "needs sudo" state until you enable sudoless Docker (Setup > Security > Sudoless Docker) and log in again.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `showCount` | `true` | Show the running container count next to the icon |
| `refreshIntervalSec` | `10` | Bar refresh cadence; the popup refreshes every 3 seconds while open |
| `hideWhenIdle` | `false` | Hide the widget while no container is running |

## IPC

```
omarchy-shell joamag.docker toggle
omarchy-shell joamag.docker refresh
omarchy-shell joamag.docker version
```

## Data source

`docker.sh` checks the CLI and the socket permission, then runs `docker ps -a` with a tab-separated format. Actions run `docker start|stop|unpause|restart <id>` directly.
