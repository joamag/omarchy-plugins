#!/bin/bash

# OpenRGB devices as tab-separated lines for the widget, plus the one action
# the popup runs:
#
#   rgb.sh                          snapshot:
#     state   ok | missing | error
#     error   message, only with state error
#     device  index  name  type  serial  modes   (one per device, modes as OpenRGB prints them)
#   rgb.sh set INDEX MODE [COLOR [SPEED]]
#                                   switch device INDEX to MODE, painted COLOR
#                                   (RRGGBB) when the mode takes one, running at
#                                   SPEED (0-100% of its range) when it has one
#
# OpenRGB talks to its SDK server when one is running (the openrgb service)
# and detects every device itself otherwise, which takes a few seconds a call.
# Either way it reports a mode it does not know, a colour it cannot parse or a
# number of colours the mode does not take on its output and still exits 0, so
# its words are checked as well as its exit status. A mode that takes more
# colours than one says how many, and is asked again with that many of it.
#
# The set action prints "error<TAB>message" when it fails and nothing on
# success; the popup keeps what it asked for either way.

set -o pipefail

fail() {
  printf 'error\t%s\n' "$*"
  exit 0
}

# The first thing OpenRGB said went wrong: its "Error: ..." line without the
# prefix, its complaint about the number of colours a mode takes, or the exit
# status when it failed without a word.
error_of() {
  local output="$1" status="$2" message
  message=$(printf '%s\n' "$output" | sed -n -e 's/^Error: *//p' -e '/^Wrong number of colors/p' | head -n 1)
  if [[ -z $message ]] && (( status == 124 )); then message="OpenRGB took too long to answer"; fi
  if [[ -z $message ]] && (( status != 0 )); then message="openrgb exited $status"; fi
  printf '%s' "$message"
}

# Runs the set action with COLORS (one or more, comma separated, or none),
# leaving what OpenRGB said in $out and its exit status in $status.
set_device() {
  local colors="$1" args=(--device "$index" --mode "$mode")
  [[ -n $colors ]] && args+=(--color "$colors")
  [[ -n $speed ]] && args+=(--speed "$((10#$speed))")
  out=$(timeout 30 openrgb "${args[@]}" 2>&1)
  status=$?
}

snapshot() {
  if ! command -v openrgb >/dev/null 2>&1; then
    printf 'state\tmissing\n'
    exit 0
  fi

  local out status message
  out=$(timeout 30 openrgb --list-devices 2>&1)
  status=$?
  # Newer OpenRGB lists the names alone under --list-devices and moved the rest
  # to --list-detailed, which older ones do not know, so a list of devices
  # without a single mode line is the short one and is asked for again.
  if (( status == 0 )) && grep -q '^[0-9]\+: ' <<<"$out" && ! grep -q '^ \+Modes:' <<<"$out"; then
    out=$(timeout 30 openrgb --list-detailed 2>&1)
    status=$?
  fi
  message=$(error_of "$out" "$status")
  if [[ -n $message ]]; then
    printf 'state\terror\nerror\t%s\n' "${message//$'\t'/ }"
    exit 0
  fi

  printf 'state\tok\n'
  # One block per device: "N: name", then indented "Type:", "Serial:" and
  # "Modes:" lines among others. Whatever OpenRGB says about its server before
  # the list is not a device header and is skipped.
  awk '
    function flush() {
      if (idx != "") printf "device\t%s\t%s\t%s\t%s\t%s\n", idx, name, type, serial, modes
      idx = ""; name = ""; type = ""; serial = ""; modes = ""
    }
    /^[0-9]+: / {
      flush()
      idx = $1; sub(/:$/, "", idx)
      name = $0; sub(/^[0-9]+: /, "", name); gsub(/\t/, " ", name)
      next
    }
    idx == "" { next }
    /^ +Type:/ { type = $0; sub(/^ +Type: */, "", type); next }
    /^ +Serial:/ { serial = $0; sub(/^ +Serial: */, "", serial); gsub(/[ \t]+$/, "", serial); gsub(/\t/, " ", serial); next }
    /^ +Modes:/ { modes = $0; sub(/^ +Modes: */, "", modes); gsub(/\t/, " ", modes); next }
    END { flush() }
  ' <<<"$out"
}

case "${1:-}" in
  "")
    snapshot
    ;;
  set)
    index=${2:-}
    mode=${3:-}
    color=${4:-}
    speed=${5:-}
    [[ $index =~ ^[0-9]+$ ]] || fail "device index required"
    [[ -n $mode ]] || fail "mode required"
    if [[ -n $color ]]; then
      [[ $color =~ ^[0-9A-Fa-f]{6}$ ]] || fail "colour must be six hex digits"
    fi
    if [[ -n $speed ]]; then
      [[ $speed =~ ^[0-9]{1,3}$ ]] && (( 10#$speed <= 100 )) || fail "speed must be 0 to 100"
    fi
    command -v openrgb >/dev/null 2>&1 || fail "openrgb not found"
    set_device "$color"
    # OpenRGB checks the count before it switches anything, so asking again
    # with the least the mode takes, all in the one colour, is safe.
    if [[ -n $color && $out =~ Please\ provide\ between\ ([0-9]{1,2})\ and\ [0-9]+\ colors ]] && (( 10#${BASH_REMATCH[1]} > 1 )); then
      wanted=$((10#${BASH_REMATCH[1]}))
      colors=$color
      for (( i = 1; i < wanted; i++ )); do colors+=",$color"; done
      set_device "$colors"
    fi
    message=$(error_of "$out" "$status")
    [[ -z $message ]] || fail "$message"
    ;;
  *)
    echo "Usage: rgb.sh [set INDEX MODE [COLOR [SPEED]]]" >&2
    exit 1
    ;;
esac
