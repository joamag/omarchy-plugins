# joamag.disks

Disk overview for the Omarchy bar: the root filesystem's usage in the bar, and a popup with a usage meter per mount, removable media you can mount, unmount or eject, and two cleanup rows for the trash and the pacman package cache.

## Interactions

- Left click on the bar: open the popup. Middle click: refresh. Right click: open the file manager.
- Mount rows: click or Enter opens the mount in the file manager, `u` (or right click) unmounts a removable one, `e` ejects its whole disk after unmounting every partition.
- Not mounted rows: click, Enter or `u` mounts the partition through udisks; it then appears under Mounts.
- Cleanup rows arm on the first activation and run on the second within four seconds: Trash empties through `gio trash --empty`; Package cache opens a floating terminal running `sudo paccache -rk1`, which keeps the latest version of each package.
- `j`/`k` move over rows and footer actions, `r` refreshes, `o` opens the file manager, Esc closes, Tab switches to the neighbouring panel. Footer: Refresh, Files, Speed test (Omarchy's disk speed test overlay).

Only devices the kernel flags as removable, mounted under `/run/media`, `/media` or `/mnt`, get the unmount and eject actions, so a USB system disk is never offered for eject. ISO and squashfs mounts are always full and never count as over the threshold.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `barMode` | `"percent"` | Root filesystem figure in the bar: `percent`, `free`, `used` or `none` |
| `warnPct` | `90` | Usage that turns a mount and the bar label urgent |
| `refreshIntervalSec` | `30` | Refresh cadence |

## IPC

```
omarchy-shell joamag.disks toggle
omarchy-shell joamag.disks refresh
omarchy-shell joamag.disks version
```

## Data source

`disks.sh` reads `df` (pseudo filesystems excluded, btrfs subvolumes collapsed to their shortest mount point), `lsblk` for removable flags, parent disks and unmounted partitions, and `du` for the trash and cache sizes. Actions go through `udisksctl` (mount, unmount, power-off) and `gio`; nothing needs root except the package cache cleanup, which asks through sudo in its own terminal.
