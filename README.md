# Audio Router

Persistent per-app audio routing for the Omarchy shell. A bar icon opens a
two-column patchbay: drag any app onto any output (or click-click) to route it.
Pinned routes live on disk and are reasserted continuously, so a pin made while
an app is silent applies from the first moment that app plays — and survives
reboots.

![Audio Router in action — drag an app onto an output, or route with the keyboard badges](screenshots/screenshot-2026-09-29_12-29-12.png)

## Highlights

- **Pins stick.** Routes are reasserted continuously and survive reboots; pre-pin
  an app while it's silent and it routes itself from the moment it plays.
- **One row per app**, with full output names — no raw PipeWire node IDs.
- **Keyboard-native.** Every row bears its shortcut: a letter picks the app, a
  number routes it, `r` toggles routing on and off.
- **Bluetooth-friendly.** Rules follow the device, not its profile, so a headset
  that disconnects falls back to the default (never silence) and reconnects
  still routed.
- **Private.** No network connections or telemetry; your pins are two local
  files that `--purge` removes.

## Requirements

- Omarchy shell
- `pactl`, `python3`
- `bluetoothctl` *(optional)* — shows a friendly name for a paired Bluetooth
  device; without it the plugin falls back to PipeWire's name, then to
  `Bluetooth AA:BB:CC:DD:EE:FF`

## Install

```sh
omarchy plugin add https://github.com/petealeon/audio-router.git --enable
```

Or, from a checkout of this repo:

```sh
./install.sh          # install + enable the widget
```

`./install.sh` backs up the running install first (keeping the 3 newest
`.petealeon.router.bak.*` copies) and upgrades the old `peter.router` id
cleanly. Your rules in `~/.config/omarchy/router-rules.json` are never touched.

## Uninstall

```sh
omarchy plugin remove petealeon.router     # removes the widget; pins are kept
./install.sh --purge                        # also deletes pins and state
```

`omarchy plugin remove` / `./install.sh --remove` leave your pins in place so a
reinstall restores them. `--purge` additionally deletes `petealeon-router.json`
(the on/off preference and cached Bluetooth names).

## Usage

Click the link icon (right side of the bar) to open the patchbay, or press your
bar's panel hotkey — see *Keyboard*.

- **Route / reset:** drag an app row onto an output column. To unroute, drag it
  back onto the default output row, or click the ring beside the app's name.
- **Live vs idle:** a row with an active stream draws at full weight; idle apps
  are dimmed. The circle/ring marks the pin — accent when the app is routed to
  one of your outputs.
- **Routing on/off:** the header switch pauses routing. Off moves every stream
  back to the system default, dims the patch, and any route you set is *stored*
  only (drawn dashed, no endpoint dot) until you switch back on. Rules are kept,
  so switching on re-pins the same apps; resets still apply immediately.

Every audio client is listed whether or not it's playing, so you can pre-pin
before a call instead of during it. System services (quickshell, wireplumber,
pipewire, the portals, EasyEffects) are never listed or steered.

## Keyboard

The panel opens like any other bar widget: the link icon, or the bar's panel
hotkey (`Bar panel N` — for us, `SUPER + CTRL + 1` while the router is the first
panel). To bind a key that doesn't depend on bar order, point it at
`omarchy-shell shell toggle petealeon.router`.

Open, the panel is fully drivable without a mouse. The first arrow press only
wakes the cursor — it doesn't move or scroll, so the panel never jumps on a
stray key.

### Quick routing

Two steps, and every row shows its shortcut on the badge: apps carry letters,
outputs carry numbers (`1`–`9`, then leftover letters past #9).

1. Press the **letter** of the app you want to route — it highlights and stays
   selected.
2. Press the **number** (or letter) of the output to send it there.

No modifier, nothing to arm: a letter is always a source *or* an output (never
both — sources claim the alphabet first), and routes chain — `a` `1` `b` `1`
`c` `2`. Routing on/off is `r`, matching the mnemonic-letter convention of the
built-in Bluetooth (`b`), Wi-Fi (`w`) and Tailscale (`t`) panels.

| Key | Action |
| --- | --- |
| `j` / `Down`, `k` / `Up` | Move the cursor a row. From the first app row, up enters the header; from the header, down returns to the app list |
| `l` / `Right` | From an app row: jump to the output it is connected to, ready to re-route |
| `h` / `Left` | Back to the app row from the output column |
| `Return` / `Space` | On the header: toggle routing. On an output: route the app to it |
| `x` | Reset the app to the system default (same as clicking its ring) |
| `a`–`z` | Select the app with that badge — quick routing's first step. `j k h l x` (movement/delete) and `r` (routing) are reserved, so no row bears them |
| `1`–`9` | Route the selected app to that output — quick routing's second step. With no app picked first it uses the app under the cursor (from the header, the last app it sat on); an output's letter badge works the same as its number |
| `r` | Toggle routing on/off, from anywhere in the panel |
| `Tab`, `Shift+Tab` | Next / previous panel |
| `Escape` | Close |

The cursor spans both columns, so moving right lands on the output the app is
currently on and left comes back. Both columns share one row height, so a source
and the output beside it sit on the same line.

## Bluetooth devices

- **Disconnects fall back cleanly.** If a pinned device goes away, its streams
  move to the *system default* (never mute into a vanished headset) and the rule
  is kept, so when the device returns the routes re-apply automatically.
- **Rules follow the device, not the cable.** PipeWire renumbers Bluetooth
  profile indices between reconnects, so a name-based match would read a
  re-indexed headset as "gone" and drop it to your speakers. Rules match the
  device itself and survive reconnects and profile changes; wired outputs are
  matched exactly.
- **Names survive power-off.** A disconnected Bluetooth output is still shown by
  name (remembered from last time) rather than a raw `bluez_output…` id — see
  *Privacy and data* for what that remembers.

## Privacy and data

The plugin is local-only. It reads `pactl` output and writes exactly two files,
both under `~/.config/omarchy/`, both mode `0600`:

| File | Contains | Written by |
| --- | --- | --- |
| `router-rules.json` | Your pins: app identity and the output each is pinned to | you, by pinning |
| `petealeon-router.json` | The on/off preference, and a cache of **Bluetooth device names and MAC addresses** | the helper, from BlueZ |

`bluetoothctl` (optional) is used only to resolve a MAC to a name; the result is
cached once per device and survives disconnects — the whole point, since the
sink vanishes from `pactl` exactly when you want the name. Because the state
file holds device identifiers, treat it accordingly: it's `0600`, and
`./install.sh --purge` removes it. No other identifier or telemetry is
collected, and neither file is ever transmitted.

---

The rest is for people building on or debugging the plugin; you can stop here.

# For developers

## How routing works

- **Bar widget:** `petealeon.router` (BarWidget.qml + Panel.qml + Model.js).
- **Helper:** `assets/omarchy-router`, a pure-Python `pactl` watcher. `move()`
  is the only code path that changes audio — one `pactl move-sink-input` call.
- **Store:** `~/.config/omarchy/router-rules.json`; state
  `~/.config/omarchy/petealeon-router.json`.

Rules are matched per stream in order of specificity:

1. process-binary basename (e.g. `brave`, `mpv`)
2. PipeWire `node.name` basename
3. `application.name`, a trailing `" input"` ignored
4. the app named inside a `PipeWire ALSA [app]` wrapper

The panel lists **one row per app**, not per key: a stream and a pin that share
any of an app's names fold into a single row (a pin is keyed by its pin, not by
a node name that can change), and two unrelated apps that only share a name stay
separate. System services are never steered. A pin left over from an older
version that names an internal node is not shown (the helper refuses to steer
stack names), but stays in the store until you remove it by name:

```sh
python3 assets/omarchy-router remove cliamp
```

`set-sink` de-duplicates by identity, so re-pinning an app whose
`process.binary` only became visible after the first pin replaces the old rule
instead of duplicating it.

**Exclusions** are exact, tag-stripped names only (`pipewire`, wireplumber, the
portals, quickshell, systemd, EasyEffects, this plugin's own tooling) applied
case- and suffix-insensitively on binary and name — no first-word or namespace
rule that could swallow a real app.

## Watcher

- Polls every 0.5s while audio plays, 2.5s once silent, reasserting rules in
  both cadences; logs to `$XDG_RUNTIME_DIR/omarchy-router.watch.log` (256 KB,
  one previous generation).
- **On/off is enforced where the move happens:** the watcher reads the
  preference itself, so a stray watcher cannot steer anything you switched off.
- **Singleton** via `flock`; **self-healing**: a crashed watcher is restarted
  (3s delay, 5 attempts per session), reflected in the header switch. Flock
  contention and clean exits aren't crashes. Switching routing off stops the
  watcher until the switch returns.
- **`restore`** makes "routing off" mean it: it takes the watch lock and moves
  every valid stream to `pactl get-default-sink`, without touching rules.
- Manual start: `python3 assets/omarchy-router watch`.

## CLI

```sh
python3 assets/omarchy-router list                              # full state as JSON
python3 assets/omarchy-router set-sink <app> <binary> <node> <sink|__default__>
python3 assets/omarchy-router set-rule <app> <binary> <node> <sink|__default__>
python3 assets/omarchy-router remove <app-or-binary>
python3 assets/omarchy-router restore                            # all streams back to the default sink
python3 assets/omarchy-router watch                             # poll watcher
python3 assets/omarchy-router selftest                          # zero-I/O sanity checks
```

`set-sink` stores a rule *and* moves matching streams; `set-rule` only stores it
(the panel's behavior while routing is off). `selftest` runs the parsers,
matcher, store mutation and exclusion/cadence policies on canned pactl output —
no real pactl, no real store — exiting 0/1, and doubles as the CI gate.

## Development

- `./install.sh` is the only supported way to touch a live install; never edit
  `~/.config/omarchy/plugins/petealeon.router` directly.
- The assistant contract (`list` JSON shape, `set-sink` args) is shared between
  `Panel.qml` and `assets/omarchy-router`; `cmd_watch` is an infinite real-pactl
  loop, so its safety properties are asserted by the selftest against its source
  text — extend those checks when the loop changes.
- `./scripts/qml-lint.sh` finds `qmllint` itself (not on `PATH` on Arch — it
  ships in `qt6-declarative` as `/usr/lib/qt6/bin/qmllint`) and builds a `qs.*`
  import shim from `/usr/share/omarchy/shell`. **Only a parse error fails the
  check.** The ~108 remaining `[unqualified]`/`[missing-property]` advisories
  come from the shell's runtime-injected `bar`/`hostWidget` objects and its
  singletons, and are the same classes — in larger numbers — that the built-in
  panels emit. CI runs the same script.