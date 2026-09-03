#!/bin/bash

# Disk snapshot as tab-separated lines, plus the actions the popup offers.
#
#   disks.sh                 snapshot:
#     mount   target source fstype size_kb used_kb avail_kb pct label removable disk
#     volume  path label fstype size disk       removable partition with a filesystem, not mounted
#     trash_kb / trash_items / pkgcache_kb / pkgcache_files
#   disks.sh unmount TARGET  unmount the filesystem at TARGET
#   disks.sh eject DISK      unmount every partition of DISK, then power it off
#   disks.sh mount DEVICE    mount a partition through udisks
#   disks.sh empty-trash     empty the user's trash
#
# Actions print "error<TAB>message" when they fail and nothing on success; the
# popup refreshes afterwards. Removable means the kernel flags the device
# removable, so a USB system disk is never offered for eject.

set -o pipefail

CACHE_DIR=${OMARCHY_PKG_CACHE:-/var/cache/pacman/pkg}
TRASH_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files

fail() {
  printf 'error\t%s\n' "$*"
  exit 0
}

snapshot() {
  # Device flags from lsblk, keyed by path: removable bit and parent disk.
  declare -A removable parent
  while IFS= read -r line; do
    eval "$line"
    [[ -n ${PATH_:-} ]] || continue
    removable[$PATH_]=$RM
    parent[$PATH_]=$PKNAME
  done < <(lsblk -P -o PATH,PKNAME,RM,TYPE 2>/dev/null | sed 's/^PATH=/PATH_=/')

  disk_of() {
    local dev="$1"
    while [[ -n ${parent[$dev]:-} ]]; do dev="/dev/${parent[$dev]}"; done
    printf '%s' "$dev"
  }

  is_removable() {
    local dev="$1"
    while [[ -n $dev ]]; do
      [[ ${removable[$dev]:-0} == 1 ]] && return 0
      [[ -n ${parent[$dev]:-} ]] || return 1
      dev="/dev/${parent[$dev]}"
    done
    return 1
  }

  # One line per filesystem. btrfs subvolumes repeat the same device and
  # numbers under several targets; the shortest target represents them all.
  declare -A seen
  while read -r source fstype size used avail pct target; do
    [[ $source == /dev/* ]] || continue
    key="$source|$size|$used"
    [[ -n ${seen[$key]:-} ]] && continue
    seen[$key]=1
    label=$(lsblk -nro LABEL "$source" 2>/dev/null | head -n 1)
    disk=$(disk_of "$source")
    flag=0
    if is_removable "$source" && [[ $target == /run/media/* || $target == /media/* || $target == /mnt/* ]]; then flag=1; fi
    printf 'mount\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$source" "$fstype" "$size" "$used" "$avail" "${pct%\%}" "$label" "$flag" "$disk"
  done < <(df -PkT -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay -x fuse.portal 2>/dev/null | awk 'NR > 1' | sort -k7)

  # Removable partitions carrying a filesystem but not mounted anywhere.
  while IFS= read -r line; do
    eval "$line"
    [[ $TYPE == part && -n $FSTYPE && -z $MOUNTPOINTS ]] || continue
    is_removable "$PATH_" || continue
    printf 'volume\t%s\t%s\t%s\t%s\t%s\n' "$PATH_" "$LABEL" "$FSTYPE" "$SIZE" "$(disk_of "$PATH_")"
  done < <(lsblk -P -o PATH,TYPE,FSTYPE,LABEL,MOUNTPOINTS,SIZE 2>/dev/null | sed 's/^PATH=/PATH_=/')

  if [[ -d $TRASH_DIR ]]; then
    printf 'trash_kb\t%s\n' "$(du -sk "$TRASH_DIR" 2>/dev/null | cut -f1)"
    printf 'trash_items\t%s\n' "$(find "$TRASH_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
  else
    printf 'trash_kb\t0\ntrash_items\t0\n'
  fi
  if [[ -d $CACHE_DIR ]]; then
    printf 'pkgcache_kb\t%s\n' "$(du -sk "$CACHE_DIR" 2>/dev/null | cut -f1)"
    printf 'pkgcache_files\t%s\n' "$(find "$CACHE_DIR" -maxdepth 1 -type f \( -name '*.pkg.tar.*' ! -name '*.sig' \) 2>/dev/null | wc -l)"
  fi
}

case "${1:-}" in
  "")
    snapshot
    ;;
  unmount)
    target=${2:?target required}
    source=$(findmnt -n -o SOURCE --mountpoint "$target" 2>/dev/null)
    [[ -n $source ]] || fail "nothing is mounted at $target"
    udisksctl unmount -b "${source%%\[*}" --no-user-interaction >/dev/null 2>"${TMPDIR:-/tmp}/disks.err" || fail "$(tr '\n' ' ' <"${TMPDIR:-/tmp}/disks.err")"
    ;;
  eject)
    disk=${2:?disk required}
    while read -r part mountpoint; do
      [[ -n $mountpoint ]] || continue
      udisksctl unmount -b "$part" --no-user-interaction >/dev/null 2>&1 || fail "could not unmount $part"
    done < <(lsblk -nro PATH,MOUNTPOINT "$disk" 2>/dev/null)
    udisksctl power-off -b "$disk" --no-user-interaction >/dev/null 2>"${TMPDIR:-/tmp}/disks.err" || fail "$(tr '\n' ' ' <"${TMPDIR:-/tmp}/disks.err")"
    ;;
  mount)
    device=${2:?device required}
    udisksctl mount -b "$device" --no-user-interaction >/dev/null 2>"${TMPDIR:-/tmp}/disks.err" || fail "$(tr '\n' ' ' <"${TMPDIR:-/tmp}/disks.err")"
    ;;
  empty-trash)
    gio trash --empty 2>"${TMPDIR:-/tmp}/disks.err" || fail "$(tr '\n' ' ' <"${TMPDIR:-/tmp}/disks.err")"
    ;;
  *)
    echo "Usage: disks.sh [unmount TARGET | eject DISK | mount DEVICE | empty-trash]" >&2
    exit 1
    ;;
esac
