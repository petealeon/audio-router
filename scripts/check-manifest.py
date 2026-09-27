#!/usr/bin/env python3
"""Statically validate a plugin repository against the Omarchy marketplace
manifest contract (plugins.omarchy.org/publish).

Checks (no omarchy install needed) and never touches the system:
  - manifest.json exists, is valid JSON, schemaVersion == 1
  - required fields: id, name, version (<=64 chars), author, description, kinds
  - id is a valid third-party id (not under the reserved omarchy. namespace)
  - kinds is a non-empty subset of known plugin kinds
  - every entryPoint file exists relative to the repo root
  - listing metadata is present and well-formed (license, homepage, repository,
    keywords) and a LICENSE file exists to back the declared license
  - the manifest version matches the version the widget reports
  - the repository contains no symlinks

The version cross-check exists because manifest.json and BarWidget.qml carried
the same string in two places with nothing tying them together: a release that
bumped one and not the other shipped a panel advertising the wrong version, and
CI stayed green because nothing compared them.

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
# These two are rendered as links on the listing, so the failure worth catching
# before submission is a value that is not a URL at all. Paths are allowed: the
# repository URL is not a bare host.
URL_RE = re.compile(r"^https://[^\s/$.?#].[^\s]*$", re.IGNORECASE)
KNOWN_LICENSES = {"MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "GPL-2.0", "GPL-3.0", "ISC", "MPL-2.0", "Unlicense"}
WIDGET_VERSION_RE = re.compile(r'property\s+string\s+version\s*:\s*"([^"]+)"')


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

    for field in ("license", "homepage", "repository"):
        val = m.get(field)
        if not val:
            fail(f"missing listing metadata field {field!r} (required for the marketplace listing)")
        elif not isinstance(val, str):
            fail(f"{field} must be a string, got {type(val).__name__}")
        elif field != "license" and not URL_RE.match(val):
            fail(f"{field} must be an https:// URL, got {val!r}")

    lic = m.get("license")
    if isinstance(lic, str) and lic and lic not in KNOWN_LICENSES:
        fail(f"license {lic!r} is not a recognised SPDX id (known: {', '.join(sorted(KNOWN_LICENSES))})")
    if lic and not any(os.path.isfile(os.path.join(REPO, n)) for n in ("LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING")):
        fail(f"manifest declares license {lic!r} but the repository has no LICENSE file")

    kws = m.get("keywords")
    if kws is None:
        fail("missing listing metadata field 'keywords' (used for marketplace search)")
    elif not isinstance(kws, list) or not kws:
        fail("keywords must be a non-empty list")
    elif not all(isinstance(k, str) and k.strip() for k in kws):
        fail("keywords must all be non-empty strings")
    elif len(kws) > 20:
        fail(f"keywords has {len(kws)} entries; keep the list short enough to be a search aid")

    # The widget advertises its own version in the panel footer, and that string
    # was previously kept in step with the manifest by hand.
    ver = m.get("version", "")
    if ver:
        found = {}
        for dirpath, dirnames, filenames in os.walk(REPO):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for name in filenames:
                if not name.endswith(".qml"):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    with open(path, encoding="utf-8") as f:
                        for fv in WIDGET_VERSION_RE.findall(f.read()):
                            found.setdefault(fv, []).append(os.path.relpath(path, REPO))
                except OSError:
                    pass
        if not found:
            fail("no QML file declares a version property to compare against the manifest")
        for fv, files in sorted(found.items()):
            if fv != ver:
                fail(f"version mismatch: manifest says {ver!r} but {', '.join(sorted(files))} "
                     f"declares {fv!r}")

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