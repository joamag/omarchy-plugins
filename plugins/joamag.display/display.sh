#!/bin/bash

# Display controls as tab-separated lines, plus the actions the popup runs:
#
#   display.sh snapshot [MONITOR]
#     monitor      DP-1
#     bus          3              i2c bus, only when the monitor answers DDC/CI
#     brightness   75             percent, omitted when nothing can report it
#     contrast     75             percent, omitted without DDC/CI
#     gamma        1.00           exponent, omitted when the ramp daemon is down
#     temperature  6500           kelvin, omitted when the ramp daemon is down
#     scale        2              scale of the focused monitor
#     displays     [{...}]        one entry per monitor, as JSON
#   display.sh brightness MONITOR PERCENT
#   display.sh contrast MONITOR PERCENT
#   display.sh gamma EXPONENT
#   display.sh temperature KELVIN
#   display.sh ramp                      just the ramp values, no i2c
#   display.sh restore EXPONENT KELVIN   replay both onto a fresh daemon
#
# The monitor list is part of the same snapshot rather than a second call to
# omarchy-monitor-state: that helper reads DDC brightness itself, and two
# processes reading the same i2c bus at once is asking for a garbled answer.
#
# Brightness is Omarchy's own helper, which already picks the backlight, an
# Apple display or DDC/CI for the monitor; contrast is DDC/CI directly (VCP
# 0x12, MCCS "Contrast").
#
# No monitor exposes a gamma VCP, so gamma is the compositor's gamma ramp,
# driven through wl-gammarelay-rs over D-Bus. Its Gamma is a true exponent
# with 1.0 neutral, the same quantity the NVIDIA control panel calls gamma,
# and its Temperature is the ramp's white point. Both cover every display at
# once. hyprsunset is deliberately not used: it only scales the ramp linearly
# (0-100%), which is a dimmer rather than a gamma curve, and only one client
# can own the ramp at a time.
#
# Actions print "error<TAB>message" when they fail and nothing on success; the
# popup refreshes afterwards.

set -o pipefail

CACHE_DIR=${XDG_RUNTIME_DIR:-/tmp}/joamag-display
# A bus number only changes when displays are replugged, so it is cached until
# a read against it fails. A monitor that does not answer is remembered for a
# minute so a refresh every few seconds does not re-probe every i2c bus.
UNAVAILABLE_TTL=60
# How long to wait for a ramp daemon started on demand, in quarter seconds.
GAMMA_START_ATTEMPTS=${OMARCHY_GAMMA_START_ATTEMPTS:-20}

fail() {
  printf 'error\t%s\n' "$*"
  exit 0
}

monitors_json() {
  hyprctl monitors all -j 2>/dev/null
}

focused_monitor() {
  printf '%s' "$1" | jq -r '[.[] | select(.focused == true)][0].name // ""' 2>/dev/null
}

cache_file() {
  printf '%s/%s.bus' "$CACHE_DIR" "${1//[^[:alnum:]_.-]/_}"
}

detect_bus() {
  # `detect --brief` prints the bus and the DRM connector of each display;
  # the connector carries the same name Hyprland uses, after its card prefix.
  ddcutil --skip-ddc-checks detect --brief 2>/dev/null | awk -v monitor="$1" '
    /I2C bus:/ {
      bus = $NF
      sub(/^.*\/i2c-/, "", bus)
    }
    /DRM connector:/ {
      connector = $NF
      sub(/^card[0-9]+-/, "", connector)
      if (connector == monitor && bus != "") {
        print bus
        exit
      }
      bus = ""
    }
  '
}

find_bus() {
  local monitor="$1" file bus stamp now
  [[ -n $monitor ]] || return 1
  file=$(cache_file "$monitor")

  if [[ -r $file ]]; then
    read -r bus stamp <"$file" || true
    if [[ $bus == unavailable ]]; then
      now=$(date +%s)
      [[ $stamp =~ ^[0-9]+$ ]] && (( now - stamp < UNAVAILABLE_TTL )) && return 1
      rm -f "$file"
    elif [[ $bus =~ ^[0-9]+$ ]]; then
      printf '%s' "$bus"
      return 0
    fi
  fi

  bus=$(detect_bus "$monitor")
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  if [[ ! $bus =~ ^[0-9]+$ ]]; then
    printf 'unavailable %s\n' "$(date +%s)" >"$file" 2>/dev/null || true
    return 1
  fi
  printf '%s\n' "$bus" >"$file" 2>/dev/null || true
  printf '%s' "$bus"
}

forget_bus() {
  rm -f "$(cache_file "$1")" 2>/dev/null || true
}

# Percentage of a VCP pair, rounded half up. A maximum of zero would be a
# monitor answering nonsense, so it is treated as no answer at all.
percent_of() {
  local current="$1" maximum="$2"
  [[ $current =~ ^[0-9]+$ && $maximum =~ ^[0-9]+$ ]] || return 1
  (( maximum > 0 )) || return 1
  printf '%s' "$(( (current * 100 + maximum / 2) / maximum ))"
}

# Both features come back in one exchange: two round trips over the AUX
# channel cost twice the latency for no reason.
read_vcp_pair() {
  ddcutil --bus "$1" --skip-ddc-checks getvcp 10 12 --brief 2>/dev/null | awk '
    $1 == "VCP" && $3 == "C" && $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ {
      print tolower($2), $4, $5
    }
  '
}

set_vcp() {
  local bus="$1" code="$2" raw="$3"
  ddcutil --bus "$bus" --skip-ddc-checks --noverify setvcp "$code" "$raw" >/dev/null 2>&1
}

# The gamma ramp belongs to the compositor, and wl-gammarelay-rs is the client
# that owns it for the session: its Gamma is a true exponent and its
# Temperature the ramp's white point. Readiness is the D-Bus name rather than a
# process match, because the binary name is 16 characters and `pgrep -x`
# compares against a 15-character comm field.
RAMP_BUS=rs.wl-gammarelay
RAMP_IFACE=rs.wl.gammarelay

ramp_get() {
  local out
  out=$(busctl --user get-property "$RAMP_BUS" / "$RAMP_IFACE" "$1" 2>/dev/null) || return 1
  # "d 1.35" or "q 6500"; drop the type prefix busctl puts in front.
  out=${out#* }
  [[ -n $out ]] || return 1
  printf '%s' "$out"
}

ramp_set() {
  busctl --user set-property "$RAMP_BUS" / "$RAMP_IFACE" "$1" "$2" "$3" >/dev/null 2>&1
}

ramp_running() {
  busctl --user list 2>/dev/null | grep -q "^${RAMP_BUS}[[:space:]]"
}

ramp_spawn() {
  command -v wl-gammarelay-rs >/dev/null 2>&1 || return 1
  if command -v uwsm-app >/dev/null 2>&1; then
    setsid uwsm-app -- wl-gammarelay-rs >/dev/null 2>&1 &
  else
    setsid wl-gammarelay-rs >/dev/null 2>&1 &
  fi
}

ramp_ensure_running() {
  ramp_running && return 0
  ramp_spawn || return 1
  local i
  for (( i = 0; i < GAMMA_START_ATTEMPTS; i++ )); do
    ramp_running && return 0
    sleep 0.25
  done
  return 1
}

# Snapshot-side revival: fire the daemon off without waiting for it, so a
# refresh never blocks, and the sliders come back on the next one. The cooldown
# keeps a daemon that refuses to start from being respawned every few seconds.
ramp_revive() {
  local marker="$CACHE_DIR/ramp.attempt" stamp now
  now=$(date +%s)
  if [[ -r $marker ]]; then
    read -r stamp <"$marker" || true
    [[ $stamp =~ ^[0-9]+$ ]] && (( now - stamp < UNAVAILABLE_TTL )) && return 1
  fi
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  printf '%s\n' "$now" >"$marker" 2>/dev/null || true
  ramp_spawn
}

snapshot() {
  local monitor="$1" bus="" feature current maximum value monitors
  monitors=$(monitors_json)
  [[ -n $monitor ]] || monitor=$(focused_monitor "$monitors")
  [[ -n $monitor ]] && printf 'monitor\t%s\n' "$monitor"

  if bus=$(find_bus "$monitor"); then
    printf 'bus\t%s\n' "$bus"
    while read -r feature current maximum; do
      value=$(percent_of "$current" "$maximum") || continue
      case "$feature" in
        10) printf 'brightness\t%s\n' "$value" ;;
        12) printf 'contrast\t%s\n' "$value" ;;
      esac
    done < <(read_vcp_pair "$bus")
  fi

  # No DDC/CI: a laptop backlight or an Apple display still reports brightness
  # through Omarchy's helper, and contrast simply does not exist there.
  if [[ -z $bus ]]; then
    value=$(omarchy-brightness-display --monitor "$monitor" 2>/dev/null | head -n 1)
    [[ $value =~ ^[0-9]+$ ]] && printf 'brightness\t%s\n' "$value"
  fi

  if ramp_running; then
    value=$(ramp_get Gamma) && printf 'gamma\t%s\n' "$value"
    value=$(ramp_get Temperature) && printf 'temperature\t%s\n' "$value"
  else
    ramp_revive || true
  fi

  value=$(omarchy-hyprland-monitor-scaling 2>/dev/null) && [[ -n $value ]] && printf 'scale\t%s\n' "$value"
  value=$(printf '%s' "$monitors" | jq -c '[.[] | {name, enabled:(.disabled != true), focused:(.focused == true), width, height}]' 2>/dev/null)
  [[ -n $value ]] && printf 'displays\t%s\n' "$value"
}

clamp_percent() {
  local value="$1" low="$2"
  [[ $value =~ ^[0-9]+$ ]] || return 1
  (( value < low )) && value=$low
  (( value > 100 )) && value=100
  printf '%s' "$value"
}

# Gamma is a decimal exponent, so the clamping is done in awk rather than in
# bash arithmetic, and the value is printed the way the D-Bus double wants it.
clamp_gamma() {
  [[ $1 =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v v="$1" 'BEGIN { if (v < 0.3) v = 0.3; if (v > 2.8) v = 2.8; printf "%.2f", v }'
}

clamp_kelvin() {
  [[ $1 =~ ^[0-9]+$ ]] || return 1
  local value="$1"
  (( value < 1000 )) && value=1000
  (( value > 10000 )) && value=10000
  printf '%s' "$value"
}

command=${1:-snapshot}
shift || true

case "$command" in
  snapshot)
    snapshot "${1:-}"
    ;;
  brightness)
    monitor=${1:?monitor required}
    percent=$(clamp_percent "${2:-}" 1) || fail "brightness percent required"
    # Omarchy's helper owns every kind of display and the OSD lock, so the
    # widget never writes VCP 0x10 itself.
    omarchy-brightness-display --no-osd --monitor "$monitor" "$percent%" >/dev/null 2>&1 ||
      fail "could not set brightness on $monitor"
    ;;
  contrast)
    monitor=${1:?monitor required}
    percent=$(clamp_percent "${2:-}" 0) || fail "contrast percent required"
    bus=$(find_bus "$monitor") || fail "$monitor does not answer DDC/CI"
    # Every monitor seen so far reports 0..100 for contrast, but the maximum
    # is what the scale is really against, so it is read rather than assumed.
    maximum=$(read_vcp_pair "$bus" | awk '$1 == "12" { print $3; exit }')
    [[ $maximum =~ ^[0-9]+$ ]] && (( maximum > 0 )) || { forget_bus "$monitor"; fail "$monitor does not report contrast"; }
    if ! set_vcp "$bus" 12 "$(( (percent * maximum + 50) / 100 ))"; then
      forget_bus "$monitor"
      fail "could not set contrast on $monitor"
    fi
    ;;
  gamma)
    value=$(clamp_gamma "${1:-}") || fail "gamma exponent required"
    ramp_ensure_running || fail "wl-gammarelay-rs is not available"
    ramp_set Gamma d "$value" || fail "could not set gamma to $value"
    ;;
  temperature)
    value=$(clamp_kelvin "${1:-}") || fail "temperature in kelvin required"
    ramp_ensure_running || fail "wl-gammarelay-rs is not available"
    ramp_set Temperature q "$value" || fail "could not set temperature to $value"
    ;;
  ramp)
    # Just the two ramp values, and nothing at all when the daemon is down.
    # Costs one D-Bus round trip and never touches i2c, so the widget can
    # afford to run it on a timer while the popup is closed.
    if ramp_running; then
      value=$(ramp_get Gamma) && printf 'gamma\t%s\n' "$value"
      value=$(ramp_get Temperature) && printf 'temperature\t%s\n' "$value"
    fi
    ;;
  restore)
    # Both ramp values in one run, for the widget to replay what it remembered
    # onto a daemon that has just come up at its own defaults.
    gamma=$(clamp_gamma "${1:-1}") || fail "gamma exponent required"
    kelvin=$(clamp_kelvin "${2:-6500}") || fail "temperature in kelvin required"
    ramp_ensure_running || fail "wl-gammarelay-rs is not available"
    ramp_set Gamma d "$gamma" || fail "could not set gamma to $gamma"
    ramp_set Temperature q "$kelvin" || fail "could not set temperature to $kelvin"
    ;;
  *)
    echo "Usage: display.sh [snapshot [MONITOR] | brightness MONITOR PCT | contrast MONITOR PCT | gamma EXPONENT | temperature KELVIN | ramp | restore EXPONENT KELVIN]" >&2
    exit 1
    ;;
esac
