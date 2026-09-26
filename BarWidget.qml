import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "peter.router"
  property string version: "1.2.0"

  // Watcher health, surfaced to Panel.qml through the injected hostWidget
  // reference. A crashed watcher loses rule re-assertion silently, so the
  // Process below self-heals (bounded) and these properties drive the panel's
  // health dot.
  property int watchRestarts: 0
  property int watchPid: 0
  property bool watchAlive: false
  property bool watchDead: false
  property int _suppressExit: 0
  property int _flockRetries: 0

  function logEvent(msg) {
    console.log("[peter.router] " + msg)
  }

  function restartWatcher() {
    root.watchRestarts = 0
    root.watchDead = false
    root._flockRetries = 0
    root._suppressExit += 1
    root.logEvent("watcher restart requested by user")
    watchProc.running = false
    watchProc.running = true
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
  Process {
    id: watchProc
    running: true
    command: ["python3", root.helperPath(), "watch"]

    onStarted: {
      root.watchAlive = true
      root.watchPid = watchProc.processId || 0
      root._flockRetries = 0
      root.logEvent("watcher started pid=" + root.watchPid)
    }

    onExited: function(exitCode) {
      root.watchAlive = false
      if (root._suppressExit > 0) {
        // This exit was the stop half of a manual/retry restart; the respawn
        // is on its way.
        root._suppressExit -= 1
        return
      }
      if (root.watchDead) return
      if (exitCode === 3) {
        // Intentional watcher exit — normally another watcher holding the
        // flock. That clears within ~0.5s of a shell reload (the old watcher
        // sees its parent die), so retry once before giving up.
        if (root._flockRetries < 1) {
          root._flockRetries += 1
          root.logEvent("watcher exited (code 3); another watcher may hold the flock — retrying in 3s")
          watchRetry.restart()
        } else {
          root.logEvent("watcher exited (code 3); another watcher appears to hold the flock — click the health dot to force a restart")
        }
        return
      }
      if (root.watchRestarts >= 5) {
        root.watchDead = true
        root.logEvent("watcher crashed (code=" + exitCode + "); restart budget exhausted, routes will not reassert until shell reload or manual restart")
        return
      }
      root.watchRestarts += 1
      root.logEvent("watcher crashed (code=" + exitCode + "), restarting (" + root.watchRestarts + "/5) in 3s")
      watchRetry.restart()
    }
  }

  Timer {
    id: watchRetry
    interval: 3000
    running: false
    onTriggered: {
      if (root.watchDead) return
      root._suppressExit += 1
      watchProc.running = false
      watchProc.running = true
    }
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

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}