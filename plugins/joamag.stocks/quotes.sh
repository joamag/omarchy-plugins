#!/bin/bash

# Fetch market data from Yahoo Finance's public chart endpoint (no API key) and
# emit one compact JSON object per line:
#
#   quotes.sh quotes SYMBOL [SYMBOL...]   intraday (1d, 5 minute) data per symbol
#   quotes.sh series SYMBOL RANGE         closes for RANGE: 1d 5d 1mo 6mo 1y 5y
#   quotes.sh search QUERY                symbol suggestions for the add field
#   quotes.sh news [SYMBOL]               headlines for SYMBOL, or the top stories
#
# Each object carries symbol, name, currency, price, prevClose, high, low,
# state and points ([unix time, close] pairs). Failures become
# {"symbol":..., "error":...} so one bad ticker never hides the others.

set -o pipefail

UA="Mozilla/5.0 (X11; Linux x86_64) omarchy-stocks/0.1"
BASE="https://query1.finance.yahoo.com/v8/finance/chart"

# Top stories for the news tab, as "source|url" pairs.
FEEDS=(
  "CNBC|https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114"
  "MarketWatch|https://feeds.content.dowjones.io/public/rss/mw_topstories"
)

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

# Symbol search for autocomplete: one JSON line with up to eight matches,
# each with symbol, name, exchange and type.
search() {
  local query="$1"
  curl -sS --max-time 6 -A "$UA" \
    "https://query2.finance.yahoo.com/v1/finance/search?q=$(urlencode "$query")&quotesCount=8&newsCount=0&listsCount=0&enableFuzzyQuery=false" 2>/dev/null |
    jq -c --arg query "$query" '
      { query: $query,
        results: [ (.quotes // [])[]
                   | select(.symbol != null)
                   | { symbol: .symbol,
                       name: (.shortname // .longname // .symbol),
                       exchange: (.exchDisp // ""),
                       type: (.typeDisp // .quoteType // "") } ] }' 2>/dev/null ||
    printf '{"query":%s,"results":[],"error":"search failed"}\n' "$(json_string "$query")"
}

# Headlines for one symbol: one JSON line with up to ten items, each with
# title, publisher, time and link.
symbol_news() {
  local sym="$1"
  curl -sS --max-time 6 -A "$UA" \
    "https://query2.finance.yahoo.com/v1/finance/search?q=$(urlencode "$sym")&quotesCount=0&newsCount=10&listsCount=0" 2>/dev/null |
    jq -c --arg feed "$sym" '
      { feed: $feed,
        items: [ (.news // [])[]
                 | select(.title != null and .link != null)
                 | { title: .title,
                     publisher: (.publisher // ""),
                     time: .providerPublishTime,
                     link: .link } ] }' 2>/dev/null ||
    printf '{"feed":%s,"items":[],"error":"news failed"}\n' "$(json_string "$sym")"
}

# One RSS feed handed over whole as a JSON line; Model.js reads the items, so
# no XML tool is needed here.
rss() {
  local source="$1" url="$2" body
  body=$(curl -sS --max-time 8 -A "$UA" "$url" 2>/dev/null)
  if [[ $body != *"<item"* ]]; then
    printf '{"feed":"markets","source":%s,"error":"fetch failed"}\n' "$(json_string "$source")"
    return
  fi
  jq -Rsc --arg source "$source" '{ feed: "markets", source: $source, xml: . }' <<<"$body"
}

# Top stories: every feed fetched in parallel, one line each, in FEEDS order.
top_news() {
  local tmp i=0 entry
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  for entry in "${FEEDS[@]}"; do
    rss "${entry%%|*}" "${entry#*|}" >"$tmp/$i.json" &
    (( i++ ))
  done
  wait
  for (( j = 0; j < i; j++ )); do cat "$tmp/$j.json"; done
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
  search)
    [[ -n ${1:-} ]] || exit 1
    search "$1"
    ;;
  news)
    if [[ -n ${1:-} ]]; then symbol_news "$1"; else top_news; fi
    ;;
  *)
    echo "Usage: quotes.sh quotes SYMBOL... | series SYMBOL RANGE | search QUERY | news [SYMBOL]" >&2
    exit 1
    ;;
esac
