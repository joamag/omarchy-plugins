# joamag.files

A file navigator in the Omarchy bar, in the spirit of GNOME Files: a popup under its bar button that pops out into its own window, with tabs. It complements Nautilus rather than replacing it, so anything it does not cover is one click (or `N`) away, opened at the folder on screen.

## Layout

- **Header**: back, forward, up, a Go to button (in the popup), the path bar, the filter, the List / Grid / Columns switch, the hidden files toggle (the eye: dot files and folders shown or not, remembered across restarts), the preview pane, pop out or dock, and a ⋮ menu (new folder or file, paste, select all, hidden files, sort, bookmark, Nautilus).
- **Tabs** under the header, each with its place glyph, its name and its number for the `1`-`9` keys; `+` opens a new one at the same folder.
- **The folder** as a list (name, type, size, date, sortable by clicking a column), a grid with the pictures themselves for images, the first page of PDFs and thumbnails for videos, audio, documents and fonts, or columns from the root of the path down to the folder on screen, followed by the folder under the cursor or the file's preview. Recent, Trash and search results also say where each item lives.
- **Preview pane** (`i`): the selected file up close, as large as the pane allows: pictures; PDF pages, with ‹ › (or `<` `>`) to turn them and the page count; a frame of a video, an album cover, the first page of an office document or a font sample from the thumbnailers the system registers (the ones Nautilus uses); or the first lines of a text file (a binary file says so instead of showing noise). Under it the kind, size, date and folder, and Open / Open with, Open / In new tab, or Restore / Delete.
- **Footer**: a progress line with Cancel while a long copy or move runs, the item count and the selection on the left, the clipboard, hidden files and free space on the right, the action buttons, and a line of key hints.
- **Window**: the same view in a regular window that Hyprland moves, resizes and tiles, with a places sidebar: the standard folders, the bookmarks shared with Nautilus, drives with their free space and eject or mount, Recent and the Trash.

The popup and the window share the tabs; they are saved on the widget's `shell.json` entry and come back after a restart. The window is never open together with the popup: popping out closes the popup, docking (or a left click on the bar button) closes the window.

## Interactions

- Left click on the bar: open the popup, or dock the window back into it. Middle click: pop out into a window or dock. Right click: open the folder on screen in Nautilus.
- Click selects, Ctrl+click adds to the selection, Shift+click selects a range, double click opens. Right click on an item or on empty space opens a menu.
- The wheel scrolls in whole rows with no glide: the system's wheel step per notch (three rows by default), one row of tiles in the grid, one column sideways in the columns view; a touchpad's movement adds up to whole rows. Pressing and dragging never scrolls the list, it moves files.
- Click a path segment to go there, or the empty end of the path bar to type a path (`~/Downloads`, `/etc`, `file:///…`, or a name relative to the folder on screen).
- Type in the filter to narrow the folder on screen as you type; Enter searches every folder below it by name (hidden files too while they are shown), ↓ goes to the results, Esc clears.
- Drag files onto a folder, a tab, a sidebar place or a path segment to move them there (hold Ctrl to copy), or out to another app. Files dropped from another app are copied in.
- Copy and cut use the clipboard file managers share (`x-special/gnome-copied-files`, through `wl-clipboard`): files copied or cut here paste in Nautilus (and Thunar or Dolphin), and files copied or cut there, or copied as a file list by any app, paste here, a cut moving them. Opening the widget picks up what is on the clipboard, so the count in the status line and the dimmed cut files stay right. Members of an archive are not files until they are taken out, so copying them empties the shared clipboard and only this widget pastes them.
- Paste where a name is already taken asks first: skip, keep both (the new one becomes `name (copy).ext`) or replace (the old one goes to the Trash), for that file or for the rest too. Pasting next to the original makes a copy without asking.
- Move to Trash shows a note with Undo (or Ctrl+Z); in the Trash, Enter restores an item to where it was (under a "(copy)" name if that name was taken again meanwhile). Delete for good and Empty Trash ask first.
- Opening a drive that is not mounted mounts it; the eject button in the sidebar unmounts and ejects it, and any tab on it goes home.

## Archives

Zip files and everything else `bsdtar` reads (tar, tar.gz / xz / zst / bz2, 7z, rar, iso, cpio) open like folders:

- **Browse inside**: Enter, `l` or a double click opens an archive as a read-only folder in the tab; the path bar runs through it (`Downloads › photos.zip › 2024`), `h` climbs out. Files inside preview like any other (they are taken out into the cache as they are looked at) and open in their app; an archive inside an archive opens as a folder too. Renaming, the Trash and pasting are off inside, and dragging out is not offered: copy instead.
- **Copy out**: `y` (or Copy out) inside the archive, then `p` in any folder: the files are extracted aside and moved into place through the usual paste, so a name that is taken is asked about.
- **Extract**: Extract here (`E`, or from the menus) unpacks into a new folder beside the archive, named after its single top folder or after the archive, under a free name. Extract to… asks for the folder (made if missing; files already in it are kept), for the whole archive or for what is selected inside it. Both show the progress line with Cancel, which removes what a cancelled extraction made.
- **In the preview pane**: an archive under the cursor lists what it holds, with the file and folder counts and the unpacked size.
- **Compress**: `Z` or Compress to .zip… packs the selection into a new archive beside it; the name is asked for (`Archive.zip` or the item's name), and its suffix picks the format: `.zip`, `.7z`, `.tar`, `.tar.gz`, `.tar.xz`, `.tar.zst` or `.tar.bz2`.

## Keys

The panel keys of the other widgets and the Nautilus shortcuts both work; `?` shows them all.

| Keys | Does |
|---|---|
| `j` `k` `↓` `↑` | Move (in the grid, the arrows move by rows) |
| `J` `K`, Shift+`↓` `↑` | Extend the selection |
| `l`, Enter | Open (`l` only enters folders) |
| `h`, Backspace, Alt+`↑` | Up a folder |
| Alt+`←` Alt+`→` | Back, forward |
| Space, Ctrl+A | Select, select all |
| `y` `x` `p`, Ctrl+C X V | Copy, cut, paste |
| `r`, F2 | Rename (Enter keeps it, Esc cancels) |
| `a`, Ctrl+Shift+N, `n` | New folder, new file |
| `d`, Delete | Move to Trash (delete for good inside the Trash) |
| Ctrl+Z | Undo the last move to the Trash |
| Shift+Delete | Delete for good |
| `o` | Open with |
| `E` | Extract the archive under the cursor here (inside an archive: all of it) |
| `Z` | Compress the selection |
| `<` `>` | Previous, next page of the PDF in the preview |
| `/`, Ctrl+F | Filter; Enter searches below |
| `g` | Go to: `h` home, `k` desktop, `D` documents, `d` downloads, `m` music, `p` pictures, `v` videos, `r` recent, `t` trash, `/` system, digits for bookmarks and drives |
| `e`, Ctrl+L | Type a path |
| `t` `q`, Ctrl+T Ctrl+W | New tab, close tab |
| `[` `]`, Ctrl+Tab, Ctrl+PageUp PageDown | Previous, next tab |
| `1`-`9` | Go to a tab |
| `v`, Ctrl+1 2 3 | List, grid, columns |
| `.`, Ctrl+H | Hidden files |
| `i` | Preview pane |
| `s` | Sort by the next column (click a column header to flip its direction) |
| Ctrl+D | Bookmark the folder (shared with Nautilus) |
| `w` | Pop out or dock |
| `N` | Open in Nautilus |
| Esc | Close a menu, then clear the clipboard, the selection and the filter, then close |
| Tab | Next widget's popup |

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`; the widget writes them itself as you switch:

| Key | Default | Meaning |
|---|---|---|
| `showHidden` | `false` | Show dot files |
| `showPreview` | `false` | Show the preview pane |
| `sortKey` | `"name"` | `name`, `modified`, `size` or `type`; folders always come first |
| `sortDescending` | `false` | Reverse the order |
| `tabs` | `[]` | The open tabs as `{ "path": …, "view": "list" \| "grid" \| "columns" }`; empty opens home |
| `activeTab` | `0` | The tab on screen |

## IPC

```
omarchy-shell joamag.files toggle
omarchy-shell joamag.files go ~/Downloads
omarchy-shell joamag.files popOut
omarchy-shell joamag.files dock
omarchy-shell joamag.files version
```

## Data source

Qt's folder model (`Qt.labs.folderlistmodel`) lists the folder on screen and follows changes on disk. Everything else goes through `files.sh`: the standard folders (`xdg-user-dir`), the GTK bookmarks file Nautilus uses, drives from `lsblk` and `df`, Recent from `recently-used.xbel`, the Trash from `~/.local/share/Trash` (items trashed on other drives stay in that drive's own trash), search with `find`, "Open with" from `gio mime`, and thumbnails from the `.thumbnailer` files the system registers, made once per version of a file and kept in `~/.cache/joamag-files/thumbnails` (pictures unused for three months are dropped). PDF pages are drawn by Qt's PDF reader when it is installed (`qt6-webengine` ships it), and by the PDF thumbnailer otherwise. Archives are listed, extracted and made with `bsdtar` (libarchive, which pacman itself depends on); members looked at inside an archive are kept in `~/.cache/joamag-files/archives` for a week. The shared clipboard goes through `wl-copy` and `wl-paste`; without them the widget keeps its own. Copies run `cp -a` and moves `mv`, with the progress measured as the copy lands; Cancel stops the item in flight, and a cancelled copy removes what it wrote. The Trash, restore, mount and eject go through `gio`. Nothing needs root.

Network shares, editing inside archives and file properties stay with Nautilus.
