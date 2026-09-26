# Changelog

All notable changes to `peter.router` are documented here. SemVer; releases are
tagged `vX.Y.Z`.

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