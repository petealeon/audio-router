# petealeon.router — Audio Router

Persistent per-app audio routing for the Omarchy shell. A dedicated bar icon
opens a two-column patchbay; drag any app onto any output (or click-click) to
route it. Pinned routes live on disk and are reasserted continuously, so a pin
made while an app is silent kicks in the moment that app starts playing — and
survives reboots.

- **Bar widget:** `petealeon.router` (BarWidget.qml + Panel.qml + Model.js)
- **Watcher/helper:** `assets/omarchy-router` (pure-python, zero deps beyond `pactl`)
- **Rules store:** `~/.config/omarchy/router-rules.json`

## Requirements

- Omarchy shell (uses `omarchy`, `quickshell`, `jq`)
- `pactl`, `python3`

## Install

```sh
./install.sh          # install + enable widget (the running install is backed up first)
```

Re-installing over a newer version never clobbers it: the current plugin dir is
copied to `.petealeon.router.bak.<timestamp>` next to the plugins folder (the 3
newest backups are kept).

Upgrading from the old `peter.router` id needs no manual step — just run
`./install.sh`. The installer notices the superseded id, stops its watcher,
unregisters the old plugin, strips its stale bar entry and re-adds the widget
under `petealeon.router` in the same right-hand section. Your routing rules in
`~/.config/omarchy/router-rules.json` are never touched by the rename.

## Marketplace

Listed on the Omarchy plugin marketplace (plugins.omarchy.org) — install,
update and review it there. The repository at the point of a tagged release
(`vX.Y.Z`) is always the source of truth; see `docs/marketplace-submission.md`
for the listing details.

## Uninstall

```sh
./install.sh --remove   # removes the widget; routing rules are kept
./install.sh --purge    # removes the widget and the routing rules
```

Note: `omarchy plugin remove` alone leaves `router-rules.json` in place by
design, so a reinstall restores your pins.

## Usage

Click the link icon (right side of the bar) to open the patchbay.

- **Route:** drag an app row onto an output column.
- **Reset to default:** drag onto the current default output row or click the
  ring on the app row.
- **Live sources:** a speaker glyph on the left of a row means that source is
  playing right now (accent when it is pinned, plain when it is just on the
  system default).
- **Routing on/off:** the header switch (like other Omarchy tools) turns routing
  on and off. Off moves every stream back to the system default output and stops
  re-asserting; saved rules are kept, so switching back on re-pins the same apps.
  While off the patch dims and any route you set is only *stored* — it draws as
  a dashed line with no endpoint dot, and the stream stays where it is until the
  switch comes back on. Resets still apply immediately, since "everything is
  already on the default" is what off means.

Only apps that are actually playing are listed: system services (quickshell,
wireplumber, pipewire, portals, …) are never steered, so there is nothing to
pre-pin.

## Keyboard

The panel is fully drivable without a mouse. The first arrow press only wakes
the cursor — it does not move or scroll, so the panel never jumps on a stray
keypress.

| Key | Action |
| --- | --- |
| `j` / `Down`, `k` / `Up` | Move the cursor a row (crosses into the header from the first row) |
| `l` / `Right` | From an app row: jump to the output it is connected to, ready to re-route |
| `h` / `Left` | Back to the app row from the output column |
| `Return` / `Space` | On the header: toggle routing. On an output: route the app to it |
| `x` | Reset the app to the system default (same as clicking its ring) |
| `1`–`9` | Route the app to the nth output without walking the column |
| `Tab`, `Shift+Tab` | Next / previous panel |
| `Escape` | Close |

The cursor spans both columns, mirroring the patch: rows are shared, so moving
right lands on the output the app is currently on. Highlighting is the same one
the mouse uses, and hovering the routing switch with the mouse focuses it too.
The cursor is tracked by app and output key rather than by row number, so it
survives the 1s refresh — including an app whose stream stops mid-navigation.

## Rule matching

Rules are matched per stream in order of specificity:

1. process-binary basename (e.g. `brave`, `mpv`)
2. PipeWire `node.name` basename
3. `application.name`, with a trailing `" input"` ignored

Browser streams often carry a stable `node.name` but no reliably unique binary
per process, so the node key keeps Brave/Signal rules matching. System services
(EasyEffects, Quickshell, wireplumber, pipewire, systemd, the portals) are never
steered.

`set-sink` de-duplicates by identity (not just key), so re-pinning an app whose
`process.binary` only became visible after the first pin still replaces the old
rule instead of creating a second one.

## Bluetooth / device fallback

When a pinned device disconnects (e.g. a Bluetooth headset powers off), the
next poll moves matching streams to the *system default* instead of leaving them
muted on the vanished device — and keeps the rule. When the device returns, the
watcher routes the streams back and logs one `rules reasserted (n)` line.
Watcher log: `$XDG_RUNTIME_DIR/omarchy-router.watch.log`.

## Watcher behavior

- Polls every 0.5s, applies rules, exits when its spawning parent is gone.
- **Singleton:** one watcher per shell via an `flock`; a shell or plugin reload
  can never spawn a duplicate.
- **Self-healing:** the widget restarts a crashed watcher (bounded, 3s delay,
  5 attempts per session), reflected in the header's routing switch. A manual
  restart resets the counter. Flock conflicts, SIGTERM teardown and clean exits
  are not counted as crashes: the watcher briefly waits out a stale lock holder
  on plugin reloads, retries a contended flock once, and otherwise re-arms
  quietly on a 30s timer — with a liveness backstop should the engine deliver
  no death event at all. Switching routing off stops the watcher completely; no
  timer re-arms it until the switch is turned back on.
- Manual start: `python3 assets/omarchy-router watch`
- `restore` is what makes "routing off" mean what it says: it takes the watch
  lock (bounded, so a just-stopped watcher finishes first) and moves every
  valid stream to `pactl get-default-sink`. Rules are never modified, so
  switching routing back on re-pins the same apps.

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

`set-sink` stores the rule *and* moves matching streams. `set-rule` only stores
it, which is what the panel uses while routing is off. Both take the same four
arguments, so the panel switches on one flag rather than maintaining two
different call shapes.

`selftest` exercises the parsers, matcher, fallback, store mutation and the
`set-rule`/`set-sink` split on canned pactl output (no pactl, no store) and
exits 0/1 — run it after a deploy or in CI.

## Development

- `./install.sh` is the only supported way to touch the live install; never edit
  `~/.config/omarchy/plugins/petealeon.router` directly.
- QML changes land in `BarWidget.qml` / `Panel.qml` / `Model.js`; the helper
  contract (`list` JSON shape, `set-sink` args) is shared with the panel.
- `assets/omarchy-router` selftest should stay green (or be extended) whenever
  the helper's parsing/matching changes.
- `./scripts/qml-lint.sh` runs `qmllint` over all three. It finds the binary
  itself (`qmllint` is not on `PATH` on Arch — it ships in `qt6-declarative` as
  `/usr/lib/qt6/bin/qmllint`; on Debian/Ubuntu install
  `qt6-declarative-dev-tools`) and builds the `qs.*` import shim from
  `/usr/share/omarchy/shell` so the omarchy types resolve. It exits non-zero
  only on parse errors, which is the check worth enforcing; the ~90
  `unqualified`/`missing-property` warnings are inherent to reaching singletons
  and the dynamic `bar` property, and match the built-in panels. `--verbose`
  prints full source context. CI runs the same script.