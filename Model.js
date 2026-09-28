// petealeon.router data helpers.
//
// Contract with assets/omarchy-router list:
//   { sinks:[{index,name,desc,available}], defaultSink, sinkInputs:[{id,appName,binary,nodeName,sink,sinkName}],
//     clients:[{appName,binary}], rules:[{app,binary,node,sink}],
//     labels:{sinkName: friendlyName}, sinkAliases:{staleSinkName: liveSinkName} }
// rule.sink is the output NAME (or "__default__").
// binary values are already basenames.
// labels maps sink name to the best name we have for it, and covers rule sinks
// that pactl no longer reports — the disconnected-device case. A key present
// with an empty value means "asked, and nothing knows it".
//
// Two things here are the panel's identity authority and are mirrored, by hand,
// in assets/omarchy-router: isExcludedApp()/identitiesOverlap() below, and
// stripDeleted() above. A selftest in the helper reads this file and asserts the
// two agree, on the predicate and not merely on the shared list of names —
// comparing the lists was not enough, because both sides can hold identical
// names and still disagree about which names to reject.

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

// PipeWire tags some client names with a bracketed suffix: "WirePlumber
// [client]", "PipeWire ALSA [cliamp]". Stripping the tag is what lets the rest
// of the pipeline see one name. It is NOT evidence that the name is internal --
// see alsaClientName() for what "PipeWire ALSA [x]" actually names.
// Mirrors CLIENT_TAG_RE in assets/omarchy-router.
var CLIENT_TAG_RE = /\s*\[[^\]]{0,64}\]\s*$/

// PipeWire's wrapper name for a client that opened an ALSA PCM: the application
// is the bracketed part, not PipeWire. A live session here reports
// "PipeWire ALSA [cliamp]" for the terminal music player cliamp, whose binary is
// /usr/bin/cliamp -- a real, installed, routable application. See
// isExcludedApp() for what happened when this was treated as plumbing.
// Returns the real application name, or "" when the name is not that wrapper.
var ALSA_WRAPPER_RE = /^pipewire\s+alsa\s+\[([^\]]{1,64})\]$/i

// Applications that must never appear as a routable row. Stored lowercase and
// compared normalised, never by raw membership: pactl reports "WirePlumber"
// and "quickshell", so a list holding "wireplumber" and "Quickshell" matched
// neither. The QML copy lives here and here only; Panel.qml used to keep a
// second list in a systemBinaries property, and the two drifted.
var EXCLUDE_APPS = [
  "easyeffects", "quickshell", "wireplumber", "pipewire", "systemd",
  "pactl", "pw-dump", "python3",
  "xdg-desktop-portal", "xdg-desktop-portal-hyprland"
]

// The application named inside a PipeWire ALSA wrapper, or "" if this is not one.
function alsaClientName(name) {
  var m = ALSA_WRAPPER_RE.exec(String(name == null ? "" : name).trim())
  return m ? m[1].trim() : ""
}

// Leading tokens that name the audio stack's own namespace. There is no such
// rule any more, and its absence is deliberate: a first-word match here could
// not be tested against any name a real session reports, because every one of
// them is already in EXCLUDE_APPS, while still being able to over-match -- and
// it did. "PipeWire ALSA [x]" is not the stack, it is the application x
// (see alsaClientName), so a rule covering the pipewire namespace removed the
// installed music player cliamp from the panel. Exact names only.

function normClientName(s) {
  return String(s == null ? "" : s).replace(CLIENT_TAG_RE, "").trim().toLowerCase()
}

// True for the audio stack and our own tooling. One predicate for every call
// site -- the client rows, the rule rows and the stream rows -- because a row
// the panel offers but the matcher refuses to move is a dead end, and the
// reverse is a stream being dragged somewhere nobody asked for.
//
// Exact match on the tag-stripped name, and nothing else. There was a
// first-word namespace rule here as well, to catch stack names not yet seen;
// it is gone because it could not be tested against anything real (every stack
// name this session reports is already in EXCLUDE_APPS) while being free to
// over-match, and over-matching is how it removed a real installed application
// -- cliamp, reported as "PipeWire ALSA [cliamp]" -- from the panel. A name
// added here is a name someone has actually seen in a session.
function isExcludedApp(name) {
  return EXCLUDE_APPS.indexOf(normClientName(name)) >= 0
}

// True when a record belongs to the audio stack, by name or by binary. Both are
// consulted because either can identify it: WirePlumber arrives as the appName
// "WirePlumber [client]", and a stream reporting an unfamiliar appName with a
// binary of "wireplumber" is just as much the session manager.
function isExcludedClient(e) {
  if (!e) return false
  return isExcludedApp(e.appName) || isExcludedApp(basename(e.binary || ""))
}

// Rule shape is {app,binary,node}; stream/client shape is {appName,binary,nodeName}.
function recordAppName(e) {
  if (!e) return ""
  return e.appName != null && e.appName !== "" ? e.appName : (e.app || "")
}

function recordNodeName(e) {
  if (!e) return ""
  if (e.nodeName != null && e.nodeName !== "") return e.nodeName
  return e.node || ""
}

function listSnapshot(list) {
  return list ? list.slice() : []
}

// Pactl "Sink Input #N" is NOT the quickshell PwNodeIface id; pactl's own
// counter is the only handle pactl accepts for move-sink-input. Identity
// between the two worlds is established via the PipeWire node.name, which is
// why appKey() prefers process binary, then node name, then application name
// (browser streams often omit binary but always carry a node.name).
//
// appKey() picks the FIRST non-empty field, so it is only a name for a record,
// never the definition of an app. The definition is identityList() below; where
// the two disagreed, one app became two rows.
function appKey(entry) {
  var b = basename(String(entry ? entry.binary : "").toLowerCase())
  if (b !== "") return b
  var n = basename(String(entry ? entry.nodeName : "").toLowerCase())
  if (n !== "") return n
  return stripInput(String((entry && entry.appName) || "unknown")).toLowerCase()
}

// Every normalised name a record answers to. An app is the set of identities its
// records agree on, and two records are the same app when the sets intersect.
//
// This is the rule the helper's identities_overlap() has always used, expressed
// on the panel side. The mismatch was the bug: a stream reported without
// application.process.binary keyed on its node.name, the client and rule for the
// same app keyed on the binary, and the panel drew two rows for one app while
// the watcher moved it as one. A "brave (deleted)" split earlier, for the same
// reason in a single field; fixing that one field did not fix this one.
//
// Deduplicated, because binary and application.name routinely normalise to the
// same string and a repeated entry would make the sets read as if they agreed
// twice.
function identityList(entry) {
  var e = entry || {}
  var out = []
  var b = String(e.binary == null ? "" : e.binary).split("/").pop().trim().toLowerCase()
  var n = String(recordNodeName(e)).split("/").pop().trim().toLowerCase()
  var raw = stripInput(recordAppName(e))
  var a = raw.toLowerCase()
  if (b !== "") out.push(b)
  if (n !== "" && n !== b) out.push(n)
  if (a !== "" && a !== b && a !== n) out.push(a)
  // The application inside a "PipeWire ALSA [app]" wrapper answers to "app" as
  // well. Today the stream and its client report the identical wrapper string
  // and fold on that; if a PipeWire version ever reported the bare "cliamp" for
  // one of them and the wrapper for the other, the sets would stop intersecting
  // and the app would draw two rows again. This is what makes the fold
  // independent of how the server happens to spell it.
  var w = alsaClientName(raw).toLowerCase()
  if (w !== "" && out.indexOf(w) < 0) out.push(w)
  return out
}

function identitiesOverlap(a, b) {
  var as = identityList(a)
  if (as.length === 0) return false
  var bs = identityList(b)
  for (var i = 0; i < as.length; ++i) {
    if (bs.indexOf(as[i]) >= 0) return true
  }
  return false
}

// The name to show a person. Accepts both record shapes ({appName,nodeName} for
// a stream or client, {app,node} for a rule) so every row labels through one
// function rather than three ad-hoc expressions.
//
// A "PipeWire ALSA [app]" wrapper is unwrapped to the application it names:
// that is the app a person installed and would recognise, and the row reading
// "PipeWire ALSA [cliamp]" invites the belief that the row belongs to PipeWire.
// Only display is decided here -- identityList() decides what is the same app.
function friendlyLabel(entry) {
  var e = entry || {}
  var app = stripInput(recordAppName(e))
  if (app !== "") {
    var inner = alsaClientName(app)
    return inner !== "" ? inner : app
  }
  var b = basename(String(e.binary == null ? "" : e.binary))
  if (b !== "") return b
  var n = String(recordNodeName(e)).trim()
  // An ALSA node's own name carries the driver's PCM as "alsa_playback.<pcm>";
  // the part after the dot is what a person recognises.
  if (n !== "") return n.replace(/^alsa_(?:playback|capture)\./, "")
  return "unknown"
}

function ruleKey(rule) {
  return appKey({ binary: rule ? rule.binary : "", nodeName: rule ? rule.node : "", appName: rule ? rule.app : "" })
}

// There is deliberately no ruleForRow() here any more. It compared a row's key
// to ruleKey(rule) for equality, which is the assumption that let one app render
// as two rows; it had no callers, and leaving a function that states the old
// identity rule invites the next reader to use it. Use identitiesOverlap().

// Last resort for a sink that has no remembered description and that BlueZ does
// not know: turn the identifier into something a person can recognise and
// match to a device. Only bluetooth is rewritten. alsa/USB sink names vary per
// device and per driver, so a speculative parse would produce confident
// nonsense; those keep their raw name, which is at least self-explanatory.
//
//   bluez_output.24_06_11_A5_E7_95.1  ->  "Bluetooth 24:06:11:A5:E7:95"
function friendlySinkName(name) {
  var s = String(name || "").trim()
  var m = /^bluez_output\.([0-9A-Fa-f_]+)(?:\.\d+)?$/.exec(s)
  if (!m) return s
  return "Bluetooth " + m[1].replace(/_/g, ":").toUpperCase()
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

// Fold rows that name the same app into one, where "same app" is decided by
// identitiesOverlap() rather than by key equality. Rows are connected
// transitively: A~B and B~C fold to one row even when A and C share nothing, so
// an app seen three ways still draws once.
//
// Folded row keeps, in order of preference:
//   key     the rule's key when pinned, else the first row's key. The key is how
//           the panel finds a row for a pin, an unpin and a keyboard cursor, and
//           ruleKey() is what all three compare against, so a pinned row that
//           kept a stream-derived key would lose its own badge.
//   label   the first row's, which is the stream's friendlier formatting when a
//           stream exists -- the same order buildRows() adds them in today, so
//           nothing that renders differently before this change renders
//           differently after it.
//   rule    the first attached, since effectiveRules() already collapses several
//           rules for one app to one.
//   identity fields the rule's, when it has them: a pin is the persisted intent
//           and the helper matches on any identity, so writing the rule's own
//           values keeps the store stable instead of rewriting a pin with a
//           degraded identity the first time a stream happens to be reported
//           without its binary.
// A pinned row is keyed by, and described by, its rule. Panel.qml attaches a
// rule to an existing stream row by identity overlap and only then calls
// mergeRows, so without this a pinned row would keep the key of whichever
// stream it happened to be born from -- a key that changes when the app's
// node name changes. Doing it here means the key is the same whether the row
// arrived already-merged or was folded.
function normalisePinned(row, rule) {
  var r = rule !== undefined ? rule : row.rule
  if (!r) return row
  row.rule = r
  if (r.app) row.appName = r.app
  if (r.binary) row.binary = r.binary
  if (r.node) row.nodeName = r.node
  row.key = ruleKey(r)
  // ids was computed before the rule was adopted, so the rule's own key is not
  // in it yet. Append rather than recompute: on a folded row ids is the union
  // over every member, and recomputing from this one row would drop the others.
  var ids = row.ids || identityList(row)
  if (ids.indexOf(row.key) < 0) ids.push(row.key)
  row.ids = ids
  return row
}

function mergeRows(rows) {
  var list = rows || []
  if (list.length < 2) {
    // Still normalise: this is Panel.qml's usual path, where findRow() has
    // already attached the rule to the stream's row and the fold has nothing
    // left to do. Skipping it here is what left a pinned row keyed by a node
    // name that changes under it.
    for (var k = 0; k < list.length; ++k) {
      list[k].ids = identityList(list[k])
      normalisePinned(list[k])
    }
    return list.slice()
  }

  // Union-find over row indices; "find" walks the parent chain.
  var parent = []
  for (var i = 0; i < list.length; ++i) parent[i] = i
  function find(x) {
    while (parent[x] !== x) {
      parent[x] = parent[parent[x]]
      x = parent[x]
    }
    return x
  }
  for (i = 0; i < list.length; ++i) {
    list[i].ids = identityList(list[i])
    for (var j = i + 1; j < list.length; ++j) {
      if (identitiesOverlap(list[i], list[j])) {
        var ri = find(i)
        var rj = find(j)
        if (ri !== rj) parent[Math.max(ri, rj)] = Math.min(ri, rj)
      }
    }
  }

  var groups = {}
  var order = []
  for (i = 0; i < list.length; ++i) {
    var root = find(i)
    if (!(root in groups)) {
      groups[root] = { first: list[i], members: [] }
      order.push(groups[root])
    }
    groups[root].members.push(list[i])
  }

  var out = []
  for (i = 0; i < order.length; ++i) {
    var g = order[i]
    if (g.members.length === 1) {
      out.push(normalisePinned(g.first))
      continue
    }
    // Read every member before writing to g.first: the group's first member IS
    // g.first, the same object, so clearing its fields before reading them
    // would silently discard the streams and identities of the row the fold is
    // keeping.
    var streams = []
    var ids = []
    var rule = null
    var isPending = false
    var pendingDefault = false
    var idle = false
    var runIdle = false
    for (var m = 0; m < g.members.length; ++m) {
      var src = g.members[m]
      var st = src.streams || []
      for (var n = 0; n < st.length; ++n) streams.push(st[n])
      for (n = 0; n < (src.ids || []).length; ++n) {
        if (ids.indexOf(src.ids[n]) < 0) ids.push(src.ids[n])
      }
      if (!rule && src.rule) rule = src.rule
      if (src.isPending) isPending = true
      if (src.pendingDefault) pendingDefault = true
      if (src.idle) idle = true
      if (src.runIdle) runIdle = true
    }
    var row = g.first
    row.streams = streams
    row.ids = ids
    row.isPending = isPending
    row.pendingDefault = pendingDefault
    row.idle = idle
    row.runIdle = runIdle
    out.push(normalisePinned(row, rule))
  }
  return out
}
