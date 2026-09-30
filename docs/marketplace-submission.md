# Marketplace submission — petealeon.router

Submitted on **2026-09-29** as
[omacom/omarchy-plugin-marketplace#9263](https://github.com/omacom/omarchy-plugin-marketplace/issues/9263)
(v1.4.3). Automated validation **passed**; the maintainer's security review
found two file-safety blockers, which were fixed and the submission re-run for
a fresh validation + review (see "Review round" below).

Status: **review in progress, not yet listed.** This file is the only place that says so —
the README deliberately says nothing about marketplace status, so a reader's first
impression of the plugin is the plugin rather than its distribution. Nothing in
this repository claims the plugin is listed.

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
- [x] The commit being submitted is tagged (`v1.4.3`) and pushed — **do this
      last**, after the checklist above passes on that exact tree

## Suggested listing

**Repository URL:** https://github.com/petealeon/audio-router
As submitted in [#9263](https://github.com/omacom/omarchy-plugin-marketplace/issues/9263).

**Category:** Widgets

**Tags:** `bar`, `quickshell`, `media` (lowercase, as submitted; the form's
fixed options — no audio tag exists yet — **"Audio"** was suggested, reviewers
decide on it)

**Name:** Audio Router

**Author:** petealeon

**Version:** 1.4.3

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
  "version": "1.4.3",
  "author": "petealeon",
  "description": "Persistent per-app audio routing: link any app to any output from a dedicated two-column patchbay widget",
  "license": "MIT",
  "homepage": "https://github.com/petealeon/audio-router",
  "repository": "https://github.com/petealeon/audio-router",
  "keywords": ["audio", "routing", "pipewire", "pulseaudio", "bluetooth", "bar-widget", "patchbay"],
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "Audio Router",
    "description": "Two-column patchbay for routing apps to outputs, with persistent pinned rules",
    "category": "Info",
    "defaultSection": "right",
    "allowMultiple": false
  }
}
```

Copied from the repository's `manifest.json` — re-check it with
`python3 scripts/check-manifest.py` if in doubt, since this block is meant to
be a paste and a paste is only correct if it matches the file.

## Review round (2026-09-29)

Automated validation **passed** (commit `7fb8009`); the security baseline
posted `review-required` and the maintainer's review found **two file-safety
blockers**, both fixed:

- `assets/omarchy-router`: `write_rules()` (and the same pattern in
  `modify_state()`) wrote to a predictable `*.tmp` path with a plain
  `open("w")`, which follows a pre-placed symlink and truncates its target.
  Both now write through an exclusively-created `mkstemp` temp file in the same
  directory (fsynced) and atomically rename over the target; a failed write
  cleans its temp up.
- `install.sh`: `drop_legacy` and `remove` deleted the `peter.router` /
  `petealeon.router` directory on a name match alone. Both now first verify the
  directory's `manifest.json` declares the matching plugin id, and leave
  anything unverified untouched with a note on how to remove it manually.

Also added: a root `preview.png` (the validation bot had fallen back to its
placeholder preview). Both fixes carry selftest source guards, so a regression
fails `python3 assets/omarchy-router selftest`.

After the fixes, the `v1.4.3` tag was moved onto the fixed tree (no version
bump — still pre-publication) and the issue was re-edited to re-run validation
on the new commit; then a maintainer approves and lists it.

## After submitting

- The automated validation scans the exact commit SHA; then a maintainer
  approves and lists it.
- When you push a newer release, request an update via the marketplace's
  "verify and publish a newer upstream commit" flow.
- Bump `manifest.json` **and** the `version` property in `BarWidget.qml`
  together. `scripts/check-manifest.py` fails when they disagree — that check
  exists because they were previously kept in sync by hand and had already
  drifted once.
