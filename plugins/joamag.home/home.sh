#!/bin/bash

# Thin client for a Home Assistant instance over its REST API through curl.
# Every command prints one JSON envelope:
#
#   { "state": "ok", "url": ..., "fetchedAt": ..., "entities": [...] }
#   { "state": "unconfigured", "url": ..., "username": ..., "missing": [...] }
#   { "state": "unauthorized", "url": ..., "username": ..., "error": ... }
#   { "state": "unreachable", "error": ..., "entities": <last cached list or []> }
#   { "state": "error", "error": ... }                 any other failure
#
# Commands:
#   home.sh snapshot [ENTITIES]          the listed entities (comma separated),
#                                        or every climate, light and switch
#   home.sh toggle ENTITY                lights, switches, fans, covers
#   home.sh turn_on ENTITY | turn_off ENTITY
#   home.sh brightness ENTITY PERCENT    lights that dim
#   home.sh activate ENTITY              scenes and scripts
#   home.sh climate ENTITY temperature N | mode MODE
#   home.sh discover                     every controllable entity, to pick from
#   home.sh configure                    sign in with HOME_ASSISTANT_SET_URL /
#                                        _USERNAME / _PASSWORD, then snapshot
#
# Signing in runs Home Assistant's own login flow, the one its web page uses,
# and keeps only the refresh token it hands back (owner-only, under
# ~/.cache/omarchy/home); the password is used once and never written down.
# Access tokens are minted from it as they expire. A long-lived token pasted
# into the credentials file as HOME_ASSISTANT_TOKEN is honoured instead, for
# accounts with two-factor authentication, which the login flow cannot pass.
#
# Credentials live in $HOME_ASSISTANT_ENV (default ~/.config/omarchy/home.env)
# as HOME_ASSISTANT_URL and HOME_ASSISTANT_USERNAME lines (plus the optional
# token); the file is parsed, never sourced. Actions answer with the refreshed
# snapshot so the popup never needs a second round trip.

set -o pipefail
umask 077

ENV_FILE=${HOME_ASSISTANT_ENV:-$HOME/.config/omarchy/home.env}
CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/home
CACHE="$CACHE_DIR/states.json"
TOKENS="$CACHE_DIR/tokens.json"
mkdir -p "$CACHE_DIR"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

emit() { jq -cn "$@"; }

command=${1:-snapshot}
shift || true

# KEY=VALUE lines only; anything else is ignored so the file cannot execute
# code inside the shell. Only whole-line comments are recognised and only a
# pair of matching wrapping quotes is removed.
read_env() {
  [[ -f $ENV_FILE ]] || return 0
  local line key value
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*(HOME_ASSISTANT_URL|HOME_ASSISTANT_USERNAME|HOME_ASSISTANT_TOKEN)[[:space:]]*=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    if [[ ${#value} -ge 2 && ( ( $value == \"*\" ) || ( $value == \'*\' ) ) ]]; then
      value=${value:1:${#value}-2}
    fi
    [[ -n ${!key:-} ]] || printf -v "$key" '%s' "$value"
  done <"$ENV_FILE"
}

# http METHOD URL [BODY] [CONTENT_TYPE] [BEARER]: prints the HTTP code, the
# body lands in $tmp/body. A 000 code means curl never got an answer.
http() {
  local method="$1" url="$2" body="${3:-}" ctype="${4:-application/json}" bearer="${5:-}" code
  local args=(-sS --max-time 12 -X "$method" -H "Accept: application/json" -o "$tmp/body" -w '%{http_code}')
  [[ -n $bearer ]] && args+=(-H "Authorization: Bearer $bearer")
  [[ -n $body ]] && args+=(-H "Content-Type: $ctype" --data-binary "$body")
  code=$(curl "${args[@]}" "$url" 2>"$tmp/curl.err") || code="000"
  printf '%s' "$code"
}

client_id() { printf '%s/' "$URL"; }

# Trade a refresh token for a fresh access token; writes the tokens file.
refresh_access() {
  local refresh code
  refresh=$(jq -r '.refresh_token // empty' "$TOKENS" 2>/dev/null)
  [[ -n $refresh ]] || return 1
  code=$(http POST "$URL/auth/token" "grant_type=refresh_token&refresh_token=$refresh&client_id=$(client_id)" "application/x-www-form-urlencoded")
  [[ $code == 200 ]] || return 1
  jq -c --arg r "$refresh" '{access_token, refresh_token: $r, expires_at: (now + (.expires_in // 1800) | floor)}' "$tmp/body" >"$TOKENS.tmp" && mv "$TOKENS.tmp" "$TOKENS"
}

# The bearer to use: a long-lived token from the file, else the cached
# access token, refreshed when it is about to expire.
bearer() {
  if [[ -n ${HOME_ASSISTANT_TOKEN:-} ]]; then
    printf '%s' "$HOME_ASSISTANT_TOKEN"
    return 0
  fi
  [[ -f $TOKENS ]] || return 1
  if ! jq -e --argjson now "$(date +%s)" '.access_token and (.expires_at // 0) > $now + 60' "$TOKENS" >/dev/null 2>&1; then
    refresh_access || return 1
  fi
  jq -r '.access_token // empty' "$TOKENS"
}

# login USERNAME PASSWORD: Home Assistant's login flow, three requests. Prints
# nothing on success, a reason word on failure: invalid, mfa, unreachable, error.
login() {
  local user="$1" pass="$2" cid code flow body
  cid=$(client_id)
  body=$(jq -cn --arg c "$cid" '{client_id: $c, handler: ["homeassistant", null], redirect_uri: $c}')
  code=$(http POST "$URL/auth/login_flow" "$body")
  [[ $code == 000 ]] && { printf 'unreachable'; return 1; }
  [[ $code == 200 ]] || { printf 'error'; return 1; }
  flow=$(jq -r '.flow_id // empty' "$tmp/body")
  [[ -n $flow ]] || { printf 'error'; return 1; }
  body=$(jq -cn --arg c "$cid" --arg u "$user" --arg p "$pass" '{client_id: $c, username: $u, password: $p}')
  code=$(http POST "$URL/auth/login_flow/$flow" "$body")
  [[ $code == 200 ]] || { printf 'error'; return 1; }
  case "$(jq -r '.type // ""' "$tmp/body")" in
    create_entry) ;;
    form)
      if [[ $(jq -r '.step_id // ""' "$tmp/body") == mfa ]]; then printf 'mfa'; else printf 'invalid'; fi
      return 1
      ;;
    *) printf 'error'; return 1 ;;
  esac
  local auth_code
  auth_code=$(jq -r '.result // empty' "$tmp/body")
  [[ -n $auth_code ]] || { printf 'error'; return 1; }
  code=$(http POST "$URL/auth/token" "grant_type=authorization_code&code=$auth_code&client_id=$cid" "application/x-www-form-urlencoded")
  [[ $code == 200 ]] || { printf 'error'; return 1; }
  jq -c '{access_token, refresh_token, expires_at: (now + (.expires_in // 1800) | floor)}' "$tmp/body" >"$TOKENS.tmp" && mv "$TOKENS.tmp" "$TOKENS"
}

# The popup's sign-in form hands the values over in the environment (readable
# only by the same user, unlike argv). The file is only written once the
# login has succeeded, so a typo never clobbers a working setup.
if [[ $command == configure ]]; then
  set_url=${HOME_ASSISTANT_SET_URL%/}
  if [[ -z $set_url || -z ${HOME_ASSISTANT_SET_USERNAME:-} || -z ${HOME_ASSISTANT_SET_PASSWORD:-} ]]; then
    emit '{state: "error", error: "URL, username and password are all required"}'
    exit 0
  fi
  URL=$set_url
  if reason=$(login "$HOME_ASSISTANT_SET_USERNAME" "$HOME_ASSISTANT_SET_PASSWORD"); then
    mkdir -p "$(dirname "$ENV_FILE")"
    printf 'HOME_ASSISTANT_URL=%s\nHOME_ASSISTANT_USERNAME=%s\n' "$set_url" "$HOME_ASSISTANT_SET_USERNAME" >"$ENV_FILE.tmp" &&
      mv "$ENV_FILE.tmp" "$ENV_FILE" || {
      emit --arg file "$ENV_FILE" '{state: "error", error: ("could not write " + $file)}'
      exit 0
    }
    chmod 600 "$ENV_FILE"
    unset HOME_ASSISTANT_URL HOME_ASSISTANT_USERNAME HOME_ASSISTANT_TOKEN
    command=snapshot
  else
    case "$reason" in
      invalid) emit --arg url "$set_url" --arg user "$HOME_ASSISTANT_SET_USERNAME" '{state: "unauthorized", url: $url, username: $user, error: "Home Assistant rejected that username or password"}' ;;
      mfa) emit --arg url "$set_url" --arg user "$HOME_ASSISTANT_SET_USERNAME" '{state: "unauthorized", url: $url, username: $user, error: "That account uses two-factor authentication. Create a long-lived access token in your Home Assistant profile and put it in the credentials file as HOME_ASSISTANT_TOKEN."}' ;;
      unreachable) emit --arg url "$set_url" --arg e "$(head -c 200 "$tmp/curl.err" | tr '\n' ' ')" '{state: "unreachable", url: $url, error: (if $e == "" then "no response" else $e end), entities: []}' ;;
      *) emit --arg url "$set_url" '{state: "error", error: ("Sign-in failed at " + $url)}' ;;
    esac
    exit 0
  fi
fi

read_env
URL=${HOME_ASSISTANT_URL%/}
missing=()
[[ -n $URL ]] || missing+=("HOME_ASSISTANT_URL")
if [[ -z ${HOME_ASSISTANT_TOKEN:-} && ! -f $TOKENS ]]; then missing+=("sign-in"); fi
if (( ${#missing[@]} > 0 )); then
  emit --arg file "$ENV_FILE" --arg url "$URL" --arg user "${HOME_ASSISTANT_USERNAME:-}" \
    --argjson missing "$(printf '%s\n' "${missing[@]}" | jq -R . | jq -sc .)" \
    '{state: "unconfigured", file: $file, url: $url, username: $user, missing: $missing}'
  exit 0
fi

# call METHOD PATH [JSON]: authenticated request, with one transparent token
# refresh when the access token has been revoked or expired early.
call() {
  local method="$1" path="$2" body="${3:-}" token code
  token=$(bearer) || { printf '401'; return; }
  code=$(http "$method" "$URL$path" "$body" "application/json" "$token")
  if [[ $code == 401 && -z ${HOME_ASSISTANT_TOKEN:-} ]]; then
    refresh_access || { printf '401'; return; }
    token=$(jq -r '.access_token // empty' "$TOKENS")
    code=$(http "$method" "$URL$path" "$body" "application/json" "$token")
  fi
  printf '%s' "$code"
}

# The jq that turns /api/states into the widget's entity list. With a list of
# ids the order is the list's; without one every climate, light and switch
# that is not unavailable, climate first, then by name.
CONDENSE='
  def domain: split(".")[0];
  def row: {
    id: .entity_id,
    domain: (.entity_id | domain),
    name: (.attributes.friendly_name // .entity_id),
    state: .state,
    brightness: .attributes.brightness,
    temperature: .attributes.temperature,
    current: .attributes.current_temperature,
    action: .attributes.hvac_action,
    modes: (.attributes.hvac_modes // []),
    step: (.attributes.target_temp_step // 1),
    min: .attributes.min_temp,
    max: .attributes.max_temp,
    changed: .last_changed
  };
  if ($ids | length) > 0 then
    . as $all | [ $ids[] as $id | ($all[] | select(.entity_id == $id) | row) ]
  else
    [ .[] | select((.entity_id | domain) as $d | ["climate", "light", "switch"] | index($d)) | select(.state != "unavailable") | row ]
    | sort_by((if .domain == "climate" then 0 elif .domain == "light" then 1 else 2 end), .name)
  end'

# finish CODE IDS: turn the last response into the widget's envelope.
finish() {
  local code="$1" ids="$2" detail
  case "$code" in
    200)
      if jq -e 'type == "array"' "$tmp/body" >/dev/null 2>&1; then
        cp "$tmp/body" "$CACHE"
        jq -c --arg url "$URL" --argjson ids "$ids" "$CONDENSE"' | {state: "ok", url: $url, fetchedAt: (now | floor), entities: .}' "$tmp/body"
      else
        emit '{state: "error", error: "Unexpected response from Home Assistant"}'
      fi
      ;;
    401 | 403)
      emit --arg url "$URL" --arg user "${HOME_ASSISTANT_USERNAME:-}" '{state: "unauthorized", url: $url, username: $user, error: "Home Assistant no longer accepts the saved sign-in"}'
      ;;
    000)
      detail=$(head -c 200 "$tmp/curl.err" | tr '\n' ' ')
      if [[ -f $CACHE ]]; then
        jq -c --arg url "$URL" --arg e "${detail:-no response}" --argjson ids "$ids" "$CONDENSE"' | {state: "unreachable", url: $url, error: $e, entities: .}' "$CACHE"
      else
        emit --arg url "$URL" --arg e "${detail:-no response}" '{state: "unreachable", url: $url, error: $e, entities: []}'
      fi
      ;;
    *)
      detail=$(jq -r '.message // empty' "$tmp/body" 2>/dev/null)
      emit --arg e "HTTP $code${detail:+: $detail}" '{state: "error", error: $e}'
      ;;
  esac
}

# The ids as a JSON array. An empty list has to reach jq as one empty line,
# not as no input at all, or --argjson gets nothing and refuses to run.
ids_json() {
  printf '%s\n' "${1:-}" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))'
}

snapshot() {
  finish "$(call GET /api/states)" "$(ids_json "${1:-}")"
}

# service DOMAIN SERVICE ENTITY [EXTRA_JSON]: call it, then answer with the
# snapshot so the popup shows the result. A failed call is reported instead.
service() {
  local domain="$1" name="$2" entity="$3" extra="${4:-{\}}" code body
  body=$(jq -cn --arg id "$entity" --argjson extra "$extra" '{entity_id: $id} + $extra')
  code=$(call POST "/api/services/$domain/$name" "$body")
  case "$code" in
    200 | 201) snapshot "${HOME_ENTITIES:-}" ;;
    *) finish "$code" '[]' ;;
  esac
}

domain_of() { printf '%s' "${1%%.*}"; }

case "$command" in
  snapshot)
    snapshot "${1:-}"
    ;;
  toggle | turn_on | turn_off)
    entity=${1:?entity required}
    domain=$(domain_of "$entity")
    # Covers do not turn on and off, they open and close.
    if [[ $domain == cover ]]; then
      case "$command" in turn_on) command=open_cover ;; turn_off) command=close_cover ;; esac
    fi
    service "$domain" "$command" "$entity"
    ;;
  brightness)
    entity=${1:?entity required}
    [[ ${2:-} =~ ^[0-9]+$ ]] || { emit '{state: "error", error: "brightness percent required"}'; exit 0; }
    pct=$2; (( pct > 100 )) && pct=100
    if (( pct == 0 )); then
      service light turn_off "$entity"
    else
      service light turn_on "$entity" "$(jq -cn --argjson p "$pct" '{brightness_pct: $p}')"
    fi
    ;;
  activate)
    entity=${1:?entity required}
    service "$(domain_of "$entity")" turn_on "$entity"
    ;;
  climate)
    entity=${1:?entity required}
    case "${2:-}" in
      temperature)
        [[ ${3:-} =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { emit '{state: "error", error: "temperature required"}'; exit 0; }
        service climate set_temperature "$entity" "$(jq -cn --argjson t "$3" '{temperature: $t}')"
        ;;
      mode)
        [[ -n ${3:-} ]] || { emit '{state: "error", error: "mode required"}'; exit 0; }
        service climate set_hvac_mode "$entity" "$(jq -cn --arg m "$3" '{hvac_mode: $m}')"
        ;;
      *)
        emit '{state: "error", error: "climate needs temperature N or mode MODE"}'
        ;;
    esac
    ;;
  discover)
    code=$(call GET /api/states)
    if [[ $code == 200 ]]; then
      jq -c --arg url "$URL" '[ .[] | select((.entity_id | split(".")[0]) as $d | ["climate", "light", "switch", "fan", "cover", "scene", "script", "input_boolean"] | index($d)) | {id: .entity_id, name: (.attributes.friendly_name // .entity_id), state: .state} ] | sort_by(.id) | {state: "ok", url: $url, entities: .}' "$tmp/body"
    else
      finish "$code" '[]'
    fi
    ;;
  *)
    echo "Usage: home.sh snapshot [ENTITIES] | toggle ENTITY | turn_on ENTITY | turn_off ENTITY | brightness ENTITY PCT | activate ENTITY | climate ENTITY temperature N | climate ENTITY mode MODE | discover | configure" >&2
    exit 1
    ;;
esac
