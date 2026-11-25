import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
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
  // Space: the entry under the cursor in a large preview over the view.
  property bool lookOpen: false
  // f: the start of a name typed to find it, the way Explorer does.
  property bool finding: false
  property string findText: ""

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
  // Listings of folders seen lately, by path, so a folder shown again (in
  // the tab or as a column) is on screen at once while it is read again.
  property var listingCache: ({})
  // A column width while a divider is being dragged, 0 otherwise.
  property int columnDrag: 0
  // The sidebar's or the preview's width while its edge is being dragged,
  // 0 otherwise.
  property int sidebarDrag: 0
  property int previewDrag: 0
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
  // Where the members being copied out land in the staging folder, kept as
  // the copy starts: the clipboard may change while they are extracted.
  property var stagingPaths: []
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
  // A cancelled extraction into a folder that was there already keeps what
  // it wrote.
  property bool taskKept: false

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
  // What files.sh last applied of each integration (Model.INTEGRATIONS):
  // on, off, or nothing yet this start.
  property var applied: ({})
  // An app's Open or Save dialog on screen (Model.chooserRequest), the ones
  // waiting for it, and what it borrowed from the widget: its tabs, given
  // back when the dialog ends.
  property var chooser: null
  property var chooserQueue: []
  property var lent: null
  property int chooserFilter: 0
  property string chooserName: ""
  // Names already taken where the dialog saves: { paths, files }.
  property var chooserClash: null
  // The window hides and shows again around a dialog; that is not the user
  // closing it.
  property bool windowSwapping: false
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
  readonly property int columnWidth: Model.columnWidth(setting("columnWidth", Model.COLUMN_WIDTH))
  readonly property int sidebarWidth: Model.sidebarWidth(setting("sidebarWidth", Model.SIDEBAR_WIDTH))
  readonly property int previewWidth: Model.previewWidth(setting("previewWidth", Model.PREVIEW_WIDTH))
  readonly property int windowPreviewWidth: Model.previewWidth(setting("windowPreviewWidth", Model.PREVIEW_WINDOW_WIDTH), Model.PREVIEW_WINDOW_WIDTH)
  readonly property bool defaultManager: setting("defaultFileManager", false) === true
  readonly property bool fileChooser: setting("fileChooser", false) === true
  readonly property bool launcherEntry: setting("launcherEntry", false) === true
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
  readonly property bool shown: opened || detached || chooser !== null
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
  readonly property string emptyMessage: searchProc.running ? "Searching…" : reading ? "" : Model.emptyText(location, query, deep, Model.prettyPath(location, home))
  // A folder not read yet shows nothing, rather than "empty", until it is.
  readonly property bool reading: inFolder && listedFolder !== location
  readonly property bool columnsShown: view === "columns" && inFolder && !deep
  readonly property var cursorEntry: cursorIndex >= 0 && cursorIndex < entries.length ? entries[cursorIndex] : null
  // One long job at a time, from its first question (the names in the
  // way, a conflict to answer, an archive's listing) until it exits.
  readonly property bool busy: actionProc.running || transferProc.running || namesProc.running || conflictJob !== null || extractJob !== null
  readonly property var conflictJob: transferJob ? transferJob.jobs[Model.conflictIndex(transferJob.jobs)] || null : null
  readonly property string hintMode: {
    if (prompt) return "prompt"
    if (jumpOpen) return "jump"
    if (finding) return "find"
    if (renamePath !== "") return "rename"
    if (editingPath) return "path"
    if (filtering && filterFocused) return "filter"
    if (chooser) return "chooser"
    if (inArchive) return "archive"
    return inTrash ? "trash" : "browse"
  }

  // What a dialog answers with as things stand, in words: the files
  // picked, the folder, or the files saved.
  readonly property string chooserSummary: {
    if (!chooser) return ""
    var paths = Model.chooserPaths(chooser, location, chooserName, picked(), chooserFilter)
    if (chooser.kind === "savefiles") return Model.itemsLabel(chooser.files.length, chooser.files[0]) + " here"
    if (chooser.kind === "folder") return paths.length > 0 ? Model.prettyPath(paths[0], home) : "Open a folder"
    return paths.length > 0 ? paths.map(Model.baseName).join(", ") : "Nothing yet: pick a file"
  }

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // An icon sits centred in a box of one width with one gap before its
  // label, so labels start the same distance from their icons everywhere:
  // the sidebar, the menus, the path bar, the tabs and every view.
  readonly property real iconBox: Style.space(18)
  readonly property real iconGap: Style.space(6)

  // A view asks for focus on one of its fields, or on itself.
  signal focusRequested(string what)
  // Around a refresh of the folder on screen, so views keep their scroll.
  signal listingWillChange()
  signal listingChanged()
  // A move into a folder (1) or back out to one (-1), for the views to
  // slide the new folder in from that side.
  signal moved(int direction)
  // Another tab on screen, its folder fading in.
  signal tabShown()
  // A new tab, growing in at INDEX.
  signal tabAdded(int index)

  // ---- Motion -------------------------------------------------------------
  // Every animation runs Style.duration(ms) on Style.easeOut, the shell's:
  // Hyprland's own easeOutQuint, and 0 ms when Hyprland's animations are off.

  // Entries that came or went in the folder on screen: the rest settle
  // from where they were (places moved, by path) and the new ones fade in,
  // as settle runs from 1 down to 0.
  property var settleShifts: ({})
  property var arrived: ({})
  property real settle: 0
  // Entries on their way out (to the Trash, deleted, restored) fade while
  // the action runs; only just after they are marked does the fade animate.
  property var leaving: ({})
  property bool leavingFades: false
  // The tab shrinking away before it closes, and the moment it goes.
  property int closingTab: -1
  property bool tabsSnap: false

  // What changed between the listing BEFORE and the one on screen now
  // settles into place.
  function settleFrom(before) {
    var moves = Style.duration(140) > 0 ? Model.settleMoves(before, entries) : null
    if (!moves) return
    settleShifts = moves.shifts
    arrived = moves.arrived
    settleRun.restart()
  }

  function markLeaving(list) {
    var out = {}
    for (var i = 0; i < list.length; i++) out[list[i].path] = true
    leavingFades = true
    leaving = out
    leavingFadeTimer.restart()
    leavingClearTimer.stop()
  }

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
    lookOpen = false
    endFind()
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
    var direction = Model.moveDirection(location, target)
    updateTab(Model.navigateTab(tab, target))
    visited = Model.addVisited(visited, target, Model.VISITED_MAX)
    resetFolderState()
    refreshLocation()
    focusRequested("view")
    moved(direction)
  }

  function back() {
    if (!Model.canGoBack(tab)) return
    pendingSelect = location
    updateTab(Model.tabBack(tab))
    resetFolderState()
    refreshLocation()
    moved(-1)
  }

  function forward() {
    if (!Model.canGoForward(tab)) return
    updateTab(Model.tabForward(tab))
    resetFolderState()
    refreshLocation()
    moved(1)
  }

  function up() {
    var parent = Model.parentPath(location)
    if (parent === "") return
    // Out of the top of an archive, the cursor lands on the archive file.
    var from = inArchive && archiveAt.inner === "" ? archiveAt.archive : location
    // Set first: a folder seen lately is listed while going there.
    pendingSelect = from
    go(parent)
  }

  function newTab(path) {
    // A tab still shrinking away goes first, so it is the one that closes.
    if (closingTab >= 0) {
      closeTabTimer.stop()
      removeTab(closingTab)
    }
    var result = Model.addTab(tabs, activeTab, Model.newTab(path || location, view))
    if (result.tabs === tabs) {
      showToast("Close a tab first: " + Model.MAX_TABS + " is the most")
      return
    }
    setTabs(result.tabs, result.active)
    visited = Model.addVisited(visited, path || location, Model.VISITED_MAX)
    resetFolderState()
    refreshLocation()
    tabAdded(result.active)
    tabShown()
  }

  // The tab shrinks away first, then goes.
  function closeTab(index) {
    if (tabs.length <= 1) {
      showToast("The last tab stays open")
      return
    }
    if (closingTab >= 0) return
    if (Style.duration(160) <= 0) {
      removeTab(index)
      return
    }
    closingTab = index
    closeTabTimer.restart()
  }

  function removeTab(index) {
    closingTab = -1
    tabsSnap = true
    Qt.callLater(function() { root.tabsSnap = false })
    var wasActive = index === activeTab
    var result = Model.closeTab(tabs, index, activeTab)
    setTabs(result.tabs, result.active)
    if (wasActive) {
      resetFolderState()
      refreshLocation()
      tabShown()
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
    tabShown()
  }

  function setView(key) {
    updateTab(Model.withView(tab, key))
  }

  // Dragging a column divider sizes every column at once; the width is
  // kept when the divider is let go, or set outright by a double click.
  function resizeColumns(units) {
    columnDrag = Model.columnWidth(units)
  }

  function keepColumnWidth() {
    if (columnDrag <= 0) return
    setColumnWidth(columnDrag)
    columnDrag = 0
  }

  function setColumnWidth(units) {
    persistSettings({ columnWidth: Model.columnWidth(units) })
  }

  // The sidebar's edge and the preview's size them the same way, and a
  // double click puts the default width back. The preview keeps one width
  // in the popup and another in the window.
  function resizeSidebar(units) {
    sidebarDrag = Model.sidebarWidth(units)
  }

  function keepSidebarWidth() {
    if (sidebarDrag <= 0) return
    setSidebarWidth(sidebarDrag)
    sidebarDrag = 0
  }

  function setSidebarWidth(units) {
    persistSettings({ sidebarWidth: Model.sidebarWidth(units) })
  }

  function resizePreview(units) {
    previewDrag = Model.previewWidth(units)
  }

  function keepPreviewWidth(windowed) {
    if (previewDrag <= 0) return
    setPreviewWidth(previewDrag, windowed)
    previewDrag = 0
  }

  function setPreviewWidth(units, windowed) {
    if (windowed) persistSettings({ windowPreviewWidth: Model.previewWidth(units, Model.PREVIEW_WINDOW_WIDTH) })
    else persistSettings({ previewWidth: Model.previewWidth(units) })
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

  // Folders from other apps, Show in folder and the file manager keys come
  // here while the default file manager setting is on, apps' Open and Save
  // dialogs while the file chooser one is, and the window is in the app
  // launcher while that one is; each goes back when turned off. One run of
  // files.sh at a time; the last word wins.
  function syncIntegrations() {
    if (integrationProc.running) return
    var next = Model.nextIntegration({ "default": defaultManager, chooser: fileChooser, launcher: launcherEntry }, applied)
    if (!next) return
    var done = Object.assign({}, applied)
    done[next.name] = next.state
    applied = done
    integrationProc.command = [root.scriptPath, next.name, next.state]
    integrationProc.running = true
  }

  function saveTabs() {
    // A dialog's own tab is never saved; the widget's come back after it.
    if (chooser) return
    tabsDirty = false
    persistSettings({ tabs: Model.serializeTabs(tabs), activeTab: activeTab, recentFolders: visited })
  }

  // The saved tabs come back on start, and when shell.json is edited by hand.
  function loadTabs() {
    if (tabsDirty || chooser) return
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
      showListed()
      // The preview moves to the new folder at once, rather than staying a
      // moment on the entry the cursor had in the folder left behind.
      previewTimer.stop()
      previewEntry = cursorEntry
      freeTimer.restart()
    }
  }

  // A folder read lately shows at once from that reading, and one never
  // read shows nothing rather than the last folder's files; the folder
  // model's own read follows and changes only what changed.
  function showListed() {
    if (listedFolder === location) return
    var seen = listingCache[location]
    var cache = {}
    for (var i = 0; i < (seen || []).length; i++) cache[seen[i].path] = seen[i]
    entryCache = cache
    listedFolder = seen ? location : ""
    folderEntries = seen || []
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
    // Half read, the folder would show as empty or cut short.
    if (folderModel.status === FolderListModel.Loading) return
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
    listingCache = Model.rememberListing(listingCache, location, out)
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
    var before = entries
    listingWillChange()
    apply()
    if (path !== "" && pendingSelect === "") {
      var idx = Model.indexOfPath(entries, path)
      if (idx >= 0) {
        if (anchorIndex === cursorIndex) anchorIndex = idx
        cursorIndex = idx
      }
    }
    settleFrom(before)
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

  // The cursor on the entry asked for, once it is listed.
  function landPending() {
    if (pendingSelect === "") return
    var idx = Model.indexOfPath(entries, pendingSelect)
    if (idx < 0) return
    cursorIndex = idx
    anchorIndex = idx
    pendingSelect = ""
  }

  // A fresh listing keeps the cursor on the same entry, or lands it on the
  // one asked for; the selection drops what went away.
  onEntriesChanged: {
    landPending()
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
    else if (chooser) cancelChooser()
    else if (!detached) root.close()
  }

  // ---- Opening ----------------------------------------------------------

  function openEntry(entry) {
    if (!entry) return
    if (chooser && !entry.dir) {
      pickForChooser(entry)
      return
    }
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

  // In the app GIO picks, the default Open with marks: xdg-open, outside a
  // desktop it knows, hands a type without a default of its own (a log,
  // YAML, JSON) to a browser instead.
  function openFile(path) {
    Util.execArgv(["gio", "open", path])
    if (!detached) root.close()
  }

  // Enter on a selection: a folder opens in place, several files each open
  // in their own app.
  function openPicked(chosen) {
    var list = chosen || picked()
    if (list.length === 0) return
    if (chooser && !list[0].dir) {
      pickForChooser(list[0])
      return
    }
    if (list[0].trashName) {
      restore(list)
      return
    }
    if (list.length === 1 || list[0].dir) {
      openEntry(list[0])
      return
    }
    for (var i = 0; i < list.length && i < 12; i++) if (!list[i].dir && !Model.isArchiveLocation(list[i].path)) Util.execArgv(["gio", "open", list[i].path])
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

  function setClipboard(mode, chosen) {
    if (mode === "cut" && readOnly()) return
    var list = (chosen || picked()).filter(function(e) { return !e.trashName })
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

  // Copy path: the full paths of the selection, or of the item, one a line,
  // as text for a terminal, an editor or a chat. The files the widget had
  // on the clipboard are no longer there.
  function copyPaths() {
    var list = picked().filter(function(e) { return !Model.isArchiveLocation(e.path) })
    if (list.length === 0) return
    clipboard = null
    Util.execArgv([root.scriptPath, "clipboard-text", list.map(function(e) { return e.path }).join("\n")])
    showToast(list.length === 1 ? "Copied the path of " + list[0].name : "Copied " + list.length + " paths")
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
    transfer(clipboard.paths, pasteDest, clipboard.mode === "cut" ? "move" : "copy", clipboard.mode === "cut")
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
    stagingPaths = members.map(function(m) { return Model.joinPath(stage, Model.baseName(m)) })
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
    taskKept = false
    taskShown = false
    taskTimer.restart()
    transferProc.command = [root.scriptPath].concat(args)
    transferProc.running = true
  }

  // First the names already in the destination, so every conflict can be
  // asked about before anything is written. CUT, a paste of cut files that
  // leave the clipboard once moved, belongs to the transfer once accepted.
  function transfer(paths, dest, mode, cut) {
    if (Model.isVirtual(dest) || !dest) {
      showToast("Open a folder to paste into")
      return
    }
    if (!paths || paths.length === 0 || busy) {
      if (busy) showToast("Wait for the running copy or move to finish")
      return
    }
    pastingCut = cut === true
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
    stagingPaths = []
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
    if (r.kept) taskKept = true
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
  // Members taken out of the version before are taken out again when asked.
  function loadArchive(path, modified, force) {
    var held = archives[path]
    if (held && !force && (held.loading || modified === undefined || held.modified === modified)) return
    extracted = Model.withoutMembers(extracted, path)
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
      var staged = stagingPaths
      // After the extraction's process has fully let go.
      Qt.callLater(function() { root.transfer(staged, root.stagingDest, "move") })
      return
    }
    if (taskCancelled) showToast(finished.mode !== "extract" ? "Compression cancelled; nothing was written" : taskKept ? "Extraction cancelled; what it extracted so far stays" : "Extraction cancelled; what it made is gone")
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
    if (Model.LEAVES.indexOf(kind) >= 0 && context && context.entries) markLeaving(context.entries)
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

  function askPurge(chosen) {
    if (readOnly()) return
    var list = chosen || picked()
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
    // What stayed fades back in; what left is gone once the folder is read
    // again, by when the marks go too.
    if (Model.LEAVES.indexOf(job.kind) >= 0) {
      if (failed) markLeaving([])
      else leavingClearTimer.restart()
    }
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
      // Only what reached the Trash; a folder that failed is still there.
      for (i = 0; i < r.trashed.length; i++) list = Model.retargetTabs(list, r.trashed[i].path, "")
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

  // Space: the entry under the cursor up close, over the whole view. It
  // shows the preview's entry, which follows the cursor as j and k step.
  function openLook() {
    if (!cursorEntry) return
    previewTimer.stop()
    previewEntry = cursorEntry
    previewPage = 0
    menu = null
    goMenuOpen = false
    lookOpen = true
  }

  function closeLook() {
    lookOpen = false
  }

  // f, then the start of a name: the cursor goes to the first name that
  // starts that way, as typing does in Explorer, until a second passes with
  // nothing typed.
  function startFind() {
    finding = true
    findText = ""
    findTimer.restart()
  }

  function endFind() {
    finding = false
    findText = ""
    findTimer.stop()
  }

  function findTo(text) {
    findText = text
    findTimer.restart()
    var at = Model.typeAheadIndex(entries, text, cursorIndex)
    if (at >= 0) {
      cursorIndex = at
      anchorIndex = at
    }
  }

  // Letters add to the name and Backspace takes one back; Esc stops, and
  // Enter stops and opens what was found, whatever else is selected. Any
  // other key stops finding and does what it always does.
  function findKey(event) {
    var mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
    if (event.key === Qt.Key_Escape) endFind()
    else if (!mods && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      endFind()
      if (cursorEntry) openEntry(cursorEntry)
    }
    else if (event.key === Qt.Key_Backspace && findText !== "") findTo(findText.slice(0, -1))
    else if (event.key === Qt.Key_Backspace) endFind()
    else if (!mods && event.text.length === 1 && event.text >= " " && event.text !== "\u007f") findTo(findText + event.text)
    else {
      endFind()
      return false
    }
    return true
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
    // One check at a time: a folder asked for meanwhile waits its turn.
    if (pathCheckProc.running) {
      pathCheckProc.queued = { target: target, inNewTab: inNewTab === true }
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
    // A preview's buttons act on the entry it shows, which the cursor may
    // have left the selection for; menus and keys act on the selection.
    var chosen = Model.entriesFor(picked(), entry)
    switch (id) {
    case "open": openPicked(chosen); break
    case "opentab": openInNewTab(target); break
    case "openwith": openWith(target); break
    case "copy": setClipboard("copy", chosen); break
    case "cut": setClipboard("cut", chosen); break
    case "copypath": copyPaths(); break
    case "paste": paste(location); break
    case "pasteinto": if (target && target.dir) paste(target.path); break
    case "rename": startRename(target ? target.path : ""); break
    case "bookmark": toggleBookmark(target && target.dir && entry ? target.path : location); break
    case "trash": trashPicked(); break
    case "purge": askPurge(chosen); break
    case "restore": restore(chosen); break
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

  // The window to the front, on whichever workspace it is. Found by its
  // title, before it changes with the next folder.
  function raiseWindow() {
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      if (list[i].title !== window.title) continue
      var address = String(list[i].address)
      if (address.indexOf("0x") !== 0) address = "0x" + address
      Hyprland.dispatch('hl.dsp.focus({window = hl.get_window("address:' + address + '")})')
      return
    }
  }

  // A folder from another app or the file manager keys, in the popup or,
  // popped out, in the window brought to the front. With pick, the path is
  // an item to land on in its folder.
  function showPath(path, pick) {
    if (detached) raiseWindow()
    if (pick) {
      pendingSelect = path
      go(Model.parentPath(path))
      // In the folder on screen nothing new is listed to land on it.
      landPending()
    } else {
      go(path)
    }
    if (!detached) open()
  }

  // ---- File chooser -----------------------------------------------------

  // An app's Open or Save dialog from filechooser.py: shown now, or after
  // the one on screen. "ok" tells the service the widget took it.
  function chooseFor(id, raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (e) {
      return "error: " + e.message
    }
    var request = Model.chooserRequest(parsed, home)
    request.id = id
    if (chooser) chooserQueue = chooserQueue.concat([request])
    else startChooser(request)
    return "ok"
  }

  // The dialog borrows the widget's view: a tab of its own at the folder
  // the app suggests, in the window floated over the app. The widget's tabs
  // and window come back when it ends.
  function startChooser(request) {
    if (!lent) lent = { tabs: tabs, activeTab: activeTab, dirty: tabsDirty }
    if (opened) root.close()
    var shown = view
    chooser = request
    chooserFilter = request.filter
    chooserName = request.name
    chooserClash = null
    lastError = ""
    tabs = [Model.newTab(request.folder, shown)]
    activeTab = 0
    tabsDirty = false
    resetFolderState()
    refreshLocation()
    windowBuilt = true
    remapWindow(true)
  }

  // The window shows again under its new title, so Hyprland floats it as a
  // dialog or tiles it as the widget's window; or it goes.
  function remapWindow(show) {
    windowSwapping = true
    window.visible = false
    Qt.callLater(function() {
      root.windowSwapping = false
      if (!show) return
      window.visible = true
      root.focusRequested(root.chooser && root.chooser.kind === "save" ? "chooser" : "view")
    })
  }

  // The next dialog waiting, or the widget as it was.
  function endChooser() {
    chooser = null
    chooserClash = null
    lastError = ""
    if (chooserQueue.length > 0) {
      var next = chooserQueue[0]
      chooserQueue = chooserQueue.slice(1)
      startChooser(next)
      return
    }
    var was = lent
    lent = null
    if (was) {
      tabs = was.tabs
      activeTab = was.activeTab
      tabsDirty = was.dirty
    }
    resetFolderState()
    refreshLocation()
    remapWindow(detached)
  }

  // The answer goes back to the app through files.sh: the paths, with the
  // filter on screen, or nothing when cancelled.
  function answerChooser(response, paths) {
    if (!chooser) return
    var filter = response === 0 && chooser.filters.length > 0 ? chooserFilter : -1
    Util.execArgv([root.scriptPath, "chosen", chooser.id, String(response), String(filter)].concat(paths || []))
    endChooser()
  }

  function cancelChooser() {
    answerChooser(1, [])
  }

  // The app closed its dialog: it ends without an answer.
  function closeChooser(id) {
    chooserQueue = chooserQueue.filter(function(r) { return r.id !== id })
    if (chooser && chooser.id === id) endChooser()
  }

  // Save, Open or Select: the dialog answers with LIST (or what is picked),
  // once it can; a name already taken asks first.
  function acceptChooser(list) {
    if (!chooser) return
    var paths = Model.chooserPaths(chooser, location, chooserName, list || picked(), chooserFilter)
    var problem = Model.chooserProblem(chooser, location, chooserName, paths)
    if (problem !== "") {
      showToast(problem)
      return
    }
    if (chooser.kind === "save" || chooser.kind === "savefiles") {
      var clash = Model.chooserClash(folderEntries, paths)
      if (clash.folders.length > 0) {
        showToast(clash.folders[0] + " is a folder here")
        return
      }
      if (clash.files.length > 0) {
        chooserClash = { paths: paths, files: clash.files }
        // The card's keys go through the view, not the name.
        focusRequested("view")
        return
      }
    }
    answerChooser(0, paths)
  }

  // A name taken where the dialog saves: back to the dialog (skip), keep
  // both (the new ones get free names) or replace.
  function resolveChooserClash(how) {
    var clash = chooserClash
    chooserClash = null
    if (!clash) return
    if (how === "skip") {
      focusRequested(chooser && chooser.kind === "save" ? "chooser" : "view")
      return
    }
    answerChooser(0, how === "keep" ? Model.chooserKeepBoth(folderEntries, clash.paths) : clash.paths)
  }

  // Enter or a double click on a file: in a Save dialog its name is the one
  // to save as; otherwise it is what the dialog answers with, along with
  // the rest of the selection when it is part of it.
  function pickForChooser(entry) {
    if (chooser.kind === "save") {
      chooserName = entry.name
      focusRequested("chooser")
    } else if (Model.chooserPicks(chooser, chooserFilter, entry)) {
      acceptChooser(Model.entriesFor(picked(), entry))
    } else {
      showToast(chooser.kind === "folder" ? "Pick a folder" : "This dialog does not take " + entry.name)
    }
  }

  function nextChooserFilter() {
    if (chooser && chooser.filters.length > 0) chooserFilter = (chooserFilter + 1) % chooser.filters.length
  }

  // Files the dialog cannot take, faded the way hidden ones are.
  function chooserDims(entry) {
    return chooser !== null && !entry.dir && !Model.chooserPicks(chooser, chooserFilter, entry)
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

    if (finding && findKey(event)) return true
    // In a Save dialog, Tab goes to the name.
    if (chooser && key === Qt.Key_Tab && !ctrl && chooser.kind === "save") {
      focusRequested("chooser")
      return true
    }
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
      case Qt.Key_S: if (chooser) acceptChooser(null); return chooser !== null
      case Qt.Key_Space: toggleCursorSelection(); return true
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
    case Qt.Key_Space: openLook(); return true
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
    case "f": startFind(); return true
    case "g": goMenuOpen = true; return true
    case "e": startPathEdit(); return true
    case "i": togglePreview(); return true
    case ".": toggleHidden(); return true
    case "w": if (!chooser) toggleDetached(); return true
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
    function go(path: string): void { root.showPath(Model.expandPath(path, root.home, root.home), false) }
    function reveal(path: string): void { root.showPath(Model.expandPath(path, root.home, root.home), true) }
    // The file manager keys: the popup opens or closes, the window comes
    // to the front.
    function summon(): void {
      if (root.detached) root.raiseWindow()
      else root.toggle()
    }
    function popOut(): void { root.popOut() }
    function dock(): void { root.dock() }
    // From the app launcher: the window, shown or brought to the front.
    function window(): void {
      if (root.detached || root.chooser) root.raiseWindow()
      else root.popOut()
    }
    // An app's Open or Save dialog from filechooser.py, and the app closing
    // it; "ok" once the widget took it.
    function choose(id: string, request: string): string { return root.chooseFor(id, request) }
    function chooserClose(id: string): void { root.closeChooser(id) }
    function version(): string { return "0.1.0" }
  }

  Component.onCompleted: {
    loadTabs()
    refreshPlaces()
    // Applied again at every start, so the services run from then and the
    // settings win over shell.json edited by hand; off with nothing set up
    // changes nothing.
    syncIntegrations()
  }

  onSettingsChanged: loadTabs()

  onDefaultManagerChanged: syncIntegrations()
  onFileChooserChanged: syncIntegrations()
  onLauncherEntryChanged: syncIntegrations()

  onOpenedChanged: {
    // A dialog has the view: it comes to the front instead.
    if (opened && chooser) {
      root.close()
      raiseWindow()
      return
    }
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
      lookOpen = false
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

  NumberAnimation {
    id: settleRun
    target: root
    property: "settle"
    from: 1
    to: 0
    duration: Style.duration(140)
    easing.type: Easing.Bezier
    easing.bezierCurve: Style.easeOut
  }

  Timer {
    id: leavingFadeTimer
    interval: 250
    onTriggered: root.leavingFades = false
  }

  // Past the read that takes the entries out of the listing.
  Timer {
    id: leavingClearTimer
    interval: snapshotTimer.interval + 600
    onTriggered: root.leaving = ({})
  }

  Timer {
    id: closeTabTimer
    interval: Style.duration(160)
    onTriggered: root.removeTab(root.closingTab)
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

  // Finding stops a second after the last letter, or two when none came.
  Timer {
    id: findTimer
    interval: root.findText === "" ? 2000 : 1000
    onTriggered: root.endFind()
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
    // What a stopped search still prints belongs to the query before.
    stdout: SplitParser { onRead: function(line) { if (!root.searchRestart) root.searchBuffer.push(line) } }
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
    property var queued: null
    onExited: function(exitCode) {
      if (exitCode === 0) root.openFolder(target, inNewTab)
      else root.showToast("No folder at " + Model.prettyPath(target, root.home))
      var next = queued
      queued = null
      if (next) root.checkFolder(next.target, next.inNewTab)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyAction(text) }
  }

  Process {
    id: integrationProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var errors = Model.parseResult(text).errors
        if (errors.length === 0) return
        root.lastError = errors[errors.length - 1]
        root.showToast(root.lastError)
      }
    }
    // The next integration, or a setting changed again while this ran.
    onExited: root.syncIntegrations()
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
    // Under a dialog's title, the File chooser setting's rule has Hyprland
    // float it over the app that asked.
    title: root.chooser ? "Files chooser · " + root.chooser.title + (root.chooser.app ? " · " + root.chooser.app : "") : "Files · " + root.locationLabel
    color: Color.background
    implicitWidth: 1120
    implicitHeight: 700
    minimumSize: Qt.size(640, 420)

    // Closed from Hyprland rather than docked: the tabs stay for next time;
    // a dialog on screen is cancelled.
    onVisibleChanged: {
      if (visible || root.windowSwapping) return
      if (root.chooser) {
        root.cancelChooser()
        return
      }
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
          active: root.detached || root.chooser !== null
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

    readonly property bool typing: pathField.activeFocus || filterField.activeFocus || chooserField.activeFocus || root.renamePath !== "" || root.prompt !== null || root.jumpOpen
    readonly property real rowHeight: Style.space(26)
    // The widest the sidebar and the preview may be on screen, so the files
    // always keep some room.
    readonly property real sidebarRoom: Math.round(width / 3)
    readonly property real previewRoom: Math.max(0, body.width - 2 - Style.space(220))

    focus: true
    Keys.onPressed: function(event) {
      if (root.confirm) {
        if (confirmDialog.handleKey(event)) event.accepted = true
        else event.accepted = event.key !== Qt.Key_Tab
        return
      }
      if (root.conflictJob || root.chooserClash) {
        if (conflictCard.handleKey(event)) event.accepted = true
        return
      }
      if (root.lookOpen) {
        if (lookCard.handleKey(event)) event.accepted = true
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
        } else if (what === "chooser") {
          // The name with its stem picked, ready to be typed over.
          chooserField.text = root.chooserName
          chooserField.forceActiveFocus()
          var dot = root.chooserName.lastIndexOf(".")
          chooserField.select(0, dot > 0 ? dot : root.chooserName.length)
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

      function onMoved(direction) { viewRoot.slideIn(direction) }
      function onTabShown() { viewRoot.slideIn(0) }
    }

    // A new folder slides in from the side it comes from and fades in, or,
    // with another tab, only fades in. The columns slide on their own.
    function slideIn(direction) {
      if (!active || (direction !== 0 && views.shownKey === "columns")) return
      arriveShift.from = Style.space(24) * direction
      arriveShift.duration = Style.duration(170)
      arriveFade.duration = Style.duration(direction === 0 ? 120 : 170)
      arriveRun.restart()
    }

    // The item under the cursor, where the large preview grows from.
    function cursorRect() {
      if (views.shownKey === "grid") return gridView.cursorRect(viewRoot)
      if (views.shownKey === "columns") return columnsView.cursorRect(viewRoot)
      return listView.cursorRect(viewRoot)
    }

    onActiveChanged: if (active) Qt.callLater(function() { viewRoot.forceActiveFocus() })

    Row {
      anchors.fill: parent
      spacing: Style.space(10)

      // ---------- Places sidebar, once it is a window ----------
      Sidebar {
        id: sidebar
        visible: viewRoot.windowed
        width: viewRoot.windowed ? Math.min(Style.space(root.sidebarDrag || root.sidebarWidth), viewRoot.sidebarRoom) : 0
        height: parent.height
        foreground: viewRoot.foreground

        // Its edge fills the gap before the files.
        PaneEdge {
          anchors.left: parent.right
          width: Style.space(10)
          height: parent.height
          sizes: "sidebar"
          windowed: viewRoot.windowed
          limit: viewRoot.sidebarRoom
        }
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
            visible: !root.chooser
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
        Item {
          width: parent.width
          height: Style.spacing.controlHeight

          // The active tab's fill, gliding from tab to tab.
          CursorSurface {
            x: root.activeTab * (tabStrip.tabWidth + tabStrip.spacing)
            width: tabStrip.tabWidth
            height: parent.height
            foreground: viewRoot.foreground
            current: true
            opacity: root.closingTab === root.activeTab ? 0 : 1
            Behavior on x { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
            Behavior on width { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
            Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }
          }

          Row {
            id: tabStrip
            anchors.fill: parent
            spacing: Style.space(4)

            readonly property real addWidth: Style.spacing.controlHeight
            readonly property real tabWidth: Math.min(Style.space(200), (width - addWidth - spacing * root.tabs.length) / Math.max(1, root.tabs.length))

            // Counted rather than handed the list, so stepping through
            // folders updates the chips instead of building them again. A
            // new tab grows in, a closing one shrinks away, and the rest
            // make room.
            Repeater {
              model: root.tabs.length

              TabChip {
                id: tabChip
                required property int index
                property real grown: 1
                width: index === root.closingTab ? 0 : tabStrip.tabWidth * grown
                height: tabStrip.height
                clip: true
                tabData: root.tabs[index] || root.tab
                tabIndex: index
                foreground: viewRoot.foreground

                // As a tab goes the chips are counted again, each showing
                // the tab after it, so their widths land at once then.
                Behavior on width {
                  enabled: !growRun.running && !root.tabsSnap
                  NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
                }

                NumberAnimation {
                  id: growRun
                  target: tabChip
                  property: "grown"
                  from: 0
                  to: 1
                  duration: Style.duration(200)
                  easing.type: Easing.Bezier
                  easing.bezierCurve: Style.easeOut
                }

                Connections {
                  target: root
                  function onTabAdded(at) { if (at === tabChip.index) growRun.restart() }
                }
              }
            }

            IconButton { glyph: "󰐕"; tip: "New tab (Ctrl+T)"; onClicked: root.newTab("") }
          }
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

            Item {
              id: views
              anchors.fill: parent
              transform: Translate { id: viewsShift }

              // The view on screen: the list stands in for the columns
              // outside folders and in search results.
              readonly property string shownKey: root.view === "grid" ? "grid" : (root.columnsShown ? "columns" : "list")
              // The view going away fades out over the one coming in.
              property string goneKey: ""
              property string lastKey: ""
              property real incoming: 1
              property real outgoing: 0

              function alpha(key) {
                return key === shownKey ? incoming : (key === goneKey ? outgoing : 0)
              }

              onShownKeyChanged: {
                if (lastKey !== "" && viewRoot.active) {
                  goneKey = lastKey
                  swapRun.restart()
                }
                lastKey = shownKey
              }
              Component.onCompleted: lastKey = shownKey

              ParallelAnimation {
                id: swapRun
                NumberAnimation { target: views; property: "incoming"; from: 0; to: 1; duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
                NumberAnimation { target: views; property: "outgoing"; from: 1; to: 0; duration: Style.duration(120) }
                onFinished: views.goneKey = ""
              }

              ParallelAnimation {
                id: arriveRun
                NumberAnimation { id: arriveShift; target: viewsShift; property: "x"; to: 0; easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
                NumberAnimation { id: arriveFade; target: views; property: "opacity"; from: 0; to: 1; easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
              }

              ListPane {
                id: listView
                anchors.fill: parent
                visible: views.shownKey === "list" || views.goneKey === "list"
                opacity: views.alpha("list")
                enabled: views.shownKey === "list"
                foreground: viewRoot.foreground
                rowHeight: viewRoot.rowHeight
                shown: visible && viewRoot.active
              }

              GridPane {
                id: gridView
                anchors.fill: parent
                visible: views.shownKey === "grid" || views.goneKey === "grid"
                opacity: views.alpha("grid")
                enabled: views.shownKey === "grid"
                foreground: viewRoot.foreground
                shown: visible && viewRoot.active
              }

              ColumnsPane {
                id: columnsView
                anchors.fill: parent
                visible: views.shownKey === "columns" || views.goneKey === "columns"
                opacity: views.alpha("columns")
                enabled: views.shownKey === "columns"
                foreground: viewRoot.foreground
                background: viewRoot.background
                rowHeight: viewRoot.rowHeight
                shown: visible && viewRoot.active
              }
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
            width: Math.min(Style.space(root.previewDrag || (viewRoot.windowed ? root.windowPreviewWidth : root.previewWidth)), viewRoot.previewRoom)
            foreground: viewRoot.foreground
            entry: root.showPreview ? root.previewEntry : null

            PaneEdge {
              anchors.horizontalCenter: parent.left
              height: parent.height
              sizes: "preview"
              windowed: viewRoot.windowed
              limit: viewRoot.previewRoom
            }
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
            visible: root.chooser === null
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

          // An app's Open or Save dialog: the places saved in lately, then
          // the name (or what is picked), the file type, Cancel and the
          // app's own word for going ahead.
          Column {
            id: chooserBand
            visible: root.chooser !== null
            width: parent.width
            spacing: Style.space(6)

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: chooserBand.visible ? Model.chooserPlaces(root.location, root.visited, root.home) : []

                Button {
                  required property string modelData
                  height: Style.spacing.controlHeight
                  iconText: Model.placeIcon(modelData, root.home, root.places, root.drives)
                  iconSize: Style.font.body
                  text: Model.placeLabel(modelData, root.home, root.places, root.drives)
                  fontSize: Style.font.bodySmall
                  foreground: viewRoot.foreground
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.spacing.sm
                  bordered: true
                  hasCursor: modelData === root.location
                  onClicked: root.go(modelData)
                }
              }
            }

            Row {
              id: chooserRow
              width: parent.width
              spacing: Style.space(6)

              readonly property real buttonWidth: Style.space(96)
              readonly property real fieldWidth: width - chooserLabel.width - (filterButton.visible ? filterButton.width + spacing : 0) - (buttonWidth + spacing) * 2 - spacing

              Text {
                id: chooserLabel
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: !root.chooser ? "" : root.chooser.kind === "save" ? "Name" : root.chooser.kind === "folder" ? "Folder" : root.chooser.kind === "savefiles" ? "Saving" : "Picked"
                color: viewRoot.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              TextField {
                id: chooserField
                visible: root.chooser !== null && root.chooser.kind === "save"
                width: chooserRow.fieldWidth
                height: Style.spacing.controlHeight
                // The stem stays picked while the window takes the focus,
                // and the highlight goes once the name is left for the
                // folder or another field.
                persistentSelection: true
                onActiveFocusChanged: if (!activeFocus && Window.active) deselect()
                foreground: viewRoot.foreground
                font.family: root.fontFamily
                text: root.chooserName
                onTextChanged: if (text !== root.chooserName) root.chooserName = text
                Keys.onPressed: function(event) {
                  var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (ctrl && event.key === Qt.Key_S)) {
                    root.acceptChooser(null)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    root.cancelChooser()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                    viewRoot.forceActiveFocus()
                    event.accepted = true
                  }
                }
              }

              Text {
                visible: !chooserField.visible
                width: chooserRow.fieldWidth
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.chooserSummary
                color: viewRoot.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideMiddle
              }

              Button {
                id: filterButton
                visible: root.chooser !== null && root.chooser.filters.length > 0
                width: Style.space(150)
                height: Style.spacing.controlHeight
                text: visible ? root.chooser.filters[root.chooserFilter].label + " ▾" : ""
                fontSize: Style.font.bodySmall
                foreground: viewRoot.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.nextChooserFilter()
              }

              Button {
                width: chooserRow.buttonWidth
                height: Style.spacing.controlHeight
                text: "Cancel"
                fontSize: Style.font.bodySmall
                foreground: viewRoot.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.cancelChooser()
              }

              Button {
                width: chooserRow.buttonWidth
                height: Style.spacing.controlHeight
                text: root.chooser ? root.chooser.accept : ""
                fontSize: Style.font.bodySmall
                foreground: Color.accent
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.acceptChooser(null)
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

    FindBox {
      x: main.x + Style.space(14)
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

    LookCard {
      id: lookCard
      anchors.fill: parent
      foreground: viewRoot.foreground
      background: viewRoot.background
      itemRect: viewRoot.cursorRect
    }

    // The confirmation fades in growing to its size and fades out
    // shrinking, like the other cards, over a backdrop that only fades; what
    // it asks stays while it goes.
    Item {
      id: confirmLayer
      anchors.fill: parent
      z: 10
      visible: confirmShown > 0

      property var lastConfirm: null
      readonly property var shownConfirm: root.confirm || lastConfirm
      property real confirmShown: root.confirm !== null ? 1 : 0
      Behavior on confirmShown {
        id: confirmShowing
        NumberAnimation { duration: Style.duration(confirmShowing.targetValue > 0 ? 220 : 190); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      Connections {
        target: root
        function onConfirmChanged() { if (root.confirm) confirmLayer.lastConfirm = root.confirm }
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(viewRoot.background.r, viewRoot.background.g, viewRoot.background.b, 0.7)
        opacity: confirmLayer.confirmShown
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        opened: confirmLayer.visible
        scrim: "transparent"
        opacity: confirmLayer.confirmShown
        transform: Scale { origin.x: confirmDialog.width / 2; origin.y: confirmDialog.height / 2; xScale: 0.92 + 0.08 * confirmLayer.confirmShown; yScale: xScale }
        message: confirmLayer.shownConfirm ? confirmLayer.shownConfirm.message : ""
        confirmText: confirmLayer.shownConfirm ? confirmLayer.shownConfirm.confirmText : ""
        background: viewRoot.background
        foreground: viewRoot.foreground
        fontFamily: root.fontFamily
        onCanceled: root.confirm = null
        onConfirmed: root.confirmed()
      }
    }

    // A click outside the field being typed in (the name, the filter, the
    // path) gives the keyboard back to the folder, so its keys work again;
    // the click itself still reaches what is under it. The mouse's back and
    // forward buttons go back and forward, as the header's ‹ and › do.
    Item {
      anchors.fill: parent
      z: 100

      TapHandler {
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onTapped: function(eventPoint, button) {
          if (button === Qt.BackButton) root.back()
          else root.forward()
        }
      }

      PointHandler {
        acceptedButtons: Qt.AllButtons
        onActiveChanged: {
          if (!active) return
          var fields = [chooserField, filterField, pathField]
          for (var i = 0; i < fields.length; i++) {
            if (!fields[i].activeFocus) continue
            if (!fields[i].contains(fields[i].mapFromItem(null, point.scenePosition.x, point.scenePosition.y))) viewRoot.forceActiveFocus()
            return
          }
        }
      }
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
          spacing: crumb.index === 0 ? root.iconGap : Style.space(4)

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

          // At its own width: the path bar has no column of icons to line up
          // with, so only the gap stands between the icon and the name.
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

    // The active tab's fill and border glide under it from the tab strip.
    hasCursor: !isActive && (chipMouse.containsMouse || chipDrop.containsDrag)
    bordered: !isActive

    Row {
      anchors.left: parent.left
      anchors.right: chipClose.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.iconGap

      Text {
        width: root.iconBox
        horizontalAlignment: Text.AlignHCenter
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
        width: Math.max(0, parent.width - root.iconBox - Style.space(28))
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
    readonly property real fixedWidth: root.iconBox + root.iconGap + sizeWidth + dateWidth + gap * 2
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

      SortHead { width: root.iconBox + root.iconGap + listPane.nameWidth; key: "name"; label: "Name"; leading: root.iconBox + root.iconGap; foreground: listPane.foreground }
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

      // The cursor: one mark under the rows, moving from row to row.
      CursorSurface {
        visible: list.count > 0
        y: root.cursorIndex * listPane.rowHeight
        width: list.width
        height: listPane.rowHeight
        foreground: listPane.foreground
        hasCursor: true
      }

      delegate: EntryRow {
        id: listRow
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

        // Coming and going: settling from where it was, fading in when
        // new, and out on its way out.
        property real stay: root.leaving[listRow.entry.path] === true ? 0 : 1
        Behavior on stay {
          enabled: root.leavingFades
          NumberAnimation { duration: Style.duration(110) }
        }
        opacity: stay * (root.settle > 0 && root.arrived[listRow.entry.path] === true ? 1 - root.settle : 1)
        transform: Translate { y: root.settle > 0 ? (root.settleShifts[listRow.entry.path] || 0) * root.settle * listPane.rowHeight : 0 }
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

    // The row under the cursor, in TARGET's terms.
    function cursorRect(target) {
      var item = list.itemAtIndex(root.cursorIndex)
      return item ? item.mapToItem(target, 0, 0, item.width, item.height) : null
    }
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

    // The cursor is the list's own mark, under the rows.
    CursorSurface {
      anchors.fill: parent
      foreground: row.foreground
      current: row.isSelected && !row.isCursor
      hasCursor: !row.isCursor && (mouse.containsMouse || drop.containsDrag)
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)
      opacity: (row.isCut ? 0.45 : (row.entry.hidden ? 0.7 : 1)) * (root.chooserDims(row.entry) ? 0.4 : 1)

      // The icon and the name as a pair, the gap between them the one
      // every icon has.
      Row {
        height: parent.height
        spacing: root.iconGap

        Text {
          width: root.iconBox
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

      // The cursor: one mark under the tiles, moving from tile to tile.
      CursorSurface {
        visible: grid.count > 0
        x: (root.cursorIndex % root.gridColumns) * grid.cellWidth + Style.space(3)
        y: Math.floor(root.cursorIndex / root.gridColumns) * grid.cellHeight + Style.space(3)
        width: grid.cellWidth - Style.space(6)
        height: grid.cellHeight - Style.space(6)
        foreground: gridPane.foreground
        hasCursor: true
      }

      delegate: Item {
        id: tile
        required property int index
        readonly property var entry: root.entries[index] || root.blankEntry
        width: grid.cellWidth
        height: grid.cellHeight

        // Coming and going: settling from where it was, fading in when
        // new, and out on its way out.
        readonly property var slot: root.settle > 0 && root.settleShifts[entry.path] ? Model.slotOffset(index, root.settleShifts[entry.path], root.gridColumns) : null
        property real stay: root.leaving[entry.path] === true ? 0 : 1
        Behavior on stay {
          enabled: root.leavingFades
          NumberAnimation { duration: Style.duration(110) }
        }
        opacity: stay * (root.settle > 0 && root.arrived[entry.path] === true ? 1 - root.settle : 1)
        transform: Translate {
          x: tile.slot ? tile.slot.x * grid.cellWidth * root.settle : 0
          y: tile.slot ? tile.slot.y * grid.cellHeight * root.settle : 0
        }

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

        // The cursor is the grid's own mark, under the tiles.
        CursorSurface {
          anchors.fill: parent
          anchors.margins: Style.space(3)
          foreground: gridPane.foreground
          current: tile.isSelected && !tile.isCursor
          hasCursor: !tile.isCursor && (tileMouse.containsMouse || tileDrop.containsDrag)
        }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(4)
          opacity: (tile.isCut ? 0.45 : (tile.entry.hidden ? 0.7 : 1)) * (root.chooserDims(tile.entry) ? 0.4 : 1)

          Item {
            width: parent.width
            height: parent.height - tileName.height - tileSub.height - parent.spacing * 2

            Image {
              id: thumb
              anchors.fill: parent
              visible: status === Image.Ready
              // A picture fades in as it is read; one read before shows at once.
              opacity: status === Image.Ready ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
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
              opacity: status === Image.Ready ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
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

    // The tile under the cursor, in TARGET's terms.
    function cursorRect(target) {
      var item = grid.itemAtIndex(root.cursorIndex)
      return item ? item.mapToItem(target, 0, 0, item.width, item.height) : null
    }
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
    readonly property real columnWidth: Style.space(root.columnDrag || root.columnWidth)
    readonly property real trailWidth: trailFor(chain.length)
    readonly property var trailEntry: trailOf()
    // The column under the cursor's folder or file, faded in as it opens.
    property real trailOpacity: 1

    // The column after the folder on screen keeps one width, folder or file,
    // so the strip does not move as the cursor does.
    function trailFor(count) {
      return Math.max(columnWidth, Style.space(230), width - columnWidth * count)
    }

    // What that column shows: the entry under the cursor, once it is one of
    // this folder's. Right after a move the preview can still be on the
    // folder left behind, and that never shows.
    function trailOf() {
      var entry = root.previewEntry
      return entry !== null && Model.parentPath(entry.path) === root.location ? entry : null
    }

    // Where the folder on screen starts, how far right the strip goes, and
    // where what is worth seeing ends: past the column after it only when
    // that shows something. All worked out afresh, since inside a change
    // handler a binding, or the row's own layout, may not have caught up.
    function currentX() {
      return columnWidth * (chain.length - 1)
    }

    function lastX() {
      return Math.max(0, columnWidth * chain.length + trailFor(chain.length) - width)
    }

    function contentEnd() {
      var trail = trailOf()
      var shows = trail !== null && (trail.dir || !root.showPreview)
      return currentX() + columnWidth + (shows ? trailFor(chain.length) : 0)
    }

    // Brings the folder on screen into view, and the column after it when
    // it lists a folder, moving the strip only as far as that needs: moving
    // onto a file never moves it.
    function reveal() {
      if (!shown) return
      var trail = trailOf()
      var start = currentX()
      var end = start + columnWidth + (trail !== null && trail.dir ? trailFor(chain.length) : 0)
      slideTo(Model.revealOffset(columnsFlick.contentX, start, end, lastX(), width))
    }

    // A column or two opening or closing slides the strip there quickly,
    // the next column fading in; a jump further off lands at once.
    function slideTo(x) {
      var target = Math.max(0, Math.min(lastX(), x))
      if (target === columnsFlick.contentX && !slide.running) return
      slide.stop()
      // While a divider is dragged the strip follows it at once.
      if (root.columnDrag > 0 || Math.abs(target - columnsFlick.contentX) > columnWidth * 2) {
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
      slideTo(Model.steppedScroll(columnsFlick.contentX, count, columnWidth, contentEnd(), width))
    }

    // The row under the cursor, in TARGET's terms.
    function cursorRect(target) {
      var item = currentColumn.itemAtIndex(root.cursorIndex)
      return item ? item.mapToItem(target, 0, 0, item.width, item.height) : null
    }

    ParallelAnimation {
      id: slide
      NumberAnimation { id: slideX; target: columnsFlick; property: "contentX"; duration: Style.duration(120); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      NumberAnimation { id: fadeIn; target: columnsPane; property: "trailOpacity"; to: 1; duration: Style.duration(120) }
    }

    // The folders above the one on screen, a column each. Only the columns
    // whose folder changed are added or removed: rebuilding them all would
    // read every folder again and redraw the whole strip.
    ListModel { id: parentColumns }

    function syncColumns() {
      var want = shown ? chain.slice(0, chain.length - 1) : []
      var keep = 0
      while (keep < parentColumns.count && keep < want.length && parentColumns.get(keep).folderPath === want[keep].path) keep++
      if (parentColumns.count > keep) parentColumns.remove(keep, parentColumns.count - keep)
      for (var i = 0; i < want.length; i++) {
        var open = chain[i + 1].path
        if (i >= keep) parentColumns.append({ folderPath: want[i].path, openPath: open })
        else if (parentColumns.get(i).openPath !== open) parentColumns.setProperty(i, "openPath", open)
      }
    }

    onChainChanged: {
      syncColumns()
      reveal()
    }
    onShownChanged: {
      syncColumns()
      reveal()
    }
    onTrailEntryChanged: reveal()
    onColumnWidthChanged: reveal()
    onWidthChanged: reveal()
    Component.onCompleted: syncColumns()

    Flickable {
      id: columnsFlick
      anchors.fill: parent
      clip: true
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.HorizontalFlick
      contentWidth: columnsRow.width
      contentHeight: height

      Row {
        id: columnsRow
        height: columnsFlick.height

        Repeater {
          model: parentColumns

          FolderColumn {
            width: columnsPane.columnWidth
            height: columnsRow.height
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

            // The cursor: one mark under the rows, moving from row to row.
            CursorSurface {
              visible: currentColumn.count > 0
              y: root.cursorIndex * columnsPane.rowHeight
              width: currentColumn.width
              height: columnsPane.rowHeight
              foreground: columnsPane.foreground
              hasCursor: true
            }

            delegate: Item {
              id: cell
              required property int index
              readonly property var entry: root.entries[index] || root.blankEntry
              width: currentColumn.width
              height: columnsPane.rowHeight

              readonly property bool renaming: root.renamePath === entry.path
              readonly property bool isCursor: root.cursorIndex === index

              // Coming and going: settling from where it was, fading in when
              // new, and out on its way out.
              property real stay: root.leaving[entry.path] === true ? 0 : 1
              Behavior on stay {
                enabled: root.leavingFades
                NumberAnimation { duration: Style.duration(110) }
              }
              opacity: stay * (root.settle > 0 && root.arrived[entry.path] === true ? 1 - root.settle : 1)
              transform: Translate { y: root.settle > 0 ? (root.settleShifts[cell.entry.path] || 0) * root.settle * columnsPane.rowHeight : 0 }

              // The cursor is the column's own mark, under the rows.
              CursorSurface {
                anchors.fill: parent
                foreground: columnsPane.foreground
                current: !cell.isCursor && root.selected.indexOf(cell.entry.path) >= 0
                hasCursor: !cell.isCursor && (cellMouse.containsMouse || cellDrop.containsDrag)
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: root.iconGap
                opacity: (cell.entry.hidden ? 0.7 : 1) * (root.chooserDims(cell.entry) ? 0.4 : 1)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.iconBox
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: Model.kindIcon(cell.entry.kind)
                  color: cell.entry.dir ? Color.accent : columnsPane.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Item {
                  width: parent.width - root.iconBox - Style.space(24)
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

          ColumnDivider {
            foreground: columnsPane.foreground
            entries: root.entries
          }
        }

        // What is under the cursor: a folder's contents, or a file's preview.
        Item {
          width: columnsPane.trailWidth
          height: columnsRow.height
          opacity: columnsPane.trailOpacity

          FolderColumn {
            anchors.fill: parent
            visible: columnsPane.trailEntry !== null && columnsPane.trailEntry.dir
            folderPath: visible ? columnsPane.trailEntry.path : ""
            openPath: ""
            foreground: columnsPane.foreground
            rowHeight: columnsPane.rowHeight
            passive: true
            sideways: columnsFlick
          }

          PreviewPane {
            anchors.fill: parent
            visible: columnsPane.trailEntry !== null && !columnsPane.trailEntry.dir && !root.showPreview
            foreground: columnsPane.foreground
            entry: visible ? columnsPane.trailEntry : null
          }
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
        visible: back ? columnsFlick.contentX > 1 : columnsFlick.contentX + columnsPane.width < columnsPane.contentEnd() - 1
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
  // folder on screen (the open child highlighted and kept in sight), or the
  // folder under the cursor (passive, dimmed). Clicking an entry goes there.
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
    // Read since the folder was set, or known from the listing cache: until
    // then an empty column says nothing rather than "Empty folder".
    property bool listed: false

    // Shows a listing sorted and filtered the way the view is, unless it is
    // what is on screen already, so a column read again unchanged keeps its
    // rows and its scroll.
    function show(list) {
      var next = Model.sortEntries(Model.filterEntries(list, "", root.showHidden), root.sortKey, root.sortDescending)
      listed = true
      if (Model.sameListing(next, columnEntries)) return
      columnEntries = next
      revealOpen()
    }

    // A folder seen lately shows at once from the listing cache; the folder
    // model's own read follows.
    function load() {
      listed = false
      var seen = folderPath !== "" ? root.listingCache[folderPath] : undefined
      if (seen) show(seen)
      else columnEntries = []
    }

    function snapshot() {
      // Half read, the folder would show as empty or cut short.
      if (folderPath === "" || columnModel.status === FolderListModel.Loading) return
      var out = []
      for (var i = 0; i < columnModel.count; i++) {
        var modified = columnModel.get(i, "fileModified")
        out.push(Model.makeEntry({
          path: columnModel.get(i, "filePath"),
          dir: columnModel.get(i, "fileIsDir") === true,
          size: columnModel.get(i, "fileSize"),
          modified: modified ? modified.getTime() : NaN
        }))
      }
      root.listingCache = Model.rememberListing(root.listingCache, folderPath, out)
      show(out)
    }

    // The folder this column leads through stays in sight.
    function revealOpen() {
      var at = openPath !== "" ? Model.indexOfPath(columnEntries, openPath) : -1
      if (at < 0) return
      columnList.forceLayout()
      columnList.positionViewAtIndex(at, ListView.Contain)
    }

    onFolderPathChanged: load()
    onOpenPathChanged: revealOpen()
    Component.onCompleted: load()

    FolderListModel {
      id: columnModel
      folder: column.folderPath !== "" ? Model.fileUrl(column.folderPath) : ""
      showDirsFirst: true
      showDotAndDotDot: false
      showHidden: true
      showOnlyReadable: false
      caseSensitive: false
      onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(column.snapshot)
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
      model: column.columnEntries.length
      reuseItems: true
      opacity: column.passive ? 0.7 : 1

      delegate: Item {
        id: item
        required property int index
        readonly property var entry: column.columnEntries[index] || root.blankEntry
        width: columnList.width
        height: column.rowHeight

        readonly property bool open: entry.path === column.openPath

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
          spacing: root.iconGap

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconBox
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: Model.kindIcon(item.entry.kind)
            color: item.entry.dir ? Color.accent : column.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width - root.iconBox - Style.space(24)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: item.entry.name
            color: column.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: item.open
            elide: Text.ElideMiddle
          }

          Text {
            visible: item.entry.dir
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
            if (item.entry.dir) root.openFolder(item.entry.path, root.newTabClick(mouse))
            else {
              root.pendingSelect = item.entry.path
              root.go(column.folderPath)
            }
          }
        }

        DropArea {
          id: itemDrop
          anchors.fill: parent
          keys: ["text/uri-list"]
          enabled: item.entry.dir
          onDropped: function(event) {
            if (root.dropUrls(event.urls, item.entry.path, event.proposedAction === Qt.CopyAction)) event.accept()
          }
        }
      }
    }

    StepScroll { flick: columnList; pitch: column.rowHeight; sideways: column.sideways; sidePitch: column.width }

    Text {
      anchors.centerIn: parent
      visible: column.listed && column.columnEntries.length === 0 && column.folderPath !== ""
      textFormat: Text.PlainText
      text: "Empty folder"
      color: column.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // The dimmed last column fills what is left, so it has no divider.
    ColumnDivider {
      visible: !column.passive
      foreground: column.foreground
      entries: column.columnEntries
    }
  }

  // The line after a column. Dragged, it sizes every column at once;
  // double clicked, it fits them to the longest names in ENTRIES.
  component ColumnDivider: Item {
    id: divider
    required property color foreground
    required property var entries
    property real startX: 0
    property int startWidth: 0
    anchors.right: parent.right
    width: Style.space(7)
    height: parent.height

    readonly property bool active: dividerMouse.containsMouse || dividerMouse.pressed

    Rectangle {
      anchors.right: parent.right
      width: divider.active ? 2 : 1
      height: parent.height
      color: divider.active ? Color.accent : Qt.rgba(divider.foreground.r, divider.foreground.g, divider.foreground.b, 0.12)
    }

    TextMetrics {
      id: nameMetrics
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: dividerMouse
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      cursorShape: Qt.SplitHCursor
      // Measured on the window, since the column moves as it resizes.
      onPressed: function(mouse) {
        divider.startX = mapToItem(null, mouse.x, 0).x
        divider.startWidth = root.columnDrag || root.columnWidth
      }
      onPositionChanged: function(mouse) {
        if (pressed) root.resizeColumns(divider.startWidth + (mapToItem(null, mouse.x, 0).x - divider.startX) / Style.spaceReal(1))
      }
      onReleased: root.keepColumnWidth()
      onDoubleClicked: {
        var widest = 0
        var names = Model.longestNames(divider.entries, 8)
        for (var i = 0; i < names.length; i++) {
          nameMetrics.text = names[i]
          widest = Math.max(widest, nameMetrics.advanceWidth)
        }
        if (widest > 0) root.setColumnWidth(Math.ceil(widest / Style.spaceReal(1)) + Model.COLUMN_CHROME)
      }
    }
  }

  // The edge of the sidebar or of the preview, as SIZES says. Dragged, it
  // sizes that pane, up to LIMIT on screen; double clicked, it puts the
  // pane's default width back. It shows only while pointed at.
  component PaneEdge: Item {
    id: edge
    required property string sizes
    required property bool windowed
    required property real limit
    property real startX: 0
    property real startWidth: 0
    width: Style.space(7)

    readonly property bool active: edgeMouse.containsMouse || edgeMouse.pressed
    // The preview grows as its edge is dragged to the left.
    readonly property int grows: sizes === "preview" ? -1 : 1

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: edge.active
      width: 2
      height: parent.height
      color: Color.accent
    }

    MouseArea {
      id: edgeMouse
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      cursorShape: Qt.SplitHCursor
      // Measured on the window, since the edge moves as the pane resizes,
      // and from the width on screen, which LIMIT may hold below the
      // setting.
      onPressed: function(mouse) {
        edge.startX = mapToItem(null, mouse.x, 0).x
        edge.startWidth = edge.parent.width / Style.spaceReal(1)
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var units = Math.min(edge.startWidth + edge.grows * (mapToItem(null, mouse.x, 0).x - edge.startX) / Style.spaceReal(1), edge.limit / Style.spaceReal(1))
        if (edge.sizes === "preview") root.resizePreview(units)
        else root.resizeSidebar(units)
      }
      onReleased: {
        if (edge.sizes === "preview") root.keepPreviewWidth(edge.windowed)
        else root.keepSidebarWidth()
      }
      onDoubleClicked: {
        if (edge.sizes === "preview") root.setPreviewWidth(edge.windowed ? Model.PREVIEW_WINDOW_WIDTH : Model.PREVIEW_WIDTH, edge.windowed)
        else root.setSidebarWidth(Model.SIDEBAR_WIDTH)
      }
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
    // The first 32 kB of a text file, read with head so a huge log costs no
    // more than a small one: room for the 8192 characters looked at, however
    // many bytes each takes.
    readonly property string textPath: textual && ready ? sourcePath : ""
    property string textBody: ""
    property string textOf: ""
    // null once the file turns out to be binary.
    readonly property var lines: textual ? Model.previewText(textOf === textPath ? textBody : "", 40) : ""
    // Qt draws pictures and PDF pages itself; a PDF falls back to its cover
    // from a system thumbnailer when Qt's PDF reader is not installed, and
    // video, audio, documents and fonts always come from one.
    readonly property bool pdfFailed: kind === "pdf" && pageImage.status === Image.Error
    readonly property bool wantsThumbnail: ready && (kind === "thumbnail" || pdfFailed)
    readonly property string thumbKey: wantsThumbnail ? Model.thumbnailKey({ path: sourcePath, modified: entry.modified }, 512) : ""
    readonly property string thumbPath: thumbKey !== "" ? (root.thumbnails[thumbKey] || "") : ""
    readonly property bool media: kind === "image" || kind === "pdf" || kind === "thumbnail"

    onThumbKeyChanged: if (thumbKey !== "") root.requestThumbnail({ path: sourcePath, modified: entry.modified }, 512)
    onTextPathChanged: readText()

    function readText() {
      if (textPath === "" || textPath === textOf || paneTextProc.running) return
      paneTextProc.target = textPath
      paneTextProc.command = ["head", "-c", "32768", "--", textPath]
      paneTextProc.running = true
    }

    // The bindings above may not have caught up with a new entry yet, so the
    // entry itself is read here.
    onEntryChanged: {
      if (!entry || !entry.path) return
      previewFade.restart()
      var kindNow = Model.previewKind(entry)
      var inside = Model.isArchiveLocation(entry.path)
      if (inside && (kindNow === "image" || kindNow === "pdf" || kindNow === "text" || kindNow === "thumbnail")) root.extractMember(entry, null)
      else if (kindNow === "archive" && !inside) root.loadArchive(entry.path, entry.modified, false)
    }

    Process {
      id: paneTextProc
      property string target: ""
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          previewRoot.textBody = text
          previewRoot.textOf = paneTextProc.target
        }
      }
      // A file asked for while this one was read is read next.
      onExited: previewRoot.readText()
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

    // A new entry fades in as the cursor moves on.
    NumberAnimation {
      id: previewFade
      target: previewFlick
      property: "opacity"
      from: 0.2
      to: 1
      duration: Style.duration(110)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
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
            // A picture fades in as it is read; one read before shows at once.
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
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
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
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
              var rows = Model.previewFacts(previewRoot.entry, root.home, {
                items: previewRoot.member ? undefined : previewFolder.count,
                pages: previewRoot.kind === "pdf" ? pageImage.frameCount : 0
              })
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

          readonly property var buttons: Model.previewActions(previewRoot.entry)

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
      spacing: root.iconGap

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconBox
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: sideRow.glyph
        color: sideRow.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - root.iconBox - sideDetail.width - sideEject.width - parent.spacing * 3
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
          Behavior on width { NumberAnimation { duration: Style.duration(200) } }
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
  // What f has typed so far, in the corner while finding.
  component FindBox: BorderSurface {
    id: findCard
    required property color foreground
    required property color background
    visible: root.finding
    z: 20
    color: background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    padding: Style.space(8)
    width: findRow.implicitWidth + findCard.contentLeftInset + findCard.contentRightInset
    height: findRow.implicitHeight + findCard.contentTopInset + findCard.contentBottomInset

    Row {
      id: findRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: "Find"
        color: findCard.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        textFormat: Text.PlainText
        text: root.findText + "▏"
        // Red once no name starts with what was typed.
        color: root.findText !== "" && Model.typeAheadIndex(root.entries, root.findText, root.cursorIndex) < 0 ? Color.urgent : findCard.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  component Toast: BorderSurface {
    id: toastCard
    required property color foreground
    required property color background
    visible: toastShown > 0
    z: 20

    // The note on screen, kept while it fades out.
    property var lastToast: null
    readonly property var shownToast: root.toast || lastToast
    // It rises into place as it comes, and sinks a little as it goes.
    property real toastShown: root.toast !== null ? 1 : 0
    Behavior on toastShown {
      id: toastShowing
      NumberAnimation { duration: Style.duration(toastShowing.targetValue > 0 ? 180 : 140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    opacity: toastShown
    transform: Translate { y: Style.space(toastShowing.targetValue > 0 ? 12 : 6) * (1 - toastCard.toastShown) }

    Connections {
      target: root
      function onToastChanged() { if (root.toast) toastCard.lastToast = root.toast }
    }
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
        text: toastCard.shownToast ? toastCard.shownToast.text : ""
        color: toastCard.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Button {
        visible: toastCard.shownToast !== null && toastCard.shownToast.undo !== null
        enabled: root.toast !== null
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
    visible: goShown > 0
    z: 20

    // It grows out of the button it hangs from, and fades as it goes.
    property real goShown: root.goMenuOpen ? 1 : 0
    Behavior on goShown {
      id: goShowing
      NumberAnimation { duration: Style.duration(goShowing.targetValue > 0 ? 120 : 80); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    opacity: goShown
    transform: Scale {
      xScale: 0.96 + 0.04 * goCard.goShown
      yScale: 0.96 + 0.04 * goCard.goShown
    }
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
            id: goRow
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

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.iconGap

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconBox
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.icon
                color: goCard.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.label
                color: goCard.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: goRow.width - Style.space(28) - root.iconBox - root.iconGap
              }
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
    visible: menuShown > 0
    z: 25

    readonly property real cardWidth: Style.space(250)
    readonly property real itemHeight: Style.space(26)
    // The menu on screen, kept while it fades out.
    property var lastMenu: null
    readonly property var shownMenu: root.menu || lastMenu
    // It grows out of the pointer as it opens, and fades as it goes.
    property real menuShown: root.menu !== null ? 1 : 0
    Behavior on menuShown {
      id: menuShowing
      NumberAnimation { duration: Style.duration(menuShowing.targetValue > 0 ? 120 : 80); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    Connections {
      target: root
      function onMenuChanged() { if (root.menu) menuLayer.lastMenu = root.menu }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.menu !== null
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.menu = null
    }

    BorderSurface {
      id: menuCard
      color: menuLayer.background
      borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      padding: Style.space(4)
      width: menuLayer.cardWidth
      height: (menuLayer.shownMenu ? menuLayer.shownMenu.items.length : 0) * menuLayer.itemHeight + menuCard.contentTopInset + menuCard.contentBottomInset
      // Where the pointer was, or the middle for a menu from the keyboard.
      readonly property point pointer: !menuLayer.shownMenu || menuLayer.shownMenu.x < 0 ? Qt.point(-1, -1) : menuLayer.mapFromItem(null, menuLayer.shownMenu.x, menuLayer.shownMenu.y)
      readonly property var place: {
        if (pointer.x < 0) return { x: (menuLayer.width - width) / 2, y: (menuLayer.height - height) / 2 }
        return Model.menuPosition(pointer.x, pointer.y, width, height, menuLayer.width, menuLayer.height, menuLayer.shownMenu.alignRight)
      }
      x: place.x
      y: place.y
      opacity: menuLayer.menuShown
      transform: Scale {
        origin.x: menuCard.pointer.x < 0 ? menuCard.width / 2 : menuCard.pointer.x - menuCard.x
        origin.y: menuCard.pointer.y < 0 ? menuCard.height / 2 : menuCard.pointer.y - menuCard.y
        xScale: 0.96 + 0.04 * menuLayer.menuShown
        yScale: 0.96 + 0.04 * menuLayer.menuShown
      }

      MouseArea { anchors.fill: parent; enabled: root.menu !== null }

      Column {
        x: menuCard.contentLeftInset
        y: menuCard.contentTopInset
        width: menuCard.width - menuCard.contentLeftInset - menuCard.contentRightInset

        Repeater {
          model: menuLayer.shownMenu ? menuLayer.shownMenu.items : []

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
              spacing: root.iconGap

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconBox
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: menuItem.modelData.icon || ""
                color: menuItem.modelData.danger ? Color.urgent : menuLayer.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - root.iconBox - menuShortcut.width - parent.spacing * 2
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
              enabled: !menuItem.modelData.disabled && root.menu !== null
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
    visible: keysShown > 0
    z: 30
    color: background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    padding: Style.space(14)

    // It fades in growing to its size and fades out shrinking, on the large
    // preview's curve and times.
    property real keysShown: root.keysOpen ? 1 : 0
    Behavior on keysShown {
      id: keysShowing
      NumberAnimation { duration: Style.duration(keysShowing.targetValue > 0 ? 220 : 190); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    opacity: keysShown
    transform: Scale { origin.x: sheet.width / 2; origin.y: sheet.height / 2; xScale: 0.92 + 0.08 * sheet.keysShown; yScale: xScale }

    MouseArea { anchors.fill: parent; enabled: root.keysOpen; onClicked: root.keysOpen = false }

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
    visible: promptShown > 0
    z: 16

    // It fades in growing to its size and fades out shrinking, on the large
    // preview's curve and times; what it asks stays while it goes.
    property var lastPrompt: null
    readonly property var shownPrompt: root.prompt || lastPrompt
    property real promptShown: root.prompt !== null ? 1 : 0
    Behavior on promptShown {
      id: promptShowing
      NumberAnimation { duration: Style.duration(promptShowing.targetValue > 0 ? 220 : 190); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    Connections {
      target: root
      function onPromptChanged() { if (root.prompt) promptLayer.lastPrompt = root.prompt }
    }

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
      opacity: promptLayer.promptShown
      MouseArea { anchors.fill: parent; enabled: root.prompt !== null; onClicked: root.cancelPrompt() }
    }

    BorderSurface {
      id: promptBox
      anchors.centerIn: parent
      opacity: promptLayer.promptShown
      transform: Scale { origin.x: promptBox.width / 2; origin.y: promptBox.height / 2; xScale: 0.92 + 0.08 * promptLayer.promptShown; yScale: xScale }
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
          text: promptLayer.shownPrompt ? promptLayer.shownPrompt.title : ""
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
          visible: promptLayer.shownPrompt !== null && promptLayer.shownPrompt.error !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: promptLayer.shownPrompt ? promptLayer.shownPrompt.error : ""
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
            text: promptLayer.shownPrompt ? promptLayer.shownPrompt.confirm : ""
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
    visible: jumpShown > 0
    z: 17

    // It drops into place as it opens, and fades as it goes.
    property real jumpShown: root.jumpOpen ? 1 : 0
    Behavior on jumpShown {
      id: jumpShowing
      NumberAnimation { duration: Style.duration(jumpShowing.targetValue > 0 ? 140 : 90); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    opacity: jumpShown

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
      MouseArea { anchors.fill: parent; enabled: root.jumpOpen; onClicked: root.closeJump() }
    }

    BorderSurface {
      id: jumpBox
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.space(40)
      transform: Translate { y: jumpShowing.targetValue > 0 ? -Style.space(8) * (1 - jumpLayer.jumpShown) : 0 }
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

                Row {
                  id: jumpName
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.iconGap

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconBox
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: jumpRow.item ? jumpRow.item.icon : ""
                    color: jumpRow.item && jumpRow.item.source === "tab" ? Color.accent : jumpLayer.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, jumpRow.width * 0.4)
                    textFormat: Text.PlainText
                    text: jumpRow.item ? jumpRow.item.label : ""
                    color: jumpLayer.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(0, parent.width - parent.spacing * 2 - jumpName.width - jumpSource.width)
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

  // Space: the entry under the cursor up close, over the whole view, the way
  // Quick Look shows it. j and k step through the folder with it open, Space
  // or Esc closes it. Pictures fill it, PDFs turn their pages, text scrolls,
  // video and music play, folders and archives list what they hold, and
  // anything else shows its details.
  component LookCard: Item {
    id: lookLayer
    required property color foreground
    required property color background
    visible: root.lookOpen || lookClosing
    z: 18

    // Where the item under the cursor is, for the card to grow out of it
    // and shrink back into it: set by the view holding it.
    property var itemRect: function() { return null }
    // From 0, the item under the cursor, to 1, the whole card; its contents
    // come in over the last two thirds.
    property real lookShown: 0
    property bool lookClosing: false
    property rect lookFrom: Qt.rect(0, 0, 0, 0)
    property bool lookFromItem: false
    readonly property real contentAlpha: Math.max(0, Math.min(1, (lookShown - 0.35) / 0.65))
    // The cursor as the card last showed it, so a step slides the next
    // entry in from its side.
    property int lastIndex: -1

    function grow() {
      shrinkRun.stop()
      lookClosing = false
      lastIndex = root.cursorIndex
      startFrom(itemRect())
      growRun.restart()
    }

    function shrink() {
      growRun.stop()
      startFrom(itemRect())
      lookClosing = true
      shrinkRun.restart()
    }

    // Without the item on screen (a folder still being read) the card only
    // fades.
    function startFrom(rect) {
      lookFromItem = rect !== null && rect.width > 0 && lookBox.width > 0
      lookFrom = lookFromItem ? rect : Qt.rect(lookBox.x, lookBox.y, lookBox.width, lookBox.height)
    }

    function step(direction) {
      stepSlide.from = Style.space(28) * direction
      stepRun.restart()
    }

    Connections {
      target: root
      function onLookOpenChanged() {
        if (root.lookOpen) lookLayer.grow()
        else lookLayer.shrink()
      }
    }

    NumberAnimation { id: growRun; target: lookLayer; property: "lookShown"; from: 0; to: 1; duration: Style.duration(220); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    NumberAnimation { id: shrinkRun; target: lookLayer; property: "lookShown"; to: 0; duration: Style.duration(190); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut; onFinished: lookLayer.lookClosing = false }

    ParallelAnimation {
      id: stepRun
      NumberAnimation { id: stepSlide; target: stepShift; property: "x"; to: 0; duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      NumberAnimation { target: lookContent; property: "opacity"; from: 0; to: 1; duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    // Read through entry itself, never through a flag worked out from it: as
    // the preview closes or moves on, a flag can lag the entry by a moment.
    readonly property var entry: (root.lookOpen || lookClosing) && root.previewEntry && root.previewEntry.path !== "" ? root.previewEntry : null
    readonly property string wanted: Model.lookKind(entry)
    readonly property bool playable: wanted === "video" || wanted === "audio"
    // Without Qt Multimedia, video and music show their still instead.
    readonly property string kind: playable && mediaLoader.status === Loader.Error ? "thumbnail" : wanted
    // A member of an archive is shown from its copy in the cache, made as it
    // is previewed.
    readonly property bool member: entry !== null && Model.isArchiveLocation(entry.path)
    readonly property bool needsContent: kind === "image" || kind === "pdf" || kind === "text" || kind === "thumbnail"
    readonly property string sourcePath: !entry ? "" : (Model.isArchiveLocation(entry.path) ? (root.extracted[entry.path] || "") : entry.path)
    readonly property bool ready: sourcePath !== "" && (!member || needsContent || kind === "dir" || kind === "archive")
    readonly property bool pdfFailed: kind === "pdf" && lookPage.status === Image.Error
    // The thumbnailer's picture: for documents and fonts, a PDF Qt cannot
    // read, and as a video's still or a song's cover.
    readonly property bool wantsThumbnail: ready && (kind === "thumbnail" || pdfFailed || playable)
    readonly property string thumbKey: wantsThumbnail && entry ? Model.thumbnailKey({ path: sourcePath, modified: entry.modified }, 512) : ""
    readonly property string thumbPath: thumbKey !== "" ? (root.thumbnails[thumbKey] || "") : ""

    // A folder's or an archive's contents, and how much they hold.
    property var folderItems: []
    readonly property var archiveInfo: kind === "archive" && entry && !Model.isArchiveLocation(entry.path) ? root.archives[entry.path] || null : null
    readonly property var contents: kind === "dir" ? folderItems : (archiveInfo && archiveInfo.members && entry ? Model.archiveEntries(archiveInfo.members, entry.path, "") : [])
    readonly property string contentsSummary: {
      if (kind === "archive") {
        var l = archiveInfo
        if (!l || (l.loading && !l.members)) return "Reading the archive…"
        if (l.error !== "" && (!l.members || l.members.length === 0)) return "Cannot read it: " + l.error
        var sum = Model.archiveSummary(l.members, 0)
        return Model.plural(sum.files, "file") + ", " + Model.plural(sum.dirs, "folder") + " · " + Model.formatSize(sum.bytes) + " unpacked"
      }
      var dirs = folderItems.filter(function(e) { return e.dir }).length
      return Model.plural(folderItems.length, "item") + ", " + Model.plural(dirs, "folder")
    }

    // The first 256 kB of a text file, read with head so a huge log costs no
    // more than a small one.
    readonly property string textPath: kind === "text" && ready ? sourcePath : ""
    property string textBody: ""
    property string textOf: ""
    readonly property bool textReady: textPath !== "" && textOf === textPath
    readonly property var textLines: textReady ? Model.previewText(textBody, 5000, 262144) : ""
    readonly property var textRows: textReady && textLines ? textLines.split("\n") : []

    function readText() {
      if (textPath === "" || textPath === textOf || textProc.running) return
      textProc.target = textPath
      textProc.command = ["head", "-c", "262144", "--", textPath]
      textProc.running = true
    }

    function snapshotContents() {
      if (kind !== "dir" || contentsModel.status === FolderListModel.Loading) return
      var out = []
      for (var i = 0; i < contentsModel.count; i++) {
        out.push(Model.makeEntry({
          path: contentsModel.get(i, "filePath"),
          dir: contentsModel.get(i, "fileIsDir") === true,
          size: contentsModel.get(i, "fileSize")
        }))
      }
      folderItems = Model.sortEntries(Model.filterEntries(out, "", root.showHidden), root.sortKey, root.sortDescending)
    }

    // Open closes the preview first, as every other action does.
    function runAction(id) {
      var target = entry
      root.closeLook()
      if (id === "open") root.openEntry(target)
      else root.run(id, target)
    }

    function handleKey(event) {
      var key = event.key
      var text = event.text
      if (key === Qt.Key_Space && (event.modifiers & Qt.ControlModifier)) root.toggleCursorSelection()
      else if (key === Qt.Key_Escape || key === Qt.Key_Space) root.closeLook()
      else if (key === Qt.Key_Down || key === Qt.Key_Right || text === "j") root.moveCursor(1, false)
      else if (key === Qt.Key_Up || key === Qt.Key_Left || text === "k") root.moveCursor(-1, false)
      else if (key === Qt.Key_Return || key === Qt.Key_Enter) runAction("open")
      else if (text === "o" && entry && !entry.dir) runAction("openwith")
      else if (text === "<") root.stepPage(-1)
      else if (text === ">") root.stepPage(1)
      else if (text === "p" && mediaLoader.item) mediaLoader.item.toggle()
      else return false
      return true
    }

    onTextPathChanged: readText()
    onThumbKeyChanged: if (thumbKey !== "" && entry) root.requestThumbnail({ path: sourcePath, modified: entry.modified }, 512)
    // The bindings above may not have caught up with a new entry yet, so the
    // entry itself is read here.
    onEntryChanged: {
      folderItems = []
      if (!entry || !entry.path) return
      if (root.lookOpen && !growRun.running && lastIndex >= 0 && root.cursorIndex !== lastIndex) step(root.cursorIndex > lastIndex ? 1 : -1)
      lastIndex = root.cursorIndex
      var kindNow = Model.lookKind(entry)
      var inside = Model.isArchiveLocation(entry.path)
      if (inside && (kindNow === "image" || kindNow === "pdf" || kindNow === "text" || kindNow === "thumbnail")) root.extractMember(entry, null)
      else if (kindNow === "archive" && !inside) root.loadArchive(entry.path, entry.modified, false)
      else if (kindNow === "dir" && !inside) {
        var seen = root.listingCache[entry.path]
        if (seen) folderItems = Model.sortEntries(Model.filterEntries(seen, "", root.showHidden), root.sortKey, root.sortDescending)
      }
    }

    Process {
      id: textProc
      property string target: ""
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          lookLayer.textBody = text
          lookLayer.textOf = textProc.target
        }
      }
      // A file asked for while this one was read is read next.
      onExited: lookLayer.readText()
    }

    FolderListModel {
      id: contentsModel
      folder: lookLayer.kind === "dir" && lookLayer.entry && !Model.isArchiveLocation(lookLayer.entry.path) ? Model.fileUrl(lookLayer.entry.path) : ""
      showDirsFirst: true
      showDotAndDotDot: false
      showHidden: true
      showOnlyReadable: false
      caseSensitive: false
      onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(lookLayer.snapshotContents)
      onCountChanged: contentsTimer.restart()
    }

    Timer {
      id: contentsTimer
      interval: 40
      onTriggered: lookLayer.snapshotContents()
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(lookLayer.background.r, lookLayer.background.g, lookLayer.background.b, 0.7)
      opacity: lookLayer.lookShown
      MouseArea { anchors.fill: parent; enabled: root.lookOpen; onClicked: root.closeLook() }
    }

    BorderSurface {
      id: lookBox
      anchors.fill: parent
      anchors.margins: Style.space(14)
      color: lookLayer.background
      borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      padding: Style.space(10)
      opacity: lookLayer.lookFromItem ? 1 : lookLayer.lookShown
      transform: [
        Scale {
          xScale: lookBox.width > 0 ? lookLayer.lookFrom.width / lookBox.width + (1 - lookLayer.lookFrom.width / lookBox.width) * lookLayer.lookShown : 1
          yScale: lookBox.height > 0 ? lookLayer.lookFrom.height / lookBox.height + (1 - lookLayer.lookFrom.height / lookBox.height) * lookLayer.lookShown : 1
        },
        Translate {
          x: (lookLayer.lookFrom.x - lookBox.x) * (1 - lookLayer.lookShown)
          y: (lookLayer.lookFrom.y - lookBox.y) * (1 - lookLayer.lookShown)
        }
      ]

      MouseArea { anchors.fill: parent; enabled: root.lookOpen }

      // The name, where it is in the folder, and the way out.
      Row {
        id: lookTop
        x: lookBox.contentLeftInset
        y: lookBox.contentTopInset
        width: lookBox.width - lookBox.contentLeftInset - lookBox.contentRightInset
        height: Style.spacing.controlHeight
        spacing: root.iconGap
        opacity: lookLayer.contentAlpha

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: root.iconBox
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: lookLayer.entry ? Model.kindIcon(lookLayer.entry.kind) : ""
          color: lookLayer.entry && lookLayer.entry.dir ? Color.accent : lookLayer.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - root.iconBox - lookPosition.width - Style.spacing.controlHeight - parent.spacing * 3
          textFormat: Text.PlainText
          text: lookLayer.entry ? lookLayer.entry.name : ""
          color: lookLayer.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideMiddle
        }

        Text {
          id: lookPosition
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: (root.cursorIndex + 1) + " of " + root.entries.length
          color: lookLayer.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        IconButton { glyph: "󰅖"; tip: "Close (Space or Esc)"; onClicked: root.closeLook() }
      }

      // What the entry holds, as large as the card allows.
      Item {
        id: lookStage
        x: lookBox.contentLeftInset
        y: lookTop.y + lookTop.height + Style.space(8)
        width: lookTop.width
        height: lookFoot.y - y - Style.space(8)
        clip: true
        opacity: lookLayer.contentAlpha

        readonly property real side: Style.space(40)

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(lookLayer.foreground.r, lookLayer.foreground.g, lookLayer.foreground.b, 0.04)
        }

        Item {
          id: lookContent
          anchors.fill: parent
          transform: Translate { id: stepShift }
          anchors.leftMargin: lookStage.side
          anchors.rightMargin: lookStage.side
          anchors.topMargin: Style.space(10)
          anchors.bottomMargin: Style.space(10)

          SizedImage {
            id: lookPicture
            anchors.fill: parent
            visible: lookLayer.kind === "image" && lookLayer.ready
            // A picture fades in as it is read; one read before shows at once.
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
            url: visible ? Model.fileUrl(lookLayer.sourcePath) : ""
          }

          Image {
            id: lookPage
            anchors.fill: parent
            visible: status === Image.Ready
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
            source: lookLayer.kind === "pdf" && lookLayer.ready ? Model.fileUrl(lookLayer.sourcePath) : ""
            currentFrame: Math.min(root.previewPage, Math.max(0, frameCount - 1))
            sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
            sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            onFrameCountChanged: if (lookLayer.kind === "pdf") root.previewPages = frameCount
          }

          SizedImage {
            id: lookThumb
            anchors.fill: parent
            visible: (lookLayer.kind === "thumbnail" || lookLayer.pdfFailed) && lookLayer.thumbPath !== ""
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
            url: lookLayer.thumbPath !== "" ? Model.fileUrl(lookLayer.thumbPath) : ""
          }

          Loader {
            id: mediaLoader
            anchors.fill: parent
            active: lookLayer.playable && lookLayer.ready
            source: Qt.resolvedUrl("LookMedia.qml")
            onLoaded: {
              item.path = Qt.binding(function() { return lookLayer.sourcePath })
              item.video = Qt.binding(function() { return lookLayer.wanted === "video" })
              item.still = Qt.binding(function() { return lookLayer.thumbPath })
              item.name = Qt.binding(function() { return lookLayer.entry ? lookLayer.entry.name : "" })
              item.foreground = Qt.binding(function() { return lookLayer.foreground })
              item.fontFamily = Qt.binding(function() { return root.fontFamily })
            }
          }

          // Text and code, with line numbers, scrolling a line at a time.
          ListView {
            id: textView
            anchors.fill: parent
            visible: lookLayer.kind === "text" && lookLayer.textRows.length > 0
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            model: visible ? lookLayer.textRows.length : 0
            reuseItems: true

            readonly property real numberWidth: Style.space(12) + String(lookLayer.textRows.length).length * Style.font.caption * 0.62

            delegate: Row {
              required property int index
              width: textView.width
              spacing: Style.space(10)

              Text {
                width: textView.numberWidth
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: String(index + 1)
                color: lookLayer.foreground
                opacity: 0.35
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: textView.width - textView.numberWidth - parent.spacing
                textFormat: Text.PlainText
                text: lookLayer.textRows[index] || ""
                color: lookLayer.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
              }
            }
          }

          StepScroll { flick: textView; pitch: Style.font.caption * 1.5 }

          // A folder's or an archive's contents, a few columns of rows.
          Item {
            anchors.fill: parent
            visible: lookLayer.kind === "dir" || (lookLayer.kind === "archive" && !lookLayer.member)

            Text {
              id: contentsHead
              width: parent.width
              textFormat: Text.PlainText
              text: lookLayer.contentsSummary
              color: lookLayer.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            GridView {
              id: contentsView
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: contentsHead.bottom
              anchors.bottom: parent.bottom
              anchors.topMargin: Style.space(8)
              clip: true
              interactive: false
              boundsBehavior: Flickable.StopAtBounds
              model: parent.visible ? lookLayer.contents.length : 0
              reuseItems: true
              cellWidth: width / Math.max(1, Math.floor(width / Style.space(230)))
              cellHeight: Style.space(30)

              delegate: Item {
                id: contentsCell
                required property int index
                readonly property var item: lookLayer.contents[index] || root.blankEntry
                width: contentsView.cellWidth
                height: contentsView.cellHeight

                Rectangle {
                  anchors.fill: parent
                  anchors.rightMargin: Style.space(6)
                  anchors.bottomMargin: Style.space(4)
                  color: "transparent"
                  border.width: 1
                  border.color: Qt.rgba(lookLayer.foreground.r, lookLayer.foreground.g, lookLayer.foreground.b, 0.12)

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(4)
                    anchors.rightMargin: Style.space(8)
                    spacing: root.iconGap

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: root.iconBox
                      horizontalAlignment: Text.AlignHCenter
                      textFormat: Text.PlainText
                      text: Model.kindIcon(contentsCell.item.kind)
                      color: contentsCell.item.dir ? Color.accent : lookLayer.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - root.iconBox - contentsSize.width - parent.spacing * 2
                      textFormat: Text.PlainText
                      text: contentsCell.item.name
                      color: lookLayer.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: contentsCell.item.dir
                      elide: Text.ElideMiddle
                    }

                    Text {
                      id: contentsSize
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: contentsCell.item.dir ? "" : Model.formatSize(contentsCell.item.size)
                      color: lookLayer.foreground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            StepScroll { flick: contentsView; pitch: contentsView.cellHeight; rowsPerNotch: 1 }
          }

          // Nothing to show yet, or nothing to show at all.
          Column {
            anchors.centerIn: parent
            width: parent.width
            visible: !lookPicture.visible && !lookPage.visible && !lookThumb.visible && !mediaLoader.item && !textView.visible && !(lookLayer.kind === "dir" || (lookLayer.kind === "archive" && !lookLayer.member))
            spacing: Style.space(10)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: lookLayer.entry ? Model.kindIcon(lookLayer.entry.kind) : ""
              color: lookLayer.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: {
                if (lookLayer.member && lookLayer.needsContent && !lookLayer.ready) return "Taking it out of the archive…"
                if (lookLayer.kind === "text" && lookLayer.textReady && lookLayer.textLines === null) return "Binary file, no text to show"
                if (lookLayer.kind === "text" && lookLayer.textReady && lookLayer.textLines === "") return "Empty file"
                if (lookLayer.kind === "text" || lookLayer.kind === "image" || lookLayer.kind === "pdf") return ""
                if (lookLayer.wantsThumbnail && !(lookLayer.thumbKey in root.thumbnails)) return "Making a preview…"
                return lookLayer.entry ? "No preview for " + lookLayer.entry.type.toLowerCase() + " files" : ""
              }
              color: lookLayer.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }
          }
        }

        // Pages of a PDF: ‹ and › here, or < and > from the keyboard.
        Row {
          visible: lookLayer.kind === "pdf" && lookPage.visible && lookPage.frameCount > 1
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(14)
          spacing: Style.space(8)

          IconButton { glyph: "󰅁"; tip: "Previous page (<)"; enabled: root.previewPage > 0; onClicked: root.stepPage(-1) }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Page " + (lookPage.currentFrame + 1) + " of " + lookPage.frameCount
            color: lookLayer.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          IconButton { glyph: "󰅂"; tip: "Next page (>)"; enabled: root.previewPage < lookPage.frameCount - 1; onClicked: root.stepPage(1) }
        }

        // The previous and the next entry, at either side.
        Repeater {
          model: [-1, 1]

          Item {
            id: lookNav
            required property int modelData
            readonly property bool back: modelData < 0
            visible: back ? root.cursorIndex > 0 : root.cursorIndex < root.entries.length - 1
            x: back ? 0 : lookStage.width - width
            width: lookStage.side
            height: lookStage.height

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: lookNav.back ? "󰅁" : "󰅂"
              color: navMouse.containsMouse ? Color.accent : lookLayer.foreground
              opacity: navMouse.containsMouse ? 1 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            MouseArea {
              id: navMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.moveCursor(lookNav.modelData, false)
            }
          }
        }
      }

      // The details, what can be done with it, and the keys.
      Column {
        id: lookFoot
        x: lookBox.contentLeftInset
        y: lookBox.height - lookBox.contentBottomInset - height
        width: lookTop.width
        spacing: Style.space(6)
        opacity: lookLayer.contentAlpha

        Row {
          width: parent.width
          spacing: Style.space(10)

          Flow {
            id: lookFacts
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - lookButtons.width - parent.spacing
            spacing: Style.space(16)

            Repeater {
              model: Model.previewFacts(lookLayer.entry, root.home, {
                items: lookLayer.kind === "dir" ? lookLayer.folderItems.length : undefined,
                pages: lookLayer.kind === "pdf" ? lookPage.frameCount : 0,
                length: mediaLoader.item && mediaLoader.item.duration > 0 ? Model.formatDuration(mediaLoader.item.duration) : ""
              })

              Row {
                required property var modelData
                spacing: Style.space(6)

                Text {
                  id: factLabel
                  textFormat: Text.PlainText
                  text: modelData[0]
                  color: lookLayer.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // A long value, a deep folder's path, gives way in the middle
                // rather than running under the buttons.
                Text {
                  width: Math.min(implicitWidth, lookFacts.width - factLabel.width - parent.spacing)
                  textFormat: Text.PlainText
                  text: modelData[1]
                  color: lookLayer.foreground
                  opacity: 0.9
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }
            }
          }

          Row {
            id: lookButtons
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Repeater {
              model: Model.previewActions(lookLayer.entry)

              Button {
                required property var modelData
                width: Style.space(96)
                height: Style.spacing.controlHeight
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: lookLayer.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: lookLayer.runAction(modelData.id)
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.StyledText
          text: Model.lookHints(lookLayer.kind).map(function(h) { return "<b>" + h.key + "</b> " + h.label }).join("   ")
          color: lookLayer.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
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
    visible: conflictShown > 0
    z: 15

    property int choice: 1
    property bool all: false

    readonly property bool asking: root.conflictJob !== null || root.chooserClash !== null
    // It fades in growing to its size and fades out shrinking, on the large
    // preview's curve and times; what it says stays while it goes.
    property real conflictShown: asking ? 1 : 0
    Behavior on conflictShown {
      id: conflictShowing
      NumberAnimation { duration: Style.duration(conflictShowing.targetValue > 0 ? 220 : 190); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    property bool forChooser: false
    property string heading: ""

    function keepCard() {
      if (!asking) return
      forChooser = root.chooserClash !== null
      heading = forChooser ? Model.itemsLabel(root.chooserClash.files.length, root.chooserClash.files[0]) + (root.chooserClash.files.length === 1 ? " already exists in " : " already exist in ") + Model.placeLabel(root.location, root.home, root.places, root.drives)
        : root.conflictJob.name + " already exists in " + Model.placeLabel(root.transferJob.dest, root.home, root.places, root.drives)
    }

    Connections {
      target: root
      function onConflictJobChanged() { conflict.keepCard() }
      function onChooserClashChanged() { conflict.keepCard() }
    }

    readonly property var choices: [
      { how: "skip", label: forChooser ? "Back" : "Skip" },
      { how: "keep", label: "Keep both" },
      { how: "replace", label: "Replace" }
    ]

    function decide(index) {
      if (!asking) return
      var how = choices[index].how
      var rest = all
      choice = 1
      all = false
      if (root.chooserClash) root.resolveChooserClash(how)
      else root.resolveConflict(how, rest)
    }

    // Esc or a click beside the card: a dialog goes back to its name, a
    // copy stops.
    function back() {
      if (root.chooserClash) root.resolveChooserClash("skip")
      else root.cancelConflicts()
    }

    function handleKey(event) {
      if (event.key === Qt.Key_Escape) back()
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
      opacity: conflict.conflictShown
      MouseArea { anchors.fill: parent; enabled: conflict.asking; onClicked: conflict.back() }
    }

    BorderSurface {
      id: conflictBox
      anchors.centerIn: parent
      opacity: conflict.conflictShown
      transform: Scale { origin.x: conflictBox.width / 2; origin.y: conflictBox.height / 2; xScale: 0.92 + 0.08 * conflict.conflictShown; yScale: xScale }
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
          text: conflict.heading
          color: conflict.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: conflict.forChooser ? "Go back, keep both (the new one gets another name), or replace what is there."
            : "Skip this one, keep both (the new one is renamed), or replace it (the old one goes to the Trash)."
          color: conflict.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Item {
          visible: !conflict.forChooser
          width: allRow.implicitWidth
          height: allRow.implicitHeight

          Row {
            id: allRow
            spacing: root.iconGap

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: root.iconBox
              horizontalAlignment: Text.AlignHCenter
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
