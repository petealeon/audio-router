# Changelog

All notable changes to `peter.router` are documented here. SemVer; releases are
tagged `vX.Y.Z`.

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