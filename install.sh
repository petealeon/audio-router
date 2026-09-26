#!/usr/bin/env bash
# Install (or remove) the petealeon.router Omarchy shell plugin.
#
# Usage:
#   ./install.sh            install + enable the widget
#   ./install.sh --remove   uninstall (keeps the routing rules in
#                           ~/.config/omarchy/router-rules.json)
#   ./install.sh --purge    uninstall and delete the routing rules
#
# The plugin is the two-column audio patchbay: a dedicated bar icon opens a
# panel where any app can be dragged onto (or click-clicked into) any output.
# Pinned routes are persisted in ~/.config/omarchy/router-rules.json and
# reasserted by a self-healing watcher.

set -euo pipefail

PLUGIN_ID="petealeon.router"
# The plugin used to be published as peter.router. Its id is also its install
# directory and its bar entry, so a plain rename would leave the old copy
# registered and the bar showing the widget twice. Both the install and the
# remove paths clean these up first.
LEGACY_IDS=("peter.router")
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${HOME}/.config/omarchy/plugins"
DEST="${PLUGINS_DIR}/${PLUGIN_ID}"
SHELL_JSON="${HOME}/.config/omarchy/shell.json"

fail() { echo "install.sh: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Unregister a superseded id: stop its watcher (anchored to that install path so
# it can never match an unrelated process), drop the plugin, strip its bar entry,
# then remove any leftover directory. Routing rules live in
# ~/.config/omarchy/router-rules.json and are deliberately untouched — only
# --purge deletes those.
drop_legacy() {
  local legacy dest
  for legacy in "${LEGACY_IDS[@]}"; do
    dest="${PLUGINS_DIR}/${legacy}"
    if ! omarchy plugin list 2>/dev/null | grep -q "^${legacy}[[:space:]]" && [[ ! -d $dest ]] &&
       ! grep -q "\"${legacy}\"" "$SHELL_JSON" 2>/dev/null; then
      continue
    fi
    pkill -f "${dest}/assets/omarchy-router watch" 2>/dev/null || true
    if omarchy plugin list 2>/dev/null | grep -q "^${legacy}[[:space:]]"; then
      omarchy plugin remove "$legacy" --yes >/dev/null 2>&1 || true
    fi
    [[ -d $dest ]] && rm -rf "$dest"
    # `omarchy plugin remove` disables the plugin but leaves its entry in the
    # persisted bar layout, which would keep a dead widget slot in the bar.
    if [[ -f $SHELL_JSON ]] && command -v jq >/dev/null 2>&1 &&
       jq -e --arg id "$legacy" '.bar.layout[][]? | select(.id == $id)' "$SHELL_JSON" >/dev/null 2>&1; then
      local tmp="${SHELL_JSON}.router.tmp.$$"
      if jq --arg id "$legacy" '
            .bar.layout |= with_entries(.value |= map(select(.id != $id)))
          ' "$SHELL_JSON" >"$tmp" 2>/dev/null; then
        mv "$tmp" "$SHELL_JSON"
        echo "Removed stale bar entry for $legacy"
      else
        rm -f "$tmp"
        echo "Warning: could not strip the $legacy bar entry from shell.json" >&2
      fi
    fi
    echo "Removed superseded plugin $legacy (routing rules kept)"
  done
}

command -v omarchy >/dev/null 2>&1 || fail "omarchy not found — this installer targets Omarchy systems"

remove() {
  local purge=${1:-0}
  # Stop the rule-reassertion watcher anchored to this plugin's own helper path
  # (survives plugin removal on its own, keeping the routing rules alive; only a
  # purge should fully take that over). Path-prefixed so it can never match an
  # unrelated process whose command line merely contains the same string.
  pkill -f "${DEST}/assets/omarchy-router watch" 2>/dev/null || true
  if omarchy plugin list 2>/dev/null | grep -q "^${PLUGIN_ID}$"; then
    omarchy plugin remove "$PLUGIN_ID" --yes || fail "omarchy plugin remove failed"
  elif [[ -d $DEST ]]; then
    rm -rf "$DEST"
    omarchy restart shell
  fi
  if (( purge )); then
    rm -f "${HOME}/.config/omarchy/router-rules.json"
    echo "Purged routing rules."
  fi
  # Also clear any superseded id, so removing after the rename is a clean sweep
  # rather than leaving an orphan behind.
  drop_legacy
  echo "Removed $PLUGIN_ID."
  exit 0
}

[[ ${1:-} == "--remove" ]] && remove 0
[[ ${1:-} == "--purge" ]] && remove 1

# The rename changes the install directory and bar entry, so clear the old id
# before installing — otherwise the bar ends up with the widget twice.
drop_legacy

# ---- dependencies -----------------------------------------------------------
missing=()
for dep in pactl python3 jq; do
  have "$dep" || missing+=("$dep")
done
if (( ${#missing[@]} > 0 )); then
  echo "Missing dependencies: ${missing[*]}"
  fail "install dependencies first"
fi

# ---- files ------------------------------------------------------------------
for f in manifest.json BarWidget.qml Panel.qml Model.js; do
  [[ -f $SRC/$f ]] || fail "missing $SRC/$f — run this from the plugin repo"
done

# Auto-backup: keep the 3 newest timestamped backups of whatever is currently
# installed (same .<id>.bak.<ts> convention omarchy CLI uses) so an upgrade
# can never destroy the working widget.
if [[ -d $DEST ]]; then
  BK="$(dirname "$DEST")/.${PLUGIN_ID}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a "$DEST" "$BK"
  echo "Backed up current plugin to $BK"
  # shellcheck disable=SC2012
  ls -1dt "$(dirname "$DEST")/.${PLUGIN_ID}.bak."* 2>/dev/null | tail -n +4 | xargs -r rm -rf
fi

mkdir -p "$DEST"
mkdir -p "$DEST/assets"
for f in manifest.json BarWidget.qml Panel.qml Model.js; do
  cp "$SRC/$f" "$DEST/$f"
done
cp "$SRC/assets/omarchy-router" "$DEST/assets/omarchy-router"
chmod +x "$DEST/assets/omarchy-router"
echo "Installed plugin files into $DEST"

# ---- enable + place ---------------------------------------------------------
if ! omarchy plugin list 2>/dev/null | grep -qE "^${PLUGIN_ID}[[:space:]]"; then
  echo "Plugin not registered yet — restarting shell to rescan plugin dirs"
  omarchy restart shell
fi

if [[ -f $SHELL_JSON ]] && command -v jq >/dev/null 2>&1 &&
  jq -e --arg id "$PLUGIN_ID" '.bar.layout[][]? | select(.id == $id)' \
    "$SHELL_JSON" >/dev/null 2>&1; then
  echo "Widget already on the bar — refreshing placement"
  omarchy bar put "$PLUGIN_ID" --section right
else
  omarchy plugin enable "$PLUGIN_ID" --section right
fi

omarchy restart shell
echo "Done — look for the link icon on the right side of the menu bar."