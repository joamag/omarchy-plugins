import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Folder icon in the bar; the popup is a file navigator in the spirit of
// GNOME Files: a header with back, forward, up, the path, the filter and the
// view switch, the tabs under it, the folder as a list, a grid or columns
// with an optional preview, then a status line, the actions and a key hint
// line. It pops out into a regular window with the places sidebar and docks
// back into the bar with the same tabs. Left click opens (or docks the
// window back), right click pops out or docks, middle click opens Nautilus.
Panel {
  id: root
  moduleName: "joamag.files"
  ipcTarget: "joamag.files"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits and can add go/popOut/dock/version to open/close/toggle.
  manageIpc: false

  readonly property string home: Quickshell.env("HOME") || "/"
  // Tabs as { path, view, history, pos }; only path and view are saved, on
  // this widget's shell.json entry, a moment after the last change.
  property var tabs: [Model.newTab(home, "list")]
  property int activeTab: 0
  property bool tabsDirty: false
  // Folders opened here, newest first, saved with the tabs, for Ctrl+P.
  property var visited: []
  // The Ctrl+P jump list: open, what is typed, and the row picked.
  property bool jumpOpen: false
  property string jumpQuery: ""
  property int jumpIndex: 0

  // Places, bookmarks, drives and the trash count from files.sh, and the
  // free space of the filesystem the folder on screen lives on.
  property var placesData: Model.parsePlaces("")
  property var freeSpace: Model.parseFree("")

  // The folder model's rows, and the lists that are not folders on disk.
  property var folderEntries: []
  // Entries by path from the last listing, reused while a file's size and
  // date stay the same, and the folder that listing is of.
  property var entryCache: ({})
  property string listedFolder: ""
  // The folder changed while nothing showed it; read it again on show.
  property bool folderDirty: false
  // Search results stream in and are added a batch at a time.
  property var searchBuffer: []
  property bool searchRestart: false
  property var recentEntries: []
  property var trashEntries: []
  property var searchEntries: []

  // Filter typed into the header; deep once Enter searched every folder
  // below for it.
  property bool filtering: false
  property bool filterFocused: false
  property string query: ""
  property bool deep: false

  // Cursor, the Shift anchor and the selected paths, all for the active tab.
  property int cursorIndex: 0
  property int anchorIndex: 0
  property var selected: []
  // What the preview pane and the columns' last column show: the cursor
  // entry, at once for a single step, after a pause while a key is held.
  property var previewEntry: null
  // The PDF page the preview shows, and how many the document has.
  property int previewPage: 0
  property int previewPages: 0
  // Pictures the system thumbnailers made, by path, date and size: the PNG,
  // or "" once one could not be made. They are made one at a time, what is
  // on screen now first.
  property var thumbnails: ({})
  property var thumbQueue: []
  property string thumbRunning: ""
  // Archive listings by the archive's path: { members, modified, error,
  // loading }, read when an archive is opened or previewed.
  property var archives: ({})
  property var archiveWanted: []
  // Members extracted into the cache, by their location inside the
  // archive: the path of the copy, for the preview and for opening.
  property var extracted: ({})
  property var memberJobs: []
  // Extract here, waiting on the archive's listing or the names beside it.
  property var extractJob: null
  // A question with a text field: where to extract to, or the name of a new
  // archive. { kind, title, text, confirm, error, entries, archive, members, strip }
  property var prompt: null
  // Files copied out of an archive land here first, then move into place
  // through the usual paste, conflicts and all.
  property string stagingDir: ""
  property string stagingDest: ""
  // The window's content is built on the first pop out and kept after.
  property bool windowBuilt: false
  // A path to put the cursor on (and to rename) as soon as it is listed:
  // the folder we came up from, a renamed or a new file.
  property string pendingSelect: ""
  property string pendingRename: ""

  // { mode: "copy" | "cut", paths }: the files on the clipboard file
  // managers share (copied here, in Nautilus or elsewhere), or members of an
  // archive copied here, which only this widget can paste.
  property var clipboard: null
  // Where a paste goes once the shared clipboard has been read, and whether
  // the move under way is a paste of cut files.
  property string pasteDest: ""
  property bool pastingCut: false
  // Paste or drop waiting on its name conflicts: { mode, dest, names, jobs }.
  property var transferJob: null
  // The copy or move in flight: { mode, dest, label, count, first, total, done }.
  property var task: null
  property bool taskShown: false
  property var taskMoved: []
  property var taskErrors: []
  property string taskCreated: ""
  property bool taskCancelled: false

  property string renamePath: ""
  property string renameError: ""
  property bool editingPath: false
  // Context, "Open with" and ⋮ menus: { items, x, y, entry }.
  property var menu: null
  property int menuIndex: 0
  property bool goMenuOpen: false
  property bool keysOpen: false
  // Delete for good or empty the Trash: { kind, entries, message, confirmText }.
  property var confirm: null
  property var toast: null
  // Trash names of the last move to the Trash, for Undo and Ctrl+Z.
  property var lastTrashed: []
  property string lastError: ""
  property bool detached: false
  property var apps: []
  property string appsPath: ""
  // The action files.sh is running and what it was about.
  property var pending: null
  // Paths carried by a drag that started in this widget.
  property var dragPaths: []
  property int gridColumns: 1

  readonly property bool showHidden: setting("showHidden", false) === true
  readonly property bool showPreview: setting("showPreview", false) === true
  readonly property string sortKey: Model.normalizeSortKey(setting("sortKey", "name"))
  readonly property bool sortDescending: setting("sortDescending", false) === true
  readonly property string scriptPath: String(Qt.resolvedUrl("files.sh")).replace(/^file:\/\//, "")

  readonly property var tab: tabs[Math.max(0, Math.min(tabs.length - 1, activeTab))]
  readonly property string location: tab ? tab.path : home
  readonly property string view: tab ? tab.view : "list"
  readonly property bool inTrash: location === Model.TRASH
  readonly property bool inRecent: location === Model.RECENT
  readonly property bool inFolder: !Model.isVirtual(location)
  // Inside an archive: { archive, inner }, read-only.
  readonly property var archiveAt: Model.splitArchive(location)
  readonly property bool inArchive: archiveAt !== null
  readonly property var archiveListing: archiveAt ? archives[archiveAt.archive] || null : null
  readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"
  readonly property bool shown: opened || detached
  // What Ctrl+P offers for what is typed, and a typed path as the last row.
  readonly property var jumpList: {
    if (!jumpOpen) return []
    var list = Model.jumpMatches(Model.jumpCandidates(tabs, activeTab, visited, recentEntries, bookmarks, places, drives, home), jumpQuery, home, 50)
    var typed = Model.looksLikePath(jumpQuery) ? Model.expandPath(jumpQuery, home, home) : ""
    if (typed !== "" && !list.some(function(item) { return item.path === typed })) {
      list = list.concat([{ path: typed, source: "typed", label: "Go to " + Model.prettyPath(typed, home), icon: Model.KIND_ICONS.dir, tabIndex: -1 }])
    }
    return list
  }
  readonly property var places: placesData.places
  readonly property var bookmarks: placesData.bookmarks
  readonly property var drives: placesData.drives
  readonly property string locationLabel: Model.placeLabel(location, home, places, drives)
  readonly property bool bookmarked: isBookmarked(location)

  // The listing on screen, sorted once; the filter then only narrows it,
  // so typing into it never sorts a big folder again.
  readonly property var sortedEntries: {
    var base = folderEntries
    if (inRecent) base = recentEntries
    else if (inTrash) base = trashEntries
    else if (inArchive) base = archiveListing && archiveListing.members ? Model.archiveEntries(archiveListing.members, archiveAt.archive, archiveAt.inner) : []
    else if (deep) base = searchEntries
    // Recent keeps its newest-first order.
    return inRecent ? base : Model.sortEntries(base, sortKey, sortDescending)
  }
  readonly property var entries: Model.filterEntries(sortedEntries, deep ? "" : query, showHidden || deep)
  // The views are handed how many entries there are and read each visible
  // row from the list: handing them the list itself converts all of it on
  // every change, which a big folder pays for on every keystroke. A row
  // whose index runs past a shorter list for a moment shows this instead.
  readonly property var blankEntry: Model.makeEntry({ path: "" })
  // Why nothing is listed, shown where the listing would be.
  readonly property string emptyMessage: searchProc.running ? "Searching…" : Model.emptyText(location, query, deep, Model.prettyPath(location, home))
  readonly property bool columnsShown: view === "columns" && inFolder && !deep
  readonly property var cursorEntry: cursorIndex >= 0 && cursorIndex < entries.length ? entries[cursorIndex] : null
  readonly property bool busy: actionProc.running || transferProc.running || namesProc.running
  readonly property var conflictJob: transferJob ? transferJob.jobs[Model.conflictIndex(transferJob.jobs)] || null : null
  readonly property string hintMode: {
    if (prompt) return "prompt"
    if (jumpOpen) return "jump"
    if (renamePath !== "") return "rename"
    if (editingPath) return "path"
    if (filtering && filterFocused) return "filter"
    if (inArchive) return "archive"
    return inTrash ? "trash" : "browse"
  }

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // A view asks for focus on one of its fields, or on itself.
  signal focusRequested(string what)
  // Around a refresh of the folder on screen, so views keep their scroll.
  signal listingWillChange()
  signal listingChanged()

  // ---- Tabs and navigation ----------------------------------------------

  function setTabs(list, active) {
    tabs = list
    activeTab = Math.max(0, Math.min(list.length - 1, active))
    tabsDirty = true
    saveTabsTimer.restart()
  }

  function updateTab(next) {
    var list = tabs.slice()
    list[activeTab] = next
    setTabs(list, activeTab)
  }

  // Whatever belonged to the folder on screen (cursor, selection, filter,
  // rename) stays behind when the tab moves on.
  function resetFolderState() {
    cursorIndex = 0
    anchorIndex = 0
    selected = []
    query = ""
    filtering = false
    deep = false
    stopSearch()
    searchEntries = []
    renamePath = ""
    renameError = ""
    editingPath = false
    menu = null
    goMenuOpen = false
    lastError = ""
  }

  function go(path) {
    var target = Model.isVirtual(path) ? path : Model.normalizePath(path)
    if (target === "") return
    if (target === location) {
      resetFolderState()
      refreshLocation()
      return
    }
    updateTab(Model.navigateTab(tab, target))
    visited = Model.addVisited(visited, target, Model.VISITED_MAX)
    resetFolderState()
    refreshLocation()
    focusRequested("view")
  }

  function back() {
    if (!Model.canGoBack(tab)) return
    pendingSelect = location
    updateTab(Model.tabBack(tab))
    resetFolderState()
    refreshLocation()
  }

  function forward() {
    if (!Model.canGoForward(tab)) return
    updateTab(Model.tabForward(tab))
    resetFolderState()
    refreshLocation()
  }

  function up() {
    var parent = Model.parentPath(location)
    if (parent === "") return
    // Out of the top of an archive, the cursor lands on the archive file.
    var from = inArchive && archiveAt.inner === "" ? archiveAt.archive : location
    go(parent)
    pendingSelect = from
  }

  function newTab(path) {
    var result = Model.addTab(tabs, activeTab, Model.newTab(path || location, view))
    if (result.tabs === tabs) {
      showToast("Close a tab first: " + Model.MAX_TABS + " is the most")
      return
    }
    setTabs(result.tabs, result.active)
    visited = Model.addVisited(visited, path || location, Model.VISITED_MAX)
    resetFolderState()
    refreshLocation()
  }

  function closeTab(index) {
    if (tabs.length <= 1) {
      showToast("The last tab stays open")
      return
    }
    var wasActive = index === activeTab
    var result = Model.closeTab(tabs, index, activeTab)
    setTabs(result.tabs, result.active)
    if (wasActive) {
      resetFolderState()
      refreshLocation()
    }
  }

  function switchTab(index) {
    var next = Model.wrapIndex(index, tabs.length)
    if (next === activeTab) return
    activeTab = next
    tabsDirty = true
    saveTabsTimer.restart()
    resetFolderState()
    refreshLocation()
  }

  function setView(key) {
    updateTab(Model.withView(tab, key))
  }

  // ---- Settings ---------------------------------------------------------

  // Persist inline settings on this widget's shell.json entry, the way the
  // stocks widget keeps its watchlist, so they survive a shell restart.
  function persistSettings(changes) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var key in changes) entry[key] = changes[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistSetting(key, value) {
    var changes = {}
    changes[key] = value
    persistSettings(changes)
  }

  function saveTabs() {
    tabsDirty = false
    persistSettings({ tabs: Model.serializeTabs(tabs), activeTab: activeTab, recentFolders: visited })
  }

  // The saved tabs come back on start, and when shell.json is edited by hand.
  function loadTabs() {
    if (tabsDirty) return
    visited = Model.addVisited(setting("recentFolders", []), "", Model.VISITED_MAX)
    var saved = Model.parseTabs(setting("tabs", []), home)
    if (JSON.stringify(Model.serializeTabs(saved)) === JSON.stringify(Model.serializeTabs(tabs)) && Number(setting("activeTab", 0)) === activeTab) return
    tabs = saved
    activeTab = Math.max(0, Math.min(saved.length - 1, Math.round(Number(setting("activeTab", 0)) || 0)))
    resetFolderState()
    refreshLocation()
  }

  function toggleHidden() {
    persistSetting("showHidden", !showHidden)
    cursorIndex = Model.clampIndex(cursorIndex, entries.length)
  }

  function togglePreview() {
    persistSetting("showPreview", !showPreview)
  }

  function sortBy(key) {
    var next = Model.nextSort(sortKey, sortDescending, key)
    persistSettings({ sortKey: next.key, sortDescending: next.descending })
  }

  // ---- Listings ---------------------------------------------------------

  function refreshLocation() {
    if (inRecent) {
      if (!recentProc.running) recentProc.running = true
    } else if (inTrash) {
      if (!trashProc.running) trashProc.running = true
    } else if (inArchive) {
      loadArchive(archiveAt.archive, undefined, false)
    } else {
      freeTimer.restart()
    }
  }

  function refreshPlaces() {
    if (!placesProc.running) placesProc.running = true
  }

  // Qt's folder model lists the folder and follows changes on disk; its
  // rows are copied into plain entries so every view, Recent and the Trash
  // share one shape. An entry whose size and date did not change is reused,
  // so a change in a big folder costs a read of the rows and no more; a
  // refresh that changes nothing changes nothing on screen. While nothing
  // shows the folder it is only marked to be read on show.
  function snapshotFolder() {
    if (!shown) {
      folderDirty = true
      return
    }
    folderDirty = false
    var cache = entryCache
    var next = {}
    var out = []
    var old = listedFolder === location ? folderEntries : []
    var same = folderModel.count === old.length
    for (var i = 0; i < folderModel.count; i++) {
      var path = folderModel.get(i, "filePath")
      var size = folderModel.get(i, "fileSize")
      var modified = folderModel.get(i, "fileModified")
      var time = modified ? modified.getTime() : NaN
      var entry = cache[path]
      if (!entry || entry.modified !== time || (!entry.dir && entry.size !== size)) {
        entry = Model.makeEntry({ path: path, dir: folderModel.get(i, "fileIsDir") === true, size: size, modified: time })
        same = false
      } else if (same && old[i] !== entry) {
        same = false
      }
      next[path] = entry
      out.push(entry)
    }
    entryCache = next
    if (same && listedFolder === location) return
    var refresh = listedFolder === location
    listedFolder = location
    if (refresh) keepPlace(function() { root.folderEntries = out })
    else folderEntries = out
  }

  // A refresh of the folder on screen keeps the cursor on its file and the
  // views scrolled where they were.
  function keepPlace(apply) {
    var path = cursorEntry ? cursorEntry.path : ""
    listingWillChange()
    apply()
    if (path !== "" && pendingSelect === "") {
      var idx = Model.indexOfPath(entries, path)
      if (idx >= 0) {
        if (anchorIndex === cursorIndex) anchorIndex = idx
        cursorIndex = idx
      }
    }
    listingChanged()
  }

  function search() {
    if (!inFolder || query === "") return
    deep = true
    cursorIndex = 0
    selected = []
    searchEntries = []
    searchBuffer = []
    searchProc.command = [root.scriptPath, "search", location, query, showHidden ? "all" : ""]
    // A search still walking stops first; the new one starts as it exits.
    if (searchProc.running) {
      searchRestart = true
      searchProc.running = false
    } else {
      searchProc.running = true
    }
  }

  function stopSearch() {
    searchRestart = false
    if (searchProc.running) searchProc.running = false
  }

  // Matches gathered since the last flush join the list in one go.
  function flushSearch() {
    if (searchBuffer.length === 0) return
    var lines = searchBuffer
    searchBuffer = []
    if (deep) searchEntries = searchEntries.concat(Model.parseEntries(lines.join("\n")))
  }

  // A fresh listing keeps the cursor on the same entry, or lands it on the
  // one asked for; the selection drops what went away.
  onEntriesChanged: {
    if (pendingSelect !== "") {
      var idx = Model.indexOfPath(entries, pendingSelect)
      if (idx >= 0) {
        cursorIndex = idx
        anchorIndex = idx
        pendingSelect = ""
      }
    }
    if (pendingRename !== "" && Model.indexOfPath(entries, pendingRename) >= 0) {
      startRename(pendingRename)
      pendingRename = ""
    }
    if (selected.length > 0) selected = Model.keepSelected(selected, entries)
    cursorIndex = Model.clampIndex(cursorIndex, entries.length)
  }

  // ---- Cursor and selection ---------------------------------------------

  function moveCursor(delta, extend) {
    var n = entries.length
    if (n === 0) return
    var next = Model.clampIndex(cursorIndex + delta, n)
    if (extend) selected = Model.rangePaths(entries, anchorIndex, next)
    else anchorIndex = next
    cursorIndex = next
  }

  function setCursor(index) {
    cursorIndex = Model.clampIndex(index, entries.length)
    anchorIndex = cursorIndex
  }

  function toggleCursorSelection() {
    if (!cursorEntry) return
    selected = Model.toggleSelected(selected, cursorEntry.path)
    moveCursor(1, false)
  }

  // What an action applies to: the selection, or the entry under the
  // cursor when nothing is selected. Worked out when an action runs rather
  // than on every cursor step.
  function picked() {
    return Model.pickedEntries(entries, selected, cursorIndex)
  }

  function selectAll() {
    selected = entries.map(function(e) { return e.path })
  }

  // Click, Ctrl+click and Shift+click on a row or a tile.
  function clickEntry(index, modifiers) {
    var entry = entries[index]
    if (!entry) return
    if (renamePath !== "" && renamePath !== entry.path) cancelRename()
    if (modifiers & Qt.ShiftModifier) {
      selected = Model.rangePaths(entries, anchorIndex, index)
    } else if (modifiers & Qt.ControlModifier) {
      selected = Model.toggleSelected(selected, entry.path)
      anchorIndex = index
    } else {
      selected = [entry.path]
      anchorIndex = index
    }
    cursorIndex = index
    menu = null
  }

  // Esc peels one thing at a time: a menu, the clipboard, the selection,
  // the filter, then the popup itself.
  function clearOrClose() {
    if (menu) menu = null
    else if (goMenuOpen) goMenuOpen = false
    else if (clipboard) clearClipboard()
    else if (selected.length > 0) selected = []
    else if (filtering || query !== "") clearFilter()
    else if (!detached) root.close()
  }

  // ---- Opening ----------------------------------------------------------

  function openEntry(entry) {
    if (!entry) return
    if (entry.trashName) {
      restore([entry])
      return
    }
    if (entry.dir) {
      go(entry.path)
      return
    }
    // A file inside an archive opens from its extracted copy; an archive
    // inside one opens as a folder too.
    if (Model.isArchiveLocation(entry.path)) {
      extractMember(entry, function(copy) {
        if (Model.isArchive(entry)) root.go(Model.archiveLocation(copy, ""))
        else root.openFile(copy)
      })
      return
    }
    if (Model.isArchive(entry)) {
      go(Model.archiveLocation(entry.path, ""))
      return
    }
    openFile(entry.path)
  }

  function openFile(path) {
    Util.execArgv(["xdg-open", path])
    if (!detached) root.close()
  }

  // Enter on a selection: a folder opens in place, several files each open
  // in their own app.
  function openPicked() {
    var list = picked()
    if (list.length === 0) return
    if (list[0].trashName) {
      restore(list)
      return
    }
    if (list.length === 1 || list[0].dir) {
      openEntry(list[0])
      return
    }
    for (var i = 0; i < list.length && i < 12; i++) if (!list[i].dir && !Model.isArchiveLocation(list[i].path)) Util.execArgv(["xdg-open", list[i].path])
    if (!detached) root.close()
  }

  function stepPage(delta) {
    if (previewPages > 0) previewPage = Math.max(0, Math.min(previewPages - 1, previewPage + delta))
  }

  function requestThumbnail(entry, size) {
    var key = Model.thumbnailKey(entry, size)
    if (key === "" || key in thumbnails || key === thumbRunning) return
    var queue = thumbQueue.filter(function(job) { return job.key !== key })
    queue.unshift({ key: key, path: entry.path, size: size })
    // A folder of videos scrolled past should not leave a long backlog.
    thumbQueue = queue.slice(0, 40)
    nextThumbnail()
  }

  function nextThumbnail() {
    if (thumbProc.running || thumbQueue.length === 0) return
    var job = thumbQueue[0]
    thumbQueue = thumbQueue.slice(1)
    thumbRunning = job.key
    thumbProc.command = [root.scriptPath, "thumbnail", job.path, String(job.size)]
    thumbProc.running = true
  }

  function applyThumbnail(raw) {
    var made = Object.keys(thumbnails).length < 400 ? Object.assign({}, thumbnails) : {}
    made[thumbRunning] = Model.parseThumbnail(raw)
    thumbnails = made
    thumbRunning = ""
  }

  // Goes to a folder in the tab on screen, or opens it in a new tab.
  function openFolder(path, inNewTab) {
    if (inNewTab) newTab(path)
    else go(path)
  }

  // A middle click or a Ctrl+click on a folder asks for a new tab.
  function newTabClick(mouse) {
    return mouse.button === Qt.MiddleButton || (mouse.modifiers & Qt.ControlModifier) !== 0
  }

  function openInNewTab(entry) {
    if (!entry) return
    if (entry.dir) newTab(entry.path)
    else if (Model.isArchive(entry) && !Model.isArchiveLocation(entry.path)) newTab(Model.archiveLocation(entry.path, ""))
  }

  function openWith(entry) {
    if (!entry || entry.dir || entry.trashName) return
    if (Model.isArchiveLocation(entry.path)) {
      extractMember(entry, function(copy) { root.openWith(Model.makeEntry({ path: copy })) })
      return
    }
    appsPath = entry.path
    apps = []
    appsProc.command = [root.scriptPath, "apps", entry.path]
    appsProc.running = true
  }

  function launchApp(id, path) {
    Util.execArgv([root.scriptPath, "launch", id, path])
    if (!detached) root.close()
  }

  function openNautilus() {
    var folder = inFolder ? location : home
    if (inArchive) folder = Model.parentPath(archiveAt.archive)
    Util.execArgv(["setsid", "uwsm-app", "--", "nautilus", "--new-window", folder])
    if (!detached) root.close()
  }

  // ---- Clipboard, copy and move -----------------------------------------

  function setClipboard(mode) {
    if (mode === "cut" && readOnly()) return
    var list = picked().filter(function(e) { return !e.trashName })
    if (list.length === 0) return
    var paths = list.map(function(e) { return e.path })
    clipboard = { mode: mode, paths: paths }
    // Files go on the shared clipboard, so Nautilus pastes them too; members
    // of an archive are not files yet, so the shared clipboard is emptied
    // and only this widget can paste them.
    if (Model.isArchiveLocation(paths[0])) Util.execArgv([root.scriptPath, "clipboard-clear"])
    else Util.execArgv([root.scriptPath, "clipboard-set", mode].concat(paths))
    showToast((mode === "copy" ? "Copied " : "Cut ") + Model.itemsLabel(list.length, list[0].name) + " · paste with p or Ctrl+V, here or in Nautilus")
  }

  // Paste reads the shared clipboard first: what was copied or cut in
  // Nautilus (or any app that copies files) pastes here.
  function paste(dest) {
    pasteDest = dest || location
    readClipboard("paste")
  }

  function readClipboard(purpose) {
    if (clipboardProc.running) {
      // A read already on its way pastes when it lands.
      if (purpose === "paste") clipboardProc.purpose = purpose
      return
    }
    clipboardProc.purpose = purpose
    clipboardProc.running = true
  }

  function applyClipboard(raw, purpose) {
    var shared = Model.parseClipboard(raw)
    if (shared.state === "files") clipboard = { mode: shared.mode, paths: shared.paths }
    // Text or nothing on the shared clipboard leaves only an archive's
    // members, which never go there.
    else if (shared.state === "empty" && clipboard && !Model.isArchiveLocation(clipboard.paths[0])) clipboard = null
    if (purpose !== "paste") return
    if (!clipboard) {
      showToast("Nothing to paste: copy or cut first")
      return
    }
    if (Model.isArchiveLocation(clipboard.paths[0])) {
      copyOutOfArchive(clipboard.paths, pasteDest)
      return
    }
    pastingCut = clipboard.mode === "cut"
    transfer(clipboard.paths, pasteDest, pastingCut ? "move" : "copy")
  }

  function clearClipboard() {
    if (clipboard && !Model.isArchiveLocation(clipboard.paths[0])) Util.execArgv([root.scriptPath, "clipboard-clear"])
    clipboard = null
  }

  // Inside an archive only copying out works; it opens read-only.
  function readOnly() {
    if (!inArchive) return false
    showToast("Archives open read-only: copy files out (y, then p) or extract it (E)")
    return true
  }

  // Members of one folder of an archive, extracted into a staging folder
  // first and then moved into DEST through the usual paste, so a name that
  // is taken is asked about like any other.
  function copyOutOfArchive(paths, dest) {
    if (Model.isVirtual(dest) || !dest) {
      showToast("Open a folder to paste into")
      return
    }
    if (busy) {
      showToast("Wait for the running copy or move to finish")
      return
    }
    var first = Model.splitArchive(paths[0])
    var members = paths.map(function(p) { return Model.splitArchive(p).inner })
    var stage = cacheHome + "/joamag-files/staging/" + Date.now()
    stagingDir = stage
    stagingDest = dest
    var label = "Extracting " + Model.itemsLabel(members.length, Model.baseName(members[0])) + " from " + Model.baseName(first.archive)
    startJob("stage", dest, label, ["extract", first.archive, stage, String(Model.stripCount(Model.parentPath("/" + members[0]).slice(1)))].concat(members))
  }

  // A long job on the progress line: a copy, a move, an extraction or a
  // new archive. One runs at a time.
  function startJob(mode, dest, label, args) {
    task = { mode: mode, dest: dest, label: label, count: 0, first: "", total: 0, done: 0 }
    taskMoved = []
    taskErrors = []
    taskCreated = ""
    taskCancelled = false
    taskShown = false
    taskTimer.restart()
    transferProc.command = [root.scriptPath].concat(args)
    transferProc.running = true
  }

  // First the names already in the destination, so every conflict can be
  // asked about before anything is written.
  function transfer(paths, dest, mode) {
    if (Model.isVirtual(dest) || !dest) {
      pastingCut = false
      showToast("Open a folder to paste into")
      return
    }
    if (!paths || paths.length === 0 || busy) {
      pastingCut = false
      if (busy) showToast("Wait for the running copy or move to finish")
      return
    }
    var dirs = {}
    for (var i = 0; i < paths.length; i++) {
      var idx = Model.indexOfPath(entries, paths[i])
      var known = idx >= 0 ? entries[idx] : null
      dirs[paths[i]] = known ? known.dir : Model.extensionOf(paths[i]) === ""
    }
    transferJob = { mode: mode, dest: dest, paths: paths, dirs: dirs, names: null, jobs: [] }
    namesProc.command = [root.scriptPath, "names", dest]
    namesProc.running = true
  }

  function applyNames(raw) {
    if (!transferJob) return
    var names = Model.parseNames(raw)
    var plan = Model.planTransfer(transferJob.paths, transferJob.dest, transferJob.mode, names, transferJob.dirs)
    if (plan.error !== "") {
      transferJob = null
      pastingCut = false
      dropStaging()
      showToast(plan.error)
      return
    }
    if (plan.jobs.length === 0) {
      transferJob = null
      pastingCut = false
      dropStaging()
      return
    }
    transferJob = { mode: transferJob.mode, dest: transferJob.dest, paths: transferJob.paths, dirs: transferJob.dirs, names: names, jobs: plan.jobs }
    advanceTransfer()
  }

  function advanceTransfer() {
    if (!transferJob || Model.conflictIndex(transferJob.jobs) >= 0) return
    var job = transferJob
    transferJob = null
    var args = Model.transferArgs(job.jobs, job.dest, job.names)
    if (args.length === 0) return
    var count = args.length / 3
    var label = stagingDir !== "" ? "Copying " + Model.itemsLabel(count, Model.baseName(args[1])) + " to " + Model.placeLabel(job.dest, home, places, drives) : Model.transferLabel(job.mode, count, Model.baseName(args[1]), Model.placeLabel(job.dest, home, places, drives))
    startJob(job.mode, job.dest, label, ["transfer", job.mode].concat(args))
  }

  function resolveConflict(how, all) {
    if (!transferJob) return
    var idx = Model.conflictIndex(transferJob.jobs)
    if (idx < 0) return
    transferJob = { mode: transferJob.mode, dest: transferJob.dest, paths: transferJob.paths, dirs: transferJob.dirs, names: transferJob.names, jobs: Model.decideConflict(transferJob.jobs, idx, how, all) }
    advanceTransfer()
  }

  function cancelConflicts() {
    transferJob = null
    pastingCut = false
    dropStaging()
    focusRequested("view")
  }

  function dropStaging() {
    if (stagingDir === "") return
    Util.execArgv([root.scriptPath, "delete", stagingDir])
    stagingDir = ""
    stagingDest = ""
  }

  function applyTransferLine(line) {
    if (!task) return
    var r = Model.parseResult(line)
    var next = { mode: task.mode, dest: task.dest, label: task.label, count: task.count, first: task.first, total: task.total, done: task.done }
    if (isFinite(r.total)) next.total = r.total
    if (isFinite(r.progress)) next.done = r.progress
    if (r.done.length > 0) taskMoved = taskMoved.concat(r.done)
    if (r.created.length > 0) taskCreated = r.created[0]
    if (r.errors.length > 0) taskErrors = taskErrors.concat(r.errors)
    if (r.cancelled) taskCancelled = true
    task = next
  }

  function finishTransfer() {
    var finished = task
    var wasCut = pastingCut
    pastingCut = false
    task = null
    taskShown = false
    taskTimer.stop()
    if (!finished) return
    if (finished.mode === "stage" || finished.mode === "extract" || finished.mode === "compress") {
      finishArchiveJob(finished)
      return
    }
    // What came out of an archive is in place now; the staging folder goes.
    var fromArchive = stagingDir !== ""
    dropStaging()
    if (fromArchive) {
      if (taskCancelled) showToast("Copy stopped; what was copied stays")
      else if (taskErrors.length > 0) lastError = taskErrors[taskErrors.length - 1]
      else if (taskMoved.length > 0) showToast("Copied " + Model.itemsLabel(taskMoved.length, Model.baseName(taskMoved[0].to)) + " out to " + Model.placeLabel(finished.dest, home, places, drives))
      selected = []
      refreshLocation()
      return
    }
    if (finished.mode === "move") {
      // A moved folder takes the tabs showing it along.
      var list = tabs
      for (var i = 0; i < taskMoved.length; i++) list = Model.retargetTabs(list, taskMoved[i].from, taskMoved[i].to)
      if (list !== tabs) setTabs(list, activeTab)
      // Cut files pasted once are gone from the clipboard, as in Nautilus.
      if (wasCut) clearClipboard()
    }
    if (taskCancelled) showToast(finished.mode === "copy" ? "Copy cancelled; nothing was written" : "Move stopped; what moved stays moved")
    else if (taskErrors.length > 0) lastError = taskErrors[taskErrors.length - 1]
    else if (taskMoved.length > 0) showToast((finished.mode === "move" ? "Moved " : "Copied ") + Model.itemsLabel(taskMoved.length, Model.baseName(taskMoved[0].to)) + " to " + Model.placeLabel(finished.dest, home, places, drives))
    selected = []
    refreshPlaces()
    refreshLocation()
  }

  function cancelTransfer() {
    if (transferProc.running) transferProc.signal(15)
  }

  // ---- Archives ---------------------------------------------------------

  // Reads an archive's listing, unless the one held is of the same version.
  function loadArchive(path, modified, force) {
    var held = archives[path]
    if (held && !force && (held.loading || modified === undefined || held.modified === modified)) return
    var next = Object.assign({}, archives)
    next[path] = { members: held ? held.members : null, modified: modified, error: "", loading: true }
    archives = next
    if (archiveWanted.indexOf(path) < 0) archiveWanted = archiveWanted.concat([path])
    nextArchive()
  }

  function nextArchive() {
    if (archiveProc.running || archiveWanted.length === 0) return
    archiveProc.archive = archiveWanted[0]
    archiveWanted = archiveWanted.slice(1)
    archiveProc.command = [root.scriptPath, "archive-list", archiveProc.archive]
    archiveProc.running = true
  }

  function applyArchive(path, raw) {
    var errors = Model.parseResult(raw).errors
    var next = Object.assign({}, archives)
    var held = next[path] || {}
    next[path] = { members: Model.parseArchiveListing(raw, Date.now()), modified: held.modified, error: errors.length > 0 ? errors[errors.length - 1] : "", loading: false }
    archives = next
    if (inArchive && archiveAt.archive === path && next[path].error !== "") lastError = "Cannot read " + Model.baseName(path) + ": " + next[path].error
    if (extractJob && extractJob.archive === path) advanceExtract()
  }

  // A member of an archive copied into the cache, then THEN with its path.
  function extractMember(entry, then) {
    var copy = extracted[entry.path]
    if (copy) {
      if (then) then(copy)
      return
    }
    var at = Model.splitArchive(entry.path)
    if (!at || at.inner === "") return
    memberJobs = memberJobs.filter(function(job) { return job.location !== entry.path || job.then }).concat([{ location: entry.path, archive: at.archive, member: at.inner, then: then }])
    nextMember()
  }

  function nextMember() {
    if (memberProc.running || memberJobs.length === 0) return
    memberProc.job = memberJobs[memberJobs.length - 1]
    memberJobs = memberJobs.slice(0, memberJobs.length - 1)
    memberProc.command = [root.scriptPath, "archive-file", memberProc.job.archive, memberProc.job.member]
    memberProc.running = true
  }

  function applyMember(job, raw) {
    var lines = String(raw || "").split("\n")
    var copy = ""
    for (var i = 0; i < lines.length; i++) if (lines[i].indexOf("extracted\t") === 0) copy = lines[i].slice(10)
    if (copy === "") {
      var errors = Model.parseResult(raw).errors
      if (job.then) showToast("Cannot open " + Model.baseName(job.member) + (errors.length > 0 ? ": " + errors[0] : ""))
      return
    }
    var next = Object.assign({}, extracted)
    next[job.location] = copy
    extracted = next
    if (job.then) job.then(copy)
  }

  // Extract here: into a folder it makes beside the archive, named after the
  // archive's single top folder or after the archive. The listing and the
  // names already beside it come first.
  function extractHere(archivePath, modified) {
    if (busy) {
      showToast("Wait for the running copy or move to finish")
      return
    }
    extractJob = { archive: archivePath, parent: Model.parentPath(archivePath), names: null }
    loadArchive(archivePath, modified, false)
    extractNamesProc.command = [root.scriptPath, "names", extractJob.parent]
    extractNamesProc.running = true
  }

  function advanceExtract() {
    var job = extractJob
    if (!job || job.names === null) return
    var listing = archives[job.archive]
    if (!listing || listing.loading) return
    extractJob = null
    if (!listing.members || listing.members.length === 0) {
      showToast("Cannot read " + Model.baseName(job.archive) + (listing.error ? ": " + listing.error : ""))
      return
    }
    var target = Model.extractTarget(listing.members, Model.baseName(job.archive), job.names)
    var dest = Model.joinPath(job.parent, target.name)
    startJob("extract", dest, "Extracting " + Model.baseName(job.archive) + " into " + target.name, ["extract", job.archive, dest, String(target.strip)])
  }

  // Extract to: the whole archive, or the members picked inside it, into a
  // folder typed in the prompt.
  function askExtractTo(entry) {
    var inside = entry && Model.isArchiveLocation(entry.path)
    var archivePath = inside ? Model.splitArchive(entry.path).archive : (entry ? entry.path : "")
    if (archivePath === "") return
    var members = []
    var strip = 0
    if (inside) {
      members = picked().map(function(e) { return Model.splitArchive(e.path).inner })
      strip = Model.stripCount(archiveAt ? archiveAt.inner : "")
    }
    var parent = Model.parentPath(archivePath)
    openPrompt({
      kind: "extractto",
      title: "Extract " + (members.length > 0 ? Model.itemsLabel(members.length, Model.baseName(members[0])) + " from " : "") + Model.baseName(archivePath) + " to",
      text: Model.prettyPath(Model.joinPath(parent, Model.archiveStem(Model.baseName(archivePath))), home),
      confirm: "Extract",
      archive: archivePath,
      members: members,
      strip: strip
    })
  }

  function askCompress() {
    if (readOnly()) return
    if (!inFolder || deep) {
      showToast("Open a folder to compress files in")
      return
    }
    var list = picked().filter(function(e) { return !e.trashName })
    if (list.length === 0) return
    openPrompt({
      kind: "compress",
      title: "Compress " + Model.itemsLabel(list.length, list[0].name) + " into",
      text: Model.compressName(list, folderEntries.map(function(e) { return e.name })),
      confirm: "Compress",
      entries: list
    })
  }

  function openPrompt(spec) {
    spec.error = ""
    prompt = spec
    focusRequested("prompt")
  }

  function cancelPrompt() {
    prompt = null
    focusRequested("view")
  }

  function setPromptError(text) {
    var next = Object.assign({}, prompt)
    next.error = text
    prompt = next
  }

  function commitPrompt(text) {
    var spec = prompt
    if (!spec) return
    if (busy) {
      setPromptError("Wait for the running copy or move to finish")
      return
    }
    if (spec.kind === "extractto") {
      var dest = Model.expandPath(text, home, Model.parentPath(spec.archive))
      if (dest === "" || Model.isVirtual(dest)) {
        setPromptError("Type a folder to extract into")
        return
      }
      prompt = null
      focusRequested("view")
      startJob("extract", dest, "Extracting " + Model.baseName(spec.archive) + " into " + Model.prettyPath(dest, home), ["extract", spec.archive, dest, String(spec.strip)].concat(spec.members))
      return
    }
    var name = String(text || "").trim()
    if (name === "" || name.indexOf("/") >= 0) {
      setPromptError("Type a name without /")
      return
    }
    if (!Model.canCompressTo(name)) {
      setPromptError("End the name in .zip, .7z, .tar, .tar.gz, .tar.xz, .tar.zst or .tar.bz2")
      return
    }
    if (Model.indexOfPath(folderEntries, Model.joinPath(location, name)) >= 0) {
      setPromptError(name + " already exists here")
      return
    }
    prompt = null
    focusRequested("view")
    startJob("compress", location, "Compressing " + Model.itemsLabel(spec.entries.length, spec.entries[0].name) + " into " + name, ["compress", Model.joinPath(location, name)].concat(spec.entries.map(function(e) { return e.path })))
  }

  function finishArchiveJob(finished) {
    if (finished.mode === "stage") {
      if (taskCancelled || taskErrors.length > 0 || taskMoved.length === 0) {
        if (taskErrors.length > 0) lastError = taskErrors[taskErrors.length - 1]
        else if (taskCancelled) showToast("Copy cancelled; nothing was written")
        dropStaging()
        return
      }
      // The members are staged under their own names; they move into place.
      var staged = clipboard ? clipboard.paths.map(function(p) { return Model.joinPath(root.stagingDir, Model.baseName(Model.splitArchive(p).inner)) }) : []
      // After the extraction's process has fully let go.
      Qt.callLater(function() { root.transfer(staged, root.stagingDest, "move") })
      return
    }
    if (taskCancelled) showToast(finished.mode === "extract" ? "Extraction cancelled; what it made is gone" : "Compression cancelled; nothing was written")
    else if (taskErrors.length > 0) lastError = taskErrors[taskErrors.length - 1]
    else if (finished.mode === "extract" && taskMoved.length > 0) {
      var into = taskMoved[0].to
      if (Model.parentPath(into) === location) pendingSelect = into
      showToast("Extracted into " + Model.prettyPath(into, home))
    } else if (finished.mode === "compress" && taskCreated !== "") {
      pendingSelect = taskCreated
      showToast("Compressed into " + Model.baseName(taskCreated))
    }
    refreshPlaces()
    refreshLocation()
  }

  // Files dropped on a folder, a tab, a place or a path segment. A drag
  // that started here moves (copies with Ctrl); one from another app copies.
  function dropUrls(urls, dest, copy) {
    var paths = []
    for (var i = 0; i < urls.length; i++) {
      var p = Model.urlToPath(String(urls[i]))
      if (p !== "") paths.push(p)
    }
    if (paths.length === 0) return false
    var own = dragPaths.length > 0
    dragPaths = []
    transfer(paths, dest, own && !copy ? "move" : "copy")
    return true
  }

  // ---- Rename, new, trash and delete ------------------------------------

  function act(kind, args, context) {
    if (actionProc.running) return false
    lastError = ""
    pending = { kind: kind, context: context || {} }
    actionProc.command = [root.scriptPath].concat(args)
    actionProc.running = true
    return true
  }

  function startRename(path) {
    if (readOnly()) return
    var target = path || (cursorEntry ? cursorEntry.path : "")
    var idx = Model.indexOfPath(entries, target)
    if (idx < 0 || entries[idx].trashName || inRecent || deep) return
    setCursor(idx)
    selected = [target]
    renameError = ""
    renamePath = target
    focusRequested("rename")
  }

  function commitRename(name) {
    var idx = Model.indexOfPath(entries, renamePath)
    if (idx < 0) {
      cancelRename()
      return
    }
    if (name === entries[idx].name) {
      cancelRename()
      return
    }
    act("rename", ["rename", renamePath, name], { entry: entries[idx] })
  }

  function cancelRename() {
    renamePath = ""
    renameError = ""
    focusRequested("view")
  }

  function newItem(kind) {
    if (!inFolder || deep) {
      showToast("Open a folder first")
      return
    }
    var names = folderEntries.map(function(e) { return e.name })
    var name = Model.uniqueName(names, kind === "mkdir" ? "New folder" : "New file", kind === "mkdir")
    clearFilter()
    act(kind, [kind, location, name])
  }

  function trashPicked() {
    if (readOnly()) return
    var list = picked().filter(function(e) { return !e.trashName })
    if (list.length === 0) return
    act("trash", ["trash"].concat(list.map(function(e) { return e.path })), { entries: list })
  }

  function restore(list) {
    var items = (list || picked()).filter(function(e) { return e.trashName })
    if (items.length === 0) return
    act("restore", ["restore"].concat(items.map(function(e) { return e.trashName })), { entries: items })
  }

  function askPurge() {
    if (readOnly()) return
    var list = picked()
    if (list.length === 0) return
    confirm = {
      kind: "purge",
      entries: list,
      message: "Delete " + Model.itemsLabel(list.length, list[0].name) + " for good? This skips the Trash and cannot be undone.",
      confirmText: "Delete"
    }
  }

  function askEmptyTrash() {
    if (placesData.trashCount <= 0 && trashEntries.length === 0) return
    confirm = { kind: "emptytrash", entries: [], message: "Empty the Trash? Everything in it is deleted for good.", confirmText: "Empty Trash" }
  }

  function confirmed() {
    var c = confirm
    confirm = null
    if (!c) return
    if (c.kind === "emptytrash") {
      act("emptytrash", ["empty-trash"])
      return
    }
    var inTrashList = c.entries.filter(function(e) { return e.trashName })
    var outside = c.entries.filter(function(e) { return !e.trashName })
    if (inTrashList.length > 0) act("purge", ["purge"].concat(inTrashList.map(function(e) { return e.trashName })), { entries: inTrashList })
    else act("delete", ["delete"].concat(outside.map(function(e) { return e.path })), { entries: outside })
  }

  function undoTrash(names) {
    var list = names || lastTrashed
    if (!list || list.length === 0) return
    lastTrashed = []
    toast = null
    var items = list.map(function(n) { return { trashName: n } })
    act("restore", ["restore"].concat(list), { entries: items })
  }

  // ---- Places, drives and bookmarks -------------------------------------

  function isBookmarked(path) {
    for (var i = 0; i < bookmarks.length; i++) if (bookmarks[i].path === path) return true
    return false
  }

  function toggleBookmark(path) {
    var target = path || location
    if (Model.isVirtual(target)) return
    act(isBookmarked(target) ? "unbookmark" : "bookmark", [isBookmarked(target) ? "unbookmark" : "bookmark", target], { path: target })
  }

  // A drive that is not mounted mounts first, then opens.
  function openDrive(drive, inNewTab) {
    if (!drive) return
    if (drive.mount) openFolder(drive.mount, inNewTab)
    else act("mount", ["mount", drive.device], { drive: drive, open: true, inNewTab: inNewTab === true })
  }

  function ejectDrive(drive) {
    if (drive && drive.mount && drive.mount !== "/") act("eject", ["eject", drive.mount], { drive: drive })
  }

  function applyAction(raw) {
    var job = pending
    pending = null
    if (!job) return
    var r = Model.parseResult(raw)
    var ctx = job.context
    var failed = r.errors.length > 0
    if (failed && job.kind !== "rename") lastError = r.errors[r.errors.length - 1]
    var list = tabs
    var i
    switch (job.kind) {
    case "rename":
      if (failed) {
        renameError = r.errors[r.errors.length - 1]
        break
      }
      if (r.done.length > 0) {
        if (ctx.entry && ctx.entry.dir) list = Model.retargetTabs(list, r.done[0].from, r.done[0].to)
        pendingSelect = r.done[0].to
        selected = [r.done[0].to]
      }
      renamePath = ""
      renameError = ""
      focusRequested("view")
      break
    case "mkdir":
    case "touch":
      if (r.created.length > 0) {
        pendingSelect = r.created[0]
        pendingRename = r.created[0]
      }
      break
    case "trash":
      for (i = 0; i < (ctx.entries || []).length; i++) if (ctx.entries[i].dir) list = Model.retargetTabs(list, ctx.entries[i].path, "")
      var names = r.trashed.filter(function(t) { return t.name !== "" }).map(function(t) { return t.name })
      lastTrashed = names
      if (r.trashed.length > 0) showToast("Moved " + Model.itemsLabel(r.trashed.length, Model.baseName(r.trashed[0].path)) + " to Trash", names.length > 0 ? names : null)
      selected = []
      break
    case "restore":
      if (r.restored.length > 0) showToast("Restored " + Model.itemsLabel(r.restored.length, Model.baseName(r.restored[0].path)))
      selected = []
      break
    case "purge":
    case "delete":
      for (i = 0; i < (ctx.entries || []).length; i++) if (ctx.entries[i].dir) list = Model.retargetTabs(list, ctx.entries[i].path, "")
      if (!failed) showToast("Deleted " + Model.itemsLabel(ctx.entries.length, ctx.entries[0].name) + " for good")
      selected = []
      break
    case "emptytrash":
      if (!failed) showToast("Trash emptied")
      break
    case "mount":
      if (r.mounted !== "" && ctx.open) openFolder(r.mounted, ctx.inNewTab)
      break
    case "eject":
      if (!failed) {
        list = Model.retargetTabs(list, ctx.drive.mount, root.home, true)
        showToast("Ejected " + ctx.drive.name + "; it is safe to unplug")
      }
      break
    case "bookmark":
      if (!failed) showToast("Bookmarked " + Model.baseName(ctx.path) + ", shared with Nautilus")
      break
    case "unbookmark":
      if (!failed) showToast("Removed " + Model.baseName(ctx.path) + " from the bookmarks")
      break
    }
    if (list !== tabs) {
      setTabs(list, activeTab)
      resetFolderState()
    }
    refreshPlaces()
    refreshLocation()
  }

  // ---- Filter and path --------------------------------------------------

  function startFilter() {
    filtering = true
    focusRequested("filter")
  }

  function setQuery(text) {
    query = text
    deep = false
    stopSearch()
    searchEntries = []
    cursorIndex = 0
    selected = []
  }

  function clearFilter() {
    filtering = false
    setQuery("")
    focusRequested("view")
  }

  // Ctrl+P: the folders opened here, used lately, bookmarked or open in
  // other tabs, narrowed as you type.
  function openJump() {
    jumpQuery = ""
    jumpIndex = 0
    jumpOpen = true
    menu = null
    goMenuOpen = false
    if (recentEntries.length === 0 && !recentProc.running) recentProc.running = true
    focusRequested("jump")
  }

  function closeJump() {
    jumpOpen = false
    focusRequested("view")
  }

  function setJumpQuery(text) {
    jumpQuery = text
    jumpIndex = 0
  }

  function moveJump(delta) {
    if (jumpList.length > 0) jumpIndex = Model.clampIndex(jumpIndex + delta, jumpList.length)
  }

  // Opens the pick here, or in a new tab with Ctrl; a folder open in another
  // tab switches to that tab, and a typed path is checked first.
  function pickJump(item, inNewTab) {
    if (!item) return
    closeJump()
    if (item.source === "typed") {
      checkFolder(item.path, inNewTab)
      return
    }
    if (item.source === "tab" && !inNewTab) switchTab(item.tabIndex)
    else openFolder(item.path, inNewTab)
  }

  function startPathEdit() {
    editingPath = true
    focusRequested("path")
  }

  function commitPath(text) {
    var target = Model.expandPath(text, home, inFolder ? location : home)
    editingPath = false
    focusRequested("view")
    if (target === "") return
    if (Model.isVirtual(target)) {
      go(target)
      return
    }
    checkFolder(target, false)
  }

  // Goes to a typed folder, or opens it in a new tab, once it is known to
  // be there.
  function checkFolder(target, inNewTab) {
    if (Model.isVirtual(target)) {
      openFolder(target, inNewTab)
      return
    }
    pathCheckProc.target = target
    pathCheckProc.inNewTab = inNewTab === true
    pathCheckProc.command = ["test", "-d", target]
    pathCheckProc.running = true
  }

  function cancelPathEdit() {
    editingPath = false
    focusRequested("view")
  }

  // ---- Menus, toasts and the window -------------------------------------

  // X and Y are in window coordinates (mapToItem(null, ...)), or -1 for the
  // middle of the view; ALIGNRIGHT puts the menu's right edge on X, under a
  // button at the right end of the header.
  function openMenu(items, x, y, entry, alignRight) {
    if (!items || items.length === 0) return
    menu = { items: items, x: x, y: y, entry: entry || null, alignRight: alignRight === true }
    menuIndex = 0
    while (menuIndex < items.length && items[menuIndex].disabled) menuIndex++
  }

  function moveMenu(delta) {
    if (!menu) return
    var n = menu.items.length
    var idx = menuIndex
    for (var step = 0; step < n; step++) {
      idx = Model.wrapIndex(idx + delta, n)
      if (!menu.items[idx].disabled) break
    }
    menuIndex = idx
  }

  function itemMenuFor(entry) {
    return Model.itemMenu(entry, picked().length, !!clipboard, entry && entry.dir && isBookmarked(entry.path))
  }

  function folderMenu() {
    return Model.folderMenu(location, !!clipboard, showHidden, sortKey, bookmarked)
  }

  // Every command, whether it came from a button, a menu or a key.
  function run(id, entry) {
    menu = null
    var target = entry || cursorEntry
    if (id.indexOf("sort:") === 0) {
      sortBy(id.slice(5))
      return
    }
    if (id.indexOf("app:") === 0) {
      launchApp(id.slice(4), appsPath)
      return
    }
    switch (id) {
    case "open": openPicked(); break
    case "opentab": openInNewTab(target); break
    case "openwith": openWith(target); break
    case "copy": setClipboard("copy"); break
    case "cut": setClipboard("cut"); break
    case "paste": paste(location); break
    case "pasteinto": if (target && target.dir) paste(target.path); break
    case "rename": startRename(target ? target.path : ""); break
    case "bookmark": toggleBookmark(target && target.dir && entry ? target.path : location); break
    case "trash": trashPicked(); break
    case "purge": askPurge(); break
    case "restore": restore(); break
    case "emptytrash": askEmptyTrash(); break
    case "newfolder": newItem("mkdir"); break
    case "newfile": newItem("touch"); break
    case "selectall": selectAll(); break
    case "hidden": toggleHidden(); break
    case "nautilus": openNautilus(); break
    case "extracthere": if (target && Model.isArchive(target)) extractHere(target.path, target.modified); break
    case "extractall": if (inArchive) extractHere(archiveAt.archive, undefined); break
    case "extractto": askExtractTo(target); break
    case "compress": askCompress(); break
    }
  }

  function showToast(text, undo) {
    toast = { text: text, undo: undo || null }
    toastTimer.restart()
  }

  // Out of the bar into a window Hyprland can move, resize and tile, with
  // the same tabs; and back.
  function popOut() {
    windowBuilt = true
    detached = true
    window.visible = true
    readClipboard("sync")
    if (root.opened) root.close()
    Qt.callLater(function() { root.focusRequested("view") })
  }

  function dock() {
    detached = false
    window.visible = false
    root.open()
    if (tabsDirty) saveTabs()
  }

  function toggleDetached() {
    if (detached) dock()
    else popOut()
  }

  // ---- Keyboard ---------------------------------------------------------

  // The panel keys of the other widgets (j/k, h/l, Enter, Esc, g, the hint
  // line) and the Nautilus shortcuts both work; returns whether the key was
  // taken.
  function handleKey(event) {
    var key = event.key
    var text = event.text
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var columns = view === "grid" ? Math.max(1, gridColumns) : 1

    if (keysOpen) {
      if (key === Qt.Key_Escape || text === "?" || key === Qt.Key_Return) keysOpen = false
      return true
    }
    if (menu) {
      if (key === Qt.Key_Escape) menu = null
      else if (key === Qt.Key_Down || text === "j") moveMenu(1)
      else if (key === Qt.Key_Up || text === "k") moveMenu(-1)
      else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
        var item = menu.items[menuIndex]
        if (item && !item.disabled) run(item.id, menu.entry)
      }
      return true
    }
    if (goMenuOpen) {
      goMenuOpen = false
      var targets = Model.goTargets(places, bookmarks, drives)
      for (var g = 0; g < targets.length; g++) {
        if (targets[g].key !== text) continue
        go(targets[g].path)
        break
      }
      return true
    }

    if (ctrl) {
      switch (key) {
      case Qt.Key_T: newTab(""); return true
      case Qt.Key_W: closeTab(activeTab); return true
      case Qt.Key_Tab: switchTab(activeTab + 1); return true
      case Qt.Key_Backtab: switchTab(activeTab - 1); return true
      case Qt.Key_PageDown: switchTab(activeTab + 1); return true
      case Qt.Key_PageUp: switchTab(activeTab - 1); return true
      case Qt.Key_L: startPathEdit(); return true
      case Qt.Key_P: openJump(); return true
      case Qt.Key_H: toggleHidden(); return true
      case Qt.Key_F: startFilter(); return true
      case Qt.Key_C: setClipboard("copy"); return true
      case Qt.Key_X: setClipboard("cut"); return true
      case Qt.Key_V: paste(location); return true
      case Qt.Key_A: selectAll(); return true
      case Qt.Key_D: toggleBookmark(location); return true
      case Qt.Key_Z: undoTrash(null); return true
      case Qt.Key_N: if (shift) newItem("mkdir"); return shift
      case Qt.Key_1: setView("list"); return true
      case Qt.Key_2: setView("grid"); return true
      case Qt.Key_3: setView("columns"); return true
      case Qt.Key_Return:
      case Qt.Key_Enter:
        if (cursorEntry && Model.isArchive(cursorEntry) && !Model.isArchiveLocation(cursorEntry.path)) newTab(Model.archiveLocation(cursorEntry.path, ""))
        else openInNewTab(cursorEntry)
        return true
      }
      return false
    }
    if (alt) {
      if (key === Qt.Key_Left) back()
      else if (key === Qt.Key_Right) forward()
      else if (key === Qt.Key_Up) up()
      else return false
      return true
    }

    switch (key) {
    case Qt.Key_Down: moveCursor(columns, shift); return true
    case Qt.Key_Up: moveCursor(-columns, shift); return true
    case Qt.Key_PageDown: moveCursor(10, shift); return true
    case Qt.Key_PageUp: moveCursor(-10, shift); return true
    case Qt.Key_Home: moveCursor(-entries.length, shift); return true
    case Qt.Key_End: moveCursor(entries.length, shift); return true
    case Qt.Key_Right:
      if (view === "grid") moveCursor(1, shift)
      else if (cursorEntry && (cursorEntry.dir || Model.isArchive(cursorEntry))) openEntry(cursorEntry)
      return true
    case Qt.Key_Left:
      if (view === "grid") moveCursor(-1, shift)
      else up()
      return true
    case Qt.Key_Return:
    case Qt.Key_Enter: openPicked(); return true
    case Qt.Key_Space: toggleCursorSelection(); return true
    case Qt.Key_Backspace: up(); return true
    case Qt.Key_F2: startRename(""); return true
    case Qt.Key_Delete:
      if (shift || inTrash) askPurge()
      else trashPicked()
      return true
    case Qt.Key_Escape: clearOrClose(); return true
    }

    switch (text) {
    case "j": moveCursor(1, false); return true
    case "k": moveCursor(-1, false); return true
    case "J": moveCursor(1, true); return true
    case "K": moveCursor(-1, true); return true
    case "l": if (cursorEntry && (cursorEntry.dir || Model.isArchive(cursorEntry))) openEntry(cursorEntry); return true
    case "h": up(); return true
    case "y": setClipboard("copy"); return true
    case "x": setClipboard("cut"); return true
    case "p": paste(location); return true
    case "r": startRename(""); return true
    case "a": newItem("mkdir"); return true
    case "n": newItem("touch"); return true
    case "d":
      if (inTrash) askPurge()
      else trashPicked()
      return true
    case "o": openWith(cursorEntry); return true
    case "/": startFilter(); return true
    case "g": goMenuOpen = true; return true
    case "e": startPathEdit(); return true
    case "i": togglePreview(); return true
    case ".": toggleHidden(); return true
    case "w": toggleDetached(); return true
    case "v": setView(Model.nextView(view)); return true
    case "s": sortBy(Model.cycleSortKey(sortKey)); return true
    case "t": newTab(""); return true
    case "q": closeTab(activeTab); return true
    case "]": switchTab(activeTab + 1); return true
    case "[": switchTab(activeTab - 1); return true
    case "N": openNautilus(); return true
    case "?": keysOpen = true; return true
    case "E":
      if (inArchive) extractHere(archiveAt.archive, undefined)
      else if (cursorEntry && Model.isArchive(cursorEntry)) extractHere(cursorEntry.path, cursorEntry.modified)
      return true
    case "Z": askCompress(); return true
    case "<": stepPage(-1); return true
    case ">": stepPage(1); return true
    }
    if (text.length === 1 && text >= "1" && text <= "9") {
      var n = Number(text) - 1
      if (n < tabs.length) switchTab(n)
      return true
    }
    return false
  }

  IpcHandler {
    target: "joamag.files"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function go(path: string): void {
      root.go(Model.expandPath(path, root.home, root.home))
      if (!root.detached) root.open()
    }
    function popOut(): void { root.popOut() }
    function dock(): void { root.dock() }
    function version(): string { return "0.1.0" }
  }

  Component.onCompleted: {
    loadTabs()
    refreshPlaces()
  }

  onSettingsChanged: loadTabs()

  onOpenedChanged: {
    if (opened) {
      if (detached) {
        // The window and the popup never show at once.
        detached = false
        window.visible = false
      }
      menu = null
      goMenuOpen = false
      keysOpen = false
      refreshPlaces()
      refreshLocation()
      readClipboard("sync")
    } else {
      if (renamePath !== "") cancelRename()
      editingPath = false
      jumpOpen = false
      menu = null
      confirm = null
      if (tabsDirty) saveTabs()
    }
  }

  onShowHiddenChanged: if (deep) search()

  onCursorEntryChanged: {
    if (!previewTimer.running) previewEntry = cursorEntry
    previewTimer.restart()
  }

  onPreviewEntryChanged: {
    previewPage = 0
    previewPages = 0
  }

  onShownChanged: if (shown && folderDirty) snapshotFolder()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FolderListModel {
    id: folderModel
    folder: root.inFolder ? Model.fileUrl(root.location) : ""
    showDirsFirst: true
    showDotAndDotDot: false
    showHidden: true
    showOnlyReadable: false
    caseSensitive: false
    // A folder just opened shows as soon as it is read.
    onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(root.snapshotFolder)
  }

  // Changes on disk come in bursts (a download, a build); they are read a
  // moment after the burst settles, longer for a big folder, so a folder
  // that never stops changing never keeps the shell busy. Renames and
  // in-place changes keep the count, so the row signals are followed too.
  Connections {
    target: folderModel
    function onDataChanged() { snapshotTimer.restart() }
    function onRowsInserted() { snapshotTimer.restart() }
    function onRowsRemoved() { snapshotTimer.restart() }
    function onModelReset() { snapshotTimer.restart() }
  }

  Timer {
    id: snapshotTimer
    interval: Math.min(1500, 150 + Math.floor(root.folderEntries.length / 10))
    onTriggered: root.snapshotFolder()
  }

  // Tabs only need to survive a restart: they are written when the popup
  // closes or the window docks, or after a quiet spell, rather than on every
  // step, since each write goes through the shell's whole config.
  Timer {
    id: saveTabsTimer
    interval: 6000
    onTriggered: root.saveTabs()
  }

  Timer {
    id: freeTimer
    interval: 400
    onTriggered: {
      if (!root.inFolder) return
      freeProc.command = [root.scriptPath, "free", root.location]
      if (!freeProc.running) freeProc.running = true
    }
  }

  // Leading and trailing: a single step shows at once, a held key shows
  // where it stops.
  Timer {
    id: previewTimer
    interval: 120
    onTriggered: root.previewEntry = root.cursorEntry
  }

  Timer {
    id: searchFlush
    interval: 120
    repeat: true
    running: searchProc.running
    onTriggered: root.flushSearch()
  }

  Timer {
    id: toastTimer
    interval: 4500
    onTriggered: root.toast = null
  }

  // Short copies finish before the progress line would be worth reading.
  Timer {
    id: taskTimer
    interval: 600
    onTriggered: root.taskShown = root.task !== null
  }

  Timer {
    interval: 30000
    running: root.opened || root.detached
    repeat: true
    onTriggered: root.refreshPlaces()
  }

  Process {
    id: placesProc
    command: [root.scriptPath, "places"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.placesData = Model.parsePlaces(text) }
  }

  Process {
    id: freeProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.freeSpace = Model.parseFree(text) }
  }

  Process {
    id: recentProc
    command: [root.scriptPath, "recent"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.recentEntries = Model.parseEntries(text) }
  }

  Process {
    id: trashProc
    command: [root.scriptPath, "trashed"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.trashEntries = Model.parseEntries(text) }
  }

  Process {
    id: searchProc
    stdout: SplitParser { onRead: function(line) { root.searchBuffer.push(line) } }
    onExited: {
      root.flushSearch()
      if (root.searchRestart) {
        root.searchRestart = false
        running = true
      }
    }
  }

  Process {
    id: namesProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyNames(text) }
  }

  Process {
    id: appsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.apps = Model.parseApps(text)
        var items = root.apps.map(function(a) { return { id: "app:" + a.id, label: a.name + (a.isDefault ? " (default)" : ""), icon: "󰀻" } })
        if (items.length === 0) root.showToast("No app is registered for " + Model.baseName(root.appsPath))
        else root.openMenu(items, -1, -1, null)
      }
    }
  }

  Process {
    id: archiveProc
    property string archive: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyArchive(archiveProc.archive, text) }
    onExited: Qt.callLater(root.nextArchive)
  }

  Process {
    id: memberProc
    property var job: null
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyMember(memberProc.job, text) }
    onExited: Qt.callLater(root.nextMember)
  }

  Process {
    id: extractNamesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.extractJob) return
        var job = Object.assign({}, root.extractJob)
        job.names = Model.parseNames(text)
        root.extractJob = job
        root.advanceExtract()
      }
    }
  }

  Process {
    id: clipboardProc
    property string purpose: ""
    command: [root.scriptPath, "clipboard-get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyClipboard(text, clipboardProc.purpose) }
  }

  Process {
    id: thumbProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyThumbnail(text) }
    onExited: Qt.callLater(root.nextThumbnail)
  }

  Process {
    id: pathCheckProc
    property string target: ""
    property bool inNewTab: false
    onExited: function(exitCode) {
      if (exitCode === 0) root.openFolder(target, inNewTab)
      else root.showToast("No folder at " + Model.prettyPath(target, root.home))
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyAction(text) }
  }

  Process {
    id: transferProc
    stdout: SplitParser { onRead: function(line) { root.applyTransferLine(line) } }
    onExited: root.finishTransfer()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.ICON
    fontSize: Style.font.body
    horizontalMargin: 6
    fixedWidth: Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.tabs, root.activeTab, root.locationLabel)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleDetached()
      else if (b === Qt.MiddleButton) root.openNautilus()
      else if (root.detached) root.dock()
      else root.toggle()
    }
  }

  // The popup covers the whole screen, which is how a click outside closes
  // it; while files are dragged out it takes input over its card only, so
  // the app under the pointer, and not the popup, gets the drag.
  Region {
    id: screenRegion
    width: panel.screenW
    height: panel.screenH
  }

  Region {
    id: cardRegion
    item: panel.loadedContent
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent ? panel.loadedContent.view : null
    mask: root.dragPaths.length > 0 && panel.loadedContent ? cardRegion : screenRegion
    contentWidth: panel.fittedContentWidth(Style.space(720))
    contentHeight: panel.fittedContentHeight(Style.space(560))

    // Built the first time the popup opens rather than at shell start, on
    // every monitor's bar, and kept after that so reopening is instant.
    content: Component {
      PanelKeyCatcher {
        id: keyCatcher
        readonly property Item view: popupView
        anchors.fill: parent
        // The view takes every key it knows first; what reaches the catcher
        // is Tab, to the neighbouring panel, unless a field is being typed in.
        blocked: popupView.typing
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }

        FilesView {
          id: popupView
          anchors.fill: parent
          windowed: false
          foreground: root.foreground
          background: Color.popups.background
          active: root.opened
        }
      }
    }
  }

  FloatingWindow {
    id: window
    visible: false
    title: "Files · " + root.locationLabel
    color: Color.background
    implicitWidth: 1120
    implicitHeight: 700
    minimumSize: Qt.size(640, 420)

    // Closed from Hyprland rather than docked: the tabs stay for next time.
    onVisibleChanged: {
      if (visible) return
      root.detached = false
      if (root.tabsDirty) root.saveTabs()
    }

    // Built on the first pop out, then kept for the next one.
    Loader {
      anchors.fill: parent
      anchors.margins: Style.space(10)
      active: root.windowBuilt
      focus: true

      sourceComponent: Component {
        FilesView {
          windowed: true
          foreground: Color.foreground
          background: Color.background
          active: root.detached
          focus: true
        }
      }
    }
  }

  // ======================================================================
  // The navigator itself, shared by the popup and the window.
  // ======================================================================
  component FilesView: Item {
    id: viewRoot
    required property bool windowed
    required property color foreground
    required property color background
    required property bool active

    readonly property bool typing: pathField.activeFocus || filterField.activeFocus || root.renamePath !== "" || root.prompt !== null || root.jumpOpen
    readonly property real rowHeight: Style.space(26)

    focus: true
    Keys.onPressed: function(event) {
      if (root.confirm) {
        if (confirmDialog.handleKey(event)) event.accepted = true
        else event.accepted = event.key !== Qt.Key_Tab
        return
      }
      if (root.conflictJob) {
        if (conflictCard.handleKey(event)) event.accepted = true
        return
      }
      if (viewRoot.typing) return
      if (root.handleKey(event)) event.accepted = true
    }

    Connections {
      target: root
      function onFocusRequested(what) {
        if (!viewRoot.active) return
        if (what === "filter") filterField.forceActiveFocus()
        else if (what === "path") {
          pathField.text = root.inFolder ? Model.prettyPath(root.location, root.home) : "~"
          pathField.forceActiveFocus()
          pathField.selectAll()
        } else if (what === "prompt") promptCard.focusField()
        else if (what === "jump") jumpCard.focusField()
        else if (what === "view") viewRoot.forceActiveFocus()
      }

      // The go-to card hangs under the header, from the Go to button (from
      // the files' left edge in the window, which has no such button).
      function onGoMenuOpenChanged() {
        if (!root.goMenuOpen || !viewRoot.active) return
        var at = (goButton.visible ? goButton : main).mapToItem(viewRoot, 0, 0)
        var below = header.mapToItem(viewRoot, 0, header.height + Style.space(6))
        goMenu.x = Math.max(0, Math.min(viewRoot.width - goMenu.width, at.x))
        goMenu.y = below.y
      }
    }

    onActiveChanged: if (active) Qt.callLater(function() { viewRoot.forceActiveFocus() })

    Row {
      anchors.fill: parent
      spacing: Style.space(10)

      // ---------- Places sidebar, once it is a window ----------
      Sidebar {
        id: sidebar
        visible: viewRoot.windowed
        width: viewRoot.windowed ? Style.space(210) : 0
        height: parent.height
        foreground: viewRoot.foreground
      }

      Column {
        id: main
        width: parent.width - (viewRoot.windowed ? sidebar.width + parent.spacing : 0)
        height: parent.height
        spacing: Style.space(8)

        // ---------- Header: back, forward, up, path, filter, views ----------
        Row {
          id: header
          width: parent.width
          height: Style.spacing.controlHeight
          spacing: Style.space(6)

          readonly property real square: Style.spacing.controlHeight
          // Square buttons beside the path: back, forward, up (and Go to in
          // the popup), the filter, the views, hidden files, the preview,
          // pop out or dock, and ⋮; one gap after each.
          readonly property int squares: (viewRoot.windowed ? 3 : 4) + 1 + Model.VIEWS.length + 4

          IconButton { glyph: "󰁍"; tip: "Back (Alt+←)"; enabled: Model.canGoBack(root.tab); onClicked: root.back() }
          IconButton { glyph: "󰁔"; tip: "Forward (Alt+→)"; enabled: Model.canGoForward(root.tab); onClicked: root.forward() }
          IconButton { glyph: "󰁝"; tip: "Up (h)"; enabled: Model.parentPath(root.location) !== ""; onClicked: root.up() }
          IconButton {
            id: goButton
            visible: !viewRoot.windowed
            glyph: "󰋜"
            tip: "Go to (g)"
            onClicked: root.goMenuOpen = !root.goMenuOpen
          }

          // Path bar, the path field or the filter field share this slot.
          Item {
            id: pathSlot
            width: header.width - (header.square + header.spacing) * header.squares
            height: parent.height

            Crumbs {
              anchors.fill: parent
              visible: !root.editingPath && !root.filtering
              foreground: viewRoot.foreground
            }

            TextField {
              id: pathField
              anchors.fill: parent
              visible: root.editingPath
              placeholderText: "Type a path: ~/Downloads, /etc, file:///…"
              foreground: viewRoot.foreground
              font.family: root.fontFamily
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelPathEdit()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitPath(pathField.text)
                  event.accepted = true
                }
              }
              onActiveFocusChanged: if (!activeFocus && root.editingPath) root.editingPath = false
            }

            TextField {
              id: filterField
              anchors.fill: parent
              visible: root.filtering
              placeholderText: root.deep ? "Searching below " + Model.prettyPath(root.location, root.home) : "Filter " + root.locationLabel + " · Enter searches below"
              foreground: viewRoot.foreground
              font.family: root.fontFamily
              text: root.query
              onTextChanged: if (text !== root.query) root.setQuery(text)
              onActiveFocusChanged: root.filterFocused = activeFocus
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.clearFilter()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.search()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  viewRoot.forceActiveFocus()
                  event.accepted = true
                }
              }
            }
          }

          IconButton { glyph: "󰍉"; tip: "Filter (/ or Ctrl+F)"; selected: root.filtering; onClicked: root.filtering ? root.clearFilter() : root.startFilter() }

          Repeater {
            model: Model.VIEWS

            IconButton {
              required property var modelData
              glyph: modelData.icon
              tip: modelData.label + " (Ctrl+" + (Model.VIEWS.indexOf(modelData) + 1) + ")"
              selected: root.view === modelData.key
              onClicked: root.setView(modelData.key)
            }
          }

          // Dot files and folders, shown or not; remembered across restarts.
          IconButton {
            glyph: root.showHidden ? Model.GLYPHS.hiddenShown : Model.GLYPHS.hiddenHidden
            tip: (root.showHidden ? "Hide" : "Show") + " hidden files and folders (. or Ctrl+H)"
            selected: root.showHidden
            onClicked: root.toggleHidden()
          }
          IconButton { glyph: "󰋽"; tip: "Preview pane (i)"; selected: root.showPreview; onClicked: root.togglePreview() }
          IconButton {
            glyph: viewRoot.windowed ? "󰘕" : "󰘖"
            tip: viewRoot.windowed ? "Dock back into the bar (w)" : "Pop out into a window (w)"
            onClicked: root.toggleDetached()
          }
          IconButton {
            id: moreButton
            glyph: "󰇙"
            tip: "More"
            onClicked: {
              var p = moreButton.mapToItem(null, moreButton.width, moreButton.height + Style.space(4))
              root.openMenu(root.folderMenu(), p.x, p.y, null, true)
            }
          }
        }

        // ---------- Tabs ----------
        Row {
          id: tabStrip
          width: parent.width
          height: Style.spacing.controlHeight
          spacing: Style.space(4)

          readonly property real addWidth: Style.spacing.controlHeight
          readonly property real tabWidth: Math.min(Style.space(200), (width - addWidth - spacing * root.tabs.length) / Math.max(1, root.tabs.length))

          // Counted rather than handed the list, so stepping through
          // folders updates the chips instead of building them again.
          Repeater {
            model: root.tabs.length

            TabChip {
              required property int index
              width: tabStrip.tabWidth
              height: tabStrip.height
              tabData: root.tabs[index] || root.tab
              tabIndex: index
              foreground: viewRoot.foreground
            }
          }

          IconButton { glyph: "󰐕"; tip: "New tab (Ctrl+T)"; onClicked: root.newTab("") }
        }

        // ---------- Body: the folder and the preview ----------
        Item {
          id: body
          width: parent.width
          height: main.height - header.height - tabStrip.height - footer.height - main.spacing * 3

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(viewRoot.foreground.r, viewRoot.foreground.g, viewRoot.foreground.b, 0.12)
          }

          Item {
            id: pane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: parent.width - 2 - (root.showPreview ? preview.width : 0)
            clip: true

            ListPane {
              anchors.fill: parent
              visible: root.view === "list" || (root.view === "columns" && (!root.inFolder || root.deep))
              foreground: viewRoot.foreground
              rowHeight: viewRoot.rowHeight
              shown: visible && viewRoot.active
            }

            GridPane {
              anchors.fill: parent
              visible: root.view === "grid"
              foreground: viewRoot.foreground
              shown: visible && viewRoot.active
            }

            ColumnsPane {
              anchors.fill: parent
              visible: root.columnsShown
              foreground: viewRoot.foreground
              background: viewRoot.background
              rowHeight: viewRoot.rowHeight
              shown: visible && viewRoot.active
            }

            // Drops from other apps land in the folder on screen.
            DropArea {
              anchors.fill: parent
              z: -1
              keys: ["text/uri-list"]
              enabled: root.inFolder
              onDropped: function(drop) {
                if (root.dropUrls(drop.urls, root.location, drop.proposedAction === Qt.CopyAction)) drop.accept()
              }
            }

            // The columns view says it in the column of the folder on screen.
            Text {
              anchors.centerIn: parent
              visible: root.entries.length === 0 && !root.columnsShown
              textFormat: Text.PlainText
              text: root.emptyMessage
              color: viewRoot.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PreviewPane {
            id: preview
            visible: root.showPreview
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: viewRoot.windowed ? Style.space(290) : Style.space(240)
            foreground: viewRoot.foreground
            entry: root.showPreview ? root.previewEntry : null
          }
        }

        // ---------- Footer: progress, status, actions, hints ----------
        Column {
          id: footer
          width: parent.width
          spacing: Style.space(6)

          ProgressLine {
            visible: root.taskShown && root.task !== null
            width: parent.width
            foreground: viewRoot.foreground
          }

          Text {
            visible: root.renameError !== "" || root.lastError !== ""
            textFormat: Text.PlainText
            text: root.renameError !== "" ? root.renameError : root.lastError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }

          // Count and selection on the left; clipboard, hidden files and
          // free space on the right.
          Item {
            width: parent.width
            height: Math.max(statusLeft.implicitHeight, statusRight.implicitHeight)

            Text {
              id: statusLeft
              anchors.left: parent.left
              anchors.right: statusRight.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                var text = Model.statusText(root.entries, root.selected, root.deep, Model.prettyPath(root.location, root.home))
                if (!root.inArchive) return text
                if (root.archiveListing && root.archiveListing.loading && !root.archiveListing.members) return "Reading the archive…"
                return text + " · read-only archive"
              }
              color: viewRoot.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              id: statusRight
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                var parts = []
                if (root.clipboard) parts.push((root.clipboard.mode === "copy" ? "󰆏 " : "󰆐 ") + root.clipboard.paths.length + " in clipboard")
                if (root.showHidden) parts.push("hidden files shown")
                if (root.inFolder && isFinite(root.freeSpace.avail)) parts.push(Model.formatSize(root.freeSpace.avail) + " free")
                return parts.join(" · ")
              }
              color: root.clipboard ? Color.accent : viewRoot.foreground
              opacity: root.clipboard ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: actionRow
            width: parent.width
            spacing: Style.space(6)

            readonly property var actions: root.inArchive ? [
              { id: "open", label: "Open", icon: "󰏌" },
              { id: "copy", label: "Copy out", icon: "󰆏" },
              { id: "extractto", label: "Extract to…", icon: "󰇚" },
              { id: "extractall", label: "Extract all", icon: "󰇚" },
              { id: "nautilus", label: "Nautilus", icon: "󰉋" }
            ] : root.inTrash ? [
              { id: "restore", label: "Restore", icon: "󰦛" },
              { id: "purge", label: "Delete", icon: "󰆴" },
              { id: "emptytrash", label: "Empty Trash", icon: "󰩹" },
              { id: "nautilus", label: "Nautilus", icon: "󰏌" }
            ] : [
              { id: "open", label: "Open", icon: "󰏌" },
              { id: "copy", label: "Copy", icon: "󰆏" },
              { id: "cut", label: "Cut", icon: "󰆐" },
              { id: "paste", label: "Paste", icon: "󰆒" },
              { id: "rename", label: "Rename", icon: "󰏫" },
              { id: "trash", label: "Trash", icon: "󰩹" },
              { id: "nautilus", label: "Nautilus", icon: "󰉋" }
            ]
            readonly property real cellWidth: (width - spacing * (actions.length - 1)) / actions.length

            Repeater {
              model: actionRow.actions

              Button {
                required property var modelData
                width: actionRow.cellWidth
                height: Style.spacing.controlHeight
                iconText: modelData.icon
                iconSize: Style.font.title
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: viewRoot.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.sm
                verticalPadding: Style.spacing.xs
                bordered: true
                enabled: modelData.id !== "paste" || root.clipboard !== null
                opacity: enabled ? 1 : 0.4
                onClicked: root.run(modelData.id, null)
              }
            }
          }

          // Key hint line, the way the other widgets spell out their keys.
          Text {
            width: parent.width
            textFormat: Text.StyledText
            text: Model.hints(root.hintMode).map(function(h) { return "<b>" + h.key + "</b> " + h.label }).join("   ")
            color: viewRoot.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }

    // ---------- Overlays ----------
    Toast {
      x: main.x + (main.width - width) / 2
      anchors.bottom: parent.bottom
      anchors.bottomMargin: footer.height + Style.space(14)
      foreground: viewRoot.foreground
      background: viewRoot.background
    }

    // A click outside the go-to card closes it.
    MouseArea {
      anchors.fill: parent
      visible: root.goMenuOpen
      z: 19
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.goMenuOpen = false
    }

    GoMenu {
      id: goMenu
      foreground: viewRoot.foreground
      background: viewRoot.background
    }

    MenuCard {
      anchors.fill: parent
      foreground: viewRoot.foreground
      background: viewRoot.background
    }

    KeySheet {
      anchors.fill: parent
      anchors.margins: Style.space(16)
      foreground: viewRoot.foreground
      background: viewRoot.background
    }

    ConflictCard {
      id: conflictCard
      anchors.fill: parent
      foreground: viewRoot.foreground
      background: viewRoot.background
    }

    PromptCard {
      id: promptCard
      anchors.fill: parent
      foreground: viewRoot.foreground
      background: viewRoot.background
    }

    JumpCard {
      id: jumpCard
      anchors.fill: parent
      foreground: viewRoot.foreground
      background: viewRoot.background
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      z: 10
      opened: root.confirm !== null
      message: root.confirm ? root.confirm.message : ""
      confirmText: root.confirm ? root.confirm.confirmText : ""
      background: viewRoot.background
      foreground: viewRoot.foreground
      fontFamily: root.fontFamily
      onCanceled: root.confirm = null
      onConfirmed: root.confirmed()
    }
  }

  // Discrete wheel scrolling: a notch moves the view a whole number of rows
  // (the system's wheel step) and lands on a row edge, with no glide, so the
  // files stay where the wheel left them; a touchpad's small deltas add up
  // to whole rows. It lies over the view and takes only the wheel, so
  // clicks, hovers and drags reach the rows. A sideways wheel (or
  // Shift+wheel) moves SIDEWAYS a column at a time, for the columns view.
  // The views do not flick: pressing and dragging moves files instead.
  component StepScroll: MouseArea {
    id: stepScroll
    required property Flickable flick
    required property real pitch
    property Flickable sideways: null
    property real sidePitch: 0
    property int rowsPerNotch: Math.max(1, Number(Qt.styleHints.wheelScrollLines) || 3)
    property real carry: 0
    property real sideCarry: 0
    anchors.fill: flick
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) {
      var dx = wheel.angleDelta.x || wheel.pixelDelta.x
      var dy = wheel.angleDelta.y || wheel.pixelDelta.y
      var f = stepScroll.flick
      if (dy !== 0 && !(wheel.modifiers & Qt.ShiftModifier)) {
        var step = Model.wheelRows(stepScroll.carry, dy, stepScroll.rowsPerNotch)
        stepScroll.carry = step.carry
        if (step.rows !== 0) f.contentY = f.originY + Model.steppedScroll(f.contentY - f.originY, -step.rows, stepScroll.pitch, f.contentHeight, f.height)
        wheel.accepted = true
        return
      }
      var side = stepScroll.sideways
      if (side && (dx !== 0 || dy !== 0)) {
        var across = Model.wheelRows(stepScroll.sideCarry, dx !== 0 ? dx : dy, 1)
        stepScroll.sideCarry = across.carry
        if (across.rows !== 0) side.contentX = side.originX + Model.steppedScroll(side.contentX - side.originX, -across.rows, stepScroll.sidePitch, side.contentWidth, side.width)
        wheel.accepted = true
        return
      }
      wheel.accepted = false
    }
  }

  // A square header button with a glyph.
  component IconButton: Button {
    property string glyph: ""
    property string tip: ""
    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight
    iconText: glyph
    iconSize: Style.font.title
    tooltipText: tip
    foreground: root.foreground
    fontFamily: root.fontFamily
    horizontalPadding: 0
    verticalPadding: 0
    bordered: true
    opacity: enabled ? 1 : 0.35
  }

  // The path as segments: click one to go there, click the empty end to
  // type a path. Segments take drops.
  component Crumbs: Rectangle {
    id: crumbsRoot
    required property color foreground
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.28)
    clip: true

    readonly property var parts: Model.crumbs(root.location, root.home, root.drives)

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.IBeamCursor
      onClicked: root.startPathEdit()
    }

    ListView {
      id: crumbList
      anchors.fill: parent
      anchors.leftMargin: Style.space(4)
      anchors.rightMargin: Style.space(4)
      orientation: ListView.Horizontal
      interactive: false
      model: crumbsRoot.parts
      // The deepest segment stays in view when the path is long.
      onContentWidthChanged: positionViewAtEnd()
      onWidthChanged: positionViewAtEnd()

      delegate: Item {
        id: crumb
        required property var modelData
        required property int index
        height: crumbList.height
        width: crumbRow.implicitWidth + Style.space(8)

        readonly property bool last: index === crumbsRoot.parts.length - 1

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.space(3)
          anchors.bottomMargin: Style.space(3)
          color: crumbDrop.containsDrag ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : (crumbMouse.containsMouse ? Qt.rgba(crumbsRoot.foreground.r, crumbsRoot.foreground.g, crumbsRoot.foreground.b, 0.08) : "transparent")
        }

        Row {
          id: crumbRow
          anchors.centerIn: parent
          spacing: Style.space(4)

          Text {
            visible: crumb.index > 0
            textFormat: Text.PlainText
            text: "›"
            color: crumbsRoot.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            visible: crumb.index === 0
            textFormat: Text.PlainText
            text: Model.placeIcon(crumb.modelData.path, root.home, root.places, root.drives)
            color: crumbsRoot.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            textFormat: Text.PlainText
            text: crumb.modelData.label
            color: crumbsRoot.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: crumb.last
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: crumbMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (root.newTabClick(mouse)) root.newTab(crumb.modelData.path)
            else if (!crumb.last) root.go(crumb.modelData.path)
          }
        }

        DropArea {
          id: crumbDrop
          anchors.fill: parent
          keys: ["text/uri-list"]
          enabled: !Model.isVirtual(crumb.modelData.path)
          onDropped: function(drop) {
            if (root.dropUrls(drop.urls, crumb.modelData.path, drop.proposedAction === Qt.CopyAction)) drop.accept()
          }
        }
      }
    }
  }

  // One tab: the place's glyph and name, its number for the 1-9 keys, and
  // a close button. Tabs take drops into their folder.
  component TabChip: CursorSurface {
    id: chip
    required property var tabData
    required property int tabIndex

    readonly property bool isActive: tabIndex === root.activeTab

    current: isActive
    hasCursor: chipMouse.containsMouse || chipDrop.containsDrag
    bordered: true

    Row {
      anchors.left: parent.left
      anchors.right: chipClose.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        text: Model.placeIcon(chip.tabData.path, root.home, root.places, root.drives)
        color: chip.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: Model.placeLabel(chip.tabData.path, root.home, root.places, root.drives)
        color: chip.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: chip.isActive
        elide: Text.ElideRight
        width: Math.max(0, parent.width - Style.space(40))
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: chip.tabIndex < 9 && chip.width >= Style.space(110)
        textFormat: Text.PlainText
        text: String(chip.tabIndex + 1)
        color: chip.foreground
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton) root.closeTab(chip.tabIndex)
        else root.switchTab(chip.tabIndex)
      }
    }

    Text {
      id: chipClose
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: root.tabs.length > 1
      textFormat: Text.PlainText
      text: "󰅖"
      color: closeMouse.containsMouse ? Color.urgent : chip.foreground
      opacity: closeMouse.containsMouse ? 1 : 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall

      MouseArea {
        id: closeMouse
        anchors.fill: parent
        anchors.margins: -Style.space(3)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.closeTab(chip.tabIndex)
      }
    }

    DropArea {
      id: chipDrop
      anchors.fill: parent
      keys: ["text/uri-list"]
      enabled: !Model.isVirtual(chip.tabData.path)
      onDropped: function(drop) {
        if (root.dropUrls(drop.urls, chip.tabData.path, drop.proposedAction === Qt.CopyAction)) drop.accept()
      }
    }
  }

  // The list view: a sortable header (name, type, size, date) and a row per
  // entry. Recent, Trash and search results also say where each one is.
  component ListPane: Item {
    id: listPane
    required property color foreground
    required property real rowHeight
    required property bool shown

    readonly property bool showWhere: root.inTrash || root.inRecent || root.deep
    readonly property real sizeWidth: Style.space(74)
    readonly property real dateWidth: Style.space(84)
    // The name keeps room to be read: in a narrow pane the type column goes
    // first, then the location column narrows and goes too.
    readonly property real innerWidth: width - Style.space(16)
    readonly property real gap: Style.space(10)
    readonly property real nameMin: Style.space(150)
    readonly property real fixedWidth: Style.space(20) + sizeWidth + dateWidth + gap * 3
    readonly property real typeWidth: innerWidth - fixedWidth - (showWhere ? Style.space(100) + gap : 0) - Style.space(110) - gap >= nameMin ? Style.space(110) : 0
    readonly property real whereWidth: {
      if (!showWhere) return 0
      var room = innerWidth - fixedWidth - (typeWidth > 0 ? typeWidth + gap : 0) - gap - nameMin
      return room >= Style.space(60) ? Math.min(Style.space(200), room) : 0
    }
    readonly property real nameWidth: innerWidth - fixedWidth - (typeWidth > 0 ? typeWidth + gap : 0) - (whereWidth > 0 ? whereWidth + gap : 0)

    Row {
      id: columnsHead
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      height: Style.space(24)
      spacing: listPane.gap

      SortHead { width: Style.space(20) + listPane.gap + listPane.nameWidth; key: "name"; label: "Name"; leading: Style.space(20) + listPane.gap; foreground: listPane.foreground }
      Text {
        visible: listPane.whereWidth > 0
        width: listPane.whereWidth
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.inTrash ? "DELETED FROM" : "LOCATION"
        color: listPane.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      SortHead { visible: listPane.typeWidth > 0; width: listPane.typeWidth; key: "type"; label: "Type"; foreground: listPane.foreground }
      SortHead { width: listPane.sizeWidth; key: "size"; label: "Size"; alignRight: true; foreground: listPane.foreground }
      SortHead { width: listPane.dateWidth; key: "modified"; label: root.inTrash ? "Deleted" : (root.inRecent ? "Used" : "Modified"); alignRight: true; foreground: listPane.foreground }
    }

    Rectangle {
      id: headLine
      anchors.top: columnsHead.bottom
      width: parent.width
      height: 1
      color: Qt.rgba(listPane.foreground.r, listPane.foreground.g, listPane.foreground.b, 0.12)
    }

    ListView {
      id: list
      anchors.top: headLine.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      model: listPane.shown ? root.entries.length : 0
      reuseItems: true
      currentIndex: root.cursorIndex
      highlightFollowsCurrentItem: false

      property real keptY: 0
      Connections {
        target: root
        function onListingWillChange() { list.keptY = list.contentY }
        function onListingChanged() { list.contentY = list.keptY }
      }

      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      onCountChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: EntryRow {
        required property int index
        width: list.width
        height: listPane.rowHeight
        entry: root.entries[index] || root.blankEntry
        entryIndex: index
        foreground: listPane.foreground
        nameWidth: listPane.nameWidth
        whereWidth: listPane.whereWidth
        typeWidth: listPane.typeWidth
        sizeWidth: listPane.sizeWidth
        dateWidth: listPane.dateWidth
      }

      // Empty space below the rows: click clears the selection, right
      // click opens the folder menu.
      MouseArea {
        z: -1
        width: list.width
        height: Math.max(list.height, list.contentHeight)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            var p = mapToItem(null, mouse.x, mouse.y)
            root.openMenu(root.folderMenu(), p.x, p.y, null)
          } else {
            root.selected = []
            if (root.renamePath !== "") root.cancelRename()
          }
        }
      }
    }

    StepScroll { flick: list; pitch: listPane.rowHeight }
  }

  component SortHead: Item {
    id: sortHead
    required property string key
    required property string label
    required property color foreground
    property bool alignRight: false
    property real leading: 0

    height: parent.height
    // Recent keeps its newest-first order, so no column claims the sort.
    readonly property bool on: root.sortKey === key && !root.inRecent

    Text {
      anchors.left: sortHead.alignRight ? undefined : parent.left
      anchors.right: sortHead.alignRight ? parent.right : undefined
      anchors.leftMargin: sortHead.leading
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: sortHead.label.toUpperCase() + (sortHead.on ? (root.sortDescending ? " ↓" : " ↑") : "")
      color: sortHead.foreground
      opacity: sortHead.on ? 0.9 : 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.sortBy(sortHead.key)
    }
  }

  // Mouse handling every entry shares: click selects, double click opens,
  // right click opens the item menu, dragging carries the selection to a
  // folder here or out to another app.
  component EntryMouse: MouseArea {
    id: entryMouse
    required property var entry
    required property int entryIndex
    required property Item dragItem

    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    drag.target: entry.trashName || root.renamePath === entry.path || Model.isArchiveLocation(entry.path) ? null : dragItem
    drag.threshold: Style.space(8)

    onClicked: function(mouse) {
      // Middle click opens a folder in a new tab, as Ctrl+double click does.
      if (mouse.button === Qt.MiddleButton) {
        root.openInNewTab(entryMouse.entry)
        return
      }
      if (mouse.button === Qt.RightButton) {
        if (root.selected.indexOf(entryMouse.entry.path) < 0) root.clickEntry(entryMouse.entryIndex, 0)
        else root.cursorIndex = entryMouse.entryIndex
        var p = mapToItem(null, mouse.x, mouse.y)
        root.openMenu(root.itemMenuFor(entryMouse.entry), p.x, p.y, entryMouse.entry)
      } else {
        root.clickEntry(entryMouse.entryIndex, mouse.modifiers)
      }
    }
    onDoubleClicked: function(mouse) {
      if (mouse.button !== Qt.LeftButton || root.renamePath !== "") return
      if ((mouse.modifiers & Qt.ControlModifier) && (entryMouse.entry.dir || Model.isArchive(entryMouse.entry))) root.openInNewTab(entryMouse.entry)
      else root.openEntry(entryMouse.entry)
    }
    drag.onActiveChanged: {
      if (!drag.active) return
      if (root.selected.indexOf(entryMouse.entry.path) < 0) root.clickEntry(entryMouse.entryIndex, 0)
      root.dragPaths = root.picked().map(function(e) { return e.path })
    }
  }

  // Invisible stand-in a row drags, so the row stays put while the system
  // carries the files.
  component DragCarrier: Item {
    id: carrier
    required property bool dragging
    // The entry pressed on, carried on its own if the drag starts before the
    // selection it belongs to is noted, and pictured under the pointer.
    required property var entry
    width: 1
    height: 1
    Drag.active: dragging
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.MoveAction | Qt.CopyAction
    Drag.proposedAction: Qt.MoveAction
    Drag.mimeData: Model.dragData(root.dragPaths.length > 0 ? root.dragPaths : [entry.path])
    Drag.imageSource: Quickshell.iconPath(Model.dragIcon(entry), "text-x-generic")
    Drag.onDragFinished: function(action) {
      root.dragPaths = []
      carrier.x = 0
      carrier.y = 0
    }
  }

  component EntryRow: Item {
    id: row
    required property var entry
    required property int entryIndex
    required property color foreground
    required property real nameWidth
    required property real whereWidth
    required property real typeWidth
    required property real sizeWidth
    required property real dateWidth

    readonly property bool isSelected: root.selected.indexOf(entry.path) >= 0
    readonly property bool isCursor: root.cursorIndex === entryIndex
    readonly property bool isCut: root.clipboard !== null && root.clipboard.mode === "cut" && root.clipboard.paths.indexOf(entry.path) >= 0
    readonly property bool renaming: root.renamePath === entry.path

    CursorSurface {
      anchors.fill: parent
      foreground: row.foreground
      current: row.isSelected
      hasCursor: row.isCursor || mouse.containsMouse || drop.containsDrag
      outline: row.isCursor
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)
      opacity: row.isCut ? 0.45 : (row.entry.hidden ? 0.7 : 1)

      Text {
        width: Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Model.kindIcon(row.entry.kind)
        color: row.entry.dir ? Color.accent : row.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Item {
        width: row.nameWidth
        height: parent.height

        Text {
          visible: !row.renaming
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.entry.name
          color: row.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: row.entry.dir
          elide: Text.ElideMiddle
        }

        // A text field is the heaviest thing a row could carry; only the
        // row being renamed gets one.
        Loader {
          active: row.renaming
          anchors.fill: parent
          anchors.topMargin: 1
          anchors.bottomMargin: 1
          sourceComponent: Component {
            RenameField {
              active: true
              entry: row.entry
              foreground: row.foreground
            }
          }
        }
      }

      Text {
        visible: row.whereWidth > 0
        width: row.whereWidth
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.prettyPath(row.entry.trashName ? Model.parentPath(row.entry.origin) : Model.parentPath(row.entry.path), root.home)
        color: row.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Text {
        visible: row.typeWidth > 0
        width: row.typeWidth
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.entry.type
        color: row.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: row.sizeWidth
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: Model.formatSize(row.entry.size)
        color: row.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: row.dateWidth
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: Model.formatDate(row.entry.modified, Date.now())
        color: row.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    EntryMouse {
      id: mouse
      entry: row.entry
      entryIndex: row.entryIndex
      dragItem: carrier
      enabled: !row.renaming
    }

    DragCarrier {
      id: carrier
      dragging: mouse.drag.active
      entry: row.entry
    }

    DropArea {
      id: drop
      anchors.fill: parent
      keys: ["text/uri-list"]
      enabled: row.entry.dir && !row.entry.trashName && !Model.isArchiveLocation(row.entry.path) && root.dragPaths.indexOf(row.entry.path) < 0
      onDropped: function(event) {
        if (root.dropUrls(event.urls, row.entry.path, event.proposedAction === Qt.CopyAction)) event.accept()
      }
    }
  }

  // The inline name editor: the name minus its extension starts selected,
  // Enter renames, Esc keeps the old name; a clash or a bad name says why on
  // the footer's error line.
  component RenameField: TextField {
    id: field
    required property var entry
    required property bool active

    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    verticalPadding: 0

    onActiveChanged: {
      if (!active) return
      text = entry.name
      Qt.callLater(function() {
        field.forceActiveFocus()
        var dot = field.entry.dir ? -1 : field.text.lastIndexOf(".")
        field.select(0, dot > 0 ? dot : field.text.length)
      })
    }
    Component.onCompleted: if (active) activeChanged()

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.cancelRename()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.commitRename(field.text)
        event.accepted = true
      }
    }
    onTextEdited: root.renameError = ""
  }

  // The grid view: a tile per entry, with the picture itself for images.
  component GridPane: Item {
    id: gridPane
    required property color foreground
    required property bool shown

    GridView {
      id: grid
      anchors.fill: parent
      anchors.margins: Style.space(6)
      clip: true
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      cellWidth: Math.floor(width / Math.max(1, Math.floor(width / Style.space(124))))
      cellHeight: Style.space(124)
      model: gridPane.shown ? root.entries.length : 0
      reuseItems: true
      currentIndex: root.cursorIndex
      highlightFollowsCurrentItem: false

      property real keptY: 0
      Connections {
        target: root
        function onListingWillChange() { grid.keptY = grid.contentY }
        function onListingChanged() { grid.contentY = grid.keptY }
      }

      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
      onWidthChanged: if (gridPane.shown) root.gridColumns = Math.max(1, Math.floor(width / cellWidth))
      onVisibleChanged: if (visible) root.gridColumns = Math.max(1, Math.floor(width / cellWidth))

      delegate: Item {
        id: tile
        required property int index
        readonly property var entry: root.entries[index] || root.blankEntry
        width: grid.cellWidth
        height: grid.cellHeight

        readonly property bool isSelected: root.selected.indexOf(entry.path) >= 0
        readonly property bool isCursor: root.cursorIndex === index
        readonly property bool isCut: root.clipboard !== null && root.clipboard.mode === "cut" && root.clipboard.paths.indexOf(entry.path) >= 0
        readonly property bool renaming: root.renamePath === entry.path
        // Pictures and a PDF's first page come from the file; video, audio,
        // documents and fonts from a system thumbnailer, asked for as the
        // tile shows.
        readonly property string kind: Model.isArchiveLocation(entry.path) ? "none" : Model.previewKind(entry)
        readonly property bool wantsThumbnail: kind === "thumbnail" || (kind === "pdf" && thumb.status === Image.Error)
        readonly property string thumbKey: wantsThumbnail ? Model.thumbnailKey(entry, 256) : ""
        readonly property string thumbPath: thumbKey !== "" ? (root.thumbnails[thumbKey] || "") : ""

        onThumbKeyChanged: if (thumbKey !== "") root.requestThumbnail(entry, 256)

        CursorSurface {
          anchors.fill: parent
          anchors.margins: Style.space(3)
          foreground: gridPane.foreground
          current: tile.isSelected
          hasCursor: tile.isCursor || tileMouse.containsMouse || tileDrop.containsDrag
          outline: tile.isCursor
        }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(4)
          opacity: tile.isCut ? 0.45 : (tile.entry.hidden ? 0.7 : 1)

          Item {
            width: parent.width
            height: parent.height - tileName.height - tileSub.height - parent.spacing * 2

            Image {
              id: thumb
              anchors.fill: parent
              visible: status === Image.Ready
              source: tile.kind === "image" || tile.kind === "pdf" ? Model.fileUrl(tile.entry.path) : ""
              currentFrame: 0
              sourceSize.width: Style.space(220)
              sourceSize.height: Style.space(160)
              fillMode: tile.kind === "pdf" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
              asynchronous: true
              cache: true
            }

            Image {
              id: tileThumb
              anchors.fill: parent
              visible: tile.wantsThumbnail && status === Image.Ready
              source: tile.thumbPath !== "" ? Model.fileUrl(tile.thumbPath) : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }

            Text {
              anchors.centerIn: parent
              visible: !thumb.visible && !tileThumb.visible
              textFormat: Text.PlainText
              text: Model.kindIcon(tile.entry.kind)
              color: tile.entry.dir ? Color.accent : gridPane.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          Item {
            id: tileName
            width: parent.width
            height: Style.space(20)

            Text {
              visible: !tile.renaming
              anchors.fill: parent
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: tile.entry.name
              color: gridPane.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            Loader {
              active: tile.renaming
              anchors.fill: parent
              sourceComponent: Component {
                RenameField {
                  active: true
                  entry: tile.entry
                  foreground: gridPane.foreground
                }
              }
            }
          }

          Text {
            id: tileSub
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: tile.entry.dir ? "Folder" : Model.formatSize(tile.entry.size)
            color: gridPane.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        EntryMouse {
          id: tileMouse
          entry: tile.entry
          entryIndex: tile.index
          dragItem: tileCarrier
          enabled: !tile.renaming
        }

        DragCarrier {
          id: tileCarrier
          dragging: tileMouse.drag.active
          entry: tile.entry
        }

        DropArea {
          id: tileDrop
          anchors.fill: parent
          keys: ["text/uri-list"]
          enabled: tile.entry.dir && !tile.entry.trashName && !Model.isArchiveLocation(tile.entry.path) && root.dragPaths.indexOf(tile.entry.path) < 0
          onDropped: function(event) {
            if (root.dropUrls(event.urls, tile.entry.path, event.proposedAction === Qt.CopyAction)) event.accept()
          }
        }
      }

      MouseArea {
        z: -1
        width: grid.width
        height: Math.max(grid.height, grid.contentHeight)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            var p = mapToItem(null, mouse.x, mouse.y)
            root.openMenu(root.folderMenu(), p.x, p.y, null)
          } else {
            root.selected = []
          }
        }
      }
    }

    StepScroll { flick: grid; pitch: grid.cellHeight; rowsPerNotch: 1 }
  }

  // The columns view: one column per folder from the root of the path down
  // to the folder on screen, which holds the cursor, then the folder under
  // the cursor, or the file's preview while the pane is off.
  component ColumnsPane: Item {
    id: columnsPane
    required property color foreground
    required property color background
    required property real rowHeight
    required property bool shown

    readonly property var chain: Model.crumbs(root.location, root.home, root.drives)
    readonly property real columnWidth: Style.space(190)
    // The column under the cursor's folder or file, faded in as it opens.
    property real trailOpacity: 1

    // As far right as the strip goes: the deepest columns in view. Worked
    // out when asked, since a binding may not have caught up yet inside
    // the strip's own change handler.
    function lastX() {
      return Math.max(0, columnsFlick.contentWidth - columnsFlick.width)
    }

    // A column or two opening or closing slides the strip there quickly,
    // the next column fading in; a jump further off lands at once.
    function slideTo(x) {
      var target = Math.max(0, Math.min(lastX(), x))
      slide.stop()
      if (Math.abs(target - columnsFlick.contentX) > columnWidth * 2) {
        columnsFlick.contentX = target
        trailOpacity = 1
        return
      }
      slideX.to = target
      fadeIn.from = target > columnsFlick.contentX ? 0 : trailOpacity
      slide.start()
    }

    // One column back (-1) or forward (1), from the column edge nearest.
    function stepColumns(count) {
      slideTo(Model.steppedScroll(columnsFlick.contentX, count, columnWidth, columnsFlick.contentWidth, columnsFlick.width))
    }

    ParallelAnimation {
      id: slide
      NumberAnimation { id: slideX; target: columnsFlick; property: "contentX"; duration: 120; easing.type: Easing.OutCubic }
      NumberAnimation { id: fadeIn; target: columnsPane; property: "trailOpacity"; to: 1; duration: 120 }
    }

    // Moving the cursor brings the deepest columns back after a scroll back.
    Connections {
      target: root
      function onCursorIndexChanged() {
        if (columnsPane.shown && columnsFlick.contentX < columnsPane.lastX()) columnsPane.slideTo(columnsPane.lastX())
      }
    }

    Flickable {
      id: columnsFlick
      anchors.fill: parent
      clip: true
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.HorizontalFlick
      contentWidth: columnsRow.width
      contentHeight: height
      // The deepest column, where the cursor is, stays in view.
      onContentWidthChanged: columnsPane.slideTo(columnsPane.lastX())


      Row {
        id: columnsRow
        height: columnsFlick.height

        Repeater {
          model: columnsPane.shown ? columnsPane.chain.slice(0, columnsPane.chain.length - 1) : []

          FolderColumn {
            required property var modelData
            required property int index
            width: columnsPane.columnWidth
            height: columnsRow.height
            folderPath: modelData.path
            openPath: columnsPane.chain[index + 1].path
            foreground: columnsPane.foreground
            rowHeight: columnsPane.rowHeight
            sideways: columnsFlick
          }
        }

        // The folder on screen, with the cursor and the selection.
        Item {
          width: columnsPane.columnWidth
          height: columnsRow.height

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            visible: root.entries.length === 0
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.emptyMessage
            color: columnsPane.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          ListView {
            id: currentColumn
            anchors.fill: parent
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            model: columnsPane.shown ? root.entries.length : 0
            reuseItems: true
            currentIndex: root.cursorIndex
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)


            delegate: Item {
              id: cell
              required property int index
              readonly property var entry: root.entries[index] || root.blankEntry
              width: currentColumn.width
              height: columnsPane.rowHeight

              readonly property bool renaming: root.renamePath === entry.path

              CursorSurface {
                anchors.fill: parent
                foreground: columnsPane.foreground
                current: root.selected.indexOf(cell.entry.path) >= 0
                hasCursor: root.cursorIndex === cell.index || cellMouse.containsMouse || cellDrop.containsDrag
                outline: root.cursorIndex === cell.index
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(6)
                opacity: cell.entry.hidden ? 0.7 : 1

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: Model.kindIcon(cell.entry.kind)
                  color: cell.entry.dir ? Color.accent : columnsPane.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Item {
                  width: parent.width - Style.space(36)
                  height: parent.height

                  Text {
                    visible: !cell.renaming
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: cell.entry.name
                    color: columnsPane.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideMiddle
                  }

                  Loader {
                    active: cell.renaming
                    anchors.fill: parent
                    sourceComponent: Component {
                      RenameField {
                        active: true
                        entry: cell.entry
                        foreground: columnsPane.foreground
                      }
                    }
                  }
                }

                Text {
                  visible: cell.entry.dir
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "›"
                  color: columnsPane.foreground
                  opacity: 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              EntryMouse {
                id: cellMouse
                entry: cell.entry
                entryIndex: cell.index
                dragItem: cellCarrier
                enabled: !cell.renaming
              }

              DragCarrier {
                id: cellCarrier
                dragging: cellMouse.drag.active
                entry: cell.entry
              }

              DropArea {
                id: cellDrop
                anchors.fill: parent
                keys: ["text/uri-list"]
                enabled: cell.entry.dir && !Model.isArchiveLocation(cell.entry.path) && root.dragPaths.indexOf(cell.entry.path) < 0
                onDropped: function(event) {
                  if (root.dropUrls(event.urls, cell.entry.path, event.proposedAction === Qt.CopyAction)) event.accept()
                }
              }
            }
          }

          StepScroll { flick: currentColumn; pitch: columnsPane.rowHeight; sideways: columnsFlick; sidePitch: columnsPane.columnWidth }

          Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: Qt.rgba(columnsPane.foreground.r, columnsPane.foreground.g, columnsPane.foreground.b, 0.12)
          }
        }

        // What is under the cursor: a folder's contents, or a file's preview.
        FolderColumn {
          visible: root.previewEntry !== null && root.previewEntry.dir
          opacity: columnsPane.trailOpacity
          width: visible ? Math.max(columnsPane.columnWidth, columnsPane.width - columnsRow.x - columnsPane.columnWidth * columnsPane.chain.length) : 0
          height: columnsRow.height
          folderPath: visible ? root.previewEntry.path : ""
          openPath: ""
          foreground: columnsPane.foreground
          rowHeight: columnsPane.rowHeight
          passive: true
          sideways: columnsFlick
        }

        PreviewPane {
          visible: root.previewEntry !== null && !root.previewEntry.dir && !root.showPreview
          opacity: columnsPane.trailOpacity
          width: visible ? Math.max(Style.space(230), columnsPane.width - columnsPane.columnWidth * columnsPane.chain.length) : 0
          height: columnsRow.height
          foreground: columnsPane.foreground
          entry: visible ? root.previewEntry : null
        }
      }
    }

    // Columns scrolled off to one side: a ‹ or › fading in at that edge
    // steps one column back into view.
    Repeater {
      model: columnsPane.shown ? [-1, 1] : []

      Item {
        id: edge
        required property int modelData
        readonly property bool back: modelData < 0
        visible: back ? columnsFlick.contentX > 1 : columnsFlick.contentX < columnsPane.lastX() - 1
        x: back ? 0 : columnsPane.width - width
        width: Style.space(26)
        height: columnsPane.height

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: edge.back ? columnsPane.background : Qt.rgba(columnsPane.background.r, columnsPane.background.g, columnsPane.background.b, 0) }
            GradientStop { position: 1; color: edge.back ? Qt.rgba(columnsPane.background.r, columnsPane.background.g, columnsPane.background.b, 0) : columnsPane.background }
          }
        }

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: edge.back ? "‹" : "›"
          color: edgeMouse.containsMouse ? Color.accent : columnsPane.foreground
          opacity: edgeMouse.containsMouse ? 1 : 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        MouseArea {
          id: edgeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: columnsPane.stepColumns(edge.modelData)
        }
      }
    }
  }

  // A folder listed in its own column: the ancestors to the left of the
  // folder on screen (the open child highlighted), or the folder under the
  // cursor (passive, dimmed). Clicking an entry goes there.
  component FolderColumn: Item {
    id: column
    required property string folderPath
    required property string openPath
    required property color foreground
    required property real rowHeight
    property bool passive: false
    // The columns view's flickable, moved sideways by a sideways wheel.
    property Flickable sideways: null

    property var columnEntries: []

    function snapshot() {
      var out = []
      for (var i = 0; i < columnModel.count; i++) {
        out.push(Model.makeEntry({
          path: columnModel.get(i, "filePath"),
          name: columnModel.get(i, "fileName"),
          dir: columnModel.get(i, "fileIsDir") === true,
          size: columnModel.get(i, "fileSize")
        }))
      }
      columnEntries = Model.sortEntries(Model.filterEntries(out, "", root.showHidden), root.sortKey, root.sortDescending)
    }

    FolderListModel {
      id: columnModel
      folder: column.folderPath !== "" ? Model.fileUrl(column.folderPath) : ""
      showDirsFirst: true
      showDotAndDotDot: false
      showHidden: true
      onStatusChanged: columnTimer.restart()
      onCountChanged: columnTimer.restart()
    }

    Timer {
      id: columnTimer
      interval: 40
      onTriggered: column.snapshot()
    }

    Connections {
      target: root
      function onShowHiddenChanged() { column.snapshot() }
      function onSortKeyChanged() { column.snapshot() }
      function onSortDescendingChanged() { column.snapshot() }
    }

    ListView {
      id: columnList
      anchors.fill: parent
      clip: true
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      model: column.columnEntries
      opacity: column.passive ? 0.7 : 1


      delegate: Item {
        id: item
        required property var modelData
        width: columnList.width
        height: column.rowHeight

        readonly property bool open: modelData.path === column.openPath

        CursorSurface {
          anchors.fill: parent
          foreground: column.foreground
          current: item.open
          hasCursor: itemMouse.containsMouse || itemDrop.containsDrag
        }

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Model.kindIcon(item.modelData.kind)
            color: item.modelData.dir ? Color.accent : column.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width - Style.space(36)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: item.modelData.name
            color: column.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: item.open
            elide: Text.ElideMiddle
          }

          Text {
            visible: item.modelData.dir
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "›"
            color: column.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        MouseArea {
          id: itemMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (item.modelData.dir) root.openFolder(item.modelData.path, root.newTabClick(mouse))
            else {
              root.pendingSelect = item.modelData.path
              root.go(column.folderPath)
            }
          }
        }

        DropArea {
          id: itemDrop
          anchors.fill: parent
          keys: ["text/uri-list"]
          enabled: item.modelData.dir
          onDropped: function(event) {
            if (root.dropUrls(event.urls, item.modelData.path, event.proposedAction === Qt.CopyAction)) event.accept()
          }
        }
      }
    }

    StepScroll { flick: columnList; pitch: column.rowHeight; sideways: column.sideways; sidePitch: column.width }

    Text {
      anchors.centerIn: parent
      visible: column.columnEntries.length === 0 && column.folderPath !== ""
      textFormat: Text.PlainText
      text: "Empty folder"
      color: column.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      anchors.right: parent.right
      width: 1
      height: parent.height
      color: Qt.rgba(column.foreground.r, column.foreground.g, column.foreground.b, 0.12)
    }
  }

  // The selected entry up close: the picture or the first lines of a text
  // file, its details, and what can be done with it.
  component PreviewPane: Item {
    id: previewRoot
    required property color foreground
    required property var entry

    readonly property bool hasEntry: entry !== null && entry !== undefined && entry.path !== ""
    readonly property string kind: Model.previewKind(entry)
    // A member of an archive is shown from its copy in the cache, made as it
    // is previewed; an archive inside an archive only shows its details.
    readonly property bool member: hasEntry && Model.isArchiveLocation(entry.path)
    readonly property bool needsContent: kind === "image" || kind === "pdf" || kind === "text" || kind === "thumbnail"
    readonly property string sourcePath: !hasEntry ? "" : (member ? (root.extracted[entry.path] || "") : entry.path)
    readonly property bool ready: sourcePath !== "" && (!member || needsContent)
    readonly property var listing: kind === "archive" && !member ? root.archives[entry.path] || null : null
    readonly property var summary: listing && listing.members ? Model.archiveSummary(listing.members, 40) : null
    readonly property bool textual: kind === "text"
    // null once the file turns out to be binary.
    readonly property var lines: textual ? Model.previewText(previewFile.text(), 40) : ""
    // Qt draws pictures and PDF pages itself; a PDF falls back to its cover
    // from a system thumbnailer when Qt's PDF reader is not installed, and
    // video, audio, documents and fonts always come from one.
    readonly property bool pdfFailed: kind === "pdf" && pageImage.status === Image.Error
    readonly property bool wantsThumbnail: ready && (kind === "thumbnail" || pdfFailed)
    readonly property string thumbKey: wantsThumbnail ? Model.thumbnailKey({ path: sourcePath, modified: entry.modified }, 512) : ""
    readonly property string thumbPath: thumbKey !== "" ? (root.thumbnails[thumbKey] || "") : ""
    readonly property bool media: kind === "image" || kind === "pdf" || kind === "thumbnail"

    onThumbKeyChanged: if (thumbKey !== "") root.requestThumbnail({ path: sourcePath, modified: entry.modified }, 512)
    // The bindings above may not have caught up with a new entry yet, so the
    // entry itself is read here.
    onEntryChanged: {
      if (!entry || !entry.path) return
      var kindNow = Model.previewKind(entry)
      var inside = Model.isArchiveLocation(entry.path)
      if (inside && (kindNow === "image" || kindNow === "pdf" || kindNow === "text" || kindNow === "thumbnail")) root.extractMember(entry, null)
      else if (kindNow === "archive" && !inside) root.loadArchive(entry.path, entry.modified, false)
    }

    FileView {
      id: previewFile
      path: previewRoot.textual && previewRoot.ready ? previewRoot.sourcePath : ""
      printErrors: false
      blockLoading: false
    }

    FolderListModel {
      id: previewFolder
      folder: previewRoot.hasEntry && previewRoot.entry.dir && !previewRoot.member ? Model.fileUrl(previewRoot.entry.path) : ""
      showHidden: root.showHidden
      showDotAndDotDot: false
    }

    Rectangle {
      anchors.left: parent.left
      width: 1
      height: parent.height
      color: Qt.rgba(previewRoot.foreground.r, previewRoot.foreground.g, previewRoot.foreground.b, 0.12)
    }

    Flickable {
      id: previewFlick
      anchors.fill: parent
      anchors.margins: Style.space(10)
      clip: true
      interactive: false
      contentHeight: previewColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds


      Column {
        id: previewColumn
        width: parent.width
        spacing: Style.space(10)

        Text {
          visible: !previewRoot.hasEntry
          textFormat: Text.PlainText
          text: "Nothing selected"
          color: previewRoot.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // The picture, the PDF page or the thumbnail, as large as the pane
        // allows, so files can be told apart at a glance.
        Item {
          id: mediaBox
          visible: previewRoot.hasEntry && !previewRoot.textual
          width: parent.width
          height: previewRoot.media ? Math.max(Style.space(150), Math.min(Style.space(360), previewRoot.height * 0.55)) : Style.space(110)

          Image {
            id: pageImage
            anchors.fill: parent
            visible: status === Image.Ready
            source: previewRoot.ready && (previewRoot.kind === "image" || previewRoot.kind === "pdf") ? Model.fileUrl(previewRoot.sourcePath) : ""
            currentFrame: previewRoot.kind === "pdf" ? Math.min(root.previewPage, Math.max(0, frameCount - 1)) : 0
            sourceSize.width: Math.round(mediaBox.width)
            sourceSize.height: Math.round(mediaBox.height)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            onFrameCountChanged: if (previewRoot.kind === "pdf") root.previewPages = frameCount
          }

          Image {
            id: thumbImage
            anchors.fill: parent
            visible: previewRoot.wantsThumbnail && status === Image.Ready
            source: previewRoot.thumbPath !== "" ? Model.fileUrl(previewRoot.thumbPath) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          Column {
            anchors.centerIn: parent
            visible: !pageImage.visible && !thumbImage.visible
            spacing: Style.space(6)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: previewRoot.hasEntry ? Model.kindIcon(previewRoot.entry.kind) : ""
              color: previewRoot.hasEntry && previewRoot.entry.dir ? Color.accent : previewRoot.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: (previewRoot.wantsThumbnail && previewRoot.thumbPath === "" && !(previewRoot.thumbKey in root.thumbnails)) || (previewRoot.member && previewRoot.needsContent && !previewRoot.ready)
              textFormat: Text.PlainText
              text: previewRoot.member && !previewRoot.ready ? "Taking it out of the archive…" : "Making a preview…"
              color: previewRoot.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Pages of a PDF: ‹ and › here, or < and > from the keyboard.
        Row {
          visible: previewRoot.kind === "pdf" && pageImage.visible && pageImage.frameCount > 1
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          IconButton { glyph: "󰅁"; tip: "Previous page (<)"; enabled: root.previewPage > 0; onClicked: root.stepPage(-1) }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Page " + (pageImage.currentFrame + 1) + " of " + pageImage.frameCount
            color: previewRoot.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          IconButton { glyph: "󰅂"; tip: "Next page (>)"; enabled: root.previewPage < pageImage.frameCount - 1; onClicked: root.stepPage(1) }
        }

        Text {
          visible: previewRoot.hasEntry
          width: parent.width
          textFormat: Text.PlainText
          text: previewRoot.hasEntry ? previewRoot.entry.name : ""
          color: previewRoot.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          wrapMode: Text.WrapAnywhere
        }

        // What an archive holds, without going in.
        Column {
          visible: previewRoot.kind === "archive" && !previewRoot.member
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: {
              var l = previewRoot.listing
              if (!l || (l.loading && !l.members)) return "Reading the archive…"
              if (l.error !== "" && (!l.members || l.members.length === 0)) return "Cannot read it: " + l.error
              var sum = previewRoot.summary
              return Model.plural(sum.files, "file") + ", " + Model.plural(sum.dirs, "folder") + " · " + Model.formatSize(sum.bytes) + " unpacked"
            }
            color: previewRoot.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          Rectangle {
            visible: previewRoot.summary !== null && previewRoot.summary.names.length > 0
            width: parent.width
            height: Math.min(Style.space(240), archiveNames.implicitHeight + Style.space(12))
            color: Qt.rgba(previewRoot.foreground.r, previewRoot.foreground.g, previewRoot.foreground.b, 0.05)
            border.width: 1
            border.color: Qt.rgba(previewRoot.foreground.r, previewRoot.foreground.g, previewRoot.foreground.b, 0.12)
            clip: true

            Text {
              id: archiveNames
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(6)
              textFormat: Text.PlainText
              text: previewRoot.summary ? previewRoot.summary.names.join("\n") + (previewRoot.summary.more > 0 ? "\n… and " + previewRoot.summary.more + " more" : "") : ""
              color: previewRoot.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }
        }

        Text {
          visible: previewRoot.textual && previewRoot.lines === null
          textFormat: Text.PlainText
          text: "Binary file, no text to show"
          color: previewRoot.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          visible: previewRoot.textual && previewRoot.lines !== null
          width: parent.width
          height: Math.min(Style.space(220), previewText.implicitHeight + Style.space(12))
          color: Qt.rgba(previewRoot.foreground.r, previewRoot.foreground.g, previewRoot.foreground.b, 0.05)
          border.width: 1
          border.color: Qt.rgba(previewRoot.foreground.r, previewRoot.foreground.g, previewRoot.foreground.b, 0.12)
          clip: true

          Text {
            id: previewText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(6)
            textFormat: Text.PlainText
            text: previewRoot.lines || ""
            color: previewRoot.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }
        }

        Grid {
          visible: previewRoot.hasEntry
          width: parent.width
          columns: 2
          columnSpacing: Style.space(10)
          rowSpacing: Style.space(3)

          Repeater {
            model: {
              var e = previewRoot.entry
              if (!e) return []
              var rows = [["Kind", e.type]]
              if (!e.dir) rows.push(["Size", Model.formatSize(e.size)])
              else if (!previewRoot.member) rows.push(["Contains", Model.plural(previewFolder.count, "item")])
              if (previewRoot.kind === "pdf" && pageImage.frameCount > 0) rows.push(["Pages", String(pageImage.frameCount)])
              if (isFinite(e.modified)) rows.push([e.trashName ? "Deleted" : "Modified", Model.formatFullDate(e.modified)])
              rows.push([e.trashName ? "From" : "Where", Model.prettyPath(Model.parentPath(e.trashName ? e.origin : e.path), root.home)])
              var flat = []
              for (var i = 0; i < rows.length; i++) flat.push({ text: rows[i][0], key: true }, { text: rows[i][1], key: false })
              return flat
            }

            Text {
              required property var modelData
              width: modelData.key ? Style.space(64) : previewColumn.width - Style.space(74)
              textFormat: Text.PlainText
              text: modelData.text
              color: previewRoot.foreground
              opacity: modelData.key ? 0.5 : 0.9
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }
        }

        Row {
          visible: previewRoot.hasEntry
          width: parent.width
          spacing: Style.space(6)

          readonly property var buttons: {
            var e = previewRoot.entry
            if (!e) return []
            if (e.trashName) return [{ id: "restore", label: "Restore" }, { id: "purge", label: "Delete" }]
            if (previewRoot.member) return [{ id: "open", label: "Open" }, { id: "copy", label: "Copy out" }]
            if (Model.isArchive(e)) return [{ id: "open", label: "Browse" }, { id: "extracthere", label: "Extract here" }]
            if (e.dir) return [{ id: "open", label: "Open" }, { id: "opentab", label: "In new tab" }]
            return [{ id: "open", label: "Open" }, { id: "openwith", label: "Open with" }]
          }

          Repeater {
            model: parent.buttons

            Button {
              required property var modelData
              width: (previewColumn.width - Style.space(6)) / 2
              height: Style.spacing.controlHeight
              text: modelData.label
              fontSize: Style.font.bodySmall
              foreground: previewRoot.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.run(modelData.id, previewRoot.entry)
            }
          }
        }
      }
    }

    StepScroll { flick: previewFlick; pitch: Style.space(20) }
  }

  // The window's sidebar: the standard folders, the bookmarks Nautilus
  // shares, drives with their free space and eject or mount, Recent and
  // the Trash. Folders take drops.
  component Sidebar: Item {
    id: side
    required property color foreground

    Flickable {
      id: sideFlick
      anchors.fill: parent
      clip: true
      interactive: false
      contentHeight: sideColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: sideColumn
        width: side.width
        spacing: Style.space(2)

        PanelSectionHeader { text: "PLACES"; foreground: side.foreground; fontFamily: root.fontFamily }
        Repeater {
          model: root.places
          SideRow { required property var modelData; glyph: modelData.icon; label: modelData.label; path: modelData.path; foreground: side.foreground }
        }

        Item { width: 1; height: Style.space(8) }
        PanelSectionHeader { visible: root.bookmarks.length > 0; text: "BOOKMARKS"; foreground: side.foreground; fontFamily: root.fontFamily }
        Repeater {
          model: root.bookmarks
          SideRow { required property var modelData; glyph: Model.GLYPHS.bookmark; label: modelData.label; path: modelData.path; foreground: side.foreground }
        }

        Item { width: 1; height: Style.space(8) }
        PanelSectionHeader { text: "DRIVES"; foreground: side.foreground; fontFamily: root.fontFamily }
        Repeater {
          model: root.drives
          SideRow {
            required property var modelData
            glyph: modelData.removable ? Model.GLYPHS.removable : Model.GLYPHS.drive
            label: modelData.name
            path: modelData.mount
            drive: modelData
            detail: modelData.mount ? Model.formatSize(modelData.avail) + " free" : "not mounted"
            foreground: side.foreground
          }
        }

        Item { width: 1; height: Style.space(8) }
        PanelSectionHeader { text: "MORE"; foreground: side.foreground; fontFamily: root.fontFamily }
        SideRow { glyph: Model.GLYPHS.recent; label: "Recent"; path: Model.RECENT; foreground: side.foreground }
        SideRow { glyph: Model.GLYPHS.trash; label: "Trash"; path: Model.TRASH; detail: root.placesData.trashCount > 0 ? String(root.placesData.trashCount) : ""; foreground: side.foreground }
      }
    }

    StepScroll { flick: sideFlick; pitch: Style.space(30) }
  }

  component SideRow: CursorSurface {
    id: sideRow
    required property string glyph
    required property string label
    required property string path
    property var drive: null
    property string detail: ""

    width: parent ? parent.width : 0
    height: Style.space(28)
    current: path !== "" && root.location === path
    hasCursor: sideMouse.containsMouse || sideDrop.containsDrag
    opacity: drive && !drive.mount ? 0.6 : 1

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: sideRow.glyph
        color: sideRow.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(26) - sideDetail.width - sideEject.width - parent.spacing * 2
        textFormat: Text.PlainText
        text: sideRow.label
        color: sideRow.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        id: sideDetail
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: sideRow.detail
        color: sideRow.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: sideEject
        anchors.verticalCenter: parent.verticalCenter
        visible: sideRow.drive !== null && sideRow.drive.removable && sideRow.drive.mount !== ""
        width: visible ? implicitWidth : 0
        textFormat: Text.PlainText
        text: Model.GLYPHS.eject
        color: ejectMouse.containsMouse ? Color.accent : sideRow.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body

        MouseArea {
          id: ejectMouse
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.ejectDrive(sideRow.drive)
        }
      }
    }

    MouseArea {
      id: sideMouse
      anchors.fill: parent
      z: -1
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      // Ctrl+click or a middle click opens the place in a new tab.
      onClicked: function(mouse) {
        if (sideRow.drive) root.openDrive(sideRow.drive, root.newTabClick(mouse))
        else root.openFolder(sideRow.path, root.newTabClick(mouse))
      }
    }

    DropArea {
      id: sideDrop
      anchors.fill: parent
      keys: ["text/uri-list"]
      enabled: sideRow.path !== "" && !Model.isVirtual(sideRow.path)
      onDropped: function(drop) {
        if (root.dropUrls(drop.urls, sideRow.path, drop.proposedAction === Qt.CopyAction)) drop.accept()
      }
    }
  }

  // The progress line of a long copy or move, with Cancel.
  component ProgressLine: Item {
    id: progress
    required property color foreground
    height: Style.spacing.controlHeight

    readonly property real fraction: root.task && root.task.total > 0 ? Math.min(1, root.task.done / root.task.total) : 0

    Row {
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        id: progressLabel
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, progress.width * 0.4)
        textFormat: Text.PlainText
        text: root.task ? root.task.label : ""
        color: progress.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - progressLabel.width - progressFigure.width - cancelButton.width - parent.spacing * 3
        height: Style.space(4)
        color: Qt.rgba(progress.foreground.r, progress.foreground.g, progress.foreground.b, 0.15)

        Rectangle {
          height: parent.height
          width: parent.width * progress.fraction
          color: Color.accent
          Behavior on width { NumberAnimation { duration: 200 } }
        }
      }

      Text {
        id: progressFigure
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.task && root.task.total > 0 ? Model.formatSize(root.task.done) + " of " + Model.formatSize(root.task.total) : "working…"
        color: progress.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        id: cancelButton
        anchors.verticalCenter: parent.verticalCenter
        height: Style.spacing.controlHeight
        width: Style.space(84)
        iconText: "󰅖"
        text: "Cancel"
        fontSize: Style.font.caption
        foreground: progress.foreground
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.cancelTransfer()
      }
    }
  }

  // Short-lived note at the bottom, with Undo after a move to the Trash.
  component Toast: BorderSurface {
    id: toastCard
    required property color foreground
    required property color background
    visible: root.toast !== null
    z: 20
    color: background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    padding: Style.space(8)
    width: Math.min(parent.width - Style.space(40), toastRow.implicitWidth + toastCard.contentLeftInset + toastCard.contentRightInset)
    height: toastRow.implicitHeight + toastCard.contentTopInset + toastCard.contentBottomInset

    Row {
      id: toastRow
      anchors.centerIn: parent
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, toastCard.parent.width - Style.space(160))
        textFormat: Text.PlainText
        text: root.toast ? root.toast.text : ""
        color: toastCard.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Button {
        visible: root.toast !== null && root.toast.undo !== null
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(22)
        width: Style.space(70)
        iconText: "󰕌"
        text: "Undo"
        fontSize: Style.font.caption
        foreground: toastCard.foreground
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.undoTrash(root.toast.undo)
      }
    }
  }

  // The `g` "go to" card: a key per place, the way yazi spells them out.
  component GoMenu: BorderSurface {
    id: goCard
    required property color foreground
    required property color background
    visible: root.goMenuOpen
    z: 20
    color: background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    padding: Style.space(10)
    width: Math.min(parent.width - Style.space(40), Style.space(440))
    height: goGrid.implicitHeight + goTitle.implicitHeight + Style.space(6) + goCard.contentTopInset + goCard.contentBottomInset

    readonly property var targets: Model.goTargets(root.places, root.bookmarks, root.drives)

    PanelSectionHeader {
      id: goTitle
      x: goCard.contentLeftInset
      y: goCard.contentTopInset
      text: "G · GO TO"
      foreground: goCard.foreground
      fontFamily: root.fontFamily
    }

    Grid {
      id: goGrid
      x: goCard.contentLeftInset
      y: goTitle.y + goTitle.implicitHeight + Style.space(6)
      width: goCard.width - goCard.contentLeftInset - goCard.contentRightInset
      columns: 2
      columnSpacing: Style.space(18)
      rowSpacing: Style.space(4)

      Repeater {
        model: goCard.targets

        Item {
          required property var modelData
          width: (goGrid.width - goGrid.columnSpacing) / 2
          height: Style.space(20)

          Row {
            anchors.fill: parent
            spacing: Style.space(8)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: Style.space(18)
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(goCard.foreground.r, goCard.foreground.g, goCard.foreground.b, 0.3)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.key
                color: goCard.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.icon + "  " + modelData.label
              color: goCard.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width - Style.space(28)
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              root.goMenuOpen = false
              root.openFolder(modelData.path, root.newTabClick(mouse))
            }
          }
        }
      }
    }
  }

  // Context, ⋮ and "Open with" menus, at the pointer or, from the
  // keyboard, in the middle. A click outside closes it.
  component MenuCard: Item {
    id: menuLayer
    required property color foreground
    required property color background
    visible: root.menu !== null
    z: 25

    readonly property real cardWidth: Style.space(250)
    readonly property real itemHeight: Style.space(26)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.menu = null
    }

    BorderSurface {
      id: menuCard
      color: menuLayer.background
      borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      padding: Style.space(4)
      width: menuLayer.cardWidth
      height: (root.menu ? root.menu.items.length : 0) * menuLayer.itemHeight + menuCard.contentTopInset + menuCard.contentBottomInset
      readonly property var place: {
        if (!root.menu || root.menu.x < 0) return { x: (menuLayer.width - width) / 2, y: (menuLayer.height - height) / 2 }
        var p = menuLayer.mapFromItem(null, root.menu.x, root.menu.y)
        return Model.menuPosition(p.x, p.y, width, height, menuLayer.width, menuLayer.height, root.menu.alignRight)
      }
      x: place.x
      y: place.y

      MouseArea { anchors.fill: parent }

      Column {
        x: menuCard.contentLeftInset
        y: menuCard.contentTopInset
        width: menuCard.width - menuCard.contentLeftInset - menuCard.contentRightInset

        Repeater {
          model: root.menu ? root.menu.items : []

          CursorSurface {
            id: menuItem
            required property var modelData
            required property int index
            width: parent.width
            height: menuLayer.itemHeight
            foreground: menuLayer.foreground
            hasCursor: root.menuIndex === index
            opacity: modelData.disabled ? 0.35 : 1

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                textFormat: Text.PlainText
                text: menuItem.modelData.icon || ""
                color: menuItem.modelData.danger ? Color.urgent : menuLayer.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(24) - menuShortcut.width - parent.spacing
                textFormat: Text.PlainText
                text: menuItem.modelData.label
                color: menuItem.modelData.danger ? Color.urgent : menuLayer.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: menuShortcut
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: menuItem.modelData.shortcut || ""
                color: menuLayer.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              enabled: !menuItem.modelData.disabled
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.menuIndex = menuItem.index
              onClicked: root.run(menuItem.modelData.id, root.menu ? root.menu.entry : null)
            }
          }
        }
      }
    }
  }

  // `?`: every key on one sheet.
  component KeySheet: BorderSurface {
    id: sheet
    required property color foreground
    required property color background
    visible: root.keysOpen
    z: 30
    color: background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    padding: Style.space(14)

    MouseArea { anchors.fill: parent; onClicked: root.keysOpen = false }

    PanelSectionHeader {
      id: sheetTitle
      x: sheet.contentLeftInset
      y: sheet.contentTopInset
      text: "KEYS · VIM AND NAUTILUS · ESC OR ? CLOSES"
      foreground: sheet.foreground
      fontFamily: root.fontFamily
    }

    Grid {
      x: sheet.contentLeftInset
      y: sheetTitle.y + sheetTitle.implicitHeight + Style.space(8)
      width: sheet.width - sheet.contentLeftInset - sheet.contentRightInset
      columns: 2
      columnSpacing: Style.space(24)
      rowSpacing: Style.space(3)

      Repeater {
        model: Model.KEYS

        Row {
          required property var modelData
          width: (sheet.width - sheet.contentLeftInset - sheet.contentRightInset - Style.space(24)) / 2
          spacing: Style.space(10)

          Text {
            width: Style.space(150)
            textFormat: Text.PlainText
            text: modelData[0]
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width - Style.space(160)
            textFormat: Text.PlainText
            text: modelData[1]
            color: sheet.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A question with a text field: the folder to extract into, or the name
  // of a new archive. Enter goes ahead, Esc or a click outside cancels, a
  // name that will not do says why.
  component PromptCard: Item {
    id: promptLayer
    required property color foreground
    required property color background
    visible: root.prompt !== null
    z: 16

    function focusField() {
      if (!root.prompt) return
      promptField.text = root.prompt.text
      promptField.forceActiveFocus()
      var dot = root.prompt.kind === "compress" ? promptField.text.indexOf(".") : -1
      promptField.select(0, dot > 0 ? dot : promptField.text.length)
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(promptLayer.background.r, promptLayer.background.g, promptLayer.background.b, 0.7)
      MouseArea { anchors.fill: parent; onClicked: root.cancelPrompt() }
    }

    BorderSurface {
      id: promptBox
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(32), Style.space(440))
      height: promptColumn.implicitHeight + promptBox.contentTopInset + promptBox.contentBottomInset
      color: promptLayer.background
      borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      padding: Style.space(18)

      MouseArea { anchors.fill: parent }

      Column {
        id: promptColumn
        x: promptBox.contentLeftInset
        y: promptBox.contentTopInset
        width: promptBox.width - promptBox.contentLeftInset - promptBox.contentRightInset
        spacing: Style.space(10)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.prompt ? root.prompt.title : ""
          color: promptLayer.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          wrapMode: Text.Wrap
        }

        TextField {
          id: promptField
          width: parent.width
          foreground: promptLayer.foreground
          font.family: root.fontFamily
          onTextEdited: if (root.prompt && root.prompt.error !== "") root.setPromptError("")
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancelPrompt()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.commitPrompt(promptField.text)
              event.accepted = true
            }
          }
        }

        Text {
          visible: root.prompt !== null && root.prompt.error !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.prompt ? root.prompt.error : ""
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Row {
          anchors.right: parent.right
          spacing: Style.space(8)

          Button {
            width: Style.space(96)
            height: Style.spacing.controlHeight
            text: "Cancel"
            fontSize: Style.font.bodySmall
            foreground: promptLayer.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.cancelPrompt()
          }

          Button {
            width: Style.space(96)
            height: Style.spacing.controlHeight
            text: root.prompt ? root.prompt.confirm : ""
            fontSize: Style.font.bodySmall
            foreground: promptLayer.foreground
            fontFamily: root.fontFamily
            bordered: true
            active: true
            onClicked: root.commitPrompt(promptField.text)
          }
        }
      }
    }
  }

  // Ctrl+P: a field and the folders that fit it, the way an editor's quick
  // open looks. Up and Down choose, Enter opens (in a new tab with Ctrl), Esc
  // or a click outside closes.
  component JumpCard: Item {
    id: jumpLayer
    required property color foreground
    required property color background
    visible: root.jumpOpen
    z: 17

    readonly property real rowHeight: Style.space(30)
    // Where the pointer last was, so rows scrolling under a still pointer
    // do not take the pick from the arrow keys.
    property point pointer: Qt.point(-1, -1)

    function focusField() {
      jumpField.text = ""
      jumpField.forceActiveFocus()
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(jumpLayer.background.r, jumpLayer.background.g, jumpLayer.background.b, 0.7)
      MouseArea { anchors.fill: parent; onClicked: root.closeJump() }
    }

    BorderSurface {
      id: jumpBox
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.space(40)
      width: Math.min(parent.width - Style.space(32), Style.space(520))
      height: Math.min(parent.height - y - Style.space(16), jumpColumn.implicitHeight + jumpBox.contentTopInset + jumpBox.contentBottomInset)
      color: jumpLayer.background
      borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      padding: Style.space(10)

      MouseArea { anchors.fill: parent }

      Column {
        id: jumpColumn
        x: jumpBox.contentLeftInset
        y: jumpBox.contentTopInset
        width: jumpBox.width - jumpBox.contentLeftInset - jumpBox.contentRightInset
        spacing: Style.space(8)

        TextField {
          id: jumpField
          width: parent.width
          placeholderText: "Jump to a folder: type part of its name or path"
          foreground: jumpLayer.foreground
          font.family: root.fontFamily
          onTextChanged: root.setJumpQuery(text)
          Keys.onPressed: function(event) {
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            if (event.key === Qt.Key_Escape) root.closeJump()
            else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) root.moveJump(1)
            else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) root.moveJump(-1)
            else if (event.key === Qt.Key_PageDown) root.moveJump(8)
            else if (event.key === Qt.Key_PageUp) root.moveJump(-8)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.pickJump(root.jumpList[root.jumpIndex], ctrl)
            else return
            event.accepted = true
          }
        }

        Text {
          visible: root.jumpList.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: root.jumpQuery === "" ? "No folders yet: the ones you open, bookmark or use lately show here" : "No folder fits “" + root.jumpQuery + "”"
          color: jumpLayer.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Item {
          visible: root.jumpList.length > 0
          width: parent.width
          height: Math.min(root.jumpList.length, 10) * jumpLayer.rowHeight

          ListView {
            id: jumpView
            anchors.fill: parent
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            model: root.jumpList.length
            currentIndex: root.jumpIndex
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: CursorSurface {
              id: jumpRow
              required property int index
              readonly property var item: root.jumpList[index] || null
              width: jumpView.width
              height: jumpLayer.rowHeight
              foreground: jumpLayer.foreground
              hasCursor: root.jumpIndex === index

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: jumpRow.item ? jumpRow.item.icon : ""
                  color: jumpRow.item && jumpRow.item.source === "tab" ? Color.accent : jumpLayer.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  id: jumpLabel
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, parent.width * 0.4)
                  textFormat: Text.PlainText
                  text: jumpRow.item ? jumpRow.item.label : ""
                  color: jumpLayer.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(0, parent.width - Style.space(18) - parent.spacing * 3 - jumpLabel.width - jumpSource.width)
                  textFormat: Text.PlainText
                  text: jumpRow.item && jumpRow.item.source !== "typed" ? Model.prettyPath(jumpRow.item.path, root.home) : ""
                  color: jumpLayer.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }

                Text {
                  id: jumpSource
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: {
                    var it = jumpRow.item
                    if (!it) return ""
                    if (it.source === "tab") return "tab " + (it.tabIndex + 1)
                    if (it.source === "visited") return "opened"
                    if (it.source === "recent") return "recent"
                    if (it.source === "bookmark") return "bookmark"
                    return ""
                  }
                  color: jumpLayer.foreground
                  opacity: 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: jumpMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  var at = mapToItem(null, mouse.x, mouse.y)
                  if (at.x === jumpLayer.pointer.x && at.y === jumpLayer.pointer.y) return
                  jumpLayer.pointer = at
                  root.jumpIndex = jumpRow.index
                }
                onClicked: function(mouse) { root.pickJump(jumpRow.item, root.newTabClick(mouse)) }
              }
            }
          }

          StepScroll { flick: jumpView; pitch: jumpLayer.rowHeight }
        }
      }
    }
  }

  // A name already taken where the files are going: skip it, keep both
  // (the new one gets a "(copy)" name) or replace it (the old one goes to
  // the Trash), for this one or for the rest too.
  component ConflictCard: Item {
    id: conflict
    required property color foreground
    required property color background
    visible: root.conflictJob !== null
    z: 15

    property int choice: 1
    property bool all: false

    readonly property var choices: [
      { how: "skip", label: "Skip" },
      { how: "keep", label: "Keep both" },
      { how: "replace", label: "Replace" }
    ]

    function decide(index) {
      var how = choices[index].how
      var rest = all
      choice = 1
      all = false
      root.resolveConflict(how, rest)
    }

    function handleKey(event) {
      if (event.key === Qt.Key_Escape) root.cancelConflicts()
      else if (event.key === Qt.Key_Left || event.text === "h") choice = Math.max(0, choice - 1)
      else if (event.key === Qt.Key_Right || event.text === "l" || event.key === Qt.Key_Tab) choice = Math.min(2, choice + 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) decide(choice)
      else if (event.key === Qt.Key_Space || event.text === "a") all = !all
      else if (event.text === "s") decide(0)
      else if (event.text === "k") decide(1)
      else if (event.text === "r") decide(2)
      return true
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(conflict.background.r, conflict.background.g, conflict.background.b, 0.7)
      MouseArea { anchors.fill: parent; onClicked: root.cancelConflicts() }
    }

    BorderSurface {
      id: conflictBox
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(32), Style.space(420))
      height: conflictColumn.implicitHeight + conflictBox.contentTopInset + conflictBox.contentBottomInset
      color: conflict.background
      borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      padding: Style.space(18)

      MouseArea { anchors.fill: parent }

      Column {
        id: conflictColumn
        x: conflictBox.contentLeftInset
        y: conflictBox.contentTopInset
        width: conflictBox.width - conflictBox.contentLeftInset - conflictBox.contentRightInset
        spacing: Style.space(12)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.conflictJob ? root.conflictJob.name + " already exists in " + Model.placeLabel(root.transferJob.dest, root.home, root.places, root.drives) : ""
          color: conflict.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Skip this one, keep both (the new one is renamed), or replace it (the old one goes to the Trash)."
          color: conflict.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Item {
          width: allRow.implicitWidth
          height: allRow.implicitHeight

          Row {
            id: allRow
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: conflict.all ? "󰄲" : "󰄱"
              color: conflict.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Do this for the rest (Space)"
              color: conflict.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: conflict.all = !conflict.all
          }
        }

        Row {
          anchors.right: parent.right
          spacing: Style.space(8)

          Repeater {
            model: conflict.choices

            Button {
              required property var modelData
              required property int index
              width: Style.space(96)
              height: Style.spacing.controlHeight
              text: modelData.label
              fontSize: Style.font.bodySmall
              foreground: modelData.how === "replace" ? Color.urgent : conflict.foreground
              fontFamily: root.fontFamily
              bordered: true
              hasCursor: conflict.choice === index
              onClicked: conflict.decide(index)
              onHovered: function(h) { if (h) conflict.choice = index }
            }
          }
        }
      }
    }
  }
}
