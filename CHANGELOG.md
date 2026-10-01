# Changelog

All notable changes to `petealeon.router` are documented here. SemVer; releases are
tagged `vX.Y.Z`.

## [1.4.3] - 2026-09-29

Keyboard routing you can see, output rows that follow the mouse, and a README
written for the person who installs the widget.

### Added
- **Two-step keyboard routing.** Every row now carries a shortcut badge — a
  letter on each app row, a number (`1`–`9`, then leftover letters past #9) on
  each output row — so the shortcuts are always visible and there is no mode to
  arm. A letter selects the app, a number (or letter) routes it, and routes can
  be chain-typed one after another. `r` toggles routing on/off from anywhere in
  the panel, the same mnemonic-letter convention the built-in Bluetooth (`b`),
  Wi-Fi (`w`) and Tailscale (`t`) panels use; `j k h l x` are reserved for
  movement and delete, so no row is badged with a key that does something else.

### Fixed
- **Output rows only highlighted while a drag or the keyboard cursor crossed
  them.** A plain mouse hover on the output column lit nothing, which made the
  top output read as the default until you dragged. Output rows now respond to
  a plain hover exactly like the app rows do.

### Security
- **Marketplace review hardening.** File-safety issues found during the listing
  review are fixed. The rules and state files are now written through an
  exclusively-created temp file in the same directory, fsynced, then atomically
  renamed — a predictable temp path can no longer be a pre-placed symlink that
  `open("w")` truncates. `install.sh` no longer carries the superseded
  `peter.router` id at all: that cleanup path both deleted a whole plugin
  directory on a name/id match alone (including any user-added or modified
  files) and rewrote `shell.json` through a predictable `shell.json.router.tmp.<pid>`
  redirect that followed symlinks. Both were removed rather than made safer, so
  the only directory the installer deletes is its own — behind the explicit
  `--remove`/`--purge` decision, and only when the directory's `manifest.json`
  declares `petealeon.router`. A root `preview.png` was added so the listing has
  a real preview image.

### Changed
- **Both columns share one 32px row height.** Output rows had been two lines
  tall to show full device names, which made a same-level source and output sit
  on different lines and a snap drag land according to the *other* column's
  height. One shared height keeps a route exactly level — and the output column
  still shows full names, it just draws them on the same row.
- **The playing glyph is gone.** The redundant speaker icon next to the app name
  — its live/paused signal was already carried by the row's circle and label
  weight — was removed to make room for the shortcut badge; a row that is
  actually playing draws at full weight, idle rows are dimmed.
- **The README was rewritten for end users.** Highlights, install, usage,
  keyboard, Bluetooth and privacy now lead; rule matching, watcher internals,
  the CLI and development notes moved behind a clearly separated "For
  developers" appendix. A screenshot of the panel in action links from the top.

## [1.4.2] - 2026-09-28

A malformed rule file could silence the whole panel, and a crashed watcher
could report itself as switched off.

### Fixed
- **One bad entry in `router-rules.json` could blank the entire panel.** The
  helper checked that the file's root was a list, but not what was inside it,
  while every consumer went on to call `.get()` on each element as a rule. A
  store containing a bare string, number, `null` or nested list — a hand-edit, a
  bad merge, or anything else that wrote valid JSON of the wrong shape — raised
  `AttributeError` inside rule matching. That took down `list`, `set-sink` and
  the watcher's re-assert together, and the panel's only symptom was an empty
  patchbay with nothing in the log to say why. Entries that are not rule objects
  are now ignored, every remaining rule keeps working, and the panel reports how
  many entries were skipped. **The file on disk is left exactly as written**:
  the bad entry is not silently deleted, so nothing is lost by fixing it by
  hand, and the rest of your rules survive in the meantime.

- **A killed watcher was reported as a clean shutdown.** The watcher's stderr
  carries a marker saying *why* it exited, and arrives before the process-exit
  signal that carries the code. The panel passed `0` — a clean exit — from that
  first channel, so any death the helper had not deliberately marked (a `SIGKILL`
  from the OOM killer, for instance) was classified as intentional: a 30-second
  re-arm instead of the 3-second retry, and no charge against the five-restart
  budget. A watcher crash-looping every few seconds therefore looked exactly like
  a user who had switched routing off. That channel now passes no code at all,
  and says only what it knows. The exit signal then supplies the real code, so
  the two together classify the death correctly — and a crash now supersedes the
  quiet re-arm if the two disagreed.

- **A snap drop could land on the wrong output.** Dragging a source row snapped
  to a row chosen with the *source* column's row height instead of the output
  column's, and bounded its search by that height too. The two grids are sized
  independently, so which output you got depended on how tall the other column's
  rows happened to be — and a drop past the end of the last output was refused
  outright. The output grid is measured the same way clicking it is measured.

### Changed
- The README no longer carries a marketplace section. Submission status is not
  something a person who installed the plugin needs, and the end-user docs now
  read as the tool rather than as its distribution. `docs/marketplace-submission.md`
  remains the single place that tracks it.

## [1.4.1] - 2026-09-28

One application could be listed twice, and one could be listed not at all.

### Fixed
- **A PipeWire ALSA app could be listed twice.** PipeWire names the ALSA client
  of an application `PipeWire ALSA [app]`, and reports the resulting stream with
  no `application.process.binary` at all. The panel therefore keyed the row by
  the node name, `alsa_playback.cliamp`, while the client and any pin on it were
  keyed by the binary, `cliamp`: two different keys, one label, two rows. Rows
  are now folded by identity rather than by key, so one app is one row however
  the audio server happens to name its parts, and a pin's identity is carried
  through the fold instead of being lost. Verified against the live session that
  reported it, and against a real application split the same way, which must
  also come out as one row.

- **A real application could be hidden as audio-stack plumbing.** Fixing the row
  above, `PipeWire ALSA [x]` was treated as a name owned by the audio stack and
  excluded by its first word. It is not: `x` is the application. On the machine
  that reported the duplicate, `x` was `cliamp` 2.0.1, an installed terminal
  music player, and it vanished from the panel entirely — an application you had
  installed and were using, gone, with nothing on screen to say why. Stack names
  are now excluded by exact, tag-stripped name only — `pipewire`, the
  session manager, the portals, `quickshell`, `systemd`, `EasyEffects` and this
  plugin's own tooling — with no first-word or namespace rule to over-match.
  The panel's row for such an app also reads as the application now — `cliamp`,
  not `PipeWire ALSA [cliamp]`.

- **`remove <name>` could miss a rule.** A rule written as
  `PipeWire ALSA [cliamp]` is listed and displayed as `cliamp`, and removing by
  the displayed name left it in place while reporting success. Matching is now
  by identity set, so either spelling finds it.

### Changed
- **The circle sits next to its source's name.** It used to sit at the far right
  of the source column, so a short name like `cliamp` had its circle marooned
  across 140px of empty row, reading as decoration rather than as that app's
  state. The circle now follows the end of the name, and the ring you click to
  unlink comes with it. That gives the label back the right-hand gutter the
  circle used to reserve.

- **Output names no longer need an ellipsis.** An output's name carries its
  identity at the *end* — `RODE NT-USB Analog Stereo` says the port is analog
  stereo — and an ellipsis eats exactly that. Output labels now wrap to two
  lines in a wider column, sized so the longest name this plugin has seen
  (`ThinkPad Dock USB Audio Analog Stereo`) fits whole. The source column pays
  for the extra width and keeps roughly the same label width as before, which is
  the right trade: long source names are uncommon, and when they happen the
  start of the name is the part that identifies them.

- **A connected output no longer grows a second dot.** Wrapping the output names
  put the output's own dot out of step with the line that terminates on it, and a
  connected output drew two: the dot belonging to the name, and a second one
  where the line actually landed. The dot now sits on the name's first line, the
  way a leading icon reads against wrapped text rather than floating in the gap
  between the two, and the line and the dot read the same position from the row
  that draws them — so the two cannot come apart again, whatever the name or the
  font scale.

- One exclusion list, in one place. `Model.js` owns the rule and the helper's
  selftest runs the same cases against both implementations, so a name edited
  in one and not the other fails the suite — the drift that let this through.
  The shared table is data, and it records *why* each name is or is not the
  audio stack, so the same mistake cannot be re-derived from a plausible-looking
  example again.
- An app answers to the name inside a PipeWire wrapper as well as the wrapper,
  when deciding what is the same app. Today every record for an ALSA app reports
  the identical wrapper string and they fold on that; a PipeWire version
  reporting the bare name on one side and the wrapper on the other would
  otherwise split the app across two rows again.
- A pinned row is keyed by its pin, so its identity no longer follows whatever
  node name the stream happened to have.

## [1.4.0] - 2026-09-27

A correctness and hardening release. Three bugs could affect audio a user did
not intend to move, and one could empty the whole panel.

### Fixed
- **The audio stack could be steered.** The list of applications never to route
  was compared case-sensitively against names that PipeWire does not spell that
  way. A live session here reports `WirePlumber` and `quickshell`, and the list
  held `wireplumber` and `Quickshell`, so neither matched: both were offered in
  the panel as routable, and `restore` — the command that implements "routing
  off" — would move their streams. The same session also reports some clients
  twice, once tagged `WirePlumber [client]`, and the tagged spelling slipped
  through as well. Exclusion is now case-insensitive, ignores a trailing
  bracketed tag, and is checked against the process binary as well as the
  reported application name, so a stack stream cannot be moved even if it
  presents an unfamiliar name. A test now cross-checks the helper's list
  against the one in `Panel.qml`, because the two had drifted — which is how
  this survived — and edits to either alone now fail the suite.

- **One invalid byte could empty the entire panel.** Subprocess output was
  decoded as UTF-8 with no error policy, and a single undecodable byte raised
  inside the decode. Because the helper turns any failure into an empty string,
  the result was not one bad character in one device name: the whole `list`
  payload came back empty and the panel showed nothing at all. Device and
  application names come from arbitrary user-controlled metadata, so this was
  reachable. The output is now decoded with replacement, which costs the one
  name a `\ufffd` and keeps the rest of the document.

- **A Bluetooth rule broke when the device reconnected as a different profile.**
  PipeWire suffixes Bluetooth outputs with a profile index that is not stable
  across reconnects, so a headset that comes back as profile 2 exposes the same
  speaker as `bluez_output.<mac>.2` where the rule says `.1`. Matching on the
  sink name read that as "the device disconnected", so the app silently fell
  back to the default output and played through the laptop while the panel
  still showed it pinned to the headset — and replugging did not help, because
  the rule failed the same comparison every time. Rules now match on the
  embedded MAC, so the pin follows the device in either direction. Wired
  outputs are still matched exactly, and a rule never moves to a device it did
  not name. The panel no longer draws a second "disconnected" row for a device
  that is present under another index.

- **The routing off-switch was only enforced in the panel.** A watcher started
  by a stale panel, by hand, or by anything else kept moving streams after the
  user had switched routing off. The watcher now reads the preference itself, so
  the switch holds at the point where the move happens; it idles instead of
  steering, and costs one small file read per poll.

### Changed
- **The watcher polls at two speeds.** It previously spawned roughly four
  `pactl` processes a second — about 1.9% of a core — for the whole session,
  whether or not any audio existed. It now polls every 0.5s while something is
  playing, which is the only time a stream can start on the wrong output, and
  backs off to 2.5s when the session is silent, lingering briefly at the fast
  cadence after the last stream so a pause between tracks cannot cause the next
  one to be missed.

- **The watcher log is bounded.** It lives on tmpfs, so an unbounded log is
  memory the session never recovers, and it was written to without limit while
  an unroutable app repeated the same line every 10 seconds. It is now capped at
  256 KB with one previous generation kept, and an app with no matching rule is
  reported once instead of every 10 seconds — the fact does not change between
  polls, and a later match is already covered by the `rules reasserted (n)`
  line.

### Hardened
- The state file is written mode `0600`, matching the rules store. It holds the
  on/off preference and, since 1.3.2, a cache of Bluetooth device names and MAC
  addresses; it was world-readable.
- `Panel.qml` normalises the helper's payload before reading it, so a short or
  unexpected response can no longer throw where it would wedge the panel until
  the plugin was reloaded.
- A store lock that cannot be opened is now a refusal with a message rather
  than an unhandled error, and it falls back to a lock beside the rules file
  when `$XDG_RUNTIME_DIR` is absent — the case outside a user session, where the
  write previously could not proceed at all. A fresh install creates its
  directory before looking for the lock.
- An unreadable rules file is preserved once per process rather than retried
  twice a second, and when the rename cannot happen the panel says the file was
  left in place instead of claiming a backup was made.

### Docs and metadata
- The README no longer claims the plugin is listed on the marketplace; it is
  not. It also no longer claims only playing apps are listed — the panel lists
  every client, and a pin can be made before an app has ever played. A *Data and
  privacy* section now documents both files that are written, their contents,
  their `0600` modes, the fact that `bluetoothctl` is optional, and how to
  remove the cached device names.
- `manifest.json` gained the `license`, `homepage`, `repository` and `keywords`
  fields the marketplace listing uses.
- `scripts/check-manifest.py` now requires those fields, checks the license
  against known SPDX identifiers, requires a `LICENSE` file to back the declared
  license, and cross-checks the manifest version against the version the widget
  reports. Those two version strings were previously kept in step by hand.
- ShellCheck runs in CI over both shell scripts. `bash -n` only proves a script
  parses; it cannot see an unquoted expansion or a variable read under `set -u`,
  in a script that runs as root during install. This surfaced one dead
  assignment in `scripts/qml-lint.sh`.
- `docs/marketplace-submission.md` is refreshed for this version, with the
  tagging step left explicitly last: the marketplace scans the exact tagged
  commit, so the listing metadata has to be correct on that tree.

## [1.3.2] - 2026-09-27

### Fixed
- **A disconnected Bluetooth output is now named, not shown as a raw sink
  identifier.** An output a rule still points at but PipeWire no longer reports
  — a Bluetooth device that has disconnected, or a dock that has been
  unplugged — kept a row in the panel, and that row was labelled with the sink
  name itself, so the Bluetooth entry read `bluez_output.24_06_11_A5_E7_95.1`.
  This was the most visible symptom because a disconnected device is not in
  `pactl list sinks` at all, so this row is the *only* place it could appear.

  The row now carries the device name, for example `MOONDROP BLOCK`, resolved in
  the order that costs the least: the description PipeWire last reported for
  that sink, captured while it was connected, then a one-time lookup of the MAC
  embedded in the sink name against BlueZ, then a last-resort
  `Bluetooth 24:06:11:A5:E7:95`. Nothing about the routing key changes, so rules
  and the routing-off switch are unaffected, and the row stays ghosted and
  marked `offline` exactly as before.

### Notes
- The remembered names and the lookup results are cached in
  `~/.config/omarchy/petealeon-router.json`, and the on/off preference now shares
  that file with a locked read-modify-write so a toggle and a background poll
  cannot overwrite each other. A Bluetooth lookup that *fails* is not cached, so
  a `bluetoothctl` that was briefly unavailable does not pin the raw name.
  `--purge` already removed this file.
- Only Bluetooth sink names are rewritten. `alsa_output.*` and USB names vary per
  device and driver, so those rows keep their raw name rather than risk a
  confident misparse.

## [1.3.1] - 2026-09-27

### Fixed
- **An app no longer appears twice while it is playing.** When PipeWire reports
  a process's binary with its ` (deleted)` artifact — which it does after the
  executable is replaced under a running process, as happens when Brave updates
  itself — the live stream keyed as `brave (deleted)` while the same app's
  client and its stored rule keyed as `brave`. The panel's identity key is
  first-non-empty-field-wins, so the rule failed to find the live row and
  created a second one with no streams: Brave showed a row with a playing icon
  and a row without, collapsing back to one on stop. The artifact is now
  stripped from identity and label fields, in `assets/omarchy-router` (so it can
  never be written into the rule store) and in `Model.js` (which also covers a
  rule already saved with it). The same mismatch had been quietly weakening rule
  matching: Brave's rule was only landing via its PipeWire node name, so a stream
  without one would have missed its rule and fallen back to the default output
  without saying so.
- **Turning routing off now actually reverts the audio.** The revert is run only
  once the watcher is confirmed gone, instead of racing it: previously `restore`
  was fired while the watcher was still dying, and the dying watcher could win
  and re-pin a stream after the revert had already moved it. The switch then
  read "off" with the app still on its pinned output, with nothing indicating
  anything had gone wrong. The revert is now started from the watcher's exit
  (with a bounded 1.5s backstop and the helper's own 5s lock wait behind it), and
  saved rules are still left untouched so switching back on re-pins the same
  apps.
- **A failed revert is no longer silent.** The revert ran through
  `execDetached`, which discards stdout and stderr, so a failure and a clean
  revert were indistinguishable — and the switch reported success either way. It
  is now a managed process whose result the panel reads, and the helper re-reads
  the stream list afterwards to confirm every valid stream actually reached
  `pactl get-default-sink` instead of trusting the moves it issued. Failures are
  reported in the panel ("routing off — some apps are still routed: …") rather
  than being swallowed. The helper also reports the outcome on stdout as
  `RESTORE_RESULT`, because Quickshell does not reliably deliver `onExited` for
  clean non-zero exits — exactly the shape of a failed revert.
- **Routing off survives a shell reload.** The switch only lived in a widget
  property, so any shell or plugin restart re-enabled routing with no visible
  indication. The intent is now persisted in
  `~/.config/omarchy/petealeon-router.json` and read before the watcher is
  started; a missing or unreadable file means on. The watcher is no longer
  started speculatively and then torn down for anyone who had routing off.
- **`restore` no longer looks successful when it did nothing.** It waited 2s for
  the watch lock, silently moved zero streams if `pactl` could not report a
  default sink, and gave up on any stream that did not follow. It now waits up to
  5s for the lock, fails loudly if `pactl` is unusable, and exits non-zero
  listing the apps that stayed routed.

### Added
- **`scripts/model-test.js`, wired into CI.** The identity helpers in `Model.js`
  decide which panel entries are the same app, and until now nothing tested
  them — the Python selftest cannot reach them, which is why the duplicate-row
  bug could ship. The test loads `Model.js` the way QML does and asserts the
  ` (deleted)` normalisation, the stream/client/rule agreement that produces a
  single row, and that key precedence still falls back binary → node name →
  application name.

## [1.3.0] - 2026-09-26

### Added
- **Full keyboard control.** The panel is now drivable without a mouse, following
  the same cursor conventions as the built-in panels. The first arrow press only
  wakes the cursor rather than moving or scrolling, so the panel never jumps on a
  stray keypress. `j`/`k` move a row, `l`/`h` cross between an app row and the
  output it is connected to, `Return`/`Space` routes (or, on the header, toggles
  routing), `x` resets an app to the system default, and `1`–`9` route straight
  to the nth output. The cursor spans both columns because the two share a row
  grid, and it is tracked by app/output key rather than row index so it survives
  the 1s refresh — including an app whose stream stops mid-navigation.
- **Master routing switch.** The panel header now carries an on/off switch like
  other built-in Omarchy tools. Turning routing off stops the watcher *and*
  restores every stream to the system default output (a new `restore` helper
  subcommand flocks the watch lock, so the dying watcher cannot re-assert pins
  mid-move); saved rules are untouched, so switching back on re-pins the same
  apps. The switch reflects effective state — a watcher that died with an
  exhausted crash budget reads as off, and toggling it back on resets that
  budget. A short hint tooltip names the action; the bar and hero icons dim
  while routing is off. The switch is also keyboard-operable now, which it was
  not before: `ToggleSwitch` is mouse-only, so the header had to become a cursor
  section.
- **Header matches built-in panels.** The title row is now `PanelHero` with the
  link icon, the "Audio Router" name, a two-line interaction hint as meta text,
  and a horizontal `PanelSeparator` before the link section.
- **Speaker glyph marks a live source.** A source that is currently producing
  audio now shows a small speaker icon (accent when pinned, foreground when on
  the system default) instead of the ambiguous background box; the gutter is
  reserved on every row so labels stay aligned.
- **Status notes.** A small note under the header reports a degraded `pactl`
  read in amber ("routing unavailable …") or, while routing is off, that edits
  are kept and applied when the switch comes back on. The patch dims in the
  latter case but stays editable.
- **`set-rule` helper subcommand.** Same four arguments as `set-sink`, but it
  only persists the rule and moves nothing. This is what makes the off-state
  note true: a route set while routing is off is *stored*, not applied, and draws
  as a dashed line with no endpoint dot so the patch never implies a live route.
  Resets still apply immediately, since "every stream is already on the default"
  is exactly what off means.

### Changed
- **Renamed to `petealeon.router`** (was `peter.router`) to match the GitHub
  owner and the other plugins in this namespace. The id is also the install
  directory, the bar entry and the Quickshell module name, so a plain rename
  would have left the old copy registered and the widget on the bar twice;
  `install.sh` now migrates it — it stops the old watcher, unregisters
  `peter.router` (which also drops its bar entry) and removes the old directory,
  while leaving `~/.config/omarchy/router-rules.json` intact. A stale bar entry
  is additionally swept from `shell.json` as a safety net, though `omarchy
  plugin remove` was observed to clean that up on its own. Both the install and
  the `--remove`/`--purge` paths run the migration, so no manual step is needed.
  Upgrading installs `petealeon.router` in the same right-hand bar section.
- System binaries (`quickshell`, `wireplumber`, `pipewire`, `systemd`, `pactl`,
  `pw-dump`, portals, …) are now excluded from steering in the helper itself,
  not just in the panel's row model.
- `Up`/`Down` no longer scroll the patch. The cursor takes them and scrolling
  follows the cursor, matching the built-in panels; the wheel is unaffected.
- README no longer claims a `__default__` output row exists. It does not:
  resetting is the ring click, an `x`, or a drop on whatever the current default
  output is.

### Removed
- The `+` "pre-pin an idle app" button and its picker. It could list system
  processes such as quickshell or wireplumber, which are never meaningfully
  routable, and its purpose was not discoverable. Only sources that are
  actually playing can be routed now.
- The header health dot, its status text and the version/pid tooltip, all
  superseded by the routing switch.

### Fixed
- **The panel opened in the middle of the bar instead of at its own corner.**
  It was placed with `centerOnBar: true`, which centres the card on the screen,
  so a widget at the end of a section still got a screen-centred panel. It now
  sits flush with the screen corner belonging to the bar section it lives in —
  the right end for `right`, the bottom end when the bar is on the side — and
  the corner is re-derived from the widget's live position, so moving the entry
  to another section moves the panel with it. A centre-section widget stays
  icon-centred, where "flush" has no meaningful answer.
- A `NameError` in the helper's `set-sink` path, introduced while splitting
  `set-rule` out of `set-sink` in this release and caught by the new
  `set-rule`/`set-sink` selftest coverage before it shipped.
- The CI QML lint step never actually ran. It gated on `command -v qmllint`,
  but `qmllint` is not on `PATH` on the distros that ship it, and it passed no
  import path, so `qs.Ui`/`qs.Commons` could not have resolved. It now installs
  `qt6-declarative-dev-tools` and calls `scripts/qml-lint.sh`, which locates the
  binary in the Qt6 tree, builds the `qs.*` import shim when an omarchy shell is
  present, and fails on parse errors instead of skipping silently.

## [1.2.1] - 2026-09-26

### Fixed
- **Watcher deaths are never lost and flock conflicts never burn the restart
  budget.** Quickshell's `Process.onExited` is reliable for signal deaths but
  drops clean exits (the watcher quitting on a `flock` conflict), which used to
  leave routes silently dead. The helper now announces every intentional stop
  via a `__WATCH_EXIT` marker on stderr; the widget dispatches on the first of
  that marker or `onExited` (de-duplicated), treats `{0, 3, 15}` as intentional
  stops that are quietly re-armed on a 30s timer, and only counts genuine
  crash signals (SIGKILL etc.) against the 5-restart-per-session budget. A
  20s liveness backstop re-arms even if the engine delivers no event at all.
- **Plugin reloads are quiet.** A reload's new watcher briefly shares the flock
  with its predecessor winding down; the helper now waits out a stale holder
  for up to ~2s instead of exiting, so a reload restores a single healthy
  watcher without contention noise.
- **Silent rule loss on a corrupt `router-rules.json`.** An unreadable store is
  now renamed aside to `router-rules.json.corrupt.<ts>` (never silently
  overwritten) and the problem is surfaced through `list.error` / the health
  tooltip.
- **Lost-update on store lock timeout.** `modify_store` now refuses the write
  when the exclusive lock cannot be acquired (5s) and logs it, instead of
  performing an unlocked read-modify-write.
- **Unbounded log growth on repeated poll errors.** Watch-loop diagnostics are
  rate-limited to one write per 10s per class; `traced`/`missing_reported`
  caches are capped.
- **Spurious restart during reload teardown.** `Component.onDestruction` stops
  the tracked watcher so plugin reloads don't rattle it through a crash path.
- **Flakey flock-contention recovery.** The "retry once" budget now survives
  respawns during a contention episode (cleared only after a watcher lives past
  the startup window), and a brief startup grace guarantees the tracker has
  observed the child before it may exit.

### Changed
- `router-rules.json` is written with mode `0600`.
- `install.sh --remove/--purge` kill is anchored to the plugin's own helper
  path (no broad substring match).
- Helper diagnostics (`say()` output, tracebacks) are captured into the widget
  log via a `StdioCollector` on the watcher process.
- `selftest` coverage grown to 33 checks (rate-limiter, store-issue merge,
  intentional-exit contract).

## [1.2.0] - 2026-09-26

### Added
- Degraded-mode diagnostics: when pactl reports no sink/stream data the helper
  emits an `error` field and the panel shows a ``no pactl`` status with the
  detail in the health-dot tooltip, instead of failing silently.
- CI workflow (`.github/workflows/ci.yml`) running the helper selftest, installer
  syntax check, manifest-integrity check, and QML lint on every push/PR.
- `scripts/check-manifest.py`: standalone marketplace-contract validation
  (required fields, entryPoints files, id namespace, no symlinks).
- Watcher poll errors are now also recorded in the watch log
  (`$XDG_RUNTIME_DIR/omarchy-router.watch.log`), not just stderr.
- `docs/marketplace-submission.md`: ready-to-paste marketplace listing draft.

### Changed
- `selftest` coverage grown to 26 checks (parsers, matcher, fallback, store
  mutation, degraded-read diagnostics). Empty sink-inputs stays a normal idle
  state — the degraded flag only fires on pactl absence or a missing sink read.

### Fixed
- None (maintenance + publish polish over 1.1.0).

## [1.1.0] - 2026-09-26

### Added
- Identity-based rule de-duplication (`set-sink` replaces rules by match
  identity, not just key), so re-pinning an app whose `process.binary` became
  visible later no longer creates a duplicate rule.
- `selftest` subcommand (22 zero-I/O checks) and README/license/installer polish.
- Watcher self-healing in the widget: a crashed watcher is restarted (3s delay,
  bounded 5 attempts per session), flagging state on a new header health dot
  (green alive / amber restarting / red dead / gray stopped; click to restart),
  and intentional exits (`flock` contention, parent gone) are handled with a
  single retry before giving up.
- `--remove` / `--purge` installer modes; `--remove` stops the watcher while
  keeping `router-rules.json`, `--purge` deletes it.