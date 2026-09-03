#!/bin/bash

# Fetch market data from Yahoo Finance's public chart endpoint (no API key) and
# emit one compact JSON object per line:
#
#   quotes.sh quotes SYMBOL [SYMBOL...]   intraday (1d, 5 minute) data per symbol
#   quotes.sh series SYMBOL RANGE         closes for RANGE: 1d 5d 1mo 6mo 1y 5y
#
# Each object carries symbol, name, currency, price, prevClose, high, low,
# state and points ([unix time, close] pairs). Failures become
# {"symbol":..., "error":...} so one bad ticker never hides the others.

set -o pipefail

UA="Mozilla/5.0 (X11; Linux x86_64) omarchy-stocks/0.1"
BASE="https://query1.finance.yahoo.com/v8/finance/chart"

urlencode() {
  local s="$1" out="" c hex i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case $c in
      [a-zA-Z0-9.~_-]) out+=$c ;;
      *) printf -v hex '%%%02X' "'$c"; out+=$hex ;;
    esac
  done
  printf '%s' "$out"
}

interval_for() {
  case "$1" in
    1d) echo 5m ;;
    5d) echo 30m ;;
    1mo | 3mo | 6mo) echo 1d ;;
    1y | 2y) echo 1wk ;;
    5y | 10y | max) echo 1mo ;;
    *) echo 1d ;;
  esac
}

json_string() { jq -Rn --arg s "$1" '$s'; }

fetch_once() {
  local sym="$1" range="$2" interval
  interval=$(interval_for "$range")
  curl -sS --max-time 10 -A "$UA" \
    "$BASE/$(urlencode "$sym")?range=$range&interval=$interval&includePrePost=false" 2>/dev/null |
    jq -c --arg sym "$sym" --arg range "$range" '
      (.chart.result[0]) as $r
      | if $r == null then
          { symbol: $sym, range: $range, error: (.chart.error.description // "no data") }
        else
          {
            symbol: ($r.meta.symbol // $sym),
            range: $range,
            name: ($r.meta.shortName // $r.meta.longName // $sym),
            currency: ($r.meta.currency // ""),
            exchange: ($r.meta.exchangeName // ""),
            price: $r.meta.regularMarketPrice,
            prevClose: ($r.meta.chartPreviousClose // $r.meta.previousClose),
            high: $r.meta.regularMarketDayHigh,
            low: $r.meta.regularMarketDayLow,
            time: $r.meta.regularMarketTime,
            state: ($r.meta.marketState // ""),
            points: [ range(0; (($r.timestamp // []) | length)) as $i
                      | select($r.indicators.quote[0].close[$i] != null)
                      | [$r.timestamp[$i], $r.indicators.quote[0].close[$i]] ]
          }
        end' 2>/dev/null ||
    printf '{"symbol":%s,"range":%s,"error":"fetch failed"}\n' "$(json_string "$sym")" "$(json_string "$range")"
}

# Yahoo occasionally drops one request out of a parallel batch; a single
# retry after a short pause recovers nearly all of those without making a
# genuinely unknown symbol wait long.
fetch() {
  local out
  out=$(fetch_once "$1" "$2")
  if jq -e '.error' <<<"$out" >/dev/null 2>&1; then
    sleep 0.4
    out=$(fetch_once "$1" "$2")
  fi
  printf '%s\n' "$out"
}

mode=${1:-}
shift || true

case "$mode" in
  quotes)
    (( $# > 0 )) || exit 0
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    i=0
    for sym in "$@"; do
      fetch "$sym" 1d >"$tmp/$i.json" &
      (( i++ ))
    done
    wait
    for (( j = 0; j < i; j++ )); do cat "$tmp/$j.json"; done
    ;;
  series)
    [[ -n ${1:-} ]] || exit 1
    fetch "$1" "${2:-1mo}"
    ;;
  *)
    echo "Usage: quotes.sh quotes SYMBOL... | series SYMBOL RANGE" >&2
    exit 1
    ;;
esac
