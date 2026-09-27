// petealeon.router data helpers.
//
// Contract with assets/omarchy-router list:
//   { sinks:[{index,name,desc,available}], defaultSink, sinkInputs:[{id,appName,binary,nodeName,sink,sinkName}],
//     clients:[{appName,binary}], rules:[{app,binary,sink}] }
// rule.sink is the output NAME (or "__default__").
// binary values are already basenames.

function basename(p) {
  p = String(p || "")
  var i = p.lastIndexOf("/")
  return stripDeleted(i >= 0 ? p.substring(i + 1) : p)
}

// Component names that must display under their parent app. "ringrtc" is
// Signal Desktop's WebRTC voice engine: it keeps a PipeWire client alive even
// when no Signal window is open, and would otherwise show up as a baffling
// "ringrtc" row. Its binary is already signal-desktop, so the routing key is
// shared with the Signal row either way.
var COMPONENT_BASE = { ringrtc: "Signal" }

// PipeWire's " (deleted)" artifact. When a process's on-disk executable is
// replaced under it (a browser updating itself, a package upgrade), the binary
// is reported as "brave (deleted)". That is not a binary name, and letting it
// through splits one app into two identities: the live stream keys on
// "brave (deleted)" while its client and its stored rule key on "brave", so the
// panel rendered a second, stream-less row for the same app.
//
// Normalised here as well as in the helper on purpose. This file is the panel's
// identity authority and consumes `list` JSON, which can still carry a binary
// written into the store before the helper learned to strip it, and a rule read
// back from disk is exactly that case. Mirrors strip_deleted() in
// assets/omarchy-router; covered by scripts/model-test.js.
function stripDeleted(s) {
  var t = String(s == null ? "" : s)
  // Case-insensitive marker, but the name keeps its own case.
  return t.toLowerCase().endsWith(" (deleted)") ? t.slice(0, -" (deleted)".length).trim() : t
}

// "Brave input" -> "Brave"; the " input" suffix is a browser artifact that
// appears on the client/stream name but must not leak into display or keys.
// "Brave (deleted) input" -> "Brave" as well, hence the strip inside the branch:
// the artifact sits inside the " input" suffix, not after it.
function stripInput(name) {
  var s = stripDeleted(String(name || "").trim())
  var lower = s.toLowerCase()
  if (lower in COMPONENT_BASE) return COMPONENT_BASE[lower]
  if (lower.endsWith(" input")) {
    var t = stripDeleted(s.slice(0, -6).trim())
    if (t !== "") return t
  }
  return s
}

function listSnapshot(list) {
  return list ? list.slice() : []
}

// Pactl "Sink Input #N" is NOT the quickshell PwNodeIface id; pactl's own
// counter is the only handle pactl accepts for move-sink-input. Identity
// between the two worlds is established via the PipeWire node.name, which is
// why appKey() prefers process binary, then node name, then application name
// (browser streams often omit binary but always carry a node.name).
function appKey(entry) {
  var b = basename(String(entry ? entry.binary : "").toLowerCase())
  if (b !== "") return b
  var n = basename(String(entry ? entry.nodeName : "").toLowerCase())
  if (n !== "") return n
  return stripInput(String((entry && entry.appName) || "unknown")).toLowerCase()
}

function friendlyLabel(entry) {
  var b = basename(String(entry ? entry.binary : ""))
  return String(stripInput(entry && entry.appName) || b || (entry ? entry.nodeName : "") || "unknown")
}

function ruleKey(rule) {
  return appKey({ binary: rule ? rule.binary : "", nodeName: rule ? rule.node : "", appName: rule ? rule.app : "" })
}

function ruleForRow(row, rulesList) {
  if (!row || !rulesList) return null
  var key = row.key
  for (var i = 0; i < rulesList.length; ++i) {
    var r = rulesList[i]
    if (key === ruleKey(r)) return r
  }
  return null
}

function groupKeyed(entries, keyer) {
  var map = {}
  var order = []
  for (var i = 0; i < entries.length; ++i) {
    var k = keyer(entries[i])
    if (!(k in map)) {
      map[k] = { key: k, streams: [], rule: null, isPending: false }
      order.push(map[k])
    }
  }
  return { map: map, order: order }
}

function distinctStreamTargets(row, defaultSinkName) {
  var out = []
  var seen = {}
  var streams = row.streams || []
  for (var i = 0; i < streams.length; ++i) {
    var name = streams[i].sinkName || defaultSinkName || ""
    if (name === "") continue
    if (name in seen) continue
    seen[name] = 1
    out.push({ name: name, style: name === defaultSinkName ? "default" : "live" })
  }
  return out
}