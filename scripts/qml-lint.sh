#!/usr/bin/env bash
# Lint the plugin's QML/JS with qmllint.
#
# Two things this handles that a bare `qmllint *.qml` does not:
#
#   1. qmllint is not on PATH on most distros. Arch ships it inside the Qt6
#      tree at /usr/lib/qt6/bin/qmllint (package qt6-declarative); Debian and
#      Ubuntu use qt6-declarative-dev-tools. So `command -v qmllint` alone
#      silently skips the check, which is what CI used to do.
#
#   2. The omarchy modules are declared as `qs.Ui` / `qs.Commons` but live at
#      <shell>/Ui and <shell>/Commons, so qmllint needs a `qs/` prefix on its
#      import path to resolve them. We build that shim from symlinks in a
#      temp dir when the shell is present.
#
# Exit status: qmllint returns 0 for warnings and non-zero for parse errors,
# so this fails the build on a QML file that will not load and stays advisory
# about style/unresolved-member warnings. That distinction matters: without the
# omarchy shell (as in GitHub Actions) the qs.* types cannot resolve, and we
# still want syntax checking.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"

qmllint=""
for cand in qmllint /usr/lib/qt6/bin/qmllint /usr/lib/qt6/libexec/qmllint /usr/lib/qt5/bin/qmllint; do
  if command -v "$cand" >/dev/null 2>&1; then
    qmllint="$(command -v "$cand")"
    break
  fi
done

if [ -z "$qmllint" ]; then
  echo "qml-lint: skip (qmllint not found)." >&2
  echo "qml-lint:   Arch: pacman -S qt6-declarative   Debian/Ubuntu: apt install qt6-declarative-dev-tools" >&2
  exit 0
fi

shell_dir="${OMARCHY_SHELL:-/usr/share/omarchy/shell}"
imports=()
shim=""
cleanup() { [ -n "$shim" ] && rm -rf "$shim"; }
trap cleanup EXIT

if [ -f "$shell_dir/Ui/qmldir" ]; then
  shim="$(mktemp -d)"
  mkdir -p "$shim/qs"
  for mod in Ui Commons; do
    [ -d "$shell_dir/$mod" ] && ln -sfn "$shell_dir/$mod" "$shim/qs/$mod"
  done
  imports=(-I "$shim")
  echo "qml-lint: $("$qmllint" --version 2>&1 | head -1) with omarchy imports from $shell_dir"
else
  echo "qml-lint: $("$qmllint" --version 2>&1 | head -1), no omarchy shell at $shell_dir"
  echo "qml-lint: qs.Ui/qs.Commons will not resolve; checking syntax only"
fi

cd "$root" || exit 1
out="$("$qmllint" "${imports[@]}" BarWidget.qml Panel.qml Model.js 2>&1)"
status=$?

warnings="$(printf '%s\n' "$out" | grep -cE '^(Warning|Error):' || true)"

if [ "${1:-}" = "--verbose" ]; then
  printf '%s\n' "$out"
else
  # Headlines only. The full qmllint output is mostly caret diagrams and
  # "Info:" explanations, which drown the signal at ~90 warnings.
  printf '%s\n' "$out" | grep -E '^(Warning|Error):' || true
  echo "qml-lint: (use --verbose for source context)"
fi

if [ "$status" -ne 0 ]; then
  echo "qml-lint: FAIL (qmllint exit $status) — parse errors above" >&2
  exit "$status"
fi

echo "qml-lint: ok, $warnings warning(s) (advisory)"
