#!/bin/bash

# OpenRGB devices as tab-separated lines for the widget, plus the one action
# the popup runs:
#
#   rgb.sh                          snapshot:
#     state   ok | missing | error
#     error   message, only with state error
#     device  index  name  type  modes    (one per device, modes as OpenRGB prints them)
#   rgb.sh set INDEX MODE [COLOR]   switch device INDEX to MODE, painted COLOR
#                                   (RRGGBB) when the mode takes one
#
# OpenRGB talks to its SDK server when one is running (the openrgb service)
# and detects every device itself otherwise, which takes a few seconds a call.
# Either way it reports a mode it does not know or a colour it cannot parse on
# its output and still exits 0, so its words are checked as well as its exit
# status.
#
# The set action prints "error<TAB>message" when it fails and nothing on
# success; the popup keeps what it asked for either way.

set -o pipefail

fail() {
  printf 'error\t%s\n' "$*"
  exit 0
}

# The first thing OpenRGB said went wrong: its "Error: ..." line without the
# prefix, or the exit status when it failed without one.
error_of() {
  local output="$1" status="$2" message
  message=$(printf '%s\n' "$output" | sed -n 's/^Error: *//p' | head -n 1)
  if [[ -z $message ]] && (( status == 124 )); then message="OpenRGB took too long to answer"; fi
  if [[ -z $message ]] && (( status != 0 )); then message="openrgb exited $status"; fi
  printf '%s' "$message"
}

snapshot() {
  if ! command -v openrgb >/dev/null 2>&1; then
    printf 'state\tmissing\n'
    exit 0
  fi

  local out status message
  out=$(timeout 30 openrgb --list-devices 2>&1)
  status=$?
  message=$(error_of "$out" "$status")
  if [[ -n $message ]]; then
    printf 'state\terror\nerror\t%s\n' "${message//$'\t'/ }"
    exit 0
  fi

  printf 'state\tok\n'
  # One block per device: "N: name", then indented "Type:" and "Modes:" lines
  # among others. Whatever OpenRGB says about its server before the list is
  # not a device header and is skipped.
  awk '
    function flush() {
      if (idx != "") printf "device\t%s\t%s\t%s\t%s\n", idx, name, type, modes
      idx = ""; name = ""; type = ""; modes = ""
    }
    /^[0-9]+: / {
      flush()
      idx = $1; sub(/:$/, "", idx)
      name = $0; sub(/^[0-9]+: /, "", name); gsub(/\t/, " ", name)
      next
    }
    idx == "" { next }
    /^ +Type:/ { type = $0; sub(/^ +Type: */, "", type); next }
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
    [[ $index =~ ^[0-9]+$ ]] || fail "device index required"
    [[ -n $mode ]] || fail "mode required"
    args=(--device "$index" --mode "$mode")
    if [[ -n $color ]]; then
      [[ $color =~ ^[0-9A-Fa-f]{6}$ ]] || fail "colour must be six hex digits"
      args+=(--color "$color")
    fi
    command -v openrgb >/dev/null 2>&1 || fail "openrgb not found"
    out=$(timeout 30 openrgb "${args[@]}" 2>&1)
    status=$?
    message=$(error_of "$out" "$status")
    [[ -z $message ]] || fail "$message"
    ;;
  *)
    echo "Usage: rgb.sh [set INDEX MODE [COLOR]]" >&2
    exit 1
    ;;
esac
