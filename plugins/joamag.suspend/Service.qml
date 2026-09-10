import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// Headless service that suspends the machine after `timeoutSec` seconds away
// from it. The compositor's idle notifier says when the user stopped touching
// the machine, but it cannot be trusted to time the whole wait: starting the
// screensaver and locking the session both count as activity and reset it, and
// a locked session reports active for as long as it stays locked. So the wait
// is accumulated here from three signals, any one of which means the user is
// still away, and only a genuine return clears it. A Wayland idle inhibitor
// (video playback, a game) holds the countdown, and suspend.sh applies the
// remaining checks at fire time: Omarchy's Stay Awake, the suspend toggle and
// systemd's block inhibitors.
Item {
  id: root

  // Injected by omarchy-shell when the service is created.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "joamag.suspend"
  readonly property string pluginVersion: "0.2.0"
  readonly property string scriptPath: String(Qt.resolvedUrl("suspend.sh")).replace(/^file:\/\//, "")

  // The shell stopped handing plugins the whole config and now passes the bar
  // section on its own, so take whichever of the two this shell offers.
  readonly property var entry: Model.pluginEntry(shell ? (shell.shellConfig || shell.barConfig) : null, pluginId)
  readonly property int configuredTimeout: Model.timeoutSeconds(entry, Model.DEFAULT_TIMEOUT_SECONDS)
  // The shell hands a plugin a fresh bar config only when the plugin or the
  // widget registry changes, not when a setting is written, so what arrives is
  // a change behind. The widget says what it just set, and that stands until
  // the config catches up with it.
  property int timeoutOverride: -1
  readonly property int timeoutSeconds: timeoutOverride >= 0 ? timeoutOverride : configuredTimeout
  readonly property bool dryRun: Model.dryRun(entry)
  readonly property bool armed: timeoutSeconds > 0
  // Short enough that nothing else pre-empts it; the wait itself is counted
  // by this service, not by the monitor.
  readonly property int detectionSeconds: Model.detectionSeconds(timeoutSeconds)

  // The shell's own idle and lock services still know the user is away once
  // the compositor has been reset by the screensaver or the lock, but a plugin
  // may no longer hold them directly, so they are asked over the same IPC the
  // command line uses and their answers land here.
  property bool sessionLocked: false
  property bool inIdleCycle: false
  // Someone typing a password is back, whatever the compositor thinks, so the
  // machine is not taken out from under them.
  property bool authenticating: false

  readonly property bool away: !authenticating && (idleMonitor.isIdle || inIdleCycle || sessionLocked)
  property double awaySince: 0
  // One suspend per absence, except that a skipped one is retried after a
  // while: whatever was holding sleep may well have finished.
  property bool firedThisAway: false
  property double retryAfter: 0
  // When the away timer last ran, so a sleep can be told from a normal tick.
  property double lastTick: 0

  // For the bar widget, which binds to this service directly.
  readonly property bool idle: away

  // The compositor's idle notification is registered when the monitor is
  // enabled and carries the timeout it had at that moment; changing `timeout`
  // afterwards does not re-register it, so the monitor goes deaf. Since the
  // timeout always changes at least once at startup (the default gives way to
  // the configured value once shell.json is read), the monitor has to be
  // cycled off and on after every change, one event loop turn later so the
  // new timeout is in place first.
  property bool rearming: true
  readonly property bool monitorOn: armed && !rearming

  property string lastVerdict: ""
  property string lastReason: ""
  property string lastEventAt: ""
  property int fired: 0

  function applyAwayProbe(text) {
    var probe = Model.parseAwayProbe(text)
    if (!probe.known) return
    root.sessionLocked = probe.locked
    root.inIdleCycle = probe.inIdleCycle
    root.authenticating = probe.authenticating
  }

  // Called by the widget the moment it writes a new timeout.
  function applyTimeout(seconds) {
    root.timeoutOverride = Model.timeoutSeconds({ timeoutSec: seconds }, root.timeoutSeconds)
  }

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
      idle: root.away,
      awaySeconds: Model.awaySeconds(root.awaySince, Date.now()),
      sessionLocked: root.sessionLocked,
      inIdleCycle: root.inIdleCycle,
      timeoutSec: root.timeoutSeconds,
      timeout: Model.describeTimeout(root.timeoutSeconds),
      dryRun: root.dryRun,
      fired: root.fired,
      lastVerdict: root.lastVerdict,
      lastReason: root.lastReason,
      lastEventAt: root.lastEventAt,
      // The monitor's own view, so a service that has gone deaf is visible
      // from `omarchy-shell joamag.suspend status` rather than only in hindsight.
      monitorEnabled: idleMonitor.enabled,
      monitorTimeout: idleMonitor.timeout,
      monitorIdle: idleMonitor.isIdle
    })
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.monitorOn
    timeout: root.detectionSeconds
    respectInhibitors: true
    onIsIdleChanged: root.logEvent("idle-monitor: " + (idleMonitor.isIdle ? "idle" : "active"))
  }

  onAwayChanged: {
    if (away) {
      returnTimer.stop()
      if (root.awaySince > 0) return
      // When the monitor is what noticed, it needed its detection window to
      // do so, and the absence started that much earlier. When the lock or the
      // shell's idle cycle got there first, the absence is counted from now,
      // which is late rather than early.
      root.awaySince = Date.now() - (idleMonitor.isIdle ? root.detectionSeconds * 1000 : 0)
      root.firedThisAway = false
      logEvent("away (monitor=" + idleMonitor.isIdle + " cycle=" + inIdleCycle + " locked=" + sessionLocked + ")")
    } else {
      // The three signals hand over to each other rather than overlapping: the
      // shell cancels its idle cycle a few hundred milliseconds before the lock
      // reports itself locked, and in that gap nothing claims the user is away.
      // Believing a return only after it has held for a moment keeps the count
      // running across the handover instead of restarting it there.
      returnTimer.restart()
    }
  }

  Timer {
    id: returnTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (root.away) return
      root.awaySince = 0
      root.firedThisAway = false
      root.retryAfter = 0
      root.logEvent("back at the machine")
    }
  }

  // Counts the absence out. The monitor cannot do it, so this is what actually
  // decides when the machine has been left alone for the whole timeout.
  Timer {
    id: awayTimer
    interval: 5000
    running: root.armed
    repeat: true
    onTriggered: {
      if (!awayProbe.running) awayProbe.running = true
      var now = Date.now()
      var slept = Model.resumed(root.lastTick, now, awayTimer.interval)
      root.lastTick = now
      // Coming back from a sleep spends the absence that caused it. Waking to
      // a lock screen nobody answers leaves the session locked, so `away` never
      // clears and nothing else would ever start the wait again; the machine
      // would then sit awake at the password prompt for good.
      if (slept) {
        root.firedThisAway = false
        root.retryAfter = 0
        if (root.away) root.awaySince = now
        root.logEvent("resumed from sleep, counting the wait again")
        return
      }
      if (!root.away || root.awaySince <= 0) return
      if (!Model.mayAttempt(root.firedThisAway, root.retryAfter, now)) return
      if (!Model.isDue(root.awaySince, now, root.timeoutSeconds)) return
      root.firedThisAway = true
      root.retryAfter = 0
      root.fire("away")
    }
  }

  // Both statuses in one go, so watching the lock costs a single process a tick.
  Process {
    id: awayProbe
    command: ["bash", "-c", "omarchy-shell lock status; omarchy-shell idle status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyAwayProbe(text) }
  }

  Process {
    id: suspendProcess
    stdout: StdioCollector { id: suspendOut; waitForEnd: true }
    stderr: StdioCollector { id: suspendErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(suspendOut.text, suspendErr.text, exitCode)
      root.lastVerdict = result.verdict
      root.lastReason = result.reason
      // Only a suspend settles the absence; anything else is worth another go.
      root.retryAfter = result.verdict === "suspend" ? 0 : Date.now() + Model.RETRY_SECONDS * 1000
      root.logEvent(result.verdict + ": " + result.reason)
    }
  }

  IpcHandler {
    target: "joamag.suspend"

    function status(): string { return root.statusJson() }
    function now(): string { root.fire("ipc"); return "ok" }
    function version(): string { return root.pluginVersion }
  }

  // Once the config catches up the override has nothing left to correct, and
  // dropping it keeps a later hand edit of shell.json from being masked.
  onConfiguredTimeoutChanged: if (configuredTimeout === timeoutOverride) timeoutOverride = -1

  onTimeoutSecondsChanged: {
    logEvent("timeout " + Model.describeTimeout(timeoutSeconds))
    // A new timeout is a new intention, so an attempt already made under the
    // old one must not hold the new one back.
    root.firedThisAway = false
    root.retryAfter = 0
  }

  onDetectionSecondsChanged: {
    root.rearming = true
    rearmTimer.restart()
  }

  // Lets the new timeout settle, then re-enables the monitor so it registers
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
