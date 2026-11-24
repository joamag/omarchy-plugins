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
// window back), middle click pops out, right click opens Nautilus.
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

  // Places, bookmarks, drives and the trash count from files.sh, and the
  // free space of the filesystem the folder on screen lives on.
  property var placesData: Model.parsePlaces("")
  property var freeSpace: Model.parseFree("")

  // The folder model's rows, and the lists that are not folders on disk.
  property var folderEntries: []
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
  // A path to put the cursor on (and to rename) as soon as it is listed:
  // the folder we came up from, a renamed or a new file.
  property string pendingSelect: ""
  property string pendingRename: ""

  // { mode: "copy" | "cut", paths }
  property var clipboard: null
  // Paste or drop waiting on its name conflicts: { mode, dest, names, jobs }.
  property var transferJob: null
  // The copy or move in flight: { mode, dest, label, count, first, total, done }.
  property var task: null
  property bool taskShown: false
  property var taskMoved: []
  property var taskErrors: []
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
  readonly property var places: placesData.places
  readonly property var bookmarks: placesData.bookmarks
  readonly property var drives: placesData.drives
  readonly property string locationLabel: Model.placeLabel(location, home, places, drives)
  readonly property bool bookmarked: isBookmarked(location)

  readonly property var entries: {
    var base = folderEntries
    if (inRecent) base = recentEntries
    else if (inTrash) base = trashEntries
    else if (deep) base = searchEntries
    var shown = Model.filterEntries(base, deep ? "" : query, showHidden || deep)
    // Recent keeps its newest-first order.
    return inRecent ? shown : Model.sortEntries(shown, sortKey, sortDescending)
  }
  readonly property var cursorEntry: cursorIndex >= 0 && cursorIndex < entries.length ? entries[cursorIndex] : null
  readonly property var picked: Model.pickedEntries(entries, selected, cursorIndex)
  readonly property bool busy: actionProc.running || transferProc.running || namesProc.running
  readonly property var conflictJob: transferJob ? transferJob.jobs[Model.conflictIndex(transferJob.jobs)] || null : null
  readonly property string hintMode: {
    if (renamePath !== "") return "rename"
    if (editingPath) return "path"
    if (filtering && filterFocused) return "filter"
    return inTrash ? "trash" : "browse"
  }

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // A view asks for focus on one of its fields, or on itself.
  signal focusRequested(string what)

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
    var from = location
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
    persistSettings({ tabs: Model.serializeTabs(tabs), activeTab: activeTab })
  }

  // The saved tabs come back on start, and when shell.json is edited by hand.
  function loadTabs() {
    if (tabsDirty) return
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
    } else {
      freeProc.command = [root.scriptPath, "free", location]
      if (!freeProc.running) freeProc.running = true
    }
  }

  function refreshPlaces() {
    if (!placesProc.running) placesProc.running = true
  }

  // Qt's folder model lists the folder and follows changes on disk; its
  // rows are copied into plain entries so every view, Recent and the Trash
  // share one shape.
  function snapshotFolder() {
    var out = []
    for (var i = 0; i < folderModel.count; i++) {
      var modified = folderModel.get(i, "fileModified")
      out.push(Model.makeEntry({
        path: folderModel.get(i, "filePath"),
        name: folderModel.get(i, "fileName"),
        dir: folderModel.get(i, "fileIsDir") === true,
        size: folderModel.get(i, "fileSize"),
        modified: modified ? modified.getTime() : NaN
      }))
    }
    folderEntries = out
  }

  function search() {
    if (!inFolder || query === "") return
    deep = true
    cursorIndex = 0
    selected = []
    searchProc.command = [root.scriptPath, "search", location, query, showHidden ? "all" : ""]
    searchProc.running = true
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
    else if (clipboard) clipboard = null
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
    Util.execArgv(["xdg-open", entry.path])
    if (!detached) root.close()
  }

  // Enter on a selection: a folder opens in place, several files each open
  // in their own app.
  function openPicked() {
    var list = picked
    if (list.length === 0) return
    if (list.length === 1 || list[0].dir || list[0].trashName) {
      openEntry(list[0])
      return
    }
    for (var i = 0; i < list.length && i < 12; i++) if (!list[i].dir) Util.execArgv(["xdg-open", list[i].path])
    if (!detached) root.close()
  }

  function openInNewTab(entry) {
    if (entry && entry.dir) newTab(entry.path)
  }

  function openWith(entry) {
    if (!entry || entry.dir || entry.trashName) return
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
    Util.execArgv(["setsid", "uwsm-app", "--", "nautilus", "--new-window", inFolder ? location : home])
    if (!detached) root.close()
  }

  // ---- Clipboard, copy and move -----------------------------------------

  function setClipboard(mode) {
    var list = picked.filter(function(e) { return !e.trashName })
    if (list.length === 0) return
    clipboard = { mode: mode, paths: list.map(function(e) { return e.path }) }
    showToast((mode === "copy" ? "Copied " : "Cut ") + Model.itemsLabel(list.length, list[0].name) + " · paste with p or Ctrl+V")
  }

  function paste(dest) {
    if (!clipboard) {
      showToast("Nothing to paste: copy or cut first")
      return
    }
    transfer(clipboard.paths, dest || location, clipboard.mode === "cut" ? "move" : "copy")
  }

  // First the names already in the destination, so every conflict can be
  // asked about before anything is written.
  function transfer(paths, dest, mode) {
    if (Model.isVirtual(dest) || !dest) {
      showToast("Open a folder to paste into")
      return
    }
    if (busy || !paths || paths.length === 0) return
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
      showToast(plan.error)
      return
    }
    if (plan.jobs.length === 0) {
      transferJob = null
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
    task = { mode: job.mode, dest: job.dest, label: Model.transferLabel(job.mode, count, Model.baseName(args[1]), Model.placeLabel(job.dest, home, places, drives)), count: count, first: Model.baseName(args[1]), total: 0, done: 0 }
    taskMoved = []
    taskErrors = []
    taskCancelled = false
    taskShown = false
    taskTimer.restart()
    transferProc.command = [root.scriptPath, "transfer", job.mode].concat(args)
    transferProc.running = true
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
    focusRequested("view")
  }

  function applyTransferLine(line) {
    if (!task) return
    var r = Model.parseResult(line)
    var next = { mode: task.mode, dest: task.dest, label: task.label, count: task.count, first: task.first, total: task.total, done: task.done }
    if (isFinite(r.total)) next.total = r.total
    if (isFinite(r.progress)) next.done = r.progress
    if (r.done.length > 0) taskMoved = taskMoved.concat(r.done)
    if (r.errors.length > 0) taskErrors = taskErrors.concat(r.errors)
    if (r.cancelled) taskCancelled = true
    task = next
  }

  function finishTransfer() {
    var finished = task
    task = null
    taskShown = false
    taskTimer.stop()
    if (!finished) return
    if (finished.mode === "move") {
      // A moved folder takes the tabs showing it along.
      var list = tabs
      for (var i = 0; i < taskMoved.length; i++) list = Model.retargetTabs(list, taskMoved[i].from, taskMoved[i].to)
      if (list !== tabs) setTabs(list, activeTab)
      if (clipboard && clipboard.mode === "cut") clipboard = null
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
    var list = picked.filter(function(e) { return !e.trashName })
    if (list.length === 0 || inRecent && list.length === 0) return
    act("trash", ["trash"].concat(list.map(function(e) { return e.path })), { entries: list })
  }

  function restore(list) {
    var items = (list || picked).filter(function(e) { return e.trashName })
    if (items.length === 0) return
    act("restore", ["restore"].concat(items.map(function(e) { return e.trashName })), { entries: items })
  }

  function askPurge() {
    var list = picked
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
    var items = names.map(function(n) { return { trashName: n } })
    act("restore", ["restore"].concat(names), { entries: items })
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
  function openDrive(drive) {
    if (!drive) return
    if (drive.mount) go(drive.mount)
    else act("mount", ["mount", drive.device], { drive: drive, open: true })
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
      if (r.mounted !== "" && ctx.open) go(r.mounted)
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
    searchEntries = []
    cursorIndex = 0
    selected = []
  }

  function clearFilter() {
    filtering = false
    setQuery("")
    focusRequested("view")
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
    pathCheckProc.target = target
    pathCheckProc.command = ["test", "-d", target]
    pathCheckProc.running = true
  }

  function cancelPathEdit() {
    editingPath = false
    focusRequested("view")
  }

  // ---- Menus, toasts and the window -------------------------------------

  function openMenu(items, x, y, entry) {
    if (!items || items.length === 0) return
    menu = { items: items, x: x, y: y, entry: entry || null }
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
    return Model.itemMenu(entry, picked.length, !!clipboard, entry && entry.dir && isBookmarked(entry.path))
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
    }
  }

  function showToast(text, undo) {
    toast = { text: text, undo: undo || null }
    toastTimer.restart()
  }

  // Out of the bar into a window Hyprland can move, resize and tile, with
  // the same tabs; and back.
  function popOut() {
    detached = true
    window.visible = true
    if (root.opened) root.close()
    Qt.callLater(function() { root.focusRequested("view") })
  }

  function dock() {
    detached = false
    window.visible = false
    root.open()
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
      case Qt.Key_H: toggleHidden(); return true
      case Qt.Key_F: startFilter(); return true
      case Qt.Key_C: setClipboard("copy"); return true
      case Qt.Key_X: setClipboard("cut"); return true
      case Qt.Key_V: paste(location); return true
      case Qt.Key_A: selectAll(); return true
      case Qt.Key_D: toggleBookmark(location); return true
      case Qt.Key_N: if (shift) newItem("mkdir"); return shift
      case Qt.Key_1: setView("list"); return true
      case Qt.Key_2: setView("grid"); return true
      case Qt.Key_3: setView("columns"); return true
      case Qt.Key_Return:
      case Qt.Key_Enter: openInNewTab(cursorEntry); return true
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
      else if (cursorEntry && cursorEntry.dir) go(cursorEntry.path)
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
    case "l": if (cursorEntry && cursorEntry.dir) go(cursorEntry.path); return true
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
    } else {
      if (renamePath !== "") cancelRename()
      editingPath = false
      menu = null
      confirm = null
    }
  }

  onShowHiddenChanged: if (deep) search()

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
    onStatusChanged: snapshotTimer.restart()
    onCountChanged: snapshotTimer.restart()
  }

  // The folder model also reports renames and in-place changes, which keep
  // the count.
  Connections {
    target: folderModel
    function onDataChanged() { snapshotTimer.restart() }
    function onRowsInserted() { snapshotTimer.restart() }
    function onRowsRemoved() { snapshotTimer.restart() }
    function onModelReset() { snapshotTimer.restart() }
  }

  Timer {
    id: snapshotTimer
    interval: 40
    onTriggered: root.snapshotFolder()
  }

  Timer {
    id: saveTabsTimer
    interval: 1200
    onTriggered: root.saveTabs()
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
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (root.deep) root.searchEntries = Model.parseEntries(text) }
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
    id: pathCheckProc
    property string target: ""
    onExited: function(exitCode) {
      if (exitCode === 0) root.go(target)
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
    active: root.detached
    fontSize: Style.font.body
    horizontalMargin: 6
    fixedWidth: Style.bar.iconSlot
    tooltipText: root.opened ? "" : Model.tooltip(root.tabs, root.activeTab, root.locationLabel)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openNautilus()
      else if (b === Qt.MiddleButton) root.toggleDetached()
      else if (root.detached) root.dock()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: popupView
    contentWidth: panel.fittedContentWidth(Style.space(720))
    contentHeight: panel.fittedContentHeight(Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
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

  FloatingWindow {
    id: window
    visible: false
    title: "Files · " + root.locationLabel
    color: Color.background
    implicitWidth: 1120
    implicitHeight: 700
    minimumSize: Qt.size(640, 420)

    // Closed from Hyprland rather than docked: the tabs stay for next time.
    onVisibleChanged: if (!visible) root.detached = false

    FilesView {
      id: windowView
      anchors.fill: parent
      anchors.margins: Style.space(10)
      windowed: true
      foreground: Color.foreground
      background: Color.background
      active: root.detached
      focus: true
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

    readonly property bool typing: pathField.activeFocus || filterField.activeFocus || root.renamePath !== ""
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
        } else if (what === "view") viewRoot.forceActiveFocus()
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

          IconButton { glyph: "󰁍"; tip: "Back (Alt+←)"; enabled: Model.canGoBack(root.tab); onClicked: root.back() }
          IconButton { glyph: "󰁔"; tip: "Forward (Alt+→)"; enabled: Model.canGoForward(root.tab); onClicked: root.forward() }
          IconButton { glyph: "󰁝"; tip: "Up (h)"; enabled: Model.parentPath(root.location) !== ""; onClicked: root.up() }
          IconButton {
            visible: !viewRoot.windowed
            glyph: "󰋜"
            tip: "Go to (g)"
            onClicked: root.goMenuOpen = !root.goMenuOpen
          }

          // Path bar, the path field or the filter field share this slot.
          Item {
            id: pathSlot
            width: header.width - header.children.length * header.spacing - header.square * (viewRoot.windowed ? 9 : 10)
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
              var p = moreButton.mapToItem(viewRoot, 0, moreButton.height + Style.space(4))
              root.openMenu(root.folderMenu(), p.x + moreButton.width, p.y, null)
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

          Repeater {
            model: root.tabs

            TabChip {
              required property var modelData
              required property int index
              width: tabStrip.tabWidth
              height: tabStrip.height
              tabData: modelData
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
              visible: root.view === "columns" && root.inFolder && !root.deep
              foreground: viewRoot.foreground
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

            Text {
              anchors.centerIn: parent
              visible: root.entries.length === 0
              textFormat: Text.PlainText
              text: searchProc.running ? "Searching…" : Model.emptyText(root.location, root.query, root.deep, Model.prettyPath(root.location, root.home))
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
            entry: root.cursorEntry
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
            visible: root.lastError !== ""
            textFormat: Text.PlainText
            text: root.lastError
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
              text: Model.statusText(root.entries, root.selected, root.deep, Model.prettyPath(root.location, root.home))
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

            readonly property var actions: root.inTrash ? [
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
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: footer.height + Style.space(14)
      foreground: viewRoot.foreground
      background: viewRoot.background
    }

    GoMenu {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: footer.height + Style.space(14)
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
      onCountChanged: positionViewAtEnd()
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
          cursorShape: Qt.PointingHandCursor
          onClicked: if (!crumb.last) root.go(crumb.modelData.path)
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
        visible: chip.tabIndex < 9
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
    readonly property real typeWidth: Style.space(110)
    readonly property real sizeWidth: Style.space(74)
    readonly property real dateWidth: Style.space(84)
    readonly property real whereWidth: showWhere ? Math.min(Style.space(200), width * 0.28) : 0

    Row {
      id: columnsHead
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      height: Style.space(24)
      spacing: Style.space(10)

      SortHead { width: columnsHead.width - Style.space(30) - listPane.whereWidth - listPane.typeWidth - listPane.sizeWidth - listPane.dateWidth - columnsHead.spacing * (listPane.showWhere ? 4 : 3); key: "name"; label: "Name"; leading: Style.space(30); foreground: listPane.foreground }
      Text {
        visible: listPane.showWhere
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
      SortHead { width: listPane.typeWidth; key: "type"; label: "Type"; foreground: listPane.foreground }
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
      boundsBehavior: Flickable.StopAtBounds
      model: listPane.shown ? root.entries : []
      currentIndex: root.cursorIndex
      highlightFollowsCurrentItem: false
      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      onCountChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: EntryRow {
        required property var modelData
        required property int index
        width: list.width
        height: listPane.rowHeight
        entry: modelData
        entryIndex: index
        foreground: listPane.foreground
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
  }

  component SortHead: Item {
    id: sortHead
    required property string key
    required property string label
    required property color foreground
    property bool alignRight: false
    property real leading: 0

    height: parent.height
    readonly property bool on: root.sortKey === key

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
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    drag.target: entry.trashName || root.renamePath === entry.path ? null : dragItem
    drag.threshold: Style.space(8)

    onClicked: function(mouse) {
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
      if (mouse.button === Qt.LeftButton && root.renamePath === "") root.openEntry(entryMouse.entry)
    }
    drag.onActiveChanged: {
      if (!drag.active) return
      if (root.selected.indexOf(entryMouse.entry.path) < 0) root.clickEntry(entryMouse.entryIndex, 0)
      root.dragPaths = root.picked.map(function(e) { return e.path })
    }
  }

  // Invisible stand-in a row drags, so the row stays put while the system
  // carries the files.
  component DragCarrier: Item {
    id: carrier
    required property bool dragging
    width: 1
    height: 1
    Drag.active: dragging
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.MoveAction | Qt.CopyAction
    Drag.proposedAction: Qt.MoveAction
    Drag.mimeData: ({ "text/uri-list": Model.uriList(root.dragPaths) })
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
        width: parent.width - Style.space(20) - row.whereWidth - row.typeWidth - row.sizeWidth - row.dateWidth - parent.spacing * (row.whereWidth > 0 ? 5 : 4)
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

        RenameField {
          visible: row.renaming
          active: row.renaming
          anchors.fill: parent
          anchors.topMargin: 1
          anchors.bottomMargin: 1
          entry: row.entry
          foreground: row.foreground
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
        width: row.typeWidth
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.typeLabel(row.entry)
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
    }

    DropArea {
      id: drop
      anchors.fill: parent
      keys: ["text/uri-list"]
      enabled: row.entry.dir && !row.entry.trashName && root.dragPaths.indexOf(row.entry.path) < 0
      onDropped: function(event) {
        if (root.dropUrls(event.urls, row.entry.path, event.proposedAction === Qt.CopyAction)) event.accept()
      }
    }
  }

  // The inline name editor: the name minus its extension starts selected,
  // Enter renames, Esc keeps the old name, a clash or a bad name says why.
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

    Rectangle {
      visible: root.renameError !== "" && field.active
      anchors.top: parent.bottom
      anchors.left: parent.left
      width: errorText.implicitWidth + Style.space(12)
      height: errorText.implicitHeight + Style.space(6)
      z: 5
      color: Color.popups.background
      border.width: 1
      border.color: Color.urgent

      Text {
        id: errorText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.renameError
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
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
      boundsBehavior: Flickable.StopAtBounds
      cellWidth: Math.floor(width / Math.max(1, Math.floor(width / Style.space(124))))
      cellHeight: Style.space(124)
      model: gridPane.shown ? root.entries : []
      currentIndex: root.cursorIndex
      highlightFollowsCurrentItem: false
      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
      onWidthChanged: if (gridPane.shown) root.gridColumns = Math.max(1, Math.floor(width / cellWidth))
      onVisibleChanged: if (visible) root.gridColumns = Math.max(1, Math.floor(width / cellWidth))

      delegate: Item {
        id: tile
        required property var modelData
        required property int index
        width: grid.cellWidth
        height: grid.cellHeight

        readonly property bool isSelected: root.selected.indexOf(modelData.path) >= 0
        readonly property bool isCursor: root.cursorIndex === index
        readonly property bool isCut: root.clipboard !== null && root.clipboard.mode === "cut" && root.clipboard.paths.indexOf(modelData.path) >= 0
        readonly property bool renaming: root.renamePath === modelData.path

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
          opacity: tile.isCut ? 0.45 : (tile.modelData.hidden ? 0.7 : 1)

          Item {
            width: parent.width
            height: parent.height - tileName.height - tileSub.height - parent.spacing * 2

            Image {
              id: thumb
              anchors.fill: parent
              visible: Model.isImage(tile.modelData) && status === Image.Ready
              source: Model.isImage(tile.modelData) ? Model.fileUrl(tile.modelData.path) : ""
              sourceSize.width: Style.space(220)
              sourceSize.height: Style.space(160)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
            }

            Text {
              anchors.centerIn: parent
              visible: !thumb.visible
              textFormat: Text.PlainText
              text: Model.kindIcon(tile.modelData.kind)
              color: tile.modelData.dir ? Color.accent : gridPane.foreground
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
              text: tile.modelData.name
              color: gridPane.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            RenameField {
              visible: tile.renaming
              active: tile.renaming
              anchors.fill: parent
              entry: tile.modelData
              foreground: gridPane.foreground
            }
          }

          Text {
            id: tileSub
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: tile.modelData.dir ? "Folder" : Model.formatSize(tile.modelData.size)
            color: gridPane.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        EntryMouse {
          id: tileMouse
          entry: tile.modelData
          entryIndex: tile.index
          dragItem: tileCarrier
          enabled: !tile.renaming
        }

        DragCarrier {
          id: tileCarrier
          dragging: tileMouse.drag.active
        }

        DropArea {
          id: tileDrop
          anchors.fill: parent
          keys: ["text/uri-list"]
          enabled: tile.modelData.dir && !tile.modelData.trashName && root.dragPaths.indexOf(tile.modelData.path) < 0
          onDropped: function(event) {
            if (root.dropUrls(event.urls, tile.modelData.path, event.proposedAction === Qt.CopyAction)) event.accept()
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
  }

  // The columns view: one column per folder from the root of the path down
  // to the folder on screen, which holds the cursor, then the folder under
  // the cursor, or the file's preview while the pane is off.
  component ColumnsPane: Item {
    id: columnsPane
    required property color foreground
    required property real rowHeight
    required property bool shown

    readonly property var chain: Model.crumbs(root.location, root.home, root.drives)
    readonly property real columnWidth: Style.space(190)

    Flickable {
      id: columnsFlick
      anchors.fill: parent
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.HorizontalFlick
      contentWidth: columnsRow.width
      contentHeight: height
      // The deepest column, where the cursor is, stays in view.
      onContentWidthChanged: contentX = Math.max(0, contentWidth - width)

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
          }
        }

        // The folder on screen, with the cursor and the selection.
        Item {
          width: columnsPane.columnWidth
          height: columnsRow.height

          ListView {
            id: currentColumn
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: columnsPane.shown ? root.entries : []
            currentIndex: root.cursorIndex
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Item {
              id: cell
              required property var modelData
              required property int index
              width: currentColumn.width
              height: columnsPane.rowHeight

              readonly property bool renaming: root.renamePath === modelData.path

              CursorSurface {
                anchors.fill: parent
                foreground: columnsPane.foreground
                current: root.selected.indexOf(cell.modelData.path) >= 0
                hasCursor: root.cursorIndex === cell.index || cellMouse.containsMouse || cellDrop.containsDrag
                outline: root.cursorIndex === cell.index
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(6)
                opacity: cell.modelData.hidden ? 0.7 : 1

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: Model.kindIcon(cell.modelData.kind)
                  color: cell.modelData.dir ? Color.accent : columnsPane.foreground
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
                    text: cell.modelData.name
                    color: columnsPane.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideMiddle
                  }

                  RenameField {
                    visible: cell.renaming
                    active: cell.renaming
                    anchors.fill: parent
                    entry: cell.modelData
                    foreground: columnsPane.foreground
                  }
                }

                Text {
                  visible: cell.modelData.dir
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
                entry: cell.modelData
                entryIndex: cell.index
                dragItem: cellCarrier
                enabled: !cell.renaming
              }

              DragCarrier {
                id: cellCarrier
                dragging: cellMouse.drag.active
              }

              DropArea {
                id: cellDrop
                anchors.fill: parent
                keys: ["text/uri-list"]
                enabled: cell.modelData.dir && root.dragPaths.indexOf(cell.modelData.path) < 0
                onDropped: function(event) {
                  if (root.dropUrls(event.urls, cell.modelData.path, event.proposedAction === Qt.CopyAction)) event.accept()
                }
              }
            }
          }

          Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: Qt.rgba(columnsPane.foreground.r, columnsPane.foreground.g, columnsPane.foreground.b, 0.12)
          }
        }

        // What is under the cursor: a folder's contents, or a file's preview.
        FolderColumn {
          visible: root.cursorEntry !== null && root.cursorEntry.dir
          width: visible ? Math.max(columnsPane.columnWidth, columnsPane.width - columnsRow.x - columnsPane.columnWidth * columnsPane.chain.length) : 0
          height: columnsRow.height
          folderPath: visible ? root.cursorEntry.path : ""
          openPath: ""
          foreground: columnsPane.foreground
          rowHeight: columnsPane.rowHeight
          passive: true
        }

        PreviewPane {
          visible: root.cursorEntry !== null && !root.cursorEntry.dir && !root.showPreview
          width: visible ? Math.max(Style.space(230), columnsPane.width - columnsPane.columnWidth * columnsPane.chain.length) : 0
          height: columnsRow.height
          foreground: columnsPane.foreground
          entry: visible ? root.cursorEntry : null
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
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (item.modelData.dir) root.go(item.modelData.path)
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

    readonly property bool hasEntry: entry !== null && entry !== undefined
    readonly property bool textual: hasEntry && Model.isTextual(entry)

    FileView {
      id: previewFile
      path: previewRoot.textual ? previewRoot.entry.path : ""
      printErrors: false
      blockLoading: false
    }

    FolderListModel {
      id: previewFolder
      folder: previewRoot.hasEntry && previewRoot.entry.dir ? Model.fileUrl(previewRoot.entry.path) : ""
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
      anchors.fill: parent
      anchors.margins: Style.space(10)
      clip: true
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

        Item {
          visible: previewRoot.hasEntry && !previewRoot.textual
          width: parent.width
          height: Style.space(150)

          Image {
            id: previewImage
            anchors.fill: parent
            visible: status === Image.Ready
            source: previewRoot.hasEntry && Model.isImage(previewRoot.entry) ? Model.fileUrl(previewRoot.entry.path) : ""
            sourceSize.width: Style.space(560)
            sourceSize.height: Style.space(300)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          Text {
            anchors.centerIn: parent
            visible: !previewImage.visible
            textFormat: Text.PlainText
            text: previewRoot.hasEntry ? Model.kindIcon(previewRoot.entry.kind) : ""
            color: previewRoot.hasEntry && previewRoot.entry.dir ? Color.accent : previewRoot.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
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

        Rectangle {
          visible: previewRoot.textual
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
            text: previewRoot.textual ? String(previewFile.text()).split("\n").slice(0, 30).join("\n") : ""
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
              var rows = [["Kind", Model.typeLabel(e)]]
              if (e.dir) rows.push(["Contains", Model.plural(previewFolder.count, "item")])
              else rows.push(["Size", Model.formatSize(e.size)])
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
  }

  // The window's sidebar: the standard folders, the bookmarks Nautilus
  // shares, drives with their free space and eject or mount, Recent and
  // the Trash. Folders take drops.
  component Sidebar: Flickable {
    id: side
    required property color foreground
    clip: true
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
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (sideRow.drive) root.openDrive(sideRow.drive)
        else root.go(sideRow.path)
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
        onClicked: {
          var names = root.toast.undo
          root.toast = null
          root.undoTrash(names)
        }
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
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.goMenuOpen = false
              root.go(modelData.path)
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
      x: {
        if (!root.menu || root.menu.x < 0) return (menuLayer.width - width) / 2
        var p = menuLayer.mapFromItem(null, root.menu.x, 0)
        return Math.max(0, Math.min(menuLayer.width - width, p.x - (root.menu.entry === null && root.menu.x > menuLayer.width / 2 ? width : 0)))
      }
      y: {
        if (!root.menu || root.menu.y < 0) return (menuLayer.height - height) / 2
        var p = menuLayer.mapFromItem(null, 0, root.menu.y)
        return Math.max(0, Math.min(menuLayer.height - height, p.y))
      }

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
