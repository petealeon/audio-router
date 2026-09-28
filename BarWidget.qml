import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "petealeon.router"
  property string version: "1.4.2"

  // Watcher health, surfaced to Panel.qml through the injected hostWidget
  // reference. A crashed watcher loses rule re-assertion silently, so the
  // Process below self-heals (bounded) and these properties drive the panel's
  // on/off switch.
  // `watchEnabled` is the user's intent: when false the watcher is stopped and
  // nothing re-arms it, so apps fall through to the system default routing. It
  // is persisted, because a shell reload otherwise restarted the watcher and
  // silently switched routing back on behind the user's back.
  // `watchAlive` is the observed state; the panel's switch reflects the
  // conjunction so a watcher that died (crash budget exhausted, still enabled)
  // reads as `off`.
  property bool watchEnabled: true
  property int watchRestarts: 0
  property int watchPid: 0
  property bool watchAlive: false
  property bool watchDead: false
  property bool _stopping: false
  property int _flockRetries: 0
  property int _lastExit: 0
  // What the last exit was decided to be, so the second channel for the same
  // death can tell "already handled" from "new evidence".
  property string _lastExitAction: ""
  // Set when the user moves the switch. The persisted state is read a few
  // milliseconds after load, and must not overwrite a toggle that happened in
  // the meantime (panel opened and switched immediately) — nor be cancelled
  // mid-read, which would leave the watcher unstarted.
  property bool _toggleRequested: false
  // Non-empty when the last revert to the default sink did not fully take.
  // Surfaced by Panel.qml, because a switch reading "off" while audio is still
  // pinned is exactly the failure this exists to make visible.
  property string restoreError: ""
  property bool _restoreDone: false

  function logEvent(msg) {
    console.log("[petealeon.router] " + msg)
  }

  function restartWatcher() {
    root.watchEnabled = true
    root.watchRestarts = 0
    root.watchDead = false
    root._flockRetries = 0
    root.logEvent("watcher restart requested by user")
    root._stopping = true
    watchProc.running = false
    watchProc.running = true
  }

  // Master routing switch. Off stops the watcher for good — no re-arm, no
  // crash restarts — leaving current sink assignments in place and letting new
  // streams use the system default. On resumes rule re-assertion, resetting
  // any crash-restart budget a dead watcher may have exhausted.
  function setWatchEnabled(on) {
    root._toggleRequested = true
    root.watchEnabled = on
    root.restoreError = ""
    // Persist the intent first: a crash or reload between here and the outcome
    // should still come back with the switch where the user left it.
    root.persistRouting(on)
    if (on) {
      root.watchRestarts = 0
      root.watchDead = false
      root._flockRetries = 0
      root.logEvent("watcher enabled by user")
      root._stopping = true
      watchProc.running = false
      watchProc.running = true
    } else {
      root.watchAlive = false
      root._restoreDone = false
      root.logEvent("watcher disabled by user")
      root._stopping = true
      watchProc.running = false
      // "Routing off" must mean "everything back on the system default",
      // not just "stop re-asserting": streams already moved onto a pinned
      // output would otherwise stay there indefinitely. Saved rules are
      // untouched, so switching back on re-pins the same apps.
      //
      // The revert is deliberately NOT fired here. It waits for the watcher to
      // actually be gone (see _processExit, with restoreFallback as a backstop)
      // because starting it while the watcher is still dying let the dying
      // process win the race and re-pin a stream after the restore had moved
      // it — which is how the switch came to read "off" with audio still routed.
      // The helper also flocks the watch lock, so only one of the two can
      // proceed; sequencing here just avoids depending on that lock alone.
      restoreFallback.restart()
    }
  }

  // Runs the revert and parses the helper's machine-readable result. A managed
  // Process, not execDetached: the old detached call discarded both stdout and
  // stderr, so a failed revert was indistinguishable from a successful one and
  // the switch reported success either way.
  function beginRestore() {
    if (root._restoreDone || root.watchEnabled) return
    root._restoreDone = true
    if (!restoreProc.running) restoreProc.running = true
  }

  // RESTORE_RESULT <status> <detail>, emitted on stdout by `restore`. Parsed
  // from the collected stream rather than from an exit code, because Quickshell
  // does not reliably deliver onExited for clean non-zero exits — exactly the
  // shape of a failed revert.
  function applyRestoreResult(text) {
    var line = String(text || "").trim()
    if (line.indexOf("RESTORE_RESULT") !== 0) return
    var parts = line.split(/\s+/)
    var status = parts[1] || ""
    var detail = parts.slice(2).join(" ")
    if (status === "ok") {
      root.restoreError = ""
      root.logEvent("restore ok: " + detail)
    } else {
      root.restoreError = detail || "revert to default sink failed"
      root.logEvent("restore FAILED: " + root.restoreError)
    }
  }

  function persistRouting(on) {
    // Deliberately does not touch stateProc: cancelling a waitForEnd collector
    // mid-read would mean its result never arrives, and the branch that starts
    // the watcher never runs. A stale read is handled by _toggleRequested.
    if (on) routingOnProc.running = true
    else routingOffProc.running = true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function helperPath() {
    var url = String(Qt.resolvedUrl("assets/omarchy-router"))
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.requestState) panelLoader.item.requestState()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: panelLoader.item && panelLoader.item.label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Watchdog: persisted routing rules are reasserted on a 0.5s poll, so a pin
  // created for an idle app also catches the stream the moment it starts, and
  // any external default-sink switch gets corrected within a second. The
  // helper flocks, so a shell (or plugin) reload can never spawn a second one.
  // Dispatch on the watcher's own lifecycle announcements. Quickshell only
  // fires Process.onExited for signal deaths, dropping it for a clean non-zero
  // exit (e.g. the watcher quitting on a flock conflict) — which used to leave
  // a wedge: no onExited, no restart, no re-arm, and routes silently dead. The
  // helper therefore prints a __WATCH_EXIT marker on stderr before every
  // intentional exit, and the StdioCollector (reliably delivered) dispatches
  // here. onExited remains as a de-duplicated fallback for signal deaths.
  Process {
    id: watchProc
    // Started from the routing-state read, not here: with the persisted intent
    // still unknown, running unconditionally would spawn a watcher and then
    // tear it down moments later for anyone who had routing off.
    running: false
    command: ["python3", root.helperPath(), "watch"]

    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.logEvent("watcher: " + msg)
        var m = /__WATCH_EXIT\s+(\w+)/.exec(msg)
        // The code is deliberately null, not 0. This channel is dispatched
        // before onExited, so whatever we pass here is the first classification
        // of the death -- and a hardcoded 0 read as "clean exit" for every death
        // the helper did not mark, which is all of them except the flock and
        // parent-gone cases. A SIGKILL or an OOM kill then took the
        // intentional-stop branch below: a 30s re-arm instead of the 3s retry,
        // and no charge against the 5-restart budget, so a crash loop looked
        // like a user switching routing off. null says "reason only, the real
        // code is still coming" and lets the onExited below upgrade it.
        root._processExit(m ? m[1] : "", null)
      }
    }

    onStarted: {
      root.watchAlive = true
      root.watchPid = watchProc.processId || 0
      // The stop half of any restart/respawn is behind us once a child is up;
      // a late SIGTERM notice from that stop is tolerated downstream (15 is
      // handled as a quiet no-op when a watcher is already running).
      root._stopping = false
      // Do NOT reset _flockRetries here: a flock-contention episode spans
      // respawns, so the "retry once" budget must survive spawn -> exit -> 3.
      // watchSurvived clears it once a watcher demonstrably lives past the
      // startup window.
      watchSurvived.restart()
      root.logEvent("watcher started pid=" + root.watchPid)
    }

    onExited: function(exitCode) {
      root._processExit("", exitCode)
    }
  }

  // Reads the persisted on/off intent. Runs before the watcher is started, so a
  // fresh shell or a plugin reload no longer quietly re-enables routing.
  Process {
    id: stateProc
    running: true
    command: ["python3", root.helperPath(), "routing-state"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var want = String(text || "").trim()
        if (root._toggleRequested) {
          // The switch was already moved while this read was in flight, so the
          // user's action is the newer intent; do not let the file override it.
          root.logEvent("routing state read ignored: switch already toggled")
          return
        }
        root.watchEnabled = (want !== "off")
        root.logEvent("routing state read: " + (want === "off" ? "off" : want === "on" ? "on" : "on (unrecognised, defaulting)"))
        if (root.watchEnabled) {
          root._stopping = true
          watchProc.running = true
        } else {
          // Coming back from a reload with routing off. Nothing is pinned, so
          // there is nothing to revert; just make sure no watcher sneaks up.
          root.logEvent("routing is off; watcher not started")
        }
      }
    }
  }

  Process {
    id: restoreProc
    running: false
    command: ["python3", root.helperPath(), "restore"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRestoreResult(text)
    }

    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.logEvent("restore: " + msg)
      }
    }
  }

  // Preference writes. Separate processes rather than one reused instance so a
  // rapid on/off/on cannot cancel the write it just issued.
  Process {
    id: routingOnProc
    running: false
    command: ["python3", root.helperPath(), "set-routing", "on"]
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.logEvent("set-routing: " + msg)
      }
    }
  }

  Process {
    id: routingOffProc
    running: false
    command: ["python3", root.helperPath(), "set-routing", "off"]
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.logEvent("set-routing: " + msg)
      }
    }
  }

  Timer {
    id: restoreFallback
    // Backstop only: _processExit normally starts the revert the moment the
    // watcher is confirmed gone. If that notice never arrives, the helper's own
    // flock wait (5s, bounded) is the real authority, so waiting longer than
    // this gains nothing.
    interval: 1500
    running: false
    onTriggered: root.beginRestore()
  }

  // Which of the three responses a death gets. Kept separate from the dispatch
  // below so the de-dup there can compare decisions instead of guessing from
  // timing.
  //
  // A null code means "the stderr channel, which knows only the reason" and is
  // deliberately not treated as a clean exit: the helper marks every exit it
  // intends, so a marker-less death is unexplained, and unexplained is a crash.
  // Reading null as 0 was what let a SIGKILL through as a tidy shutdown.
  function _exitAction(reason, code) {
    if (reason === "flock" || code === 3) return "flock"
    if (reason === "parent" || code === 15 || code === 0) return "stop"
    return "crash"
  }

  // Single dispatch point for watcher death. Two channels feed it — the helper
  // prints a __WATCH_EXIT marker on stderr (collected via onStreamFinished,
  // reliably delivered even when quickshell drops onExited for a clean
  // non-zero exit), and onExited carries the numeric code for signal deaths
  // (SIGKILL 9, SIGTERM 15). The stderr channel arrives FIRST and knows only
  // the reason, so it passes a null code; onExited then supplies the number.
  //
  // The two can both arrive for one death, so the second must not re-run the
  // timers, but it must not be dropped either: dropping it is what let a
  // SIGKILL reach the intentional-stop branch and never touch the restart
  // budget. So the window suppresses a duplicate only while it carries no new
  // information, and otherwise folds the real code into the first decision.
  function _processExit(reason, code) {
    if (!root.watchEnabled) {
      // Routing was just switched off and the watcher is now gone, so it can no
      // longer re-assert a pin. Only now is the revert safe to run.
      root._stopping = false
      root.beginRestore()
      return
    }
    if (root._stopping) {
      root._stopping = false
      return
    }
    if (code === undefined) code = null
    var action = root._exitAction(reason, code)
    var now = Date.now()
    if (now - root._lastExit < 200) {
      // Second channel for a death already acted on. Suppressing the duplicate
      // is the point of the window; suppressing the *upgrade* is the bug it
      // caused. stderr is dispatched first and reports no code, so onExited's
      // number is the only evidence that an unexplained death was a signal.
      if (action === root._lastExitAction) return
    }
    root._lastExit = now
    root._lastExitAction = action
    var wasAlive = root.watchAlive
    root.watchAlive = false
    if (root.watchDead) return
    if (action === "flock") {
      // Flock conflict (or the parent-gone variant, also exit 3) — retried
      // once per episode, since the orphaned holder of a reloaded shell clears
      // within its own next poll; the slow re-arm then takes over.
      if (root._flockRetries < 1) {
        root._flockRetries += 1
        root.logEvent("watcher exited with the flock contended; another watcher may be running — retrying in 3s")
        watchRetry.restart()
      } else {
        root._flockRetries = 0
        root.logEvent("watcher stopped (flock contended); will re-arm if still needed")
        watchRearm.restart()
      }
      return
    }
    if (action === "stop") {
      if (wasAlive) return // late SIGTERM from a stop whose respawn already started
      root.logEvent("watcher stopped (code " + (code === null ? reason || "none" : code) + "); will re-arm if still needed")
      watchRearm.restart()
      return
    }
    // A crash supersedes a stop already decided for this death: do not leave a
    // 30s re-arm pending when the 3s retry is the right response.
    watchRearm.stop()
    root._crash(code === null ? 9 : code)
  }

  function _crash(code) {
    root.watchAlive = false
    if (root.watchRestarts >= 5) {
      root.watchDead = true
      root.logEvent("watcher crashed (code=" + code + "); restart budget exhausted, routes will not reassert until shell reload or manual restart")
      return
    }
    root.watchRestarts += 1
    root.logEvent("watcher crashed (code=" + code + "), restarting (" + root.watchRestarts + "/5) in 3s")
    watchRetry.restart()
  }

  Timer {
    id: watchRetry
    interval: 3000
    running: false
    onTriggered: {
      if (root.watchDead || !root.watchEnabled) return
      root._stopping = true
      watchProc.running = false
      watchProc.running = true
    }
  }

  // Clears the flock-retry budget once a sibling process has demonstrably
  // survived the startup window (3s), i.e. the contention episode is over.
  Timer {
    id: watchSurvived
    interval: 3000
    running: false
    onTriggered: {
      root._flockRetries = 0
    }
  }

  // Slow quiet re-arm: a transient flock conflict (e.g. the orphaned watcher
  // of a SIGKILLed shell) clears on its own within its next poll, so a stopped
  // watcher should recover without demanding a manual click.
  Timer {
    id: watchRearm
    interval: 30000
    running: false
    onTriggered: {
      if (root.watchDead || root.watchAlive || !root.watchEnabled) return
      root.logEvent("watcher re-arming after intentional stop")
      root._stopping = true
      watchProc.running = false
      watchProc.running = true
    }
  }

  // Absolute backstop: if a death notification is dropped by the engine
  // entirely (both channels fail) and nothing is scheduled, nudge a re-arm.
  Timer {
    id: watchLost
    interval: 20000
    running: true
    repeat: true
    onTriggered: {
      if (root.watchAlive || root.watchDead || root._stopping || !root.watchEnabled) return
      if (watchRetry.running || watchRearm.running) return
      root.logEvent("watcher liveness check: nothing running, re-arming")
      root._stopping = true
      watchProc.running = false
      watchProc.running = true
    }
  }

  // On plugin/config reload the widget is torn down while the shell lives on.
  // Explicitly stop the tracked watcher so it never rattles through a crash
  // restart mid-teardown.
  Component.onDestruction: {
    root._stopping = true
    watchProc.running = false
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : ""
    slotSize: Style.bar.statusSlot
    tooltipText: ""
    opacity: root.watchEnabled ? 1.0 : 0.6

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}