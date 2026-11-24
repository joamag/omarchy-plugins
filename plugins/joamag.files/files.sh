#!/bin/bash

# Lists Qt's folder model does not cover, and every file operation the files
# widget runs, as tab-separated lines.
#
#   files.sh places                 places, bookmarks, drives and the trash count:
#     place     key path                    standard folders (home, desktop, ...)
#     bookmark  path label                  the GTK bookmarks Nautilus shares
#     drive     mount device label size avail removable   mount empty = not mounted
#     trash     count
#   files.sh free DIR               free  avail size   for the filesystem holding DIR
#   files.sh recent                 entry lines for the recently used files, newest first
#   files.sh trashed                entry lines for the items in the trash
#   files.sh search DIR QUERY [all] entry lines for the names below DIR containing QUERY
#     entry     type size mtime path origin trashname   type is d or f, mtime in seconds
#   files.sh names DIR              name  NAME   for every entry of DIR
#   files.sh apps PATH              app   id name default   the apps that open PATH
#   files.sh launch ID PATH...      open the files with the app ID
#   files.sh transfer copy|move SRC TARGET POLICY [...]
#     total BYTES, progress BYTES, done SRC TARGET; POLICY is new or replace
#   files.sh rename PATH NAME       done  PATH TARGET
#   files.sh mkdir DIR NAME         created  TARGET (touch DIR NAME for a file)
#   files.sh trash PATH...          trashed  NAME PATH   NAME empty when not in the home trash
#   files.sh restore NAME...        restored NAME TARGET
#   files.sh purge NAME...          delete trash items for good
#   files.sh delete PATH...         delete files for good
#   files.sh empty-trash
#   files.sh mount DEVICE           mounted  MOUNTPOINT
#   files.sh eject MOUNTPOINT       unmount and eject the drive
#   files.sh bookmark PATH | unbookmark PATH
#
# Actions print "error<TAB>message" when one item fails and carry on with the
# rest; the popup reports the last one. Replacing a file sends the old one to
# the trash first, so a wrong answer to a name conflict can be undone.

set -o pipefail

TRASH_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/Trash
RECENT_FILE=${XDG_DATA_HOME:-$HOME/.local/share}/recently-used.xbel
BOOKMARKS_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks
SEARCH_LIMIT=200
RECENT_LIMIT=40
ERR_FILE="${TMPDIR:-/tmp}/files-widget.$$.err"
trap 'rm -f "$ERR_FILE"' EXIT

fail() {
  printf 'error\t%s\n' "$*"
  exit 0
}

report() {
  printf 'error\t%s\n' "$*"
}

last_error() {
  tr '\n' ' ' <"$ERR_FILE" 2>/dev/null | sed 's/ *$//'
}

# file:// URIs and trashinfo paths are percent-encoded byte by byte. The
# decoded text goes into the variable named first: a command substitution
# per item would fork once per file, which is what made long lists slow.
urldecode() {
  local _ud="${2//+/%2B}"
  printf -v "$1" '%b' "${_ud//%/\\x}"
}

urlencode() {
  local LC_ALL=C s="$1" out="" c hex i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case $c in
      [a-zA-Z0-9./~_-]) out+=$c ;;
      *) printf -v hex '%%%02X' "'$c"; out+=$hex ;;
    esac
  done
  printf '%s' "$out"
}

xml_unescape() {
  local _xu="$2"
  _xu=${_xu//&lt;/<}
  _xu=${_xu//&gt;/>}
  _xu=${_xu//&quot;/\"}
  _xu=${_xu//&apos;/\'}
  # A bare & in the replacement would stand for the match (patsub_replacement).
  printf -v "$1" '%s' "${_xu//&amp;/\&}"
}

# First free "name (copy).ext", "name (copy 2).ext" ... in DIR, the way the
# widget names a pasted file that would clash. Folders and dot files keep
# their whole name as the stem.
unique_target() {
  local dir="$1" name="$2" stem ext n candidate
  [[ -e $dir/$name || -L $dir/$name ]] || { printf '%s' "$dir/$name"; return; }
  stem=$name
  ext=""
  if [[ ! -d $dir/$name && $name == ?*.* ]]; then
    stem=${name%.*}
    ext=.${name##*.}
  fi
  n=1
  while :; do
    if (( n == 1 )); then candidate="$stem (copy)$ext"; else candidate="$stem (copy $n)$ext"; fi
    [[ -e $dir/$candidate || -L $dir/$candidate ]] || break
    n=$((n + 1))
  done
  printf '%s' "$dir/$candidate"
}

entry_line() {
  # type size mtime path origin trashname
  printf 'entry\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" "${6:-}"
}

places() {
  printf 'place\thome\t%s\n' "$HOME"
  # xdg-user-dir answers $HOME for a folder that is not set up; the English
  # name is the fallback, and a folder that does not exist is left out.
  local entry key name dir
  for entry in DESKTOP:Desktop DOCUMENTS:Documents DOWNLOAD:Downloads MUSIC:Music PICTURES:Pictures VIDEOS:Videos; do
    key=${entry%%:*}
    name=${entry#*:}
    dir=$(xdg-user-dir "$key" 2>/dev/null)
    dir=${dir%/}
    [[ -z $dir || $dir == "$HOME" ]] && dir="$HOME/$name"
    [[ -d $dir ]] || continue
    printf 'place\t%s\t%s\n' "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" "$dir"
  done

  # GTK bookmarks: "file:///path optional label" per line.
  local uri label path
  if [[ -f $BOOKMARKS_FILE ]]; then
    while read -r uri label; do
      [[ $uri == file://* ]] || continue
      urldecode path "${uri#file://}"
      printf 'bookmark\t%s\t%s\n' "$path" "$label"
    done <"$BOOKMARKS_FILE"
  fi

  # The root filesystem, then every partition with a filesystem that is
  # removable or mounted as a data drive.
  local size avail source
  read -r size avail < <(df -PB1 / 2>/dev/null | awk 'NR == 2 { print $2, $4 }')
  source=$(findmnt -n -o SOURCE / 2>/dev/null)
  printf 'drive\t/\t%s\tSystem\t%s\t%s\t0\n' "${source%%\[*}" "${size:-}" "${avail:-}"

  declare -A removable parent
  local line
  while IFS= read -r line; do
    eval "$line"
    [[ -n ${PATH_:-} ]] || continue
    removable[$PATH_]=$(( ${RM:-0} || ${HOTPLUG:-0} ))
    parent[$PATH_]=$PKNAME
  done < <(lsblk -P -o PATH,PKNAME,RM,HOTPLUG 2>/dev/null | sed 's/^PATH=/PATH_=/')

  is_removable() {
    local dev="$1"
    while [[ -n $dev ]]; do
      [[ ${removable[$dev]:-0} == 1 ]] && return 0
      [[ -n ${parent[$dev]:-} ]] || return 1
      dev="/dev/${parent[$dev]}"
    done
    return 1
  }

  local mount flag
  while IFS= read -r line; do
    eval "$line"
    [[ -n $FSTYPE && $FSTYPE != swap && $FSTYPE != crypto_LUKS && $FSTYPE != LVM2_member ]] || continue
    mount=${MOUNTPOINTS%%\\x0a*}
    flag=0
    is_removable "$PATH_" && flag=1
    if [[ -n $mount ]]; then
      [[ $mount == /run/media/* || $mount == /media/* || $mount == /mnt/* ]] || continue
      read -r size avail < <(df -PB1 "$mount" 2>/dev/null | awk 'NR == 2 { print $2, $4 }')
    else
      (( flag )) || continue
      size=$SIZE
      avail=""
    fi
    printf 'drive\t%s\t%s\t%s\t%s\t%s\t%s\n' "$mount" "$PATH_" "$LABEL" "$size" "$avail" "$flag"
  done < <(lsblk -P -b -o PATH,FSTYPE,LABEL,MOUNTPOINTS,SIZE 2>/dev/null | sed 's/^PATH=/PATH_=/')

  local count=0
  [[ -d $TRASH_DIR/info ]] && count=$(find "$TRASH_DIR/info" -maxdepth 1 -name '*.trashinfo' 2>/dev/null | wc -l)
  printf 'trash\t%s\n' "$count"
}

# The newest recently used files that still exist. Dates stay the ISO
# strings the file stores; the widget reads them. One sed and one find
# however long the history is.
recent() {
  [[ -f $RECENT_FILE ]] || return 0
  local modified href path type bytes
  local -A used
  local -a paths=()
  while IFS=$'\t' read -r modified href; do
    xml_unescape href "${href#file://}"
    urldecode path "$href"
    [[ -e $path && -z ${used[$path]:-} ]] || continue
    used[$path]=$modified
    paths+=("$path")
    (( ${#paths[@]} >= RECENT_LIMIT )) && break
  done < <(sed -n 's/.*<bookmark href="\(file:[^"]*\)".* modified="\([^"]*\)".*/\2\t\1/p' "$RECENT_FILE" | sort -r)
  (( ${#paths[@]} > 0 )) || return 0
  while IFS=$'\t' read -r type bytes path; do
    [[ -n ${used[$path]:-} ]] || continue
    if [[ $type == d ]]; then bytes=""; else type=f; fi
    entry_line "$type" "$bytes" "${used[$path]}" "$path"
  done < <(find -L "${paths[@]}" -maxdepth 0 -printf '%y\t%s\t%p\n' 2>/dev/null)
}

# Everything in the home trash: one awk over the info files and one find
# over the files, so a trash with thousands of items lists in a blink.
trashed() {
  [[ -d $TRASH_DIR/info ]] || return 0
  local name type bytes path deleted origin
  local -A kinds sizes
  while IFS=$'\t' read -r name type bytes; do
    kinds[$name]=$type
    sizes[$name]=$bytes
  done < <(find "$TRASH_DIR/files" -mindepth 1 -maxdepth 1 -printf '%f\t%y\t%s\n' 2>/dev/null)
  while IFS=$'\t' read -r name path deleted; do
    [[ -n ${kinds[$name]:-} ]] || continue
    urldecode origin "$path"
    if [[ ${kinds[$name]} == d ]]; then
      entry_line d "" "$deleted" "$TRASH_DIR/files/$name" "$origin" "$name"
    else
      entry_line f "${sizes[$name]}" "$deleted" "$TRASH_DIR/files/$name" "$origin" "$name"
    fi
  done < <(find "$TRASH_DIR/info" -maxdepth 1 -name '*.trashinfo' -exec awk '
    function flush(  n) {
      n = file
      sub(/^.*\//, "", n)
      sub(/\.trashinfo$/, "", n)
      printf "%s\t%s\t%s\n", n, path, date
    }
    FNR == 1 { if (file != "") flush(); file = FILENAME; path = ""; date = "" }
    /^Path=/ { path = substr($0, 6) }
    /^DeletionDate=/ { date = substr($0, 14) }
    END { if (file != "") flush() }' {} + 2>/dev/null)
}

# Case-insensitive name match below DIR, hidden files and folders left out
# unless "all" is given, capped so a search from / stays quick. find writes
# a line at a time, so the widget shows matches while the walk goes on.
search() {
  local dir="${1:?folder required}" query="${2:-}" all="${3:-}" pattern
  local -a line_buffered=()
  [[ -d $dir ]] || fail "no folder at $dir"
  [[ -n $query ]] || return 0
  command -v stdbuf >/dev/null && line_buffered=(stdbuf -oL)
  pattern=$(printf '%s' "$query" | sed 's/[][*?\\]/\\&/g')
  if [[ $all == all ]]; then
    timeout 15 "${line_buffered[@]}" find "$dir" -mindepth 1 -iname "*$pattern*" -printf '%Y\t%s\t%T@\t%p\n' 2>/dev/null
  else
    timeout 15 "${line_buffered[@]}" find "$dir" -mindepth 1 -name '.*' -prune -o -iname "*$pattern*" -printf '%Y\t%s\t%T@\t%p\n' 2>/dev/null
  fi | head -n "$SEARCH_LIMIT" | while IFS=$'\t' read -r type size mtime path; do
    [[ $type == d ]] || type=f
    [[ $type == d ]] && size=""
    entry_line "$type" "$size" "${mtime%.*}" "$path"
  done
}

names() {
  local dir="${1:?folder required}"
  [[ -d $dir ]] || fail "no folder at $dir"
  find "$dir" -mindepth 1 -maxdepth 1 -printf 'name\t%f\n' 2>/dev/null
}

desktop_file() {
  local id="$1" base
  for base in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS//:/ }; do
    [[ -f $base/applications/$id ]] && { printf '%s' "$base/applications/$id"; return 0; }
  done
  return 1
}

apps() {
  local path="${1:?path required}" mime default id file name
  [[ -e $path ]] || fail "no file at $path"
  mime=$(gio info -a standard::content-type -- "$path" 2>/dev/null | sed -n 's/^ *standard::content-type: //p')
  [[ -n $mime ]] || fail "could not tell the type of $(basename "$path")"
  default=""
  declare -A seen
  while IFS= read -r line; do
    case $line in
      Default\ application*) default=${line##*: } ;;
      $'\t'*.desktop)
        id=${line#$'\t'}
        [[ -n ${seen[$id]:-} ]] && continue
        seen[$id]=1
        file=$(desktop_file "$id") || continue
        name=$(sed -n '/^\[Desktop Entry\]/,/^\[/{s/^Name=//p}' "$file" | head -n 1)
        if [[ $id == "$default" ]]; then
          printf 'app\t%s\t%s\t1\n' "$id" "${name:-$id}"
        else
          printf 'app\t%s\t%s\t0\n' "$id" "${name:-$id}"
        fi
        ;;
    esac
  done < <(gio mime "$mime" 2>/dev/null)
}

launch() {
  local id="${1:?app required}" file
  shift
  file=$(desktop_file "$id") || fail "no app named $id"
  gio launch "$file" "$@" >/dev/null 2>"$ERR_FILE" || fail "$(last_error)"
}

# Bytes under a list of paths, for the progress line.
bytes_of() {
  (( $# > 0 )) || { printf '0'; return; }
  du -scb -- "$@" 2>/dev/null | tail -n 1 | cut -f1
}

# Copies or moves SRC to TARGET one triple at a time. A copy (or a move to
# another filesystem) runs in the background while the size of what landed
# so far is reported every few tenths of a second. TERM stops the item in
# flight; a copy then removes everything this run wrote, a move keeps what
# already moved.
transfer() {
  local mode="${1:-}"
  shift
  [[ $mode == copy || $mode == move ]] || fail "unknown transfer mode $mode"
  (( $# > 0 && $# % 3 == 0 )) || fail "nothing to transfer"

  local -a args=("$@") measured=() created=()
  local i src target policy total=0 base=0 child=""
  for (( i = 0; i < ${#args[@]}; i += 3 )); do
    src=${args[i]}
    target=${args[i + 1]}
    [[ -e $src || -L $src ]] || continue
    if [[ $mode == copy || $(stat -c %d -- "$src" 2>/dev/null) != $(stat -c %d -- "$(dirname "$target")" 2>/dev/null) ]]; then
      measured+=("$src")
    fi
  done
  total=$(bytes_of "${measured[@]}")
  printf 'total\t%s\n' "${total:-0}"

  cancel() {
    [[ -n $child ]] && kill "$child" 2>/dev/null && wait "$child" 2>/dev/null
    if [[ $mode == copy ]]; then
      local t
      for t in "${created[@]}"; do rm -rf -- "$t"; done
    fi
    printf 'cancelled\n'
    exit 0
  }
  trap cancel TERM INT

  for (( i = 0; i < ${#args[@]}; i += 3 )); do
    src=${args[i]}
    target=${args[i + 1]}
    policy=${args[i + 2]}
    if [[ ! -e $src && ! -L $src ]]; then report "$(basename "$src") is gone"; continue; fi
    if [[ $target == "$src" || $target == "$src"/* ]]; then report "cannot put $(basename "$src") inside itself"; continue; fi
    if [[ ! -d $(dirname "$target") ]]; then report "no folder at $(dirname "$target")"; continue; fi
    if [[ -e $target || -L $target ]]; then
      if [[ $policy != replace ]]; then report "$(basename "$target") already exists"; continue; fi
      if ! gio trash -- "$target" 2>"$ERR_FILE"; then report "$(last_error)"; continue; fi
    fi
    if [[ $mode == copy ]]; then
      cp -a -- "$src" "$target" 2>"$ERR_FILE" &
      created+=("$target")
    else
      mv -- "$src" "$target" 2>"$ERR_FILE" &
    fi
    child=$!
    while kill -0 "$child" 2>/dev/null; do
      if (( total > 0 )); then printf 'progress\t%s\n' "$(( base + $(bytes_of "$target") ))"; fi
      sleep 0.3
    done
    if wait "$child"; then
      printf 'done\t%s\t%s\n' "$src" "$target"
      (( total > 0 )) && base=$(( base + $(bytes_of "$target") ))
    else
      report "$(last_error)"
    fi
    child=""
  done
  (( total > 0 )) && printf 'progress\t%s\n' "$total"
  return 0
}

check_name() {
  local name="$1"
  [[ -n ${name// /} ]] || fail "a name cannot be empty"
  [[ $name != */* ]] || fail "a name cannot contain /"
  [[ $name != . && $name != .. ]] || fail "$name is not a valid name"
}

rename() {
  local path="${1:?path required}" name="$2" target
  [[ -e $path || -L $path ]] || fail "no file at $path"
  check_name "$name"
  target="$(dirname "$path")/$name"
  [[ $target == "$path" ]] && return 0
  [[ -e $target || -L $target ]] && fail "$name already exists here"
  mv -n -- "$path" "$target" 2>"$ERR_FILE" || fail "$(last_error)"
  printf 'done\t%s\t%s\n' "$path" "$target"
}

create() {
  local kind="$1" dir="${2:?folder required}" name="$3" target
  [[ -d $dir ]] || fail "no folder at $dir"
  check_name "$name"
  target="$dir/$name"
  [[ -e $target || -L $target ]] && fail "$name already exists here"
  if [[ $kind == mkdir ]]; then
    mkdir -- "$target" 2>"$ERR_FILE" || fail "$(last_error)"
  else
    : >"$target" 2>"$ERR_FILE" || fail "$(last_error)"
  fi
  printf 'created\t%s\n' "$target"
}

# The home trash entry gio just made for PATH: the newest info file whose
# Path decodes to it. gio names the entry after the file ("name", "name.2",
# ...), so only those are read. Items on other drives go to that drive's own
# trash and come back empty.
trash_name_of() {
  local path="$1" base info best="" newest=""
  base=$(basename "$path")
  local decoded
  for info in "$TRASH_DIR"/info/"$base"*.trashinfo; do
    [[ -f $info ]] || continue
    urldecode decoded "$(sed -n 's/^Path=//p' "$info" | head -n 1)"
    [[ $decoded == "$path" ]] || continue
    if [[ -z $newest || $info -nt $newest ]]; then
      newest=$info
      best=$(basename "$info" .trashinfo)
    fi
  done
  printf '%s' "$best"
}

trash() {
  (( $# > 0 )) || fail "nothing to move to the trash"
  local path
  for path in "$@"; do
    if gio trash -- "$path" 2>"$ERR_FILE"; then
      printf 'trashed\t%s\t%s\n' "$(trash_name_of "$path")" "$path"
    else
      report "$(last_error)"
    fi
  done
}

# Back to where it came from; when that name is taken again the item comes
# back under the next free "(copy)" name instead of over the newer file.
restore() {
  (( $# > 0 )) || fail "nothing to restore"
  local name info orig target
  for name in "$@"; do
    info="$TRASH_DIR/info/$name.trashinfo"
    [[ -f $info ]] || { report "$name is not in the trash"; continue; }
    urldecode orig "$(sed -n 's/^Path=//p' "$info" | head -n 1)"
    if [[ ! -e $orig && ! -L $orig ]]; then
      if gio trash --restore "trash:///$(urlencode "$name")" 2>"$ERR_FILE"; then
        printf 'restored\t%s\t%s\n' "$name" "$orig"
      else
        report "$(last_error)"
      fi
      continue
    fi
    target=$(unique_target "$(dirname "$orig")" "$(basename "$orig")")
    if mv -n -- "$TRASH_DIR/files/$name" "$target" 2>"$ERR_FILE"; then
      rm -f -- "$info"
      printf 'restored\t%s\t%s\n' "$name" "$target"
    else
      report "$(last_error)"
    fi
  done
}

purge() {
  (( $# > 0 )) || fail "nothing to delete"
  local name
  for name in "$@"; do
    [[ -n $name && $name != */* && $name != . && $name != .. ]] || { report "$name is not in the trash"; continue; }
    rm -rf -- "$TRASH_DIR/files/$name" "$TRASH_DIR/info/$name.trashinfo"
  done
}

delete() {
  (( $# > 0 )) || fail "nothing to delete"
  local path
  for path in "$@"; do
    case $path in
      "" | / | "$HOME" | "$HOME/") report "refusing to delete ${path:-nothing}"; continue ;;
    esac
    rm -rf -- "$path" 2>"$ERR_FILE" || report "$(last_error)"
  done
}

bookmark() {
  local path="${1:?path required}"
  [[ -d $path ]] || fail "no folder at $path"
  mkdir -p "$(dirname "$BOOKMARKS_FILE")"
  touch "$BOOKMARKS_FILE"
  # Already there when dropping its lines changes the file.
  unbookmarked_lines "$path" | cmp -s - "$BOOKMARKS_FILE" || return 0
  printf 'file://%s\n' "$(urlencode "$path")" >>"$BOOKMARKS_FILE"
}

# The bookmarks file without the lines that point at PATH.
unbookmarked_lines() {
  local path="$1" line uri decoded
  while IFS= read -r line || [[ -n $line ]]; do
    uri=${line%% *}
    if [[ $uri == file://* ]]; then
      urldecode decoded "${uri#file://}"
      [[ $decoded == "$path" ]] && continue
    fi
    printf '%s\n' "$line"
  done <"$BOOKMARKS_FILE"
}

unbookmark() {
  local path="${1:?path required}" kept
  [[ -f $BOOKMARKS_FILE ]] || return 0
  kept=$(unbookmarked_lines "$path")
  if [[ -n $kept ]]; then printf '%s\n' "$kept" >"$BOOKMARKS_FILE"; else : >"$BOOKMARKS_FILE"; fi
}

case "${1:-}" in
  places)
    places
    ;;
  free)
    dir=${2:?folder required}
    df -PB1 "$dir" 2>/dev/null | awk 'NR == 2 { printf "free\t%s\t%s\n", $4, $2 }'
    ;;
  recent)
    recent
    ;;
  trashed)
    trashed
    ;;
  search)
    search "${2:-}" "${3:-}" "${4:-}"
    ;;
  names)
    names "${2:-}"
    ;;
  apps)
    apps "${2:-}"
    ;;
  launch)
    shift
    launch "$@"
    ;;
  transfer)
    shift
    transfer "$@"
    ;;
  rename)
    rename "${2:-}" "${3:-}"
    ;;
  mkdir | touch)
    create "$1" "${2:-}" "${3:-}"
    ;;
  trash)
    shift
    trash "$@"
    ;;
  restore)
    shift
    restore "$@"
    ;;
  purge)
    shift
    purge "$@"
    ;;
  delete)
    shift
    delete "$@"
    ;;
  empty-trash)
    gio trash --empty 2>"$ERR_FILE" || fail "$(last_error)"
    ;;
  mount)
    device=${2:?device required}
    output=$(gio mount -d "$device" 2>"$ERR_FILE") || fail "$(last_error)"
    printf 'mounted\t%s\n' "${output##* at }"
    ;;
  eject)
    target=${2:?mount point required}
    gio mount -e "$target" 2>"$ERR_FILE" || fail "$(last_error)"
    ;;
  bookmark)
    bookmark "${2:-}"
    ;;
  unbookmark)
    unbookmark "${2:-}"
    ;;
  *)
    echo "Usage: files.sh places | free DIR | recent | trashed | search DIR QUERY [all] | names DIR | apps PATH | launch ID PATH... | transfer copy|move SRC TARGET POLICY... | rename PATH NAME | mkdir|touch DIR NAME | trash PATH... | restore NAME... | purge NAME... | delete PATH... | empty-trash | mount DEVICE | eject MOUNTPOINT | bookmark|unbookmark PATH" >&2
    exit 1
    ;;
esac
