#!/usr/bin/env python3
"""Statically validate a plugin repository against the Omarchy marketplace
manifest contract (plugins.omarchy.org/publish).

Checks (no omarchy install needed) and never touches the system:
  - manifest.json exists, is valid JSON, schemaVersion == 1
  - required fields: id, name, version (<=64 chars), author, description, kinds
  - id is a valid third-party id (not under the reserved omarchy. namespace)
  - kinds is a non-empty subset of known plugin kinds
  - every entryPoint file exists relative to the repo root
  - the repository contains no symlinks

Exit code 0 when the repository is submission-ready.

Usage: python3 scripts/check-manifest.py [repo-root]
"""

import json
import os
import re
import sys

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(REPO, "manifest.json")

ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
KNOWN_KINDS = {"bar", "bar-widget", "overlay", "panel", "service", "menu"}
KNOWN_ENTRYPOINTS = {"barWidget", "overlay", "panel", "service", "menu"}

failures = []


def fail(msg):
    failures.append(msg)


def main():
    if not os.path.isfile(MANIFEST):
        fail(f"missing {MANIFEST}")
        return report()
    try:
        with open(MANIFEST, encoding="utf-8") as f:
            m = json.load(f)
    except Exception as e:
        fail(f"manifest.json is not valid JSON: {e}")
        return report()
    if not isinstance(m, dict):
        fail("manifest.json root must be an object")
        return report()

    if m.get("schemaVersion") != 1:
        fail(f"schemaVersion must be 1 (got {m.get('schemaVersion')!r})")

    for field in ("id", "name", "version", "author", "description"):
        if not m.get(field):
            fail(f"missing required field {field!r}")

    pid = m.get("id", "")
    if pid and not ID_RE.match(pid):
        fail(f"id {pid!r} must match {ID_RE.pattern}")
    if pid.startswith("omarchy."):
        fail(f"id {pid!r} uses the reserved omarchy. namespace")

    ver = m.get("version", "")
    if len(ver) > 64:
        fail(f"version is {len(ver)} characters (marketplace limit is 64)")

    kinds = m.get("kinds", [])
    if not isinstance(kinds, list) or not kinds:
        fail("kinds must be a non-empty list")
    else:
        unknown = [k for k in kinds if k not in KNOWN_KINDS]
        if unknown:
            fail(f"kinds contains unknown values: {unknown}")

    eps = m.get("entryPoints") or {}
    if not isinstance(eps, dict) or not eps:
        fail("entryPoints must be a non-empty object")
    for kind, path in eps.items():
        if kind not in KNOWN_ENTRYPOINTS:
            fail(f"entryPoints key {kind!r} is unknown")
        if not path or not isinstance(path, str):
            fail(f"entryPoints.{kind} must be a file path")
            continue
        target = os.path.join(REPO, path)
        if not os.path.isfile(target):
            fail(f"entryPoints.{kind} references missing file {path!r}")
        if os.path.islink(target):
            fail(f"entryPoints.{kind} {path!r} must not be a symlink")

    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in dirs + files:
            node = os.path.join(root, name)
            if os.path.islink(node):
                fail(f"symlink not allowed in repository: {os.path.relpath(node, REPO)}")

    return report()


def report():
    if failures:
        print(f"check-manifest: {len(failures)} problem(s)")
        for f in failures:
            print(f"  FAIL  {f}")
        return 1
    print("check-manifest: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)