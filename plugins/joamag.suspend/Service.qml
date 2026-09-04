import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// Headless service that suspends the machine after `timeoutSec` seconds of
// idle. The compositor's idle notifier is the clock, the same one the shell's
// own screensaver and lock run on, so any Wayland idle inhibitor (video
// playback, a game) holds the countdown. suspend.sh applies the remaining
// checks at fire time: Omarchy's Stay Awake, the suspend toggle and systemd's
// block inhibitors.
Item {
  id: root

  // Injected by omarchy-shell when the service is created.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "joamag.suspend"
  readonly property string pluginVersion: "0.1.0"
  readonly property string scriptPath: String(Qt.resolvedUrl("suspend.sh")).replace(/^file:\/\//, "")

  readonly property var entry: Model.pluginEntry(shell ? shell.shellConfig : null, pluginId)
  readonly property int timeoutSeconds: Model.timeoutSeconds(entry, Model.DEFAULT_TIMEOUT_SECONDS)
  readonly property bool dryRun: Model.dryRun(entry)
  readonly property bool armed: timeoutSeconds > 0

  property string lastVerdict: ""
  property string lastReason: ""
  property string lastEventAt: ""
  property int fired: 0

  function logEvent(message) {
    root.lastEventAt = new Date().toISOString()
    console.log("joamag.suspend " + root.lastEventAt + " " + message)
  }

  function fire(origin) {
    if (suspendProcess.running) {
      logEvent("skip: suspend.sh still running")
      return
    }
    root.fired++
    logEvent(origin + " after " + Model.describeTimeout(root.timeoutSeconds) + (root.dryRun ? " (dry run)" : "") + ", running suspend.sh")
    suspendProcess.command = root.dryRun ? [root.scriptPath, "--dry-run"] : [root.scriptPath]
    suspendProcess.running = true
  }

  function statusJson() {
    return JSON.stringify({
      armed: root.armed,
      idle: idleMonitor.isIdle,
      timeoutSec: root.timeoutSeconds,
      timeout: Model.describeTimeout(root.timeoutSeconds),
      dryRun: root.dryRun,
      fired: root.fired,
      lastVerdict: root.lastVerdict,
      lastReason: root.lastReason,
      lastEventAt: root.lastEventAt
    })
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.armed
    timeout: root.timeoutSeconds
    respectInhibitors: true
    onIsIdleChanged: if (idleMonitor.isIdle) root.fire("idle")
  }

  Process {
    id: suspendProcess
    stdout: StdioCollector { id: suspendOut; waitForEnd: true }
    stderr: StdioCollector { id: suspendErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(suspendOut.text, suspendErr.text, exitCode)
      root.lastVerdict = result.verdict
      root.lastReason = result.reason
      root.logEvent(result.verdict + ": " + result.reason)
    }
  }

  IpcHandler {
    target: "joamag.suspend"

    function status(): string { return root.statusJson() }
    function now(): string { root.fire("ipc"); return "ok" }
    function version(): string { return root.pluginVersion }
  }

  onTimeoutSecondsChanged: logEvent("timeout " + Model.describeTimeout(timeoutSeconds) + (dryRun ? " (dry run)" : ""))
  Component.onCompleted: logEvent("service ready, timeout " + Model.describeTimeout(timeoutSeconds) + (dryRun ? " (dry run)" : ""))
}
