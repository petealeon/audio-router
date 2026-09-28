#!/usr/bin/env node
// Assert the panel's identity helpers in Model.js.
//
// The Python selftest cannot reach these: they are the UI's view of which
// entries are the same app, and a mismatch there is invisible to pactl. The bug
// that motivated this file was a live Brave stream reporting its binary as
// "brave (deleted)" (PipeWire marks a process whose on-disk executable was
// replaced under it), which keyed differently from the same app's client and its
// stored rule, and rendered a second stream-less row.
//
// Model.js is loaded through vm in a fresh context, the way QML loads it as a
// script namespace, so the file stays free of module.exports.
//
// Usage: node scripts/model-test.js   (exit 0 when everything passes)

const fs = require("fs")
const path = require("path")
const vm = require("vm")

const MODEL = path.join(__dirname, "..", "Model.js")
const checks = []

function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want)
  checks.push([name, ok])
  const suffix = ok ? "" : ` (want ${JSON.stringify(want)})`
  console.log(`  ${ok ? "PASS" : "FAIL"}  ${name}: ${JSON.stringify(got)}${suffix}`)
}

const context = vm.createContext({})
vm.runInContext(fs.readFileSync(MODEL, "utf8"), context, { filename: MODEL })

// A live stream whose executable was replaced under it, its matching client,
// and its stored rule. These are three real shapes taken from `list`; before the
// normalisation the first keyed differently from the other two.
const stream = { appName: "Brave", binary: "brave (deleted)", nodeName: "Brave" }
const client = { appName: "Brave input", binary: "brave" }
const rule = { app: "Brave", binary: "brave", node: "Brave" }

check("appKey normalises the deleted artifact", context.appKey(stream), "brave")
check("appKey client agrees with stream", context.appKey(client), context.appKey(stream))
check("appKey rule agrees with stream", context.appKey(rule), context.appKey(stream))
check("ruleKey agrees with the live stream", context.ruleKey(rule), context.appKey(stream))
check(
  "a rule stored with the artifact still keys to the stream",
  context.ruleKey({ app: "Brave", binary: "brave (deleted)", node: "" }),
  context.appKey(stream)
)
check("label never surfaces the artifact", context.friendlyLabel(stream), "Brave")
check("client label never surfaces the artifact", context.friendlyLabel(client), "Brave")
check("artifact stripped case-insensitively", context.basename("Brave (Deleted)"), "Brave")
check("artifact stripped inside a path", context.basename("/usr/lib/brave-bin/brave (deleted)"), "brave")
check("artifact stripped from an input client", context.stripInput("Brave (deleted) input"), "Brave")
check("component mapping survives the artifact", context.stripInput("ringrtc (deleted)"), "Signal")

// Precedence and fallbacks must be untouched by the normalisation: binary, then
// node name, then application name.
check("binary wins over node", context.appKey({ appName: "X", binary: "B1", nodeName: "N1" }), "b1")
check("node used when binary empty", context.appKey({ appName: "X", binary: "", nodeName: "N1" }), "n1")
check("app name used when binary and node empty", context.appKey({ appName: "X", binary: "", nodeName: "" }), "x")
check("input suffix ignored as a fallback", context.appKey({ appName: "X input", binary: "", nodeName: "" }), "x")
check("null entry keys to unknown", context.appKey(null), "unknown")
// An object missing the keys coerces undefined to the string "undefined".
// Pre-existing and unreachable: the helper always emits explicit string fields,
// and both Panel.qml call sites build objects with the keys present. Pinned so a
// future change to the coercion is noticed rather than assumed.
check("object without the keys coerces to the string undefined", context.appKey({}), "undefined")

check("input suffix stripped", context.stripInput("Signal input"), "Signal")
// Capitalised too: the suffix test is on a lowercased copy, so a session
// reporting "Input" is recognised. Only a case-sensitivity bug here is invisible
// otherwise, because every recorded session spelled it lowercase.
check("input suffix stripped whatever its case", context.stripInput("Signal Input"), "Signal")
check("and with the artifact inside it", context.stripInput("Brave (deleted) Input"), "Brave")
check("unrelated similar name is left alone", context.basename("brave-deleted"), "brave-deleted")
// A bare " input" loses its leading space to the trim before the suffix test, so
// the suffix never matches. Pre-existing, and harmless.
check("bare input suffix is trimmed, not emptied", context.stripInput(" input"), "input")

// Last-resort naming for an output pactl no longer reports, which is how a
// disconnected bluetooth device shows up: a rule still points at the sink, so
// the panel keeps a row for it, and without a label that row read
// "bluez_output.24_06_11_A5_E7_95.1". The MAC is what makes it matchable to a
// device by hand.
check("bluetooth sink name becomes a readable label",
  context.friendlySinkName("bluez_output.24_06_11_A5_E7_95.1"), "Bluetooth 24:06:11:A5:E7:95")
check("bluetooth profile suffix ignored",
  context.friendlySinkName("bluez_output.24_06_11_A5_E7_95.2"), "Bluetooth 24:06:11:A5:E7:95")
check("bluetooth name without a profile suffix",
  context.friendlySinkName("bluez_output.aa_bb_cc_dd_ee_ff"), "Bluetooth AA:BB:CC:DD:EE:FF")
check("lowercase mac uppercased",
  context.friendlySinkName("bluez_output.AA_BB_CC_DD_EE_FF.1"), "Bluetooth AA:BB:CC:DD:EE:FF")
// Only bluetooth is rewritten. alsa/USB names vary per device and per driver,
// so inventing a parse would produce confident nonsense; the raw name is
// returned untouched instead.
check("alsa name passed through unchanged",
  context.friendlySinkName("alsa_output.pci-0000_00_1f.3.analog-stereo"),
  "alsa_output.pci-0000_00_1f.3.analog-stereo")
check("usb name passed through unchanged",
  context.friendlySinkName("alsa_output.usb-Generic_ThinkPad_Dock_USB_Audio-00.analog-stereo"),
  "alsa_output.usb-Generic_ThinkPad_Dock_USB_Audio-00.analog-stereo")
check("near-miss bluetooth name is not rewritten",
  context.friendlySinkName("bluez_output.not-a-mac.1"), "bluez_output.not-a-mac.1")
check("empty label for empty name", context.friendlySinkName(""), "")
check("empty label for null name", context.friendlySinkName(null), "")

// The exclusion policy, against the same table the Python selftest reads. Both
// implementations are held to one shared list of expected verdicts, because
// comparing their name lists proved nothing: they held identical names while
// disagreeing about which names to reject.
//
// The table encodes a correction as much as a policy. "PipeWire ALSA [x]" is
// PipeWire's wrapper for the ALSA client of the application x -- on this machine
// x is cliamp, an installed music player. A namespace rule that treated the
// whole pipewire namespace as plumbing deleted that real app from the panel.
const exclusionCases = JSON.parse(
  fs.readFileSync(path.join(__dirname, "exclusion-cases.json"), "utf8")
).cases
const exclusionWrong = exclusionCases
  .filter((c) => context.isExcludedClient({ appName: c.appName, binary: c.binary }) !== c.excluded)
  .map((c) => `${c.appName}/${c.binary} want ${c.excluded}`)
check(`exclusion policy matches the shared table (${exclusionCases.length} cases)`,
  exclusionWrong, [])

// isExcludedClient is what clientKey() consults, and what the panel applies to
// rules; a rule carries app/binary rather than appName/binary.
check("a real ALSA app behind a PipeWire wrapper is kept",
  context.isExcludedClient({ appName: "PipeWire ALSA [cliamp]", binary: "cliamp" }), false)
check("and so is the same app reported by node name only",
  context.isExcludedClient({ appName: "PipeWire ALSA [cliamp]", binary: "" }), false)
check("a pin naming a real app is kept",
  context.isExcludedClient({ appName: "Brave", binary: "brave" }), false)
check("the PipeWire daemon itself is still refused",
  context.isExcludedClient({ appName: "pipewire", binary: "pipewire" }), true)
check("and the session manager, tagged or not",
  [context.isExcludedClient({ appName: "WirePlumber", binary: "wireplumber" }),
    context.isExcludedClient({ appName: "WirePlumber [client]", binary: "wireplumber" })],
  [true, true])
check("an app merely containing a stack name is untouched",
  context.isExcludedClient({ appName: "MyPipeWire Viewer", binary: "mypipewire" }), false)
check("and one merely STARTING with a stack name is untouched too",
  context.isExcludedClient({ appName: "WirePlumber Dashboard", binary: "wp-dash" }), false)
check("there is no namespace rule left to mutate",
  typeof context.isStackName, "undefined")
check("and no namespace list to grow",
  /STACK_NAME_PREFIXES/.test(fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
    .replace(/^\s*\/\/.*$/gm, "")), false)

// The wrapper is unwrapped for display: the row should read like the app a
// person installed, not like a piece of the audio stack.
check("a wrapper name labels as the application inside it",
  context.friendlyLabel({ appName: "PipeWire ALSA [cliamp]", binary: "" }), "cliamp")
check("a rule carrying the wrapper labels the same way",
  context.friendlyLabel({ app: "PipeWire ALSA [cliamp]", binary: "cliamp", node: "" }), "cliamp")
check("a client carrying the wrapper labels the same way",
  context.friendlyLabel({ appName: "PipeWire ALSA [cliamp]", binary: "cliamp" }), "cliamp")
check("an ordinary name is untouched by the unwrap",
  context.friendlyLabel({ appName: "Brave", binary: "brave" }), "Brave")
check("a tagged stack name is NOT unwrapped -- it is not a wrapper",
  context.friendlyLabel({ appName: "WirePlumber [client]", binary: "wireplumber" }),
  "WirePlumber [client]")
check("an ALSA node name with no appName falls back past its prefix",
  context.friendlyLabel({ binary: "", nodeName: "alsa_playback.cliamp" }), "cliamp")

// ---------------------------------------------------------------- identity set
//
// The Brave (deleted) split above is one app disagreeing with itself in a single
// field. This is the general form: the stream keys on node.name because pactl
// reported no binary, the client and rule key on the binary, and the panel drew
// two rows for one app. identityList/identitiesOverlap are the rule the helper's
// identities_overlap has always used, stated on this side.
const cliampStream = { appName: "PipeWire ALSA [cliamp]", binary: "", nodeName: "alsa_playback.cliamp" }
const cliampRule = { app: "PipeWire ALSA [cliamp]", binary: "cliamp", node: "" }

check("identityList of a stream without a binary falls back to its node",
  context.identityList(cliampStream), ["alsa_playback.cliamp", "pipewire alsa [cliamp]", "cliamp"])
check("identityList of the matching rule", context.identityList(cliampRule),
  ["cliamp", "pipewire alsa [cliamp]"])
check("the two key differently", context.appKey(cliampStream) !== context.appKey(cliampRule), true)
check("but their identities overlap", context.identitiesOverlap(cliampStream, cliampRule), true)
check("unrelated apps do not overlap",
  context.identitiesOverlap(cliampStream, { appName: "Brave", binary: "brave" }), false)
check("an empty record overlaps nothing", context.identitiesOverlap({}, cliampRule), false)
check("two records differing in every field do not overlap",
  context.identitiesOverlap({ appName: "Brave", binary: "brave" }, { appName: "mpv", binary: "mpv" }),
  false)

// Today the stream and the client both report the identical wrapper string, so
// they already agree on it. These two cases are the reason that must not be the
// only thing holding them together: a PipeWire version that reported the bare
// application name on one side and the wrapper on the other would stop the sets
// intersecting, and the app would draw two rows again.
check("a wrapper stream and a bare-named client still overlap",
  context.identitiesOverlap(cliampStream, { appName: "cliamp", binary: "cliamp" }), true)
check("and a bare-named stream and a wrapper rule still overlap",
  context.identitiesOverlap({ appName: "cliamp", binary: "" }, cliampRule), true)
check("two different ALSA apps behind two wrappers do not overlap",
  context.identitiesOverlap(cliampStream, { appName: "PipeWire ALSA [mpv]", binary: "mpv" }), false)
check("a bare name that is not a wrapper gains no extra identity",
  context.identityList({ appName: "cliamp", binary: "" }), ["cliamp"])

// Deduplicated, because binary and node.name routinely normalise to the same
// string. A repeated entry makes two sets read as if they agreed twice, and the
// fold would carry the duplicate into every row's ids.
check("binary and node normalising alike are listed once",
  context.identityList({ appName: "Brave", binary: "brave", nodeName: "brave" }), ["brave"])
check("all three identities are kept when they differ",
  context.identityList({ appName: "Brave", binary: "brave", nodeName: "brave-web" }),
  ["brave", "brave-web"])

// ------------------------------------------------------------------- fold rows
const row = (o) => Object.assign({
  label: "", binary: "", appName: "", nodeName: "", streams: [], rule: null,
  isPending: false, idle: false
}, o)

// The two rows the panel used to draw for one ALSA application: the stream keyed
// on its node name because no binary was reported, the pin keyed on the binary.
// Both now carry the unwrapped label the panel actually displays.
const merged = context.mergeRows([
  row({ key: "alsa_playback.cliamp", label: "cliamp", appName: "PipeWire ALSA [cliamp]",
    nodeName: "alsa_playback.cliamp", streams: [{ id: "1", sinkName: "alsa_output.a" }] }),
  row({ key: "cliamp", label: "cliamp", appName: "PipeWire ALSA [cliamp]", binary: "cliamp",
    rule: { app: "PipeWire ALSA [cliamp]", binary: "cliamp", node: "", sink: "bluez_output.24_06_11_A5_E7_95.1" },
    idle: true })
])
check("one app folds to one row", merged.length, 1)
check("the folded row keeps its stream", merged[0].streams.length, 1)
check("the folded row keeps its rule", merged[0].rule.sink, "bluez_output.24_06_11_A5_E7_95.1")
check("a pinned row is keyed by its rule, so the badge and unpin find it",
  merged[0].key, "cliamp")
check("the folded row carries the union of identities",
  merged[0].ids.sort(), ["alsa_playback.cliamp", "cliamp", "pipewire alsa [cliamp]"])

// The key is what a pin, an unpin and the keyboard cursor all look a row up by,
// and all three compare against ruleKey(). A pinned row that kept its
// stream-derived key would lose its own badge.
check("ruleKey of the attached rule is the folded key",
  merged[0].key, context.ruleKey(merged[0].rule))

// Transitive: A~B and B~C fold to one row even when A and C share nothing, so an
// app seen three ways still draws once. A and B share the binary "brave"; B and C
// share the node name "brave-web"; A and C have no identity in common at all.
const transitive = context.mergeRows([
  row({ key: "brave", appName: "Brave", binary: "brave", streams: [{ id: "1" }] }),
  row({ key: "brave-web", appName: "Brave", binary: "brave", nodeName: "brave-web", streams: [{ id: "2" }] }),
  row({ key: "orphan", appName: "Orphan Tab", nodeName: "brave-web", streams: [{ id: "3" }] })
])
check("A and C genuinely share nothing", context.identitiesOverlap(
  { appName: "Brave", binary: "brave" }, { appName: "Orphan Tab", nodeName: "brave-web" }), false)
check("a three-way transitive split folds to one row", transitive.length, 1)
check("and keeps all three streams", transitive[0].streams.length, 3)

// Distinct apps stay distinct. The fold must not become a catch-all: a name
// collision or a shared node name between two unrelated apps is the failure that
// would be much worse than a duplicate row.
const distinct = context.mergeRows([
  row({ key: "brave", appName: "Brave", binary: "brave", streams: [{ id: "1" }] }),
  row({ key: "mpv", appName: "mpv", binary: "mpv", streams: [{ id: "2" }] }),
  row({ key: "signal-desktop", appName: "Signal", binary: "signal-desktop", streams: [{ id: "3" }] })
])
check("unrelated apps are not folded", distinct.length, 3)
check("and keep their own keys", distinct.map((r) => r.key), ["brave", "mpv", "signal-desktop"])

// An unpinned row keeps the key it was built with, so nothing about the common
// case (one stream, no rule) changes.
const unpinned = context.mergeRows([
  row({ key: "brave", appName: "Brave", binary: "brave", streams: [{ id: "1" }] })
])
check("an unpinned row keeps its own key", unpinned[0].key, "brave")
check("and still gets an ids field", unpinned[0].ids, ["brave"])

// A pinned row must be keyed by its rule even when there is nothing to fold.
// This is Panel.qml's usual shape, not a corner: buildRows() finds the rule's
// row by identity overlap and attaches the rule to it, so by the time
// mergeRows() runs there is a single row and no fold. Without normalisation on
// that path the row stays keyed by the stream's node name, which changes
// whenever the app renames its node -- and the pin badge, the unpin path and
// the pending-write filter all follow that key.
const singlePinned = context.mergeRows([
  row({
    key: "brave_web",
    appName: "Brave",
    binary: "",
    nodeName: "brave_web",
    streams: [{ id: "1" }],
    rule: { app: "Brave", binary: "brave", node: "", sink: "alsa_output.b" }
  })
])
check("a lone pinned row is keyed by its rule", singlePinned[0].key, "brave")
check("and adopts the rule's binary", singlePinned[0].binary, "brave")
check("and keeps its stream's node name", singlePinned[0].nodeName, "brave_web")
check("and its ids hold both identities", singlePinned[0].ids, ["brave_web", "brave"])
check("the pinned row is the only one", singlePinned.length, 1)
check("its stream survives normalisation", singlePinned[0].streams.length, 1)

// A rule with no binary of its own falls back to its node name, and the row
// must not be left holding the stream's node name under a stale key.
const singlePinnedNodeKey = context.mergeRows([
  row({
    key: "alsa_playback.cliamp",
    appName: "Brave",
    binary: "",
    nodeName: "alsa_playback.cliamp",
    streams: [{ id: "1" }],
    rule: { app: "Brave", binary: "", node: "brave_out", sink: "alsa_output.b" }
  })
])
check("a rule with no binary keys the row by node", singlePinnedNodeKey[0].key, "brave_out")
check("and ids carry the rule's node too", singlePinnedNodeKey[0].ids,
  ["alsa_playback.cliamp", "brave", "brave_out"])

// Ordering is the caller's business: buildRows sorts after folding. Asserting
// the fold does not reorder is enough to catch a sort creeping in here.
check("fold preserves first-seen order",
  context.mergeRows([
    row({ key: "b", appName: "B", binary: "b" }),
    row({ key: "a", appName: "A", binary: "a" })
  ]).map((r) => r.key), ["b", "a"])
check("empty input is empty output", context.mergeRows([]), [])
check("a pinned row's label is the stream's friendlier one",
  merged[0].label, "cliamp")

const failed = checks.filter(([, ok]) => !ok)
console.log(`model-test: ${checks.length - failed.length}/${checks.length} passed`)
process.exit(failed.length ? 1 : 0)
