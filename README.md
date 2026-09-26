# peter.router — Audio Router

Persistent per-app audio routing for the Omarchy shell. A dedicated bar icon
opens a two-column patchbay; drag any app onto any output (or click-click) to
route it. Pinned routes live on disk and are reasserted continuously, so a pin
made while an app is silent kicks in the moment that app starts playing — and
survives reboots.

- **Bar widget:** `peter.router` (BarWidget.qml + Panel.qml + Model.js)
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
copied to `.peter.router.bak.<timestamp>` next to the plugins folder (the 3
newest backups are kept).

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

- **Route:** drag an app row onto an output column, or drag onto `__default__`.
- **Reset to default:** drag onto the `__default__` row (top output) or click
  the ring on the app row.
- **Pre-pin an idle app:** apps that are currently silent are listed behind the
  `+` button; pin them and they are auto-routed when they start producing.
- **Health dot:** top-right of the panel shows the watcher state — green
  alive, amber restarting (shows attempt count), red dead. Click it to restart
  the watcher. Tooltip shows the version and watcher pid.

## Rule matching

Rules are matched per stream in order of specificity:

1. process-binary basename (e.g. `brave`, `mpv`)
2. PipeWire `node.name` basename
3. `application.name`, with a trailing `" input"` ignored

Browser streams often carry a stable `node.name` but no reliably unique binary
per process, so the node key keeps Brave/Signal rules matching. EasyEffects and
Quickshell are never steered.

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
  5 attempts per session) and reports state on the health dot. A manual restart
  resets the counter. Flock conflicts, SIGTERM teardown and clean exits are not
  counted as crashes: the watcher briefly waits out a stale lock holder on
  plugin reloads, retries a contended flock once, and otherwise re-arms
  quietly on a 30s timer — with a liveness backstop should the engine deliver
  no death event at all.
- Manual start: `python3 assets/omarchy-router watch`

## CLI

```sh
python3 assets/omarchy-router list                              # full state as JSON
python3 assets/omarchy-router set-sink <app> <binary> <node> <sink|__default__>
python3 assets/omarchy-router remove <app-or-binary>
python3 assets/omarchy-router watch                             # poll watcher
python3 assets/omarchy-router selftest                          # zero-I/O sanity checks
```

`selftest` exercises the parsers, matcher, fallback and store mutation on
canned pactl output (no pactl, no store) and exits 0/1 — run it after a deploy
or in CI.

## Development

- `./install.sh` is the only supported way to touch the live install; never edit
  `~/.config/omarchy/plugins/peter.router` directly.
- QML changes land in `BarWidget.qml` / `Panel.qml` / `Model.js`; the helper
  contract (`list` JSON shape, `set-sink` args) is shared with the panel.
- `assets/omarchy-router` selftest should stay green (or be extended) whenever
  the helper's parsing/matching changes.