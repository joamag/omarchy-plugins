#!/bin/bash

# Turns the displays off or back on for the screen-off service, with the same
# Omarchy commands the lock screen blanks and wakes with, so both leave the
# machine in the same state: DPMS and the keyboard backlight off on the way
# down, both restored on the way back.
#
#   screenoff.sh off [--dry-run]   turn the displays off, as long as Stay Awake is still on
#   screenoff.sh on [--dry-run]    turn them back on
#
# Prints one "verdict<TAB>reason" line:
#
#   off    idle        the displays were turned off
#   on     activity    the displays were turned back on
#   skip   allow-idle  Stay Awake was switched off first, Omarchy's own idle service is back in charge
#   error  message     an Omarchy command is missing or failed
#
# Exit status is 0 for off, on and skip, 1 for error. --dry-run decides but
# touches nothing. OMARCHY_STATE_DIR overrides ~/.local/state/omarchy.

set -o pipefail

state_dir="${OMARCHY_STATE_DIR:-$HOME/.local/state/omarchy}"
action="${1:-}"
dry_run=0
[[ ${2:-} == --dry-run ]] && dry_run=1

fail() {
  printf 'error\t%s\n' "$*"
  exit 1
}

# Runs an Omarchy command and stops with the first line it printed when it
# fails, or with its exit status when it failed without a word.
run() {
  local output status message
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found"
  output=$("$@" 2>&1)
  status=$?
  (( status == 0 )) && return 0
  message=$(printf '%s\n' "$output" | grep -m1 . || true)
  fail "${message:-$* exited $status}"
}

case "$action" in
  off)
    # Decided at fire time, so a Stay Awake switched off during the idle
    # period leaves the displays to the shell's own idle service.
    if [[ ! -f "$state_dir/indicators/stay-awake" ]]; then
      printf 'skip\tallow-idle\n'
      exit 0
    fi
    if (( ! dry_run )); then
      # Not every machine has a keyboard backlight, and one that will not dim
      # is no reason to leave the displays on.
      omarchy-brightness-keyboard off >/dev/null 2>&1 || true
      run omarchy-brightness-display off
    fi
    printf 'off\tidle\n'
    ;;
  on)
    (( dry_run )) || run omarchy-system-wake
    printf 'on\tactivity\n'
    ;;
  *)
    echo "Usage: screenoff.sh off|on [--dry-run]" >&2
    exit 1
    ;;
esac
