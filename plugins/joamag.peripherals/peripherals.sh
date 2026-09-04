#!/bin/bash

# One snapshot of every battery-powered peripheral, as tab-separated lines
# for the widget:
#
#   solaar   1 | 0                                   whether Solaar is installed
#   device   path  type  model  state  pct  level  minutes
#
#   peripherals.sh           the snapshot
#   peripherals.sh solaar    read the receivers through Solaar's library and
#                            rewrite the cache the snapshot merges in
#
# A single `upower -d` answers for every device the kernel drives. The
# machine's own battery and mains are left out: Omarchy's battery service
# owns those, this widget is for the mouse, keyboard and headset. Coarse
# devices (Logitech's HID++ mice report full/high/normal/low/critical rather
# than a percentage) carry the level word and a percentage upower says to
# ignore; the widget shows the word and only uses the number for the glyph.
#
# A receiver the kernel does not drive gives upower nothing: this kernel's
# hid-logitech-dj has no entry for the Bolt receiver (046d:c548), so a
# keyboard paired to one is invisible there. A second source reads the
# receivers directly through Solaar's own library, the way Solaar does. That
# read costs about a second per paired slot on a Bolt receiver, so it runs in
# the background and the snapshot merges its last result, deduplicated by
# serial against what upower reported, upower winning.

set -o pipefail

CACHE_DIR=${XDG_RUNTIME_DIR:-/tmp}/joamag-peripherals
SOLAAR_CACHE=$CACHE_DIR/solaar.tsv
# How old the Solaar reading may get before a snapshot asks for a new one in
# the background; a keyboard loses about a percent an hour.
SOLAAR_TTL=${OMARCHY_PERIPHERALS_SOLAAR_TTL:-120}

have_solaar() {
  command -v solaar >/dev/null 2>&1
}

# upower's devices, with the deduplication key (the serial, or failing that
# the model, reduced to its alphanumerics) as a ninth column that is cut off
# again before the widget sees it.
upower_devices() {
  command -v upower >/dev/null 2>&1 || return 0
  # Minutes from upower's "3.2 hours" / "45.0 minutes" time estimates.
  upower -d 2>/dev/null | awk '
    function normalize(s) { gsub(/[^0-9A-Za-z]/, "", s); return toupper(s) }
    function flush(    key) {
      if (path != "" && present != "no" && type != "line-power" && type != "battery" && path !~ /DisplayDevice$/) {
        key = normalize(serial)
        if (key == "") key = normalize(model)
        printf "device\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", path, type, model, state, pct, level, minutes, key
      }
      path = ""; type = "unknown"; model = ""; serial = ""; state = ""; pct = ""; level = ""; minutes = ""; present = ""
    }
    /^Device:/ { flush(); path = $2; next }
    /^Daemon:/ { flush(); exit }
    path == "" { next }
    # The device type is the one line with a two-space indent and no colon.
    /^  [a-z-]+$/ { type = $1; next }
    /^ +model:/ { sub(/^ +model: +/, ""); model = $0; next }
    /^ +serial:/ { serial = $2; next }
    /^ +present:/ { present = $2; next }
    /^ +state:/ { state = $2; next }
    /^ +battery-level:/ { level = $2; next }
    /^ +percentage:/ { pct = $2; sub(/%$/, "", pct); next }
    /^ +time to (empty|full):/ {
      n = $(NF - 1); unit = $NF
      if (unit ~ /^hour/) minutes = int(n * 60 + 0.5)
      else if (unit ~ /^minute/) minutes = int(n + 0.5)
      else if (unit ~ /^second/) minutes = int(n / 60 + 0.5)
      next
    }
    END { flush() }
  '
}

# The receivers through Solaar's library: every online device with a battery
# reading, in the same nine columns. Quiet when the library is not there.
solaar_devices() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - 2>/dev/null <<'PY'
import sys

try:
    from logitech_receiver import base, receiver
    from logitech_receiver.common import BatteryLevelApproximation, BatteryStatus
except Exception:
    sys.exit(0)


def normalize(value):
    return "".join(c for c in str(value or "") if c.isalnum()).upper()


# upower's words for a coarse reading. A device on the old BATTERY STATUS
# feature reports one of four discharge levels, either as the approximation
# enum or as a quantised percentage with a "next level" attached.
def level_word(battery):
    level = battery.level
    if isinstance(level, BatteryLevelApproximation):
        return {"FULL": "full", "GOOD": "normal", "LOW": "low", "CRITICAL": "critical", "EMPTY": "critical"}.get(level.name, "")
    if battery.next_level is not None and isinstance(level, int):
        return "full" if level >= 90 else "normal" if level >= 50 else "low" if level >= 20 else "critical"
    return ""


def state_word(battery):
    status = battery.status
    if status in (BatteryStatus.RECHARGING, BatteryStatus.ALMOST_FULL, BatteryStatus.SLOW_RECHARGE):
        return "charging"
    if status == BatteryStatus.FULL:
        return "fully-charged"
    if status == BatteryStatus.DISCHARGING:
        return "discharging"
    return "unknown"


for info in base.receivers():
    try:
        found = receiver.create_receiver(base, info)
    except Exception:
        found = None
    if found is None:
        continue
    try:
        for dev in found:
            try:
                if dev is None or not dev.online:
                    continue
                battery = dev.battery()
            except Exception:
                continue
            if battery is None or battery.status == BatteryStatus.OFFLINE:
                continue
            pct = int(battery.level) if isinstance(battery.level, int) else ""
            key = normalize(dev.serial) or normalize(dev.name)
            print("device\tsolaar:%s\t%s\t%s\t%s\t%s\t%s\t\t%s" % (key, dev.kind, dev.name, state_word(battery), pct, level_word(battery), key))
    finally:
        found.close()
PY
}

# One reader at a time: the widget fires several snapshots at startup, and
# two readers writing the same file would interleave their lines. Each reader
# writes its own temporary file and moves it into place whole.
refresh_solaar_cache() {
  mkdir -p "$CACHE_DIR" 2>/dev/null || return 1
  exec {lock_fd}>"$CACHE_DIR/solaar.lock"
  flock -n "$lock_fd" || return 0
  local tmp
  tmp=$(mktemp "$CACHE_DIR/solaar.XXXXXX") || return 1
  if solaar_devices >"$tmp"; then
    mv "$tmp" "$SOLAAR_CACHE"
  else
    rm -f "$tmp"
  fi
}

# Age of a file in seconds, or a very old age when it does not exist.
age_of() {
  local stamp
  stamp=$(stat -c %Y "$1" 2>/dev/null) || { printf '%s' "$SOLAAR_TTL"; return; }
  printf '%s' "$(( $(date +%s) - stamp ))"
}

# Ask for a fresh Solaar reading when the cache has aged out, without waiting
# for it; the marker keeps two snapshots from asking at once.
solaar_refresh_in_background() {
  have_solaar || return 0
  (( $(age_of "$SOLAAR_CACHE") >= SOLAAR_TTL )) || return 0
  (( $(age_of "$CACHE_DIR/solaar.attempt") >= SOLAAR_TTL )) || return 0
  mkdir -p "$CACHE_DIR" 2>/dev/null || return 0
  touch "$CACHE_DIR/solaar.attempt"
  setsid "$0" solaar >/dev/null 2>&1 &
}

snapshot() {
  if have_solaar; then
    printf 'solaar\t1\n'
  else
    printf 'solaar\t0\n'
  fi
  # upower first, so it wins the deduplication; a device without a key is
  # never a duplicate of anything, and only a whole device line gets through.
  { upower_devices; [[ -r $SOLAAR_CACHE ]] && cat "$SOLAAR_CACHE"; } |
    awk -F'\t' '$1 == "device" && NF == 9 && ($9 == "" || !seen[$9]++)' | cut -f1-8
  solaar_refresh_in_background
}

case "${1:-}" in
  "")
    snapshot
    ;;
  solaar)
    refresh_solaar_cache
    ;;
  *)
    echo "Usage: peripherals.sh [solaar]" >&2
    exit 1
    ;;
esac
