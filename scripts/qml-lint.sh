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
# about style/unresolved-member warnings. The qs.* modules are always made to
# resolve (real ones when the omarchy shell is installed, stubs otherwise) so
# that a version difference in how imports are graded cannot fail the build.

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

# The shim is built unconditionally. When the omarchy shell is present we point
# qs.Ui/qs.Commons at the real module directories; when it is not (GitHub
# Actions, or any machine without omarchy) we stub them with a bare qmldir so
# the imports still *resolve*. That matters: qmllint 6.4.x, which is what Ubuntu
# ships and therefore what CI runs, treats an unresolvable module import as a
# fatal error rather than a warning, so without the stubs the job fails on
# `import qs.Ui` instead of doing the syntax check it claims to do. The cost of a
# stub is that the omarchy types are unresolved, which is only a warning.
shim="$(mktemp -d)"
cleanup() { [ -n "$shim" ] && rm -rf "$shim"; }
trap cleanup EXIT

mkdir -p "$shim/qs"
with_shell=0
[ -f "$shell_dir/Ui/qmldir" ] && with_shell=1
for mod in Ui Commons; do
  if [ -d "$shell_dir/$mod" ]; then
    ln -sfn "$shell_dir/$mod" "$shim/qs/$mod"
  else
    mkdir -p "$shim/qs/$mod"
    printf 'module qs.%s\n' "$mod" >"$shim/qs/$mod/qmldir"
  fi
done
imports=(-I "$shim")

if [ "$with_shell" = 1 ]; then
  echo "qml-lint: $("$qmllint" --version 2>&1 | head -1) with omarchy imports from $shell_dir"
else
  echo "qml-lint: $("$qmllint" --version 2>&1 | head -1), no omarchy shell at $shell_dir"
  echo "qml-lint: qs.Ui/qs.Commons stubbed; omarchy types unresolved, checking syntax"
fi

cd "$root" || exit 1

# Pass -W -1 (max-warnings = unlimited) only where the tool understands it: it was
# added after 6.4, and 6.4.2 rejects the flag outright with "Unknown options".
# It is probed rather than assumed, and nothing below depends on it -- the
# pass/fail decision is made from the diagnostics, not from the exit code.
flags=()
if "$qmllint" --help 2>&1 | grep -q -- '--max-warnings'; then
  flags=(-W -1)
fi

out="$("$qmllint" "${flags[@]}" "${imports[@]}" BarWidget.qml Panel.qml Model.js 2>&1)"
# The exit code is deliberately not captured: qmllint returns 0 for warnings and
# non-zero for parse errors, but it also returns non-zero for the unresolved-type
# warnings that are expected whenever the omarchy shell is absent. The decision
# below comes from the diagnostics instead. (ShellCheck flags the unused
# assignment this replaced; it was left in from before that comment existed.)

warnings="$(printf '%s\n' "$out" | grep -cE '^Warning:' || true)"
# A QML file that will not load shows up as a syntax diagnostic, on every
# version tried (6.4.2 and 6.11.2 both tag it "[syntax]"). Everything else here
# is advisory: unresolved types and unqualified access are expected whenever the
# omarchy shell is not installed, which is the normal case in CI.
syntax="$(printf '%s\n' "$out" | grep -cE '\[syntax\]|^Error:' || true)"

if [ "${1:-}" = "--verbose" ]; then
  printf '%s\n' "$out"
else
  # Headlines only. The full qmllint output is mostly caret diagrams and
  # "Info:" explanations, which drown the signal at ~120 warnings.
  printf '%s\n' "$out" | grep -E '^(Warning|Error):' || true
  echo "qml-lint: (use --verbose for source context)"
fi

# qmllint refusing the invocation is a failure of the check itself, not of the
# code, and must not be mistaken for a clean run.
if printf '%s\n' "$out" | grep -q 'Unknown options'; then
  echo "qml-lint: FAIL -- this qmllint rejected the arguments:" >&2
  printf '%s\n' "$out" | grep -i 'unknown options' >&2
  exit 1
fi

if [ "$syntax" -gt 0 ]; then
  echo "qml-lint: FAIL -- $syntax syntax diagnostic(s); this QML will not load" >&2
  exit 1
fi

echo "qml-lint: ok, $warnings warning(s) (advisory)"
