import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "petealeon.router"
  ipcTarget: "petealeon.router"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // KeyboardPanel owns the popup window, keyboard-focus priming, outside-click
  // dismissal, popout coordination and the bar-strip mask, but it only offers
  // `centerOnBar` (screen centre) versus icon-centred placement, and its
  // `cardOrigin` is readonly. Neither KeyboardPanel nor PopupCard exposes a
  // section/corner mode, so a card flush with the bar section's screen corner
  // cannot be asked for through the public API. Its card is reachable from
  // content this plugin owns (content -> contentHolder -> card), so the two
  // Bindings below take over x/y only and every other behaviour is inherited.
  readonly property var card: {
    var holder = keyCatcher ? keyCatcher.parent : null
    var candidate = holder ? holder.parent : null
    // BorderSurface is the only ancestor exposing contentTopInset. Requiring
    // it keeps the override from latching onto an unrelated item should the
    // shell restructure its content hierarchy; when it does not resolve, the
    // bindings disable and KeyboardPanel's own positioning stands.
    return candidate && candidate.contentTopInset !== undefined ? candidate : null
  }

  // Top-left of the card in screen coordinates, replacing cardOrigin.
  // Perpendicular axis (away from the bar) keeps KeyboardPanel's rule: the
  // bar occupies that edge, so the card sits a `gap` clear of it. Parallel
  // axis (along the bar) is flush with the screen end nearest the icon, so a
  // widget sitting at the end of its section opens in that section's corner
  // rather than wherever the icon happens to be. Inside the deadzone the
  // shell's icon-centred placement is kept, which is the right reading for a
  // centre-section widget where "flush" has no meaningful answer.
  //
  // Everything read here is reactive: anchorScreenPos is a shell binding fed by
  // a TransformWatcher, so dragging the entry to another section re-derives
  // the flush end with no extra wiring here.
  function cardOrigin() {
    var w = panel.contentWidth
    var h = panel.contentHeight
    var sw = panel.screenW
    var sh = panel.screenH
    var m = panel.margin
    var gap = panel.gap
    var pos = panel.barPos
    var verticalBar = pos === "left" || pos === "right"
    var x = 0
    var y = 0

    if (pos === "top") y = panel.barH + gap
    else if (pos === "bottom") y = sh - panel.barH - h - gap
    else if (pos === "left") x = panel.barW + gap
    else x = sw - panel.barW - w - gap

    var extent = verticalBar ? sh : sw
    var centre = verticalBar
      ? panel.anchorScreenPos.y + panel.anchorH / 2
      : panel.anchorScreenPos.x + panel.anchorW / 2
    var half = extent / 2
    var deadzone = extent * 0.12

    if (centre > half + deadzone) {
      if (verticalBar) y = sh - h - m
      else x = sw - w - m
    } else if (centre < half - deadzone) {
      if (verticalBar) y = m
      else x = m
    } else if (verticalBar) {
      y = panel.anchorScreenPos.y + panel.anchorH / 2 - h / 2
    } else {
      x = panel.anchorScreenPos.x + panel.anchorW / 2 - w / 2
    }

    x = Math.max(m, Math.min(x, sw - w - m))
    y = Math.max(m, Math.min(y, sh - h - m))
    return Qt.point(Math.round(x), Math.round(y))
  }

  Binding {
    target: root.card
    property: "x"
    value: root.cardOrigin().x
    when: root.card !== null
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.card
    property: "y"
    value: root.cardOrigin().y
    when: root.card !== null
    restoreMode: Binding.RestoreBindingOrValue
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function") {
      root.bar.setCenterHoverRevealSuppressed(value)
      return
    }
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  readonly property string label: "\uF0C1"
  readonly property string tooltipLabel: "Audio routes"

  // ------------------------------------------------------------------ state

  property var sinks: []
  property var sinkInputs: []
  property var clients: []
  property var rules: []
  // Best known name per sink, including sinks pactl no longer reports (see
  // Model.friendlySinkName for the last-resort formatting).
  property var sinkLabels: ({})
  // {stale sink name: live sink name} for rule targets that are really the same
  // device under a different bluetooth profile index. The helper follows the
  // device by MAC, so the app stays routed; the panel uses this to avoid also
  // drawing a disconnected ghost row for the profile the rule happens to name.
  property var sinkAliases: ({})
  property var pendingWrites: []
  property string defaultSinkName: ""
  property string stateSignature: ""
  property bool stateLoaded: false
  // Set when the helper's `list` read of pactl is degraded (missing sinks or
  // streams). Surfaced as a small amber note under the header — the panel
  // cannot route while pactl is unreadable, and saying so beats silence.
  property string stateError: ""

  property var appRows: []
  property var outputRows: []
  property int pinnedCount: 0
  property string _appRowsSig: ""
  property string _outRowsSig: ""

  // ------------------------------------------------------------------ state

  property string accent: Color.accent
  readonly property color textColor: root.bar ? root.bar.foreground : Color.popups.text

  // Effective watcher state as seen by the header's on/off switch: `on` only
  // when the watcher is both enabled by intent and actually alive. A watcher
  // that died (crash budget exhausted) therefore reads as off, and toggling it
  // back on resets the budget.
  readonly property bool routingOn: root.hostWidget ? (root.hostWidget.watchEnabled && root.hostWidget.watchAlive) : false
  readonly property string toggleHint: root.routingOn ? "Turn routing off" : "Turn routing on"
  // Proxied from the host widget, which owns the revert: non-empty when moving
  // streams back to the default sink did not fully take. Routing can be off
  // (watcher stopped, switch showing off) while this is set, which is the
  // combination that used to be reported as a clean success.
  readonly property string restoreError: root.hostWidget ? String(root.hostWidget.restoreError || "") : ""

  // Omarchy theme roles: accent = "your routes" highlight, foreground =
  // system routes (neutral). Both re-evaluate live when the theme swaps.
  readonly property color userRouteColor: Color.accent
  readonly property color standardRouteColor: Color.foreground

  function lineColor(style) {
    if (style === "pinned" || style === "ghost" || style === "pending" || style === "stored") return root.userRouteColor
    return root.standardRouteColor
  }
  readonly property int rowH: Style.spacing.popupRowHeight
  readonly property int rowGap: Style.space(4)
  readonly property int rowStep: root.rowH + root.rowGap
  readonly property int minLabelW: Style.space(80)
  readonly property int appDotX: Style.space(12)
  readonly property int outDotX: Style.space(48)
  readonly property int appGutter: Style.space(48)
  readonly property int connectorLever: Style.space(30)
  // Gutter reserved left of every source label for the "is outputting" speaker
  // glyph. Reserved on every row (not only the ones with a stream) so the
  // labels stay in a single aligned column.
  readonly property int speakerGutter: Style.space(18)

  readonly property var systemBinaries: {
    var s = {}
    var list = ["pipewire", "wireplumber", "pactl", "python3", "pw-dump", "xdg-desktop-portal", "xdg-desktop-portal-hyprland", "quickshell", "easyeffects", "systemd"]
    for (var i = 0; i < list.length; ++i) s[list[i]] = 1
    return s
  }

  readonly property bool busy: root.dragging

  // interaction
  property string dragKey: ""
  property int dragRowIndex: -1
  property string selectKey: ""
  property bool dragging: false
  property real ghostX: 0
  property real ghostY: 0
  property string hoverAppKey: ""
  property string hoverTarget: ""

  // Keyboard cursor. appCol and outCol share a row grid (same rowStep, same
  // y origin), so cursorRow is literally the same screen row in either column.
  // "header" is a virtual section above row 0 holding the routing switch.
  // The cursor is keyed rather than purely indexed because rows come and go
  // under it: buildRows() re-sorts appRows whenever a stream appears, stops
  // or changes device, and the 1s refresh timer runs that even while the user
  // is navigating.
  property bool cursorActive: false
  property string cursorSection: "header"
  property int cursorRow: 0
  property string appCursorKey: ""
  property string outCursorKey: ""
  readonly property bool headerHasCursor: root.cursorActive && root.cursorSection === "header"
  readonly property int cursorRowCount: Math.max(root.appRows.length, root.outputRows.length)
  property var _clientCount: {}
  property bool _hadInputs: false
  property int _emptyStreak: 0

  property var lineSpecs: []
  property var ghostFrom: null

  function helperPath() {
    var url = String(Qt.resolvedUrl("assets/omarchy-router"))
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }

  Process {
    id: stateProc
    command: ["python3", root.helperPath(), "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 1000
    repeat: true
    running: root.opened && !root.busy
    onTriggered: root.requestState()
  }

  onOpenedChanged: {
    if (root.opened) {
      root.selectKey = ""
      root.resetCursor()
      root.requestState()
    } else {
      root.resetDrag()
    }
  }

  // appRows/outputRows are only reassigned when their signature changes, so
  // this is the exact moment the cursor's row indices can go stale.
  onAppRowsChanged: root.clampCursor()
  onOutputRowsChanged: root.clampCursor()

  // Stored rules change appearance with the switch: dashed/dim while off,
  // solid pins once routing is live again.
  onRoutingOnChanged: {
    if (!root.opened) return
    root.buildRows()
    Qt.callLater(root.rebuildPatch)
  }

  function requestState() {
    if (!stateProc.running) stateProc.running = true
  }

  function clientKey(c) {
    var cb = String(c.binary || "").toLowerCase()
    if (root.systemBinaries[cb]) return ""
    var cleaned = Model.stripInput(c.appName)
    return Model.appKey({ binary: c.binary, appName: cleaned })
  }

  function applyState(raw) {
    var obj
    try { obj = JSON.parse(raw) } catch (e) { return }
    if (!obj) return
    // Normalise before anything reads it. applyState used to assume
    // obj.sinkInputs was always an array, which holds for the current helper
    // but not for a short payload from an older or failing one — and a throw
    // here is unrecoverable, because it escapes before stateLoaded is set and
    // the panel never comes up again until the plugin is reloaded.
    if (!Array.isArray(obj.sinks)) obj.sinks = []
    if (!Array.isArray(obj.sinkInputs)) obj.sinkInputs = []
    if (!Array.isArray(obj.clients)) obj.clients = []
    if (!Array.isArray(obj.rules)) obj.rules = []
    if (!obj.labels || typeof obj.labels !== "object") obj.labels = {}
    if (!obj.sinkAliases || typeof obj.sinkAliases !== "object") obj.sinkAliases = {}
    root.stateError = obj.error || ""
    if (root.dragging) return

    root._clientCount = root._clientCount || {}

    if (obj.sinkInputs.length === 0 && root._hadInputs) {
      root._emptyStreak = (root._emptyStreak || 0) + 1
      if (root._emptyStreak < 3) return
    }
    if (obj.sinkInputs.length > 0) {
      root._hadInputs = true
      root._emptyStreak = 0
    } else {
      root._hadInputs = false
    }

    var present = {}
    var stableCl = 0
    var i
    for (i = 0; i < (obj.clients || []).length; ++i) {
      var cck = root.clientKey(obj.clients[i])
      if (!cck) continue
      present[cck] = 1
      root._clientCount[cck] = Math.min((root._clientCount[cck] || 0) + 1, 999)
      if (root._clientCount[cck] >= 3) stableCl++
    }
    var hk
    for (hk in root._clientCount) {
      if (!present[hk]) root._clientCount[hk] = 0
    }

    var sig = JSON.stringify([
      obj.sinks.map(function(s) { return [s.index, s.name, s.desc, s.available] }),
      obj.sinkInputs.map(function(i2) { return [i2.id, i2.sink, i2.sinkName] }),
      obj.rules,
      stableCl,
      obj.defaultSink || "",
      obj.labels || {},
      obj.sinkAliases || {}
    ])
    if (sig === root.stateSignature) return
    root.stateSignature = sig
    root.sinks = obj.sinks || []
    root.sinkInputs = obj.sinkInputs || []
    root.clients = obj.clients || []
    root.rules = obj.rules || []
    root.sinkLabels = obj.labels || {}
    root.sinkAliases = obj.sinkAliases || {}
    root.prunePendingWrites()
    root.defaultSinkName = obj.defaultSink || ""
    root.stateLoaded = true
    root.buildRows()
    Qt.callLater(root.rebuildPatch)
  }

  // ------------------------------------------------------------- row model

  function effectiveRules() {
    var out = []
    var seen = {}
    var i
    for (i = 0; i < root.rules.length; ++i) {
      var r = root.rules[i]
      var rk = Model.ruleKey(r)
      if (!seen[rk]) { seen[rk] = 1; out.push(r) }
    }
    for (i = 0; i < root.pendingWrites.length; ++i) {
      var w = root.pendingWrites[i]
      var wk = Model.ruleKey(w)
      if (w.sink === "__default__" || w.sink === "") {
        var kept = []
        for (var j = 0; j < out.length; ++j) if (Model.ruleKey(out[j]) !== wk) kept.push(out[j])
        out = kept
        delete seen[wk]
        continue
      }
      if (seen[wk]) {
        for (var k = 0; k < out.length; ++k) if (Model.ruleKey(out[k]) === wk) out[k] = w
      } else {
        out.push(w)
        seen[wk] = 1
      }
    }
    return out
  }

  function prunePendingWrites() {
    if (root.pendingWrites.length === 0) return
    var now = Date.now()
    var kept = []
    var changed = false
    var i, j
    for (i = 0; i < root.pendingWrites.length; ++i) {
      var w = root.pendingWrites[i]
      var wk = Model.ruleKey(w)
      var disk = null
      for (j = 0; j < root.rules.length; ++j) if (Model.ruleKey(root.rules[j]) === wk) disk = root.rules[j]
      var wantRemoval = (w.sink === "__default__" || w.sink === "")
      var confirmed = wantRemoval ? disk === null : (disk !== null && disk.sink === w.sink)
      if (confirmed || now - (w.ts || 0) > 1000) {
        if (!confirmed) root.logEvent("pin not confirmed on disk, dropped key=" + wk + " sink=" + (w.sink || ""))
        changed = true
        continue
      }
      kept.push(w)
    }
    if (changed) {
      root.pendingWrites = kept
      root.buildRows()
      Qt.callLater(root.rebuildPatch)
    }
  }

  function buildRows() {
    var rowsMap = {}
    var order = []
    var i
    var keys = []

    for (i = 0; i < root.sinkInputs.length; ++i) {
      var e = root.sinkInputs[i]
      var key = Model.appKey(e)
      var row = rowsMap[key]
      if (!row) {
        row = { key: key, label: Model.friendlyLabel(e), binary: e.binary || "", appName: e.appName || "", nodeName: e.nodeName || "", streams: [], rule: null, isPending: false, idle: false }
        rowsMap[key] = row
        order.push(row)
      }
      row.streams.push({ id: e.id, sink: e.sink, sinkName: e.sinkName || "", nodeName: e.nodeName || "" })
    }

    var effective = root.effectiveRules()
    for (i = 0; i < effective.length; ++i) {
      var r = effective[i]
      var k = Model.ruleKey(r)
      if (rowsMap[k]) {
        if (!rowsMap[k].rule) rowsMap[k].rule = r
      } else {
        var idleRow = { key: k, label: r.app || r.binary || k, binary: r.binary || "", appName: r.app || "", nodeName: r.node || "", streams: [], rule: r, isPending: false, idle: true }
        rowsMap[k] = idleRow
        order.push(idleRow)
      }
    }

    for (i = 0; i < root.pendingWrites.length; ++i) {
      var pw = root.pendingWrites[i]
      if (!pw.sink || pw.sink === "__default__") {
        var pwRow = rowsMap[Model.ruleKey(pw)]
        if (pwRow) pwRow.pendingDefault = true
      }
    }

    for (i = 0; i < root.clients.length; ++i) {
      var c = root.clients[i]
      var ck = root.clientKey(c)
      if (!ck) continue
      if (rowsMap[ck]) {
        if (rowsMap[ck].runIdle) {
          var cleaned2 = Model.stripInput(c.appName)
          if (/^[A-Z]/.test(cleaned2) && !/^[A-Z]/.test(rowsMap[ck].label)) {
            rowsMap[ck].label = cleaned2
            rowsMap[ck].appName = cleaned2
          }
        }
        continue
      }
      root._clientCount = root._clientCount || {}
      if ((root._clientCount[ck] || 0) < 3) continue
      var cb = String(c.binary || "").toLowerCase()
      var cleaned = Model.stripInput(c.appName)
      var runRow = { key: ck, label: cleaned || cb || ck, binary: c.binary || "", appName: cleaned || "", nodeName: "", streams: [], rule: null, isPending: false, idle: true, runIdle: true }
      rowsMap[ck] = runRow
      order.push(runRow)
    }

    order.sort(function(a, b) {
      var la = String(a.label || "").toLowerCase()
      var lb = String(b.label || "").toLowerCase()
      return la < lb ? -1 : la > lb ? 1 : 0
    })

    var appSig = JSON.stringify(order.map(function(r) {
      var sinks = []
      for (var si = 0; si < r.streams.length; ++si) sinks.push(r.streams[si].sinkName || "")
      return [r.key, r.rule ? r.rule.sink : "", r.isPending ? 1 : 0, r.pendingDefault ? 1 : 0, r.idle ? 1 : 0, r.runIdle ? 1 : 0, r.label, sinks.sort().join(",")]
    }))
    if (appSig !== root._appRowsSig) {
      root._appRowsSig = appSig
      root.appRows = order
    }

    var outRows = []
    var sinkKeys = {}
    for (i = 0; i < root.sinks.length; ++i) {
      var s = root.sinks[i]
      outRows.push({ key: s.name, label: s.desc || s.name, sub: s.name, available: s.available, isDefault: false })
      sinkKeys[s.name] = 1
    }
    var effective2 = root.effectiveRules()
    for (i = 0; i < effective2.length; ++i) {
      var r2 = effective2[i]
      if (!r2.sink || r2.sink === "__default__") continue
      if (sinkKeys[r2.sink]) continue
      // Same device, different profile index: the helper is routing this app to
      // the live sink above, so a ghost row for the rule's stale name would show
      // one headset twice and claim the app was not routed.
      if (root.sinkAliases[r2.sink]) continue
      // An output a rule still points at but pactl no longer reports: a
      // disconnected bluetooth device, or an unplugged one. Name it from what
      // we last saw, not from the identifier, and leave it marked unavailable so
      // it renders ghosted.
      outRows.push({ key: r2.sink, label: root.sinkLabels[r2.sink] || Model.friendlySinkName(r2.sink), sub: "offline", isDefault: false, available: false, offline: true })
      sinkKeys[r2.sink] = 1
    }
    var outSig = JSON.stringify(outRows.map(function(o) {
      return [o.key, o.label, o.available === undefined ? "" : (o.available ? 1 : 0), o.offline ? 1 : 0]
    }))
    if (outSig !== root._outRowsSig) {
      root._outRowsSig = outSig
      root.outputRows = outRows
    }

    root.pinnedCount = 0
    for (i = 0; i < order.length; ++i) if (order[i].rule) root.pinnedCount++
  }

  function rowForKey(key) {
    for (var i = 0; i < root.appRows.length; ++i) if (root.appRows[i].key === key) return root.appRows[i]
    return null
  }

  function rowIndexForKey(key) {
    for (var i = 0; i < root.appRows.length; ++i) if (root.appRows[i].key === key) return i
    return -1
  }

  function outputIndexFor(name) {
    for (var i = 0; i < root.outputRows.length; ++i) if (root.outputRows[i].key === name) return i
    return -1
  }

  function targetsFor(row) {
    var list = []
    var pin = (row.rule && row.rule.sink && row.rule.sink !== "__default__") ? row.rule.sink : ""
    if (pin !== "") {
      // While routing is off the rule is stored but not in effect, so it draws
      // as a dashed "stored" line rather than a live pin.
      list.push({ name: pin, style: root.routingOn ? "pinned" : "stored" })
      return list
    }
    if (row.isPending) {
      list.push({ name: root.defaultSinkName, style: "pending" })
      return list
    }
    if (row.pendingDefault) {
      list.push({ name: root.defaultSinkName, style: "pending" })
      return list
    }
    if (row.streams.length > 0) {
      var actual = Model.distinctStreamTargets(row, root.defaultSinkName)
      if (actual.length > 0) return actual
    }
    list.push({ name: root.defaultSinkName, style: "default" })
    return list
  }

  // ------------------------------------------------------------ keyboard cursor

  function resetCursor() {
    root.cursorActive = false
    root.cursorSection = "header"
    root.cursorRow = 0
    root.appCursorKey = root.appRows.length > 0 ? root.appRows[0].key : ""
    root.outCursorKey = root.outputRows.length > 0 ? root.outputRows[0].key : ""
  }

  // The app the outputs column is targeting. Entering the outputs column from
  // an app row sets this, so Return/x/1-9 always have a subject even when the
  // cursor is parked on the output side.
  function currentAppRow() {
    if (root.appRows.length === 0) return null
    // Inside the apps column the cursor row is the source of truth, and
    // appCursorKey is updated to follow it. appCursorKey only takes over as the
    // remembered subject once the cursor has crossed into the outputs column,
    // where cursorRow indexes outputs instead of apps.
    if (root.cursorSection === "apps") {
      var active = root.appRows[Math.min(root.cursorRow, root.appRows.length - 1)]
      if (active) root.appCursorKey = active.key
      return active
    }
    if (root.appCursorKey !== "") {
      var r = root.rowForKey(root.appCursorKey)
      if (r) return r
    }
    root.appCursorKey = root.appRows[0].key
    return root.rowForKey(root.appCursorKey)
  }

  function currentOutputKey() {
    if (root.outputRows.length === 0) return ""
    // Mirror of currentAppRow: the row is authoritative while the cursor is in
    // the outputs column, outCursorKey only remembers it afterwards.
    if (root.cursorSection === "outputs") {
      var active = root.outputRows[Math.min(root.cursorRow, root.outputRows.length - 1)]
      if (active) root.outCursorKey = active.key
      return root.outCursorKey
    }
    if (root.outCursorKey !== "" && root.outputIndexFor(root.outCursorKey) >= 0) return root.outCursorKey
    root.outCursorKey = root.outputRows[0].key
    return root.outCursorKey
  }

  // Keep the cursor on the same subject across a rebuild: re-resolve the
  // remembered keys to fresh indices, and fall back to a clamp only when the
  // subject is genuinely gone. cursorRow has to follow the re-resolved key of
  // whichever column is active, or the highlight and the row would disagree.
  function clampCursor() {
    if (root.outputRows.length === 0) {
      root.outCursorKey = ""
    } else {
      var oi = root.outputIndexFor(root.outCursorKey)
      oi = oi >= 0 ? oi : 0
      root.outCursorKey = root.outputRows[oi].key
      if (root.cursorSection === "outputs") root.cursorRow = oi
    }
    if (root.appRows.length === 0) {
      root.appCursorKey = ""
    } else {
      var ai = root.rowIndexForKey(root.appCursorKey)
      ai = ai >= 0 ? ai : 0
      root.appCursorKey = root.appRows[ai].key
      if (root.cursorSection === "apps") root.cursorRow = ai
    }
    if (root.cursorSection === "header") return
    var max = root.cursorRowCount - 1
    root.cursorRow = Math.max(0, Math.min(root.cursorRow, max))
  }

  function moveCursor(delta) {
    if (root.cursorSection === "header") {
      if (delta > 0 && root.cursorRowCount > 0) {
        root.cursorSection = "apps"
        root.syncCursorRow()
      }
      return
    }
    if (delta < 0 && root.cursorRow === 0) {
      root.cursorSection = "header"
      return
    }
    root.cursorRow = Math.max(0, Math.min(root.cursorRow + delta, root.cursorRowCount - 1))
    root.syncCursorRow()
  }

  function moveCursorH(delta) {
    if (root.cursorSection === "header") return
    if (delta > 0) {
      if (root.cursorSection === "apps") {
        var row = root.currentAppRow()
        if (!row) return
        root.appCursorKey = row.key
        // Start on the output this app is actually on, so Right lands on
        // something meaningful rather than an arbitrary row.
        var targets = root.targetsFor(row)
        var want = targets.length > 0 ? targets[0].name : root.defaultSinkName
        var oi = root.outputIndexFor(want)
        root.cursorRow = oi >= 0 ? oi : root.cursorRow
        // Switch columns before syncing: the resolvers read cursorRow against
        // the column they are in, so the new row has to be resolved as an
        // output, not as the app row it was borrowed from.
        root.cursorSection = "outputs"
        root.syncCursorRow()
      }
      return
    }
    if (root.cursorSection === "outputs") {
      root.cursorSection = "apps"
      var ai = root.rowIndexForKey(root.appCursorKey)
      if (ai >= 0) root.cursorRow = ai
      root.syncCursorRow()
    }
  }

  // Push the active section's subject into the shared hover properties, which
  // is what the row highlights and the canvas already read. No cursor-specific
  // rendering needed, and mouse hover stays the same visual language.
  function syncCursorRow() {
    if (root.cursorSection === "outputs") {
      var ok = root.currentOutputKey()
      root.hoverTarget = root.cursorActive ? ok : ""
      root.hoverAppKey = ""
      return
    }
    var key = ""
    if (root.cursorSection === "apps" && root.cursorActive) {
      var row = root.currentAppRow()
      if (row) key = row.key
    }
    root.hoverAppKey = key
    root.hoverTarget = ""
  }

  function setHeaderCursor() {
    root.cursorActive = true
    root.cursorSection = "header"
    root.hoverAppKey = ""
    root.hoverTarget = ""
  }

  function toggleRoutingFromCursor() {
    if (root.hostWidget && root.hostWidget.setWatchEnabled)
      root.hostWidget.setWatchEnabled(!root.routingOn)
  }

  function activateCursor() {
    if (root.cursorSection === "header") {
      root.toggleRoutingFromCursor()
      return
    }
    var row = root.currentAppRow()
    var out = root.currentOutputKey()
    if (!row || !out) return
    root.commitLink(row.key, out)
  }

  function deleteCursor() {
    var row = root.currentAppRow()
    if (!row) return
    root.unpinKey(row.key)
  }

  function quickRouteCursor(digit) {
    var n = parseInt(digit, 10)
    if (!(n >= 1 && n <= 9)) return
    if (root.outputRows.length < n) return
    var row = root.currentAppRow()
    if (!row) return
    root.commitLink(row.key, root.outputRows[n - 1].key)
  }

  // The built-in panels keep the focused row inside the viewport; without this
  // j/k can walk the cursor off-screen. There is no ListView here, so do it
  // against the Flickable directly.
  function ensureCursorVisible() {
    if (!routerScroll) return
    var maxY = Math.max(0, routerScroll.contentHeight - routerScroll.height)
    if (maxY <= 0) return
    var top = root.cursorRow * root.rowStep
    var bottom = top + root.rowH
    var margin = Style.space(6)
    if (root.cursorSection === "header" || top < routerScroll.contentY + margin) {
      routerScroll.contentY = Math.max(0, Math.min(maxY, top - margin))
    } else if (bottom > routerScroll.contentY + routerScroll.height - margin) {
      routerScroll.contentY = Math.max(0, Math.min(maxY, bottom + margin - routerScroll.height))
    }
  }

  // ------------------------------------------------------------- interaction

  function startDragAt(x, y) {
    var idx = Math.floor(y / root.rowStep)
    if (idx < 0 || idx >= root.appRows.length) return
    var row = root.appRows[idx]
    root.dragRowIndex = idx
    root.dragKey = row.key
    root.selectKey = row.key
    root.dragging = true
    root.ghostX = x
    root.ghostY = y
    root.ghostFrom = root.dotCenterFor(row.key, "app")
    root.logEvent("drag start key=" + row.key + " app=" + (row.appName || "") + " bin=" + (row.binary || "") + " node=" + (row.nodeName || ""))
    linkCanvas.requestPaint()
  }

  function updateDragAt(x, y) {
    root.ghostX = x
    root.ghostY = y
    root.hoverTarget = root.outputAt(x, y)
    linkCanvas.requestPaint()
  }

  function endDragAt(x, y) {
    var target = root.outputAt(x, y)
    if (target === null) target = root.snapOutputAt(x, y)
    var overApp = root.rowKeyAt(x, y)
    root.dragging = false
    root.hoverTarget = ""
    root.hoverAppKey = ""
    root.ghostFrom = null
    linkCanvas.requestPaint()
    if (target !== null) {
      root.commitLink(root.dragKey, target)
      root.dragRowIndex = -1
      root.dragKey = ""
      root.selectKey = ""
      return
    }
    if (overApp === root.dragKey) {
      // plain click on the same row — arm click-to-click selection
      root.selectKey = root.dragKey
    } else {
      root.selectKey = ""
    }
    root.dragRowIndex = -1
    root.dragKey = ""
    Qt.callLater(root.requestState)
  }

  function snapOutputAt(x, y) {
    var pad = Style.space(12)
    if (outputRepeater.count === 0) return null
    if (x < outCol.x - pad || x > outCol.x + outCol.width + pad) return null
    if (y < 0 || y >= root.outputRows.length * root.rowStep) return null
    var idx = Math.floor(y / root.rowStep)
    if (idx >= root.outputRows.length) return null
    var key = root.outputRows[idx].key
    if (key === "__default__") return null
    if (x < outCol.x) root.logEvent("snap drop x=" + Math.round(x) + " y-row=" + idx + " -> " + key)
    return key
  }

  function resetDrag() {
    root.dragging = false
    root.dragRowIndex = -1
    root.dragKey = ""
    root.selectKey = ""
    root.hoverTarget = ""
    root.hoverAppKey = ""
    root.ghostFrom = null
    linkCanvas.requestPaint()
  }

  function badgeHit(x, y, row) {
    var inRow = y - Math.floor(y / root.rowStep) * root.rowStep
    if (inRow < 0 || inRow >= root.rowH) return false
    var cx = appCol.width - root.appGutter
    var half = Style.space(9)
    return x >= cx - half && x <= cx + half
  }

  function rowKeyAt(x, y) {
    if (appRepeater.count === 0) return ""
    if (y < 0 || y >= appRepeater.count * root.rowStep) return ""
    if (x < 0 || x > appCol.width) return ""
    var idx = Math.floor(y / root.rowStep)
    if (idx >= root.appRows.length) return ""
    return root.appRows[idx].key
  }

  function outputAt(x, y) {
    if (outputRepeater.count === 0) return null
    if (x < outCol.x || x > outCol.x + outCol.width) return null
    if (y < 0 || y >= root.outputRows.length * root.rowStep) return null
    var idx = Math.floor(y / root.rowStep)
    if (idx >= root.outputRows.length) return null
    var key = root.outputRows[idx].key
    if (key === "__default__") return null
    return key
  }

  function commitLink(key, outName) {
    var row = root.rowForKey(key)
    root.selectKey = ""
    if (!row) return
    var sinkArg = (outName === "__default__") ? "__default__" : outName
    // Routing off: persist the rule but leave the stream alone — the watcher
    // applies it on the next switch-on. A reset still moves, because "every
    // stream is already on the default" is exactly what off means.
    var storeOnly = !root.routingOn && sinkArg !== "__default__"
    root.logEvent("link " + (storeOnly ? "store-only " : "") + "key=" + key + " app=" + (row.appName || "") + " bin=" + (row.binary || "") + " target=" + (sinkArg === "__default__" ? "_default_" : sinkArg))
    root.pendingWrites = root.pendingWrites.filter(function(w) {
      return Model.ruleKey(w) !== key
    })
    if (sinkArg !== "__default__") {
      root.pendingWrites.push({
        app: row.appName || "",
        binary: row.binary || "",
        node: row.nodeName || "",
        sink: sinkArg,
        ts: Date.now()
      })
    }
    root.buildRows()
    Qt.callLater(root.rebuildPatch)
    Quickshell.execDetached(["python3", root.helperPath(), storeOnly ? "set-rule" : "set-sink", row.appName || "", row.binary || "", row.nodeName || "", sinkArg])
    root.refreshAfterCommit()
  }

  function unpinKey(key) {
    var row = root.rowForKey(key)
    if (!row) return
    root.logEvent("unpin key=" + key + " app=" + (row.appName || "") + " bin=" + (row.binary || ""))
    root.pendingWrites = root.pendingWrites.filter(function(w) {
      return Model.ruleKey(w) !== key
    })
    root.pendingWrites.push({
      app: row.appName || "",
      binary: row.binary || "",
      node: row.nodeName || "",
      sink: "__default__",
      ts: Date.now()
    })
    root.selectKey = ""
    root.buildRows()
    Qt.callLater(root.rebuildPatch)
    Quickshell.execDetached(["python3", root.helperPath(), "set-sink", row.appName || "", row.binary || "", row.nodeName || "", "__default__"])
    root.refreshAfterCommit()
  }

  function logEvent(msg) {
    console.log("[petealeon.router] " + msg)
  }

  function refreshAfterCommit() {
    root.requestState()
    commitRetry.restart()
  }

  Timer {
    id: commitRetry
    interval: 200
    onTriggered: {
      root.requestState()
      root.prunePendingWrites()
    }
  }

  // ------------------------------------------------------------- patch lines

  function dotCenterFor(id, side) {
    if (side === "app") {
      var ai = root.rowIndexForKey(id)
      if (ai < 0) return null
      return { x: appCol.width - root.appGutter, y: ai * root.rowStep + root.rowH * 0.5 }
    }
    var oi = root.outputIndexFor(id)
    if (oi < 0) return null
    return { x: outCol.x + root.outDotX, y: oi * root.rowStep + root.rowH * 0.5 }
  }

  function rebuildPatch() {
    var lines = []
    var i, t
    for (i = 0; i < root.appRows.length; ++i) {
      var row = root.appRows[i]
      var tg = root.targetsFor(row)
      for (t = 0; t < tg.length; ++t) {
        var oi = root.outputIndexFor(tg[t].name)
        if (oi < 0) continue
        lines.push({ from: row.key, to: root.outputRows[oi].key, style: tg[t].style })
      }
    }
    root.lineSpecs = lines
    linkCanvas.requestPaint()
  }

  function bezierAt(p0, p1, p2, p3, t) {
    var u = 1 - t
    var uu = u * u
    var tt = t * t
    return {
      x: uu * u * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + tt * t * p3.x,
      y: uu * u * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + tt * t * p3.y
    }
  }

  function strokeLine(ctx, l) {
    var col = root.lineColor(l.style)
    var w = 1.4
    var dash = []
    var a = 0.72
    var glow = false
    var endpoint = false
    if (l.style === "pinned") {
      w = 2
      a = 0.95
      glow = true
      endpoint = true
    } else if (l.style === "pending") {
      w = 1.6
      a = 0.6
      endpoint = true
    } else if (l.style === "stored") {
      // Saved but not in effect (routing is off). Dashed, dim, and with no
      // endpoint dot — a solid line with a dot here would claim the stream is
      // actually sitting on that output.
      w = 1.6
      a = 0.5
      dash = [3, 4]
    } else if (l.style === "live") {
      w = 1.4
      a = 0.85
    } else if (l.style === "ghost") {
      w = 2.4
      a = 0.95
      dash = [4, 5]
    }
    if (glow) {
      ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, a * 0.22)
      ctx.lineWidth = w + 4
      ctx.setLineDash([])
      ctx.beginPath()
      ctx.moveTo(l.x1, l.y1)
      ctx.bezierCurveTo(l.x1 + root.connectorLever, l.y1, l.x2 - root.connectorLever, l.y2, l.x2, l.y2)
      ctx.stroke()
    }
    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, a)
    ctx.lineWidth = w
    ctx.setLineDash(dash)
    ctx.beginPath()
    ctx.moveTo(l.x1, l.y1)
    ctx.bezierCurveTo(l.x1 + root.connectorLever, l.y1, l.x2 - root.connectorLever, l.y2, l.x2, l.y2)
    ctx.stroke()
    ctx.setLineDash([])
    if (endpoint) {
      ctx.beginPath()
      ctx.arc(l.x2, l.y2, 3, 0, 2 * Math.PI)
      ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, a)
      ctx.fill()
    }
  }

  // ---------------------------------------------------------------- panel UI

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    // Placement is overridden by the card x/y Bindings above. This stays false
    // so that if root.card ever fails to resolve, the shell's fallback is
    // icon-centred rather than screen-centred.
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(routerColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        // First arrow only wakes the cursor: it must not also move or scroll,
        // or the panel jumps the moment it opens under a stray keypress.
        if (!root.cursorActive) {
          root.cursorActive = true
          root.syncCursorRow()
          root.ensureCursorVisible()
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
        root.syncCursorRow()
        root.ensureCursorVisible()
      }
      onActivateRequested: {
        if (!root.cursorActive) { root.cursorActive = true; root.syncCursorRow(); return }
        root.activateCursor()
      }
      onDeleteRequested: {
        if (!root.cursorActive) return
        root.deleteCursor()
        root.syncCursorRow()
      }
      onTextKey: function(t) {
        if (t >= "1" && t <= "9") {
          if (!root.cursorActive) { root.cursorActive = true; root.syncCursorRow() }
          root.quickRouteCursor(t)
          root.syncCursorRow()
        }
      }
    }

    Flickable {
      id: routerScroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: routerColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: routerColumn
        width: routerScroll.width
        spacing: Style.spacing.controlGap

      PanelHero {
        id: hero
        width: parent.width
        title: "Audio Router"
        meta: "drag app → output\nclick the ring to unlink"
        foreground: root.textColor
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        iconOpacity: root.routingOn ? 1.0 : 0.5
        iconComponent: Component {
          Text {
            anchors.centerIn: parent
            font.family: hero.fontFamily
            font.pixelSize: Style.font.display
            color: root.textColor
            text: root.label
          }
        }

        trailingControl: Component {
          ToggleSwitch {
            id: powerSwitch
            checked: root.routingOn
            foreground: hero.foreground
            hasCursor: root.headerHasCursor
            onHovered: function(on) { if (on) root.setHeaderCursor() }
            onToggled: {
              if (root.hostWidget && root.hostWidget.setWatchEnabled)
                root.hostWidget.setWatchEnabled(!root.routingOn)
            }

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: root.toggleHint
              fontFamily: hero.fontFamily
            }
          }
        }
      }

      // Degraded pactl beats the "routing off" note — an unreadable pactl
      // means routing cannot work at all, regardless of the switch position.
      // A failed revert outranks both: the switch says off while audio is
      // still pinned, and saying "edits kept, applied when switched on" there
      // would be a lie about the current state.
      Text {
        id: statusNote
        width: parent.width
        visible: root.stateError !== "" || root.restoreError !== "" || !root.routingOn
        font.pixelSize: Style.font.caption
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        color: root.stateError !== "" || root.restoreError !== "" ? Qt.rgba(0.85, 0.66, 0.24, 1) : root.textColor
        opacity: root.stateError !== "" || root.restoreError !== "" ? 1.0 : 0.6
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.stateError !== ""
          ? "routing unavailable — " + root.stateError
          : root.restoreError !== ""
            ? "routing off — some apps are still routed: " + root.restoreError
            : "routing off — edits kept, applied when switched on"
      }

      PanelSeparator {
        foreground: root.textColor
      }

      Item {
        id: patchArea
        width: parent.width
        height: Math.max(root.appRows.length, root.outputRows.length) * root.rowStep
        // While routing is off, drag/drop still works (edits are kept and
        // applied when the switch comes back on), but the whole patch is dimmed
        // so nothing reads as actively routed. The statusNote above carries the
        // reason.
        opacity: root.routingOn ? 1.0 : 0.55

        Column {
          id: appCol
          x: 0
          y: 0
          width: parent.width - outCol.width
          spacing: 0
          z: 2

          Repeater {
            id: appRepeater
            model: root.appRows
            delegate: Component {
              Item {
                id: appDlg
                required property var model
                readonly property string dkey: model.key
                width: appCol.width
                height: root.rowStep

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(4)
                  color: (root.hoverAppKey === appDlg.dkey || root.dragKey === appDlg.dkey)
                    ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
                    : "transparent"
                }

                Item {
                  id: appLine
                  anchors.top: parent.top
                  width: parent.width
                  height: root.rowH

                  // "This source is producing audio right now." Accent when the
                  // stream is pinned to one of the user's routes, plain
                  // foreground when it is just on the system default.
                  Text {
                    id: appSpeaker
                    x: root.appDotX
                    anchors.verticalCenter: parent.verticalCenter
                    visible: model.streams.length > 0
                    font.pixelSize: Style.font.caption
                    color: (model.rule || model.pendingDefault) ? root.userRouteColor : root.textColor
                    text: "\uF028"
                  }

                  Text {
                    id: appLabel
                    x: root.appDotX + root.speakerGutter
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(root.minLabelW, appCol.width - root.appDotX - root.appGutter - Style.space(16) - (model.streams.length > 1 ? Style.space(18) : 0))
                    elide: Text.ElideRight
                    font.pixelSize: Style.font.body
                    color: root.textColor
                    opacity: (model.streams.length === 0 && !model.rule && !model.isPending) ? 0.55 : 1.0
                    text: model.label
                  }

                  Text {
                    visible: model.streams.length > 1
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Style.font.caption
                    color: root.textColor
                    opacity: 0.5
                    text: String(model.streams.length)
                  }

                  Rectangle {
                    id: appDot
                    width: 6
                    height: 6
                    radius: 3
                    x: appLine.width - root.appGutter - 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: (model.rule || model.pendingDefault) ? root.userRouteColor : root.textColor
                    opacity: model.streams.length === 0 ? 0.25 : 0.6

                    Rectangle {
                    id: appRing
                    anchors.centerIn: parent
                    width: 13
                    height: 13
                    radius: 6.5
                    color: "transparent"
                    visible: !!(model.rule || model.pendingDefault)
                    border.width: 1.5
                    border.color: root.userRouteColor
                    MouseArea {
                      anchors.fill: parent
                      acceptedButtons: Qt.NoButton
                      cursorShape: Qt.PointingHandCursor
                    }
                  }
                  }
                }
              }
            }
          }
        }

        Column {
          id: outCol
          x: parent.width - width
          y: 0
          width: Style.space(178)
          spacing: 0
          z: 2

          Repeater {
            id: outputRepeater
            model: root.outputRows
            delegate: Component {
              Item {
                id: outDlg
                required property var model
                readonly property string okey: model.key
                width: outCol.width
                height: root.rowStep

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(4)
                  color: (root.dragging && root.hoverTarget === outDlg.okey)
                    ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
                    : "transparent"
                }

                Item {
                  anchors.top: parent.top
                  width: parent.width
                  height: root.rowH

                  Text {
                    x: root.outDotX + Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: outCol.width - (x + Style.space(6)) - (model.offline ? Style.space(34) : 0)
                    elide: Text.ElideRight
                    font.pixelSize: Style.font.body
                    color: root.textColor
                    opacity: model.available === false ? 0.35 : 1.0
                    text: model.label
                  }

                  Text {
                    visible: model.offline === true
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Style.font.caption
                    color: root.textColor
                    opacity: 0.4
                    text: model.sub || "offline"
                  }

                  Rectangle {
                    id: outDot
                    width: 6
                    height: 6
                    radius: 3
                    y: root.rowH / 2 - 3
                    x: root.outDotX - 3
                    color: root.accent
                    opacity: 0.7
                  }
                }
              }
            }
          }
        }

        Canvas {
          id: linkCanvas
          anchors.fill: parent
          z: 1
          clip: true
          onPaint: {
            var ctx = getContext("2d")
            if (!ctx) return
            ctx.clearRect(0, 0, width, height)
            var i
            for (i = 0; i < root.lineSpecs.length; ++i) {
              var sp = root.lineSpecs[i]
              var pf = root.dotCenterFor(sp.from, "app")
              var pt = root.dotCenterFor(sp.to, "out")
              if (!pf || !pt) continue
              root.strokeLine(ctx, {
                x1: pf.x, y1: pf.y, x2: pt.x, y2: pt.y, style: sp.style
              })
            }
            if (root.dragging && root.dragRowIndex >= 0) {
              var gx1 = appCol.width - root.appGutter
              var gy1 = root.dragRowIndex * root.rowStep + root.rowH * 0.5
              if (root.ghostFrom) {
                gx1 = root.ghostFrom.x
                gy1 = root.ghostFrom.y
              }
              root.strokeLine(ctx, {
                x1: gx1,
                y1: gy1,
                x2: root.ghostX,
                y2: root.ghostY,
                style: "ghost"
              })
            }
            ctx.setLineDash([])
          }
          onWidthChanged: Qt.callLater(root.rebuildPatch)
          onHeightChanged: Qt.callLater(root.rebuildPatch)
        }

        MouseArea {
          id: patchMouse
          anchors.fill: parent
          z: 1
          hoverEnabled: true
          preventStealing: true
          acceptedButtons: Qt.LeftButton

          onPositionChanged: (m) => {
            root.hoverAppKey = root.rowKeyAt(m.x, m.y)
            if (root.dragging) root.updateDragAt(m.x, m.y)
          }

          onPressed: (m) => {
            var akey = root.rowKeyAt(m.x, m.y)
            if (akey !== "") {
              var arow = root.rowForKey(akey)
              if (arow && (arow.rule || arow.pendingDefault) && root.badgeHit(m.x, m.y, arow)) {
                root.unpinKey(akey)
                return
              }
              root.startDragAt(m.x, m.y)
              return
            }
            var oat = root.outputAt(m.x, m.y)
            if (oat !== null && root.selectKey !== "") {
              root.commitLink(root.selectKey, oat)
            } else {
              root.selectKey = ""
            }
          }

          onReleased: (m) => {
            if (root.dragging) root.endDragAt(m.x, m.y)
          }
        }
      }
    }
  }
}
}