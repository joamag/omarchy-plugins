#!/bin/bash

# Thin client for an Isabella instance (the house task planner), speaking its
# session-cookie REST API through curl. Every command prints one JSON object:
#
#   { "state": "ok", "url": ..., "day": <day payload> }
#   { "state": "unconfigured", "missing": [...] }     credentials file incomplete
#   { "state": "unauthorized" }                        login refused
#   { "state": "unreachable", "error": ..., "day": <last cached payload or null> }
#   { "state": "error", "error": ... }                 any other HTTP failure
#
# Commands:
#   isabella.sh day [DATE]                 day view (default today)
#   isabella.sh toggle DATE TASK_ID        tick or untick a task
#   isabella.sh subtoggle DATE SUBTASK_ID  tick or untick a subtask
#   isabella.sh cancel DATE TASK_ID        cancel for the day (or lift a cancellation)
#   isabella.sh delay DATE TASK_ID         push to tomorrow
#   isabella.sh login                      force a fresh session
#   isabella.sh configure                  write the credentials file from
#                                          ISABELLA_SET_URL / _USERNAME /
#                                          _PASSWORD, then fetch today
#
# Credentials live in $ISABELLA_ENV (default ~/.config/omarchy/isabella.env) as
# ISABELLA_URL, ISABELLA_USERNAME and ISABELLA_PASSWORD lines; the file is
# parsed, never sourced. The session cookie and the last good day payload are
# cached under ~/.cache/omarchy/isabella with owner-only permissions.

set -o pipefail
umask 077

ENV_FILE=${ISABELLA_ENV:-$HOME/.config/omarchy/isabella.env}
CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/isabella
JAR="$CACHE_DIR/cookies"
mkdir -p "$CACHE_DIR"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

emit() { jq -cn "$@"; }

command=${1:-day}
shift || true

# The popup's credentials form hands the values over in the environment
# (readable only by the same user, unlike argv) and asks for the file to be
# (re)written before the usual day fetch runs.
if [[ $command == configure ]]; then
  set_url=${ISABELLA_SET_URL%/}
  if [[ -z $set_url || -z ${ISABELLA_SET_USERNAME:-} || -z ${ISABELLA_SET_PASSWORD:-} ]]; then
    emit '{state: "error", error: "URL, username and password are all required"}'
    exit 0
  fi
  mkdir -p "$(dirname "$ENV_FILE")"
  printf 'ISABELLA_URL=%s\nISABELLA_USERNAME=%s\nISABELLA_PASSWORD=%s\n' \
    "$set_url" "$ISABELLA_SET_USERNAME" "$ISABELLA_SET_PASSWORD" >"$ENV_FILE.tmp" &&
    mv "$ENV_FILE.tmp" "$ENV_FILE" || {
    emit --arg file "$ENV_FILE" '{state: "error", error: ("could not write " + $file)}'
    exit 0
  }
  chmod 600 "$ENV_FILE"
  rm -f "$JAR"
  unset ISABELLA_URL ISABELLA_USERNAME ISABELLA_PASSWORD
  command=day
fi

# KEY=VALUE lines only; anything else is ignored so the file cannot execute
# code inside the shell. Only whole-line comments are recognised and only a
# pair of matching wrapping quotes is removed, so a password containing `#` or
# a quote survives the round trip.
if [[ -f $ENV_FILE ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*(ISABELLA_URL|ISABELLA_USERNAME|ISABELLA_PASSWORD)[[:space:]]*=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    if [[ ${#value} -ge 2 && ( ( $value == \"*\" ) || ( $value == \'*\' ) ) ]]; then
      value=${value:1:${#value}-2}
    fi
    [[ -n ${!key:-} ]] || printf -v "$key" '%s' "$value"
  done <"$ENV_FILE"
fi

URL=${ISABELLA_URL%/}
missing=()
[[ -n $URL ]] || missing+=("ISABELLA_URL")
[[ -n ${ISABELLA_USERNAME:-} ]] || missing+=("ISABELLA_USERNAME")
[[ -n ${ISABELLA_PASSWORD:-} ]] || missing+=("ISABELLA_PASSWORD")
if (( ${#missing[@]} > 0 )); then
  emit --arg file "$ENV_FILE" --arg url "$URL" --arg user "${ISABELLA_USERNAME:-}" \
    --argjson missing "$(printf '%s\n' "${missing[@]}" | jq -R . | jq -sc .)" \
    '{state: "unconfigured", file: $file, url: $url, username: $user, missing: $missing}'
  exit 0
fi

# request METHOD PATH [JSON]; prints the HTTP code, body lands in $tmp/body.
# A 000 code means curl never got an answer.
request() {
  local method="$1" path="$2" body="${3:-}" code
  local args=(-sS --max-time 12 -b "$JAR" -c "$JAR" -X "$method" -H "Accept: application/json" -o "$tmp/body" -w '%{http_code}')
  [[ -n $body ]] && args+=(-H "Content-Type: application/json" -d "$body")
  code=$(curl "${args[@]}" "$URL$path" 2>"$tmp/curl.err") || code="000"
  printf '%s' "$code"
}

login() {
  local body code
  body=$(emit --arg u "$ISABELLA_USERNAME" --arg p "$ISABELLA_PASSWORD" '{username: $u, password: $p}')
  rm -f "$JAR"
  code=$(request POST /api/auth/login "$body")
  [[ $code == 200 ]]
}

# call METHOD PATH [JSON]: authenticated request with one transparent re-login
# when the session has expired.
call() {
  local code
  code=$(request "$@")
  if [[ $code == 401 ]]; then
    login || { printf '401'; return; }
    code=$(request "$@")
  fi
  printf '%s' "$code"
}

# finish DATE CODE: turn the last response into the widget's JSON envelope.
finish() {
  local date="$1" code="$2" cache="$CACHE_DIR/day-$1.json" detail
  case "$code" in
    200)
      if jq -e '.day' "$tmp/body" >/dev/null 2>&1; then
        cp "$tmp/body" "$cache"
        jq -c --arg url "$URL" '{state: "ok", url: $url, day: .}' "$tmp/body"
      else
        emit '{state: "error", error: "Unexpected response from Isabella"}'
      fi
      ;;
    401 | 403)
      emit --arg url "$URL" --arg user "$ISABELLA_USERNAME" '{state: "unauthorized", url: $url, username: $user}'
      ;;
    000)
      detail=$(head -c 200 "$tmp/curl.err" | tr '\n' ' ')
      if [[ -f $cache ]]; then
        jq -c --arg url "$URL" --arg e "${detail:-no response}" '{state: "unreachable", url: $url, error: $e, day: .}' "$cache"
      else
        emit --arg url "$URL" --arg e "${detail:-no response}" '{state: "unreachable", url: $url, error: $e, day: null}'
      fi
      ;;
    *)
      detail=$(jq -r '.detail // empty' "$tmp/body" 2>/dev/null)
      emit --arg e "HTTP $code${detail:+: $detail}" '{state: "error", error: $e}'
      ;;
  esac
}

case "$command" in
  day)
    date=${1:-$(date +%F)}
    finish "$date" "$(call GET "/api/day/$date")"
    ;;
  toggle | cancel | delay)
    date=${1:?date required}; id=${2:?task id required}
    finish "$date" "$(call POST "/api/day/$date/$command" "$(emit --argjson id "$id" '{task: $id}')")"
    ;;
  subtoggle)
    date=${1:?date required}; id=${2:?subtask id required}
    finish "$date" "$(call POST "/api/day/$date/toggle" "$(emit --argjson id "$id" '{subtask: $id}')")"
    ;;
  login)
    if login; then emit --arg url "$URL" '{state: "ok", url: $url}'; else emit --arg url "$URL" --arg user "$ISABELLA_USERNAME" '{state: "unauthorized", url: $url, username: $user}'; fi
    ;;
  *)
    echo "Usage: isabella.sh day [DATE] | toggle DATE ID | subtoggle DATE ID | cancel DATE ID | delay DATE ID | login | configure" >&2
    exit 1
    ;;
esac
