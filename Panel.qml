import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "peter.router"
  ipcTarget: "peter.router"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

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
  property var pendingWrites: []
  property string defaultSinkName: ""
  property string stateSignature: ""
  property bool stateLoaded: false

  property var appRows: []
  property var outputRows: []
  property var pendingApps: []
  property int pinnedCount: 0
  property string _appRowsSig: ""
  property string _outRowsSig: ""

  // ------------------------------------------------------------------ state

  property string accent: Color.accent
  readonly property color textColor: root.bar ? root.bar.foreground : Color.popups.text

  // Omarchy theme roles: accent = "your routes" highlight, foreground =
  // system routes (neutral). Both re-evaluate live when the theme swaps.
  readonly property color userRouteColor: Color.accent
  readonly property color standardRouteColor: Color.foreground

  function lineColor(style) {
    if (style === "pinned" || style === "ghost" || style === "pending") return root.userRouteColor
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
  readonly property int headerActionsWidth: Style.space(28)
  readonly property int watchStatusWidth: Style.space(84)

  function watchColor() {
    if (!root.hostWidget) return root.textColor
    if (root.hostWidget.watchDead) return Qt.rgba(0.88, 0.2, 0.2, 1)
    if (root.hostWidget.watchRestarts > 0) return Qt.rgba(0.9, 0.66, 0.24, 1)
    return Qt.rgba(0.34, 0.78, 0.42, 1)
  }

  function watchStatusText() {
    if (!root.hostWidget) return "watch"
    if (root.hostWidget.watchDead) return "dead"
    if (root.hostWidget.watchRestarts > 0) return "restart " + root.hostWidget.watchRestarts
    return "alive"
  }

  function watchTooltip() {
    var v = (root.hostWidget && root.hostWidget.version) ? root.hostWidget.version : "?"
    var pid = (root.hostWidget && root.hostWidget.watchPid) ? root.hostWidget.watchPid : 0
    return "peter.router v" + v + " · watcher " + root.watchStatusText() + (pid ? " (pid " + pid + ")" : "") + "\nclick to restart"
  }
  readonly property var systemBinaries: {
    var s = {}
    var list = ["pipewire", "wireplumber", "pactl", "python3", "pw-dump", "xdg-desktop-portal", "xdg-desktop-portal-hyprland", "quickshell", "easyeffects", "systemd"]
    for (var i = 0; i < list.length; ++i) s[list[i]] = 1
    return s
  }

  readonly property bool busy: root.dragging || root.showAddPicker

  // interaction
  property string dragKey: ""
  property int dragRowIndex: -1
  property string selectKey: ""
  property bool dragging: false
  property real ghostX: 0
  property real ghostY: 0
  property string hoverAppKey: ""
  property string hoverTarget: ""
  property var _clientCount: {}
  property bool _hadInputs: false
  property int _emptyStreak: 0
  property bool showAddPicker: false

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
      root.showAddPicker = false
      root.requestState()
    } else {
      root.resetDrag()
    }
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
      obj.defaultSink || ""
    ])
    if (sig === root.stateSignature) return
    root.stateSignature = sig
    root.sinks = obj.sinks || []
    root.sinkInputs = obj.sinkInputs || []
    root.clients = obj.clients || []
    root.rules = obj.rules || []
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

    for (i = 0; i < root.pendingApps.length; ++i) {
      var p = root.pendingApps[i]
      var pk = Model.appKey({ binary: p.binary, appName: p.appName })
      if (rowsMap[pk]) {
        rowsMap[pk].isPending = true
      } else {
        var pendRow = { key: pk, label: p.appName || p.binary || pk, binary: p.binary || "", appName: p.appName || "", streams: [], rule: null, isPending: true, idle: true }
        rowsMap[pk] = pendRow
        order.push(pendRow)
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
      outRows.push({ key: r2.sink, label: r2.sink, sub: "offline", isDefault: false, available: false, offline: true })
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
      list.push({ name: pin, style: "pinned" })
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
    if (root.showAddPicker || appRepeater.count === 0) return ""
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

  function pickerAt(x, y) {
    if (!root.showAddPicker || pickerRepeater.count === 0) return -1
    if (x < 0 || x > appCol.width) return -1
    var yRow = y - Style.space(16)
    if (yRow < 0 || yRow >= pickerRepeater.count * root.rowStep) return -1
    return Math.floor(yRow / root.rowStep)
  }

  function commitLink(key, outName) {
    var row = root.rowForKey(key)
    root.selectKey = ""
    root.showAddPicker = false
    if (!row) return
    var sinkArg = (outName === "__default__") ? "__default__" : outName
    root.logEvent("link key=" + key + " app=" + (row.appName || "") + " bin=" + (row.binary || "") + " target=" + (sinkArg === "__default__" ? "_default_" : sinkArg))
    root.pendingApps = root.pendingApps.filter(function(p) {
      return Model.appKey({ binary: p.binary, appName: p.appName }) !== key
    })
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
    Quickshell.execDetached(["python3", root.helperPath(), "set-sink", row.appName || "", row.binary || "", row.nodeName || "", sinkArg])
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
    root.showAddPicker = false
    root.buildRows()
    Qt.callLater(root.rebuildPatch)
    Quickshell.execDetached(["python3", root.helperPath(), "set-sink", row.appName || "", row.binary || "", row.nodeName || "", "__default__"])
    root.refreshAfterCommit()
  }

  function logEvent(msg) {
    console.log("[peter.router] " + msg)
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

  function pendingAdd(appName, binary) {
    root.pendingApps.push({ appName: appName, binary: binary || "" })
    root.showAddPicker = false
    root.buildRows()
    Qt.callLater(root.rebuildPatch)
  }

  function toggleAddPicker() {
    root.showAddPicker = !root.showAddPicker
    if (root.showAddPicker) root.selectKey = ""
  }

  readonly property var candidates: {
    if (!root.stateLoaded) return []
    var keys = {}
    var i
    for (i = 0; i < root.appRows.length; ++i) keys[root.appRows[i].key] = 1
    var out = []
    for (i = 0; i < root.clients.length; ++i) {
      var c = root.clients[i]
      var cleaned = Model.stripInput(c.appName)
      var k = Model.appKey({ binary: c.binary, appName: cleaned })
      if (keys[k]) continue
      out.push({ appName: cleaned, binary: c.binary })
    }
    return out
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
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(routerColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onReturnRequested: root.toggleAddPicker()
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) {
          routerScroll.contentY = Math.max(0, Math.min(routerScroll.contentHeight - routerScroll.height,
            routerScroll.contentY + dy * Style.space(40)))
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

      Row {
        id: header
        width: parent.width
        spacing: Style.spacing.controlGap

        Text {
          width: parent.width - root.headerActionsWidth - root.watchStatusWidth
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          font.pixelSize: Style.font.title
          color: root.textColor
          text: "Audio routes"
        }

        Item {
          id: watchStatus
          width: root.watchStatusWidth
          height: root.rowH

          Rectangle {
            id: statusDot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: Style.space(7)
            radius: Style.space(3.5)
            color: root.watchColor()
          }

          Text {
            anchors.right: statusDot.left
            anchors.rightMargin: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Style.font.caption
            color: root.textColor
            opacity: 0.75
            text: root.watchStatusText()

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.NoButton
              cursorShape: Qt.PointingHandCursor
            }
          }

          MouseArea {
            id: watchStatusMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
              if (root.hostWidget && root.hostWidget.restartWatcher) root.hostWidget.restartWatcher()
            }
          }

          ToolTip.visible: watchStatusMouse.hovered
          ToolTip.text: root.watchTooltip()
          ToolTip.delay: 400
        }

        Item {
          id: headerActions
          width: Style.space(64)
          height: root.rowH

          Text {
            id: addButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Style.font.body
            color: root.accent
            visible: root.candidates.length > 0
            text: root.showAddPicker ? "\u2715" : "+"
            MouseArea {
              anchors.fill: parent
              onClicked: root.toggleAddPicker()
            }
          }
        }
      }

      Text {
        width: parent.width
        font.pixelSize: Style.font.caption
        color: root.textColor
        opacity: 0.5
        horizontalAlignment: Text.AlignHCenter
        text: "drag app → output · click ring to unlink"
      }

      Item {
        id: patchArea
        width: parent.width
        height: Math.max(root.appRows.length, root.outputRows.length) * root.rowStep

        Column {
          id: appCol
          x: 0
          y: 0
          width: parent.width - outCol.width
          spacing: 0
          z: 2
          visible: !root.showAddPicker

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

                Rectangle {
                  id: appBox
                  visible: model.streams.length > 0
                  x: root.appDotX - Style.space(4)
                  y: Style.space(2)
                  width: Math.max(root.minLabelW + Style.space(26), (appDot.x + appDot.width) - x)
                  height: root.rowStep - Style.space(4)
                  radius: Style.space(8)
                  color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.9)
                  border.width: 1
                  border.color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.3)
                }

                Item {
                  id: appLine
                  anchors.top: parent.top
                  width: parent.width
                  height: root.rowH

                  Text {
                    id: appLabel
                    x: root.appDotX + Style.space(10)
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
          id: pickerCol
          x: 0
          y: 0
          width: parent.width - outCol.width
          z: 2
          visible: root.showAddPicker
          spacing: 0

          Text {
            width: parent.width
            height: Style.space(16)
            elide: Text.ElideRight
            font.pixelSize: Style.font.caption
            color: root.textColor
            opacity: 0.45
            text: "Not currently playing"
          }

          Repeater {
            id: pickerRepeater
            model: root.candidates
            delegate: Component {
              Item {
                id: pickDlg
                required property var model
                width: pickerCol.width
                height: root.rowStep

                Text {
                  x: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: pickerCol.width - Style.space(16)
                  elide: Text.ElideRight
                  font.pixelSize: Style.font.body
                  color: root.textColor
                  text: model.appName
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
            if (root.showAddPicker) return
            root.hoverAppKey = root.rowKeyAt(m.x, m.y)
            if (root.dragging) root.updateDragAt(m.x, m.y)
          }

          onPressed: (m) => {
            if (root.showAddPicker) {
              var pi = root.pickerAt(m.x, m.y)
              if (pi >= 0) {
                var cand = root.candidates[pi]
                root.pendingAdd(cand.appName, cand.binary)
              }
              return
            }
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