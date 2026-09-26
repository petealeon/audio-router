import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "petealeon.router"
  property string version: "1.3.0"

  // Watcher health, surfaced to Panel.qml through the injected hostWidget
  // reference. A crashed watcher loses rule re-assertion silently, so the
  // Process below self-heals (bounded) and these properties drive the panel's
  // on/off switch.
  // `watchEnabled` is the user's intent: when false the watcher is stopped and
  // nothing re-arms it, so apps fall through to the system default routing.
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
    root.watchEnabled = on
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
      root.logEvent("watcher disabled by user")
      root._stopping = true
      watchProc.running = false
      // "Routing off" must mean "everything back on the system default",
      // not just "stop re-asserting": streams already moved onto a pinned
      // output would otherwise stay there indefinitely. The helper's `restore`
      // flocks the watch lock (so the dying watcher cannot re-assert mid-move)
      // and puts every valid stream back on `pactl get-default-sink`. Saved
      // rules are untouched, so switching back on re-pins the same apps.
      Quickshell.execDetached(["python3", root.helperPath(), "restore"])
    }
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
    running: true
    command: ["python3", root.helperPath(), "watch"]

    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.logEvent("watcher: " + msg)
        var m = /__WATCH_EXIT\s+(\w+)/.exec(msg)
        root._processExit(m ? m[1] : "", 0)
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

  // Single dispatch point for watcher death. Two channels feed it — the helper
  // prints a __WATCH_EXIT marker on stderr (collected via onStreamFinished,
  // reliably delivered even when quickshell drops onExited for a clean
  // non-zero exit), and onExited carries the numeric code for signal deaths
  // (SIGKILL 9, SIGTERM 15). For a given death either or both may arrive; the
  // 200ms de-dup window covers the double-firing case since consecutive
  // watcher exits are always seconds apart.
  function _processExit(reason, code) {
    if (!root.watchEnabled) return
    if (root._stopping) {
      root._stopping = false
      return
    }
    var now = Date.now()
    if (now - root._lastExit < 200) return
    root._lastExit = now
    var wasAlive = root.watchAlive
    root.watchAlive = false
    if (root.watchDead) return
    if (reason === "flock" || code === 3) {
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
    if (reason === "parent" || code === 15 || code === 0) {
      if (wasAlive) return // late SIGTERM from a stop whose respawn already started
      root.logEvent("watcher stopped (code " + code + "); will re-arm if still needed")
      watchRearm.restart()
      return
    }
    root._crash(code || 9)
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