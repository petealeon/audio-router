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

const failed = checks.filter(([, ok]) => !ok)
console.log(`model-test: ${checks.length - failed.length}/${checks.length} passed`)
process.exit(failed.length ? 1 : 0)
