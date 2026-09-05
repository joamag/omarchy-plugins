#!/bin/bash

# A todo.txt file as tab-separated lines for the widget, plus the edits the
# popup makes to it:
#
#   todo.sh list                        the file
#     file   PATH
#     task   line  done  priority  created  completed  text
#   todo.sh add [--by NAME] TEXT        append a task, dated today; --by signs
#                                       it with an @NAME context
#   todo.sh toggle LINE TEXT            tick or untick line LINE
#   todo.sh remove LINE TEXT            delete line LINE
#   todo.sh priority LINE TEXT A|B|C|-  set or clear the priority of line LINE
#   todo.sh archive                     move ticked tasks to done.txt alongside
#
# The file is plain todo.txt (todotxt.org): one task per line, "x" and a date
# in front of a done one, "(A)" for a priority, a leading date for when it was
# added, +project and @context anywhere. Hand edits are fine, which is why
# every edit names the line by number and by text: a line that no longer
# says what the popup thinks it says is refused rather than clobbered. Edits
# take a lock and rewrite the file whole, so two writers cannot tear it.
#
# Every edit answers with the fresh listing. Errors are "error<TAB>message".
# TODO_FILE overrides the default ~/.local/share/omarchy/todo.txt.

set -o pipefail

FILE=${TODO_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/omarchy/todo.txt}
DONE_FILE="$(dirname "$FILE")/done.txt"

fail() {
  printf 'error\t%s\n' "$*"
  exit 0
}

ensure_file() {
  [[ -f $FILE ]] && return 0
  mkdir -p "$(dirname "$FILE")" && : >"$FILE" || fail "could not create $FILE"
}

today() { date +%F; }

# parse_line LINE: sets done, priority, created, completed and body from one
# todo.txt line. A done line may carry its old priority as a pri:X tag, the
# way todo.txt tools keep it for unticking; that is read back as the priority
# and left out of the body.
parse_line() {
  local line="$1" date='[0-9]{4}-[0-9]{2}-[0-9]{2}'
  done=0; priority=""; created=""; completed=""; body=""
  if [[ $line =~ ^x\ ($date)(\ ($date))?\ (.*)$ ]]; then
    done=1; completed=${BASH_REMATCH[1]}; created=${BASH_REMATCH[3]}; body=${BASH_REMATCH[4]}
  elif [[ $line =~ ^x\ (.*)$ ]]; then
    done=1; body=${BASH_REMATCH[1]}
  elif [[ $line =~ ^(\(([A-Z])\)\ )?(($date)\ )?(.*)$ ]]; then
    priority=${BASH_REMATCH[2]}; created=${BASH_REMATCH[4]}; body=${BASH_REMATCH[5]}
  fi
  if (( done )) && [[ $body =~ ^(.*)\ pri:([A-Z])$ ]]; then
    body=${BASH_REMATCH[1]}; priority=${BASH_REMATCH[2]}
  elif (( done )) && [[ $body =~ ^pri:([A-Z])\ (.*)$ ]]; then
    priority=${BASH_REMATCH[1]}; body=${BASH_REMATCH[2]}
  fi
}

list() {
  ensure_file
  printf 'file\t%s\n' "$FILE"
  local n=0 line
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    [[ -n ${line//[[:space:]]/} ]] || continue
    parse_line "$line"
    printf 'task\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$done" "$priority" "$created" "$completed" "${body//$'\t'/ }"
  done <"$FILE"
}

# line_at N: the raw line, failing when the file has fewer lines.
line_at() {
  local n="$1" line
  line=$(sed -n "${n}p" "$FILE")
  [[ $(wc -l <"$FILE") -ge $n || -n $line ]] || return 1
  printf '%s' "$line"
}

# check LINE TEXT: refuse an edit when line LINE no longer reads TEXT.
check() {
  local n="$1" expected="$2" line
  [[ $n =~ ^[0-9]+$ && $n -ge 1 ]] || fail "line number required"
  line=$(line_at "$n") || fail "line $n is gone; the list was refreshed"
  parse_line "$line"
  [[ $body == "$expected" ]] || fail "line $n has changed; the list was refreshed"
}

# rewrite N NEWLINE: replace line N (an empty NEWLINE deletes it), atomically
# and under the lock.
rewrite() {
  local n="$1" replacement="$2" tmp
  exec {lock_fd}>"$FILE.lock"
  flock "$lock_fd"
  tmp=$(mktemp "$FILE.XXXXXX") || fail "could not write next to $FILE"
  if [[ -z $replacement ]]; then
    sed "${n}d" "$FILE" >"$tmp"
  else
    awk -v n="$n" -v text="$replacement" 'NR == n { print text; next } { print }' "$FILE" >"$tmp"
  fi
  mv "$tmp" "$FILE"
  rm -f "$FILE.lock"
}

# compose PRIORITY CREATED BODY: a pending line in canonical order.
compose() {
  local out=""
  [[ -n $1 ]] && out+="($1) "
  [[ -n $2 ]] && out+="$2 "
  printf '%s%s' "$out" "$3"
}

command=${1:-list}
shift || true

case "$command" in
  list)
    list
    ;;
  add)
    # --by NAME: who is adding it. An LLM signing as @claude gets a context
    # tag the widget shows on the row and the file keeps, and nothing else.
    by=""
    if [[ ${1:-} == --by ]]; then
      by=$(printf '%s' "${2:-}" | tr -cd 'A-Za-z0-9_.-')
      [[ -n $by ]] || fail "--by needs a name"
      shift 2
    fi
    text=$(printf '%s' "${1:-}" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -n $text ]] || fail "nothing to add"
    if [[ -n $by ]] && ! [[ " $text " == *" @$by "* ]]; then text="$text @$by"; fi
    ensure_file
    # A typed "(A) buy milk" keeps its priority in front of today's date.
    if [[ $text =~ ^\(([A-Z])\)\ (.*)$ ]]; then
      line=$(compose "${BASH_REMATCH[1]}" "$(today)" "${BASH_REMATCH[2]}")
    else
      line=$(compose "" "$(today)" "$text")
    fi
    exec {lock_fd}>"$FILE.lock"
    flock "$lock_fd"
    printf '%s\n' "$line" >>"$FILE"
    rm -f "$FILE.lock"
    list
    ;;
  toggle)
    ensure_file
    check "${1:-}" "${2:-}"
    if (( done )); then
      rewrite "$1" "$(compose "$priority" "$created" "$body")"
    else
      tag=""; [[ -n $priority ]] && tag=" pri:$priority"
      created_part=""; [[ -n $created ]] && created_part="$created "
      rewrite "$1" "x $(today) ${created_part}${body}${tag}"
    fi
    list
    ;;
  remove)
    ensure_file
    check "${1:-}" "${2:-}"
    rewrite "$1" ""
    list
    ;;
  priority)
    ensure_file
    check "${1:-}" "${2:-}"
    new=${3:-}
    [[ $new =~ ^[A-Z]$ || $new == "-" ]] || fail "priority must be a letter or -"
    [[ $new == "-" ]] && new=""
    if (( done )); then
      tag=""; [[ -n $new ]] && tag=" pri:$new"
      created_part=""; [[ -n $created ]] && created_part="$created "
      rewrite "$1" "x ${completed:-$(today)} ${created_part}${body}${tag}"
    else
      rewrite "$1" "$(compose "$new" "$created" "$body")"
    fi
    list
    ;;
  archive)
    ensure_file
    exec {lock_fd}>"$FILE.lock"
    flock "$lock_fd"
    tmp=$(mktemp "$FILE.XXXXXX") || fail "could not write next to $FILE"
    grep -E '^x ' "$FILE" >>"$DONE_FILE" 2>/dev/null
    grep -vE '^x ' "$FILE" >"$tmp"
    mv "$tmp" "$FILE"
    rm -f "$FILE.lock"
    list
    ;;
  *)
    echo "Usage: todo.sh [list | add [--by NAME] TEXT | toggle LINE TEXT | remove LINE TEXT | priority LINE TEXT A-Z|- | archive]" >&2
    exit 1
    ;;
esac
