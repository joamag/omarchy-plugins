#!/bin/bash

# Last checks before an idle suspend, then the suspend itself. The service
# runs this once the compositor reports the session idle; everything that can
# still veto the suspend is decided here, at fire time, so a Stay Awake or a
# toggle flipped during the idle period is respected.
#
# Prints one "verdict<TAB>reason" line:
#
#   skip     stay-awake    Omarchy's Stay Awake indicator is on
#   skip     suspend-off   suspend is hidden from the system menu (omarchy toggle suspend)
#   skip     inhibited     a systemd block inhibitor holds sleep (update, backup, ...)
#   skip     other-users   another user has a graphical or tty session
#   suspend  idle          systemctl suspend was requested
#   error    message       systemctl is missing or failed
#
# Exit status is 0 for skip and suspend, 1 for error. --dry-run decides but
# never calls systemctl. OMARCHY_STATE_DIR overrides ~/.local/state/omarchy.

set -o pipefail

state_dir="${OMARCHY_STATE_DIR:-$HOME/.local/state/omarchy}"
dry_run=0
[[ ${1:-} == --dry-run ]] && dry_run=1

if [[ -f "$state_dir/indicators/stay-awake" ]]; then
  printf 'skip\tstay-awake\n'
  exit 0
fi

if [[ -f "$state_dir/toggles/suspend-off" ]]; then
  printf 'skip\tsuspend-off\n'
  exit 0
fi

if (( dry_run )); then
  printf 'suspend\tidle\n'
  exit 0
fi

if ! command -v systemctl >/dev/null 2>&1; then
  printf 'error\tsystemctl not found\n'
  exit 1
fi

# systemctl applies the same inhibitor check the menu entry would get from a
# terminal: block inhibitors fail the call with "Operation inhibited" instead
# of asking polkit to override them.
output=$(systemctl suspend --check-inhibitors=yes 2>&1)
status=$?
if (( status == 0 )); then
  printf 'suspend\tidle\n'
  exit 0
fi

if [[ $output == *inhibited* ]]; then
  printf 'skip\tinhibited\n'
  exit 0
fi

if [[ $output == *"is logged in on"* ]]; then
  printf 'skip\tother-users\n'
  exit 0
fi

message=$(printf '%s\n' "$output" | grep -m1 . || true)
printf 'error\t%s\n' "${message:-systemctl suspend exited $status}"
exit 1
