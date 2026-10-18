#!/usr/bin/env bash
# Sanitizer and timestamp tests. Headless: needs Quickshell, no compositor.
set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/mnotif-markup.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

# Quickshell only imports files under the config root, so the test runs from
# a scratch root holding the test and the module under test. Its own
# XDG_RUNTIME_DIR keeps the instance away from any running Quickshell.
mkdir -m 700 "$work/run"
cp "$repo/tests/markup.qml" "$repo/text.js" "$work/"

QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$work/run" \
	timeout 20 qs --no-color -p "$work/markup.qml" >"$work/log" 2>&1 || true
sed -n 's/^.*qml: //p' "$work/log"
grep -q 'qml: markup: all passed$' "$work/log"
