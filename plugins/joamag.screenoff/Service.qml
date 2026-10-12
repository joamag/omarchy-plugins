import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// Headless service that turns the displays off after `timeoutSec` seconds of
// idle while Omarchy's Stay Awake is on. Stay Awake works by switching the
// shell's idle service off altogether: that stops the lock and the screensaver
// as intended, but the blanking that came with the lock goes with them, so a
// machine held awake shows the same picture for as long as it is left alone.
// This service watches for idle only while Stay Awake is on and does nothing
// but the blanking: no screensaver, no lock, no sleep. Any input turns the
// displays back on, and a Wayland idle inhibitor (video playback, a game)
// keeps them on.
Item {
  id: root

  // Injected by omarchy-shell when the service is created.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "joamag.screenoff"
  readonly property string pluginVersion: "0.1.0"
  readonly property string scriptPath: String(Qt.resolvedUrl("screenoff.sh")).replace(/^file:\/\//, "")
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"

  // The shell hands a third-party service the bar section of the config and
  // nothing else, and a service without a widget is listed in `plugins[]`, so
  // the settings are read from the file itself.
  property var entry: null
  readonly property int timeoutSeconds: Model.timeoutSeconds(entry, Model.DEFAULT_TIMEOUT_SECONDS)
  readonly property bool respectInhibitors: Model.respectInhibitors(entry)
  readonly property bool dryRun: Model.dryRun(entry)
  readonly property bool armed: timeoutSeconds > 0

  // A plugin may not hold the idle service itself, so Stay Awake is asked for
  // over the same IPC the command line uses and the answer lands here.
  property bool stayAwake: false

  // The compositor's idle notification is registered when the monitor is
  // enabled and keeps the timeout it had at that moment, so a monitor whose
  // timeout changes afterwards goes deaf. It is cycled off and on after every
  // change, one event loop turn later so the new value is in place first.
  property bool rearming: true
  readonly property bool watching: armed && stayAwake && !rearming

  // What the displays should be, and what screenoff.sh last left them as. The
  // two differ only while the script is running.
  property bool blanked: false
  property bool displaysOff: false
  // Whether the last blank was only a dry run, which is how it is undone.
  property bool blankWasDry: false

  property string lastVerdict: ""
  property string lastReason: ""
  property string lastEventAt: ""
  property int fired: 0

  function applyStayAwake(text) {
    var probe = Model.parseStayAwake(text)
    if (!probe.known) return
    root.stayAwake = probe.stayAwake
  }

  function logEvent(message) {
    root.lastEventAt = new Date().toISOString()
    console.log("joamag.screenoff " + root.lastEventAt + " " + message)
  }

  function refreshStayAwake() {
    if (!stayAwakeProbe.running) stayAwakeProbe.running = true
  }

  function rearm() {
    root.rearming = true
    rearmTimer.restart()
  }

  function evaluate() {
    var action = Model.nextAction(root.watching, idleMonitor.isIdle, root.blanked)
    if (action === "") return
    root.blanked = action === "off"
    if (root.blanked) {
      root.fired++
      logEvent("idle for " + Model.describeTimeout(root.timeoutSeconds) + ", displays off" + (root.dryRun ? " (dry run)" : ""))
    } else {
      logEvent("displays back on" + (root.blankWasDry ? " (dry run)" : ""))
    }
    apply()
  }

  // One run of screenoff.sh at a time: a return that lands while the displays
  // are still going off is carried out as soon as that run has finished.
  function apply() {
    if (screenProcess.running || root.blanked === root.displaysOff) return
    var action = root.blanked ? "off" : "on"
    var dry = Model.runsDry(action, root.dryRun, root.blankWasDry)
    if (root.blanked) root.blankWasDry = dry
    var command = [root.scriptPath, action]
    if (dry) command.push("--dry-run")
    screenProcess.command = command
    screenProcess.running = true
  }

  function statusJson() {
    return JSON.stringify({
      armed: root.armed,
      stayAwake: root.stayAwake,
      watching: root.watching,
      idle: idleMonitor.isIdle,
      blanked: root.blanked,
      displaysOff: root.displaysOff,
      timeoutSec: root.timeoutSeconds,
      timeout: Model.describeTimeout(root.timeoutSeconds),
      respectInhibitors: root.respectInhibitors,
      dryRun: root.dryRun,
      fired: root.fired,
      lastVerdict: root.lastVerdict,
      lastReason: root.lastReason,
      lastEventAt: root.lastEventAt,
      // The monitor's own view, so a service that has gone deaf is visible
      // from `omarchy-shell joamag.screenoff status` rather than in hindsight.
      monitorEnabled: idleMonitor.enabled,
      monitorTimeout: idleMonitor.timeout
    })
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.watching
    timeout: root.timeoutSeconds
    respectInhibitors: root.respectInhibitors
    onIsIdleChanged: {
      root.logEvent("idle-monitor: " + (idleMonitor.isIdle ? "idle" : "active"))
      root.evaluate()
    }
  }

  onWatchingChanged: {
    logEvent(watching ? "watching, displays go off after " + Model.describeTimeout(timeoutSeconds) + " idle" : "not watching")
    evaluate()
  }

  // Nothing tells a plugin that Stay Awake was switched, so it is asked for on
  // a timer, for as long as there is a timeout to apply it to.
  Timer {
    id: stayAwakeTimer
    interval: 5000
    running: root.armed
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStayAwake()
  }

  Process {
    id: stayAwakeProbe
    command: ["omarchy-shell", "idle", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStayAwake(text) }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.entry = Model.pluginEntry(Model.parseConfig(configFile.text()), root.pluginId)
    onLoadFailed: function(error) { root.entry = null }
    onFileChanged: reload()
  }

  Process {
    id: screenProcess
    stdout: StdioCollector { id: screenOut; waitForEnd: true }
    stderr: StdioCollector { id: screenErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(screenOut.text, screenErr.text, exitCode)
      root.lastVerdict = result.verdict
      root.lastReason = result.reason
      root.displaysOff = Model.displaysOff(result.verdict, root.displaysOff)
      root.logEvent(result.verdict + ": " + result.reason)
      // A step that did not happen is left alone until idle next changes;
      // trying it again straight away would run the script in a loop.
      if (result.verdict === "skip" || result.verdict === "error") root.blanked = root.displaysOff
      if (result.verdict === "skip") root.refreshStayAwake()
      root.apply()
    }
  }

  IpcHandler {
    target: "joamag.screenoff"

    function status(): string { return root.statusJson() }
    function version(): string { return root.pluginVersion }
  }

  onTimeoutSecondsChanged: rearm()
  onRespectInhibitorsChanged: rearm()
  // The monitor has no use for this one, but re-arming stops the watch for a
  // moment, which undoes a blank made under the old setting the way it was
  // made, and the next one is made under the new.
  onDryRunChanged: rearm()

  // Lets the new setting settle, then re-enables the monitor so it registers
  // a fresh idle notification with it.
  Timer {
    id: rearmTimer
    interval: 50
    repeat: false
    onTriggered: root.rearming = false
  }
  Component.onCompleted: {
    logEvent("service ready, timeout " + Model.describeTimeout(timeoutSeconds) + (dryRun ? " (dry run)" : ""))
    rearmTimer.restart()
  }
}
