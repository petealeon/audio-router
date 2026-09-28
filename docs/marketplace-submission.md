# Marketplace submission — petealeon.router

Draft for the Omarchy plugin marketplace (plugins.omarchy.org). Paste into the
[submit form](https://plugins.omarchy.org/publish).

Status: **not submitted yet.** Nothing in this repository claims the plugin is
listed, and the README says so explicitly.

## Checklist (all must be true before submitting)

- [x] Repository is **public** on GitHub
- [x] `manifest.json` is at the repository root and passes `omarchy plugin validate`
- [x] `scripts/check-manifest.py` passes (run: `python3 scripts/check-manifest.py`)
- [x] README and LICENSE (MIT) are at the repository root, and the manifest
      declares `license`/`homepage`/`repository`/`keywords`
- [x] `selftest` passes: `python3 assets/omarchy-router selftest`
- [x] `node scripts/model-test.js` passes
- [x] Install/removal is safe: `install.sh` gains `--remove`/`--purge`
- [x] No symlinks in the repository; no secrets; ID not in the `omarchy.*` namespace
- [x] README documents the data the plugin writes, where, and how to remove it
- [ ] The commit being submitted is tagged (`v1.4.1`) and pushed — **do this
      last**, after the checklist above passes on that exact tree

## Suggested listing

**Repository URL:** https://github.com/petealeon/audio-router
Paste it into the [submit form](https://plugins.omarchy.org/publish).

**Category:** Sound & Audio

**Tags:** `audio`, `pipewire`, `routing`, `bluetooth`, `patchbay`

**Name:** Audio Router

**Author:** petealeon

**Version:** 1.4.1

**Description (short):**
`Persistent per-app audio routing: link any app to any output from a
two-column patchbay widget, by mouse or keyboard. Pins survive reboots and are
reasserted live by a self-healing watcher that polls fast only while audio is
playing. Bluetooth rules follow the device rather than PipeWire's unstable
profile index, so a headset that reconnects as a different profile stays
routed; a disconnected device is still shown by name.`

**What it touches:** reads `pactl`; writes `~/.config/omarchy/router-rules.json`
(your pins) and `~/.config/omarchy/petealeon-router.json` (on/off preference and
a cache of Bluetooth device names and MACs), both mode `0600`. No network
access. `bluetoothctl` is optional and used only to resolve a MAC to a name.
`./install.sh --purge` removes both files.

**Manifest (already in the repo):**
```json
{
  "schemaVersion": 1,
  "id": "petealeon.router",
  "name": "Audio Router",
  "version": "1.4.1",
  "author": "petealeon",
  "description": "Persistent per-app audio routing: link any app to any output from a dedicated two-column patchbay widget",
  "license": "MIT",
  "homepage": "https://github.com/petealeon/audio-router",
  "repository": "https://github.com/petealeon/audio-router",
  "keywords": ["audio", "routing", "pipewire", "pulseaudio", "bluetooth", "bar-widget", "patchbay"],
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" }
}
```

## After submitting

- The automated validation scans the exact commit SHA; then a maintainer
  approves and lists it.
- When you push a newer release, request an update via the marketplace's
  "verify and publish a newer upstream commit" flow.
- Bump `manifest.json` **and** the `version` property in `BarWidget.qml`
  together. `scripts/check-manifest.py` fails when they disagree — that check
  exists because they were previously kept in sync by hand and had already
  drifted once.
