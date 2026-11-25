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
#   files.sh clipboard-set copy|cut PATH...   put files on the clipboard other file managers share
#   files.sh clipboard-text TEXT    put text on the clipboard, a copied path for instance
#   files.sh clipboard-get          clipboard  copy|cut|empty|unavailable, then file  PATH lines
#   files.sh clipboard-clear        empty the shared clipboard
#   files.sh thumbnail PATH SIZE    thumbnail  PNG   a preview picture for PATH
#   files.sh archive-list ARCHIVE   bsdtar's listing of the members, in the C locale
#   files.sh archive-file ARCHIVE MEMBER   extracted  PATH   one member, cached
#   files.sh extract ARCHIVE DEST STRIP [MEMBER...]   total, progress, done ARCHIVE DEST
#   files.sh compress DEST PATH...  created  DEST   the format follows DEST's suffix
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
#   files.sh open [FOLDER]          show a folder (a path or a file:// URI) in the widget; none toggles it
#   files.sh open-cwd               show the focused terminal's folder in the widget
#   files.sh reveal PATH            show the folder holding PATH, with PATH picked
#   files.sh default on|off         make the widget the default file manager, or hand back to the
#                                   previous one
#   files.sh window                 show the widget's window, or bring it to the front
#   files.sh chooser on|off         show apps' Open and Save dialogs in the widget, or hand them back
#                                   to the GTK dialog
#   files.sh chosen ID RESPONSE FILTER [PATH...]   the widget's answer to one of those dialogs
#   files.sh resend                 those dialogs the apps still wait on, shown again after a restart
#   files.sh launcher on|off        list the widget's window in the app launcher, or take it out
#
# Actions print "error<TAB>message" when one item fails and carry on with the
# rest; the popup reports the last one. Replacing a file sends the old one to
# the trash first, so a wrong answer to a name conflict can be undone.

set -o pipefail

TRASH_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/Trash
RECENT_FILE=${XDG_DATA_HOME:-$HOME/.local/share}/recently-used.xbel
BOOKMARKS_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks
THUMB_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/joamag-files/thumbnails
ARCHIVE_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/joamag-files/archives
# What makes the widget the default file manager: the app that opens
# folders, the D-Bus service apps call to show a file in its folder, and
# the block of file manager keys in the user's Hyprland bindings.
APP_ID=joamag-files.desktop
APP_FILE=${XDG_DATA_HOME:-$HOME/.local/share}/applications/$APP_ID
DBUS_FILE=${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/org.freedesktop.FileManager1.service
BINDINGS_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua
MIMEAPPS_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list
PREVIOUS_FILE=${XDG_STATE_HOME:-$HOME/.local/state}/joamag-files/previous-file-manager
PREVIOUS_SERVICE=${XDG_STATE_HOME:-$HOME/.local/state}/joamag-files/previous-file-manager.service
KEYS_BEGIN="-- joamag.files: the file manager keys open the Files widget (its Default file manager setting adds and removes these lines)"
KEYS_END="-- joamag.files: end"
# What shows apps' Open and Save dialogs in the widget: the file chooser
# service, the portal file the desktop portal finds it by, the user's
# preference for it, and a rule in the user's Hyprland config that floats
# the dialog.
CHOOSER_NAME=org.freedesktop.impl.portal.desktop.joamag.files
CHOOSER_SERVICE=${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/$CHOOSER_NAME.service
CHOOSER_PORTAL=${XDG_DATA_HOME:-$HOME/.local/share}/xdg-desktop-portal/portals/joamag-files.portal
PORTALS_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/hyprland-portals.conf
PORTAL_LINE=org.freedesktop.impl.portal.FileChooser=joamag-files
# Any line of the preferences that sets the file chooser, spaces and all.
CHOOSER_KEY='^[[:space:]]*org\.freedesktop\.impl\.portal\.FileChooser[[:space:]]*='
PREVIOUS_CHOOSER=${XDG_STATE_HOME:-$HOME/.local/state}/joamag-files/previous-file-chooser
PORTALS_MADE=${XDG_STATE_HOME:-$HOME/.local/state}/joamag-files/portals-made
HYPRLAND_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua
RULE_BEGIN="-- joamag.files: the Files chooser floats over the app that asked (its File chooser setting adds and removes these lines)"
RULE_END="-- joamag.files: end"
# The widget's window in the app launcher.
LAUNCHER_FILE=${XDG_DATA_HOME:-$HOME/.local/share}/applications/joamag-files-window.desktop
# Where apps and thumbnailers are registered, the spec's default when unset.
DATA_DIRS=${XDG_DATA_DIRS:-/usr/local/share:/usr/share}
SEARCH_LIMIT=200
RECENT_LIMIT=40
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
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
  for base in "${XDG_DATA_HOME:-$HOME/.local/share}" ${DATA_DIRS//:/ }; do
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

# Files on the clipboard in every form apps look for: the one file managers
# share (x-special/gnome-copied-files: copy or cut, then a file:// URI a
# line; Nautilus, Thunar and Dolphin), the text/uri-list browsers and most
# apps read, and the paths as plain text. A picture's own bytes are not
# offered: Nautilus pastes those as a new "Pasted image" before it looks for
# files. clipboard.py offers them all at once; without Python or the
# data-control protocol, wl-copy offers the file managers' form alone.
clipboard_set() {
  local mode="${1:-}" path uri gnome uris="" plain="" dir mime status=2
  shift
  [[ $mode == copy || $mode == cut ]] || fail "unknown clipboard mode $mode"
  (( $# > 0 )) || fail "nothing to copy"
  gnome=$mode
  for path in "$@"; do
    uri="file://$(urlencode "$path")"
    gnome+=$'\n'"$uri"
    uris+="$uri"$'\r\n'
    plain+="${plain:+$'\n'}$path"
  done
  dir=$(mktemp -d "${TMPDIR:-/tmp}/files-clipboard.XXXXXX")
  printf '%s' "$gnome" >"$dir/gnome"
  printf '%s' "$uris" >"$dir/uris"
  printf '%s' "$plain" >"$dir/plain"
  local -a offers=("x-special/gnome-copied-files=$dir/gnome" "text/uri-list=$dir/uris")
  for mime in "text/plain;charset=utf-8" text/plain UTF8_STRING STRING TEXT; do offers+=("$mime=$dir/plain"); done
  if command -v python3 >/dev/null; then
    python3 "$HERE/clipboard.py" "${offers[@]}" 2>"$ERR_FILE"
    status=$?
  fi
  rm -rf -- "$dir"
  (( status == 0 )) && return 0
  (( status == 2 )) || fail "$(last_error)"
  command -v wl-copy >/dev/null || fail "wl-copy is not installed"
  printf '%s' "$gnome" | wl-copy --type x-special/gnome-copied-files 2>"$ERR_FILE" || fail "$(last_error)"
}

# Text on the clipboard under every type text is read by: Copy path puts
# the paths there to paste in a terminal, an editor or a chat. clipboard.py
# offers them all at once; without it, wl-copy offers plain text alone.
clipboard_text() {
  local text="${1:-}" dir mime status=2
  [[ -n $text ]] || fail "nothing to copy"
  dir=$(mktemp -d "${TMPDIR:-/tmp}/files-clipboard.XXXXXX")
  printf '%s' "$text" >"$dir/plain"
  local -a offers=()
  for mime in "text/plain;charset=utf-8" text/plain UTF8_STRING STRING TEXT; do offers+=("$mime=$dir/plain"); done
  if command -v python3 >/dev/null; then
    python3 "$HERE/clipboard.py" "${offers[@]}" 2>"$ERR_FILE"
    status=$?
  fi
  rm -rf -- "$dir"
  (( status == 0 )) && return 0
  (( status == 2 )) || fail "$(last_error)"
  command -v wl-copy >/dev/null || fail "wl-copy is not installed"
  printf '%s' "$text" | wl-copy --type "text/plain;charset=utf-8" 2>"$ERR_FILE" || fail "$(last_error)"
}

# What the clipboard holds: files from a file manager (copied or cut), or
# from any app that offers a text/uri-list; text is not files and comes
# back empty. Only local file:// URIs count.
clipboard_get() {
  local types mode=copy line path
  local -a uris=()
  if ! command -v wl-paste >/dev/null; then
    printf 'clipboard\tunavailable\n'
    return 0
  fi
  types=$(wl-paste --list-types 2>/dev/null)
  if grep -qx 'x-special/gnome-copied-files' <<<"$types"; then
    while IFS= read -r line || [[ -n $line ]]; do uris+=("${line%$'\r'}"); done < <(wl-paste --no-newline --type x-special/gnome-copied-files 2>/dev/null)
    mode=${uris[0]:-copy}
    uris=("${uris[@]:1}")
    [[ $mode == cut ]] || mode=copy
  elif grep -qx 'text/uri-list' <<<"$types"; then
    while IFS= read -r line || [[ -n $line ]]; do uris+=("${line%$'\r'}"); done < <(wl-paste --no-newline --type text/uri-list 2>/dev/null)
  else
    printf 'clipboard\tempty\n'
    return 0
  fi
  printf 'clipboard\t%s\n' "$mode"
  for line in "${uris[@]}"; do
    [[ $line == file://* ]] || continue
    line=${line#file://}
    line=${line#localhost}
    [[ $line == /* ]] || continue
    urldecode path "$line"
    printf 'file\t%s\n' "$path"
  done
}

# The .thumbnailer file registered for a MIME type, user ones first.
thumbnailer_for() {
  local mime="$1" base file types
  for base in "${XDG_DATA_HOME:-$HOME/.local/share}" ${DATA_DIRS//:/ }; do
    for file in "${base%/}"/thumbnailers/*.thumbnailer; do
      [[ -f $file ]] || continue
      types=$(sed -n 's/^MimeType=//p' "$file" | head -n 1)
      [[ ";$types" == *";$mime;"* ]] && { printf '%s' "$file"; return 0; }
    done
  done
  return 1
}

# A preview picture of PATH about SIZE pixels wide, made by the thumbnailer
# the system registers for its type (the ones Nautilus uses: a video frame,
# an album cover, a document's first page, a font sample) and kept in this
# widget's own cache under the file's path and date, so each version of a
# file is drawn once. An older version's picture is dropped as the new one
# lands, and pictures nobody needed for three months go.
thumbnail() {
  local path="${1:?path required}" size="${2:-256}" key mtime out mime file exec tmp word
  local -a words=() argv=()
  [[ -f $path ]] || fail "no file at $path"
  [[ $size =~ ^[0-9]+$ ]] || fail "bad size $size"
  key=$(printf '%s' "$path" | md5sum | cut -d' ' -f1)
  mtime=$(stat -c %Y -- "$path")
  out="$THUMB_DIR/$key-$mtime-$size.png"
  if [[ -s $out ]]; then
    printf 'thumbnail\t%s\n' "$out"
    return 0
  fi
  mime=$(gio info -a standard::content-type -- "$path" 2>/dev/null | sed -n 's/^ *standard::content-type: //p')
  [[ -n $mime ]] || fail "could not tell the type of $(basename "$path")"
  file=$(thumbnailer_for "$mime") || fail "no preview for $mime"
  exec=$(sed -n 's/^Exec=//p' "$file" | head -n 1)
  mkdir -p "$THUMB_DIR"
  tmp="$THUMB_DIR/.$key.$$.png"
  # Paths and URIs stand alone as arguments; quoting the replacement keeps
  # an & in a name from standing for the match (patsub_replacement).
  read -ra words <<<"$exec"
  for word in "${words[@]}"; do
    case $word in
      %i) argv+=("$path") ;;
      %u) argv+=("file://$(urlencode "$path")") ;;
      %o) argv+=("$tmp") ;;
      *) word=${word//%s/"$size"}; argv+=("${word//%%/%}") ;;
    esac
  done
  if timeout 20 "${argv[@]}" >/dev/null 2>"$ERR_FILE" && [[ -s $tmp ]]; then
    # Older versions of the file go; this one's other sizes stay in use.
    find "$THUMB_DIR" -maxdepth 1 -name "$key-*.png" ! -name "$key-$mtime-*.png" -delete 2>/dev/null
    mv -f -- "$tmp" "$out"
    find "$THUMB_DIR" -name '*.png' -mtime +90 -delete 2>/dev/null
    printf 'thumbnail\t%s\n' "$out"
  else
    rm -f -- "$tmp"
    fail "no preview: $(last_error)"
  fi
}

# bsdtar reads member names as patterns; a name with [ * ? or \ in it is
# taken literally.
member_pattern() {
  printf '%s' "$1" | sed 's/[][*?\\]/\\&/g'
}

archive_list() {
  local archive="${1:?archive required}"
  [[ -f $archive ]] || fail "no archive at $archive"
  LC_ALL=C bsdtar -tvf "$archive" 2>"$ERR_FILE" || fail "$(last_error)"
}

# One member of ARCHIVE, extracted once into the widget's cache under the
# archive's path and date, for the preview and for opening it in an app.
# Copies nobody touched for a week go.
archive_file() {
  local archive="${1:?archive required}" member="${2:-}" key out
  [[ -f $archive ]] || fail "no archive at $archive"
  [[ -n $member && $member != /* && $member != *..* ]] || fail "bad member $member"
  key=$(printf '%s|%s' "$archive" "$(stat -c %Y -- "$archive")" | md5sum | cut -d' ' -f1)
  out="$ARCHIVE_CACHE/$key"
  if [[ ! -e $out/$member ]]; then
    mkdir -p "$out"
    LC_ALL=C bsdtar -xf "$archive" -C "$out" "$(member_pattern "$member")" 2>"$ERR_FILE" || fail "$(last_error)"
  fi
  [[ -e $out/$member ]] || fail "$(basename "$member") is not in the archive"
  touch -c -- "$out"
  find "$ARCHIVE_CACHE" -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null
  printf 'extracted\t%s\n' "$out/$member"
}

# Extracts ARCHIVE into DEST, made when missing, dropping STRIP leading
# folders from each name (copying out of a folder inside the archive), all
# of it or only the MEMBERs given. The total comes from the listing and the
# progress from what has landed. Files already in DEST are kept. TERM stops
# it and removes DEST if this call made it.
extract() {
  local archive="${1:?archive required}" dest="${2:?destination required}" strip="${3:-0}" made=0 total base child="" member
  shift 3
  local -a members=()
  [[ -f $archive ]] || fail "no archive at $archive"
  [[ $strip =~ ^[0-9]+$ ]] || fail "bad strip $strip"
  for member in "$@"; do members+=("$(member_pattern "$member")"); done
  if [[ ! -d $dest ]]; then
    mkdir -p -- "$dest" 2>"$ERR_FILE" || fail "$(last_error)"
    made=1
  fi
  total=$(LC_ALL=C bsdtar -tvf "$archive" "${members[@]}" 2>/dev/null | awk '{ sum += $5 } END { print sum + 0 }')
  base=$(bytes_of "$dest")
  printf 'total\t%s\n' "$total"

  stop_extract() {
    [[ -n $child ]] && kill "$child" 2>/dev/null && wait "$child" 2>/dev/null
    if (( made )); then
      rm -rf -- "$dest"
      printf 'cancelled\n'
    else
      # In a folder that was there already, what landed stays.
      printf 'cancelled\tkept\n'
    fi
    exit 0
  }
  trap stop_extract TERM INT

  LC_ALL=C bsdtar -xkf "$archive" -C "$dest" --strip-components "$strip" "${members[@]}" 2>"$ERR_FILE" &
  child=$!
  while kill -0 "$child" 2>/dev/null; do
    printf 'progress\t%s\n' "$(( $(bytes_of "$dest") - base ))"
    sleep 0.3
  done
  if wait "$child"; then
    printf 'progress\t%s\n' "$total"
    printf 'done\t%s\t%s\n' "$archive" "$dest"
  else
    report "$(last_error)"
  fi
  return 0
}

# Packs PATHs into DEST, the format following DEST's suffix (.zip, .7z,
# .tar.gz ...). It is written under a hidden name beside DEST and renamed
# when complete, so a cancelled or failed run leaves nothing behind.
compress() {
  local dest="${1:?archive required}" tmp child="" path name
  shift
  local -a args=()
  (( $# > 0 )) || fail "nothing to compress"
  [[ -e $dest || -L $dest ]] && fail "$(basename "$dest") already exists"
  [[ -d $(dirname "$dest") ]] || fail "no folder at $(dirname "$dest")"
  for path in "$@"; do
    [[ -e $path || -L $path ]] || fail "$(basename "$path") is gone"
    name=$(basename "$path")
    [[ $name == -* ]] && name="./$name"
    args+=(-C "$(dirname "$path")" "$name")
  done
  # The hidden name keeps DEST's suffix, which is how bsdtar picks the format.
  tmp="$(dirname "$dest")/.partial-$$-$(basename "$dest")"
  printf 'total\t0\n'

  stop_compress() {
    [[ -n $child ]] && kill "$child" 2>/dev/null && wait "$child" 2>/dev/null
    rm -f -- "$tmp"
    printf 'cancelled\n'
    exit 0
  }
  trap stop_compress TERM INT

  bsdtar -a -cf "$tmp" "${args[@]}" 2>"$ERR_FILE" &
  child=$!
  if wait "$child" && mv -n -- "$tmp" "$dest" && [[ ! -e $tmp ]]; then
    printf 'created\t%s\n' "$dest"
  else
    rm -f -- "$tmp"
    fail "$(last_error)"
  fi
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
    touch -- "$target" 2>"$ERR_FILE" || fail "$(last_error)"
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

# A folder or file another app names, as a local path: a file:// URI is
# decoded and a relative path taken from here. Other URIs (sftp://, smb://)
# come back empty, for the previous file manager to open.
local_path() {
  local _lp="$2"
  case $_lp in
    file://*)
      _lp=${_lp#file://}
      _lp=${_lp#localhost}
      urldecode _lp "$_lp"
      ;;
    *://*) _lp="" ;;
    /*) ;;
    *) _lp="$PWD/$_lp" ;;
  esac
  printf -v "$1" '%s' "$_lp"
}

# The file manager the widget hands over to: the default one before it,
# else Omarchy's Files or Nautilus, whichever is installed.
previous_manager() {
  local id
  for id in "$(cat "$PREVIOUS_FILE" 2>/dev/null)" folio.desktop org.gnome.Nautilus.desktop; do
    [[ -n $id && $id != "$APP_ID" ]] && desktop_file "$id" >/dev/null && { printf '%s' "$id"; return 0; }
  done
  return 1
}

# A folder from another app, Show in folder or the file manager keys goes to
# the widget (go, or reveal for an item to pick in its folder), which shows
# it in the popup or its window; with none, the popup opens or closes, or
# with window, the window shows.
# Without the widget (not in the bar, or the shell is down), and for a
# location it cannot browse or that is not there, the previous file manager
# opens it.
show() {
  local how="$1" target="${2:-}" path="" id
  if [[ -z $target ]]; then
    [[ $how == window ]] || how=summon
    omarchy-shell joamag.files "$how" >/dev/null 2>&1 && return 0
  else
    local_path path "$target"
    [[ $how == go && -e $path && ! -d $path ]] && how=reveal
    [[ -n $path && -e $path ]] && omarchy-shell joamag.files "$how" "$path" >/dev/null 2>&1 && return 0
  fi
  id=$(previous_manager) || fail "no other file manager${target:+ to open $target}"
  if [[ -n $target ]]; then launch "$id" "$target"; else launch "$id"; fi
}

# Writes FILE only when it would change; true when it did. A file that
# cannot be written ends the command with an error.
write_changed() {
  [[ -f $1 && $(cat "$1") == "$2" ]] && return 1
  { mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" >"$1"; } 2>/dev/null || fail "cannot write $1"
}

# files.sh as the first word of an Exec line, quoted only for a plugin
# folder that needs it: xdg-mime checks the app is there by the first word
# of Exec, quotes and all, and passes over it otherwise. In the quotes a ",
# `, $ or \ takes a backslash, and every backslash is doubled again, the
# way the file's strings escape it; a % is doubled, or it is a field code.
exec_word() {
  local exec="$HERE/files.sh"
  [[ $exec == *[^A-Za-z0-9/._+-]* ]] && exec="\"$(printf '%s' "$exec" | sed -e 's/[\\"`$]/\\&/g' -e 's/\\/\\\\/g' -e 's/%/%%/g')\""
  printf '%s' "$exec"
}

# The app that opens folders, hidden from the launcher.
desktop_entry() {
  printf '%s\n' "[Desktop Entry]" "Type=Application" "Name=Files widget" \
    "Comment=Open folders in the Files widget of the bar" "Icon=system-file-manager" \
    "Exec=$(exec_word) open %U" "MimeType=inode/directory;" "NoDisplay=true" "StartupNotify=false"
}

# Files in the app launcher: the widget's window.
launcher_entry() {
  printf '%s\n' "[Desktop Entry]" "Type=Application" "Name=Files" "GenericName=File Manager" \
    "Comment=Browse, copy and move files in the Files window of the bar" "Icon=system-file-manager" \
    "Exec=$(exec_word) window" "Categories=System;FileTools;FileManager;" "Keywords=folders;explorer;" \
    "StartupNotify=false"
}

dbus_service() {
  printf '%s\n' "[D-BUS Service]" "Name=org.freedesktop.FileManager1" "Exec=$HERE/filemanager1.py"
}

# dbus-broker reads new service files only when told to.
dbus_reload() {
  gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
}

# A service's whole command line, the python script SCRIPT of the plugin,
# for pgrep and pkill: an editor or a pager on the script names it too, and
# is not it.
service_pattern() {
  local here
  here=$(printf '%s' "$HERE" | sed 's/[][\.*^$+?(){}|]/\\&/g')
  printf '(.*/)?python3 %s/%s' "$here" "${1//./\\.}"
}

chooser_service() {
  printf '%s\n' "[D-BUS Service]" "Name=$CHOOSER_NAME" "Exec=$HERE/filechooser.py"
}

chooser_portal() {
  printf '%s\n' "[portal]" "DBusName=$CHOOSER_NAME" "Interfaces=org.freedesktop.impl.portal.FileChooser;"
}

# The portal reads its preferences only when it starts.
restart_portal() {
  systemctl --user try-restart xdg-desktop-portal.service >/dev/null 2>"$ERR_FILE" ||
    report "cannot restart the desktop portal: $(last_error)"
}

# Whether the portal running started before its preferences last changed,
# so it does not go by them yet.
portal_stale() {
  local pid age
  pid=$(systemctl --user show -P MainPID xdg-desktop-portal.service 2>/dev/null)
  [[ $pid =~ ^[1-9][0-9]*$ && -f $PORTALS_FILE ]] && age=$(ps -o etimes= -p "$pid" 2>/dev/null) && [[ -n ${age// /} ]] || return 1
  (($(date +%s) - age < $(stat -c %Y "$PORTALS_FILE")))
}

# The lines of the user's Hyprland bindings that point the file manager keys
# at the widget, between two markers so they can be taken out again.
keys_block() {
  local cmd
  printf -v cmd '%q' "$HERE/files.sh"
  cmd=${cmd//\\/\\\\}
  cmd=${cmd//\"/\\\"}
  printf '%s\n' "$KEYS_BEGIN" \
    "o.rebind(\"SUPER + SHIFT + F\", \"File manager\", \"$cmd open\")" \
    "o.rebind(\"SUPER + ALT + SHIFT + F\", \"File manager (cwd)\", \"$cmd open-cwd\")" \
    "$KEYS_END"
}

# The rule that floats the file chooser over the app that asked, the way
# the portal's own dialogs float, between two markers in the user's
# Hyprland config so it can be taken out again.
rule_block() {
  printf '%s\n' "$RULE_BEGIN" \
    'o.window({ class = "^org.quickshell$", title = "^Files chooser · .*" }, { tag = "+floating-window" })' \
    "$RULE_END"
}

# FILE without the block between BEGIN and END, nor the blank lines it
# leaves at the end.
without_block() {
  awk -v begin="$2" -v end="$3" '
    $0 == begin { skip = 1; next }
    skip { if ($0 == end) skip = 0; next }
    /^$/ { blank++; next }
    { while (blank > 0) { print ""; blank-- } print }
  ' "$1"
}

# Adds BLOCK to the end of FILE, between BEGIN and END (on), or takes it
# out (off), and has Hyprland read its config again when that changed it.
set_block() {
  local file=$1 begin=$2 end=$3 kept="" next
  if [[ -f $file ]]; then
    kept=$(without_block "$file" "$begin" "$end")
  elif [[ $4 == off ]]; then
    return 0
  fi
  next=$kept
  [[ $4 == on ]] && next="${kept:+$kept$'\n\n'}$5"
  write_changed "$file" "$next" || return 0
  hyprctl reload >/dev/null 2>&1 || true
}

set_keys() {
  set_block "$BINDINGS_FILE" "$KEYS_BEGIN" "$KEYS_END" "$1" "$(keys_block)"
}

# LINE right under the [preferred] header of TEXT, or under a new one.
with_preference() {
  printf '%s\n' "$1" | awk -v line="$2" '
    { print }
    $0 == "[preferred]" && !done { print line; done = 1 }
    END { if (!done) { print "[preferred]"; print line } }
  '
}

# The preferences the portal goes by while the user has none for Hyprland:
# the first of its files, in the order it looks for them (but for its
# build-time folders), or Omarchy's.
portal_preferences() {
  local dir name config=${XDG_CONFIG_DIRS:-/etc/xdg}
  for dir in "${XDG_CONFIG_HOME:-$HOME/.config}" ${config//:/ } "${XDG_DATA_HOME:-$HOME/.local/share}" ${DATA_DIRS//:/ }; do
    for name in "${PORTALS_FILE##*/}" portals.conf; do
      [[ -f $dir/xdg-desktop-portal/$name ]] && { cat "$dir/xdg-desktop-portal/$name"; return; }
    done
  done
  printf '%s\n' "[preferred]" "default=hyprland;gtk"
}

# The user's portal preferences, with the widget for file chooser dialogs
# (on) or without it (off); true when that changed them. A file chooser of
# the user's own is set aside and comes back; with no preferences for
# Hyprland of the user's own, a copy of the ones the portal goes by is
# made, and goes again unless the user has changed it since.
set_portal() {
  local kept line made=""
  if [[ $1 == on ]]; then
    if [[ ! -f $PORTALS_FILE ]]; then
      write_changed "$PORTALS_FILE" "$(portal_preferences)"
      made=1
    fi
    grep -qxF "$PORTAL_LINE" "$PORTALS_FILE" && return 1
    line=$(grep -m 1 -E "$CHOOSER_KEY" "$PORTALS_FILE")
    [[ -n $line ]] && write_changed "$PREVIOUS_CHOOSER" "$line"
    kept=$(grep -vE "$CHOOSER_KEY" "$PORTALS_FILE")
    write_changed "$PORTALS_FILE" "$(with_preference "$kept" "$PORTAL_LINE")"
    [[ -n $made ]] && write_changed "$PORTALS_MADE" "$(cat "$PORTALS_FILE")"
    return 0
  fi
  if [[ -f $PORTALS_MADE && -f $PORTALS_FILE && $(cat "$PORTALS_FILE") == "$(cat "$PORTALS_MADE")" ]]; then
    rm -f "$PORTALS_FILE" "$PORTALS_MADE" "$PREVIOUS_CHOOSER"
    return 0
  fi
  rm -f "$PORTALS_MADE"
  [[ -f $PORTALS_FILE ]] && grep -qxF "$PORTAL_LINE" "$PORTALS_FILE" || return 1
  kept=$(grep -vxF "$PORTAL_LINE" "$PORTALS_FILE")
  if [[ -f $PREVIOUS_CHOOSER ]]; then
    write_changed "$PORTALS_FILE" "$(with_preference "$kept" "$(cat "$PREVIOUS_CHOOSER")")"
    rm -f "$PREVIOUS_CHOOSER"
  else
    write_changed "$PORTALS_FILE" "$kept"
  fi
  return 0
}

# Folders from other apps, Show in folder and the file manager keys come to
# the widget. The FileManager1 service starts once; while another file
# manager holds the name (Nautilus does while a window of it is open) it
# waits in line for it. A service file of the user's own is set aside.
default_on() {
  local current
  current=$(xdg-mime query default inode/directory 2>/dev/null)
  if [[ -n $current && $current != "$APP_ID" ]]; then
    mkdir -p "$(dirname "$PREVIOUS_FILE")"
    printf '%s\n' "$current" >"$PREVIOUS_FILE"
  fi
  write_changed "$APP_FILE" "$(desktop_entry)"
  if [[ $current != "$APP_ID" ]]; then
    xdg-mime default "$APP_ID" inode/directory 2>"$ERR_FILE" || fail "$(last_error)"
  fi
  if [[ -f $DBUS_FILE ]] && ! grep -qF "$HERE/filemanager1.py" "$DBUS_FILE"; then
    mkdir -p "$(dirname "$PREVIOUS_SERVICE")"
    mv -f -- "$DBUS_FILE" "$PREVIOUS_SERVICE"
  fi
  write_changed "$DBUS_FILE" "$(dbus_service)" && dbus_reload
  set_keys on
  pgrep -f -x -- "$(service_pattern filemanager1.py)" >/dev/null && return 0
  setsid -f "$HERE/filemanager1.py" >/dev/null 2>&1 </dev/null
}

# All of it back to the previous file manager. The widget's line leaves the
# user's mimeapps.list, so a default that came from the system (Omarchy's)
# shows through again and follows its updates; one the user had picked is
# set back. The D-Bus service file set aside comes back in place of the
# widget's; one that is not the widget's stays.
default_off() {
  local id kept was=""
  if [[ -f $MIMEAPPS_FILE ]] && grep -qxF "inode/directory=$APP_ID" "$MIMEAPPS_FILE"; then
    kept=$(grep -vxF "inode/directory=$APP_ID" "$MIMEAPPS_FILE")
    printf '%s\n' "$kept" >"$MIMEAPPS_FILE"
    was=1
  fi
  [[ $(xdg-mime query default inode/directory 2>/dev/null) == "$APP_ID" ]] && was=1
  if [[ -n $was ]] && id=$(previous_manager) && [[ $(xdg-mime query default inode/directory 2>/dev/null) != "$id" ]]; then
    xdg-mime default "$id" inode/directory 2>"$ERR_FILE" || fail "$(last_error)"
  fi
  rm -f "$APP_FILE" "$PREVIOUS_FILE"
  if [[ -f $DBUS_FILE ]] && grep -qF "$HERE/filemanager1.py" "$DBUS_FILE"; then
    rm -f "$DBUS_FILE"
    [[ -f $PREVIOUS_SERVICE ]] && mv -f -- "$PREVIOUS_SERVICE" "$DBUS_FILE"
    dbus_reload
  fi
  rmdir "$(dirname "$PREVIOUS_FILE")" 2>/dev/null
  set_keys off
  pkill -f -x -- "$(service_pattern filemanager1.py)" >/dev/null 2>&1 || true
}

# Apps' Open and Save dialogs show in the widget: the desktop portal finds
# its file chooser service by the portal file and starts it through the
# D-Bus service file once the user's preferences say so, and the dialog
# floats like the portal's own.
chooser_on() {
  write_changed "$CHOOSER_SERVICE" "$(chooser_service)" && dbus_reload
  write_changed "$CHOOSER_PORTAL" "$(chooser_portal)"
  # A restart that failed before is made again.
  if set_portal on || portal_stale; then
    restart_portal
  fi
  set_block "$HYPRLAND_FILE" "$RULE_BEGIN" "$RULE_END" on "$(rule_block)"
}

# All of it back to the GTK dialog, and the service stopped.
chooser_off() {
  local changed=""
  set_portal off && changed=1
  if [[ -f $CHOOSER_PORTAL || -f $CHOOSER_SERVICE ]]; then
    rm -f "$CHOOSER_PORTAL" "$CHOOSER_SERVICE"
    dbus_reload
    changed=1
  fi
  [[ -n $changed ]] && restart_portal
  rmdir "$(dirname "$PREVIOUS_CHOOSER")" 2>/dev/null
  set_block "$HYPRLAND_FILE" "$RULE_BEGIN" "$RULE_END" off
  pkill -f -x -- "$(service_pattern filechooser.py)" >/dev/null 2>&1 || true
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
  thumbnail)
    thumbnail "${2:-}" "${3:-}"
    ;;
  clipboard-set)
    shift
    clipboard_set "$@"
    ;;
  clipboard-text)
    clipboard_text "${2:-}"
    ;;
  clipboard-get)
    clipboard_get
    ;;
  clipboard-clear)
    command -v wl-copy >/dev/null || fail "wl-copy is not installed"
    wl-copy --clear 2>"$ERR_FILE" || fail "$(last_error)"
    ;;
  archive-list)
    archive_list "${2:-}"
    ;;
  archive-file)
    archive_file "${2:-}" "${3:-}"
    ;;
  extract)
    shift
    (( $# >= 3 )) || fail "extract needs an archive, a destination and a strip count"
    extract "$@"
    ;;
  compress)
    shift
    compress "$@"
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
  open)
    show go "${2:-}"
    ;;
  open-cwd)
    show go "$(omarchy-cmd-terminal-cwd 2>/dev/null)"
    ;;
  reveal)
    show reveal "${2:?path required}"
    ;;
  default)
    case "${2:-}" in
      on) default_on ;;
      off) default_off ;;
      *) fail "default takes on or off" ;;
    esac
    ;;
  window)
    show window ""
    ;;
  chooser)
    case "${2:-}" in
      on) chooser_on ;;
      off) chooser_off ;;
      *) fail "chooser takes on or off" ;;
    esac
    ;;
  chosen)
    shift
    "$HERE/filechooser.py" answer "$@"
    ;;
  resend)
    "$HERE/filechooser.py" resend
    ;;
  launcher)
    case "${2:-}" in
      on) write_changed "$LAUNCHER_FILE" "$(launcher_entry)" || true ;;
      off) rm -f "$LAUNCHER_FILE" ;;
      *) fail "launcher takes on or off" ;;
    esac
    ;;
  *)
    echo "Usage: files.sh places | free DIR | recent | trashed | search DIR QUERY [all] | names DIR | apps PATH | launch ID PATH... | clipboard-set copy|cut PATH... | clipboard-get | clipboard-clear | thumbnail PATH SIZE | archive-list ARCHIVE | archive-file ARCHIVE MEMBER | extract ARCHIVE DEST STRIP [MEMBER...] | compress DEST PATH... | transfer copy|move SRC TARGET POLICY... | rename PATH NAME | mkdir|touch DIR NAME | trash PATH... | restore NAME... | purge NAME... | delete PATH... | empty-trash | mount DEVICE | eject MOUNTPOINT | bookmark|unbookmark PATH | open [FOLDER] | open-cwd | reveal PATH | default on|off" >&2
    exit 1
    ;;
esac
