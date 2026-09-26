# Changelog

All notable changes to `petealeon.router` are documented here. SemVer; releases are
tagged `vX.Y.Z`.

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