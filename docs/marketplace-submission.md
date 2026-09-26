# Marketplace submission — petealeon.router

Draft for the Omarchy plugin marketplace (plugins.omarchy.org). Fill in the
repository URL once the repo is named and pushed, then paste into the
[submit form](https://plugins.omarchy.org/publish).

## Checklist (all must be true before submitting)

- [ ] Repository is **public** on GitHub
- [ ] `manifest.json` is at the repository root and passes `omarchy plugin validate`
- [ ] `scripts/check-manifest.py` passes (run: `python3 scripts/check-manifest.py`)
- [ ] README and LICENSE (MIT) are at the repository root
- [ ] `selftest` passes: `python3 assets/omarchy-router selftest`
- [ ] Install/removal is safe: `install.sh` gains `--remove`/`--purge`
- [ ] No symlinks in the repository; no secrets; ID not in the `omarchy.*` namespace
- [ ] The commit being submitted is tagged (`v1.3.0`) and pushed

## Suggested listing

**Repository URL:** not created yet — this repo is local-only (no git remote).
Intended name `petealeon/audio-router`; create it and confirm the name before
submitting, then paste the real URL into the
[submit form](https://plugins.omarchy.org/publish).

**Category:** Sound & Audio

**Tags:** `audio`, `pipewire`, `routing`

**Name:** Audio Router

**Author:** petealeon

**Version:** 1.3.0

**Description (short):**
`Persistent per-app audio routing: link any app to any output from a
two-column patchbay widget, by mouse or keyboard. Pins survive reboots and are
reasserted live by a self-healing watcher; Bluetooth fallback steers streams to
the default sink when a pinned device disconnects.`

**Manifest (already in the repo):**
```json
{
  "schemaVersion": 1,
  "id": "petealeon.router",
  "name": "Audio Router",
  "version": "1.3.0",
  "author": "petealeon",
  "description": "Persistent per-app audio routing: link any app to any output from a dedicated two-column patchbay widget",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" }
}
```

## After submitting

- The automated validation scans the exact commit SHA; then a maintainer
  approves and lists it.
- When you push a newer release, request an update via the marketplace's
  "verify and publish a newer upstream commit" flow.