#!/usr/bin/env bash
# Install (optional), launch, and screenshot an app on a booted iOS simulator,
# waiting for the UI to settle so the shot isn't a blank pre-render frame.
#
# Usage:
#   screenshot.sh --app <path/to/App.app> [--args "<launch args>"] [--out <png>] [--device <udid>]
#   screenshot.sh --bundle <id>            [--args "<launch args>"] [--out <png>] [--device <udid>]
#   screenshot.sh                          # just screenshot whatever is on screen
#
# Prints the screenshot path on success.
set -euo pipefail

APP="" BUNDLE="" ARGS="" OUT="/tmp/sim-screenshot.png" DEVICE="booted"
while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --bundle) BUNDLE="$2"; shift 2 ;;
    --args) ARGS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Resolve the booted device UDID unless one was passed.
if [ "$DEVICE" = "booted" ]; then
  DEVICE=$(xcrun simctl list devices booted \
    | grep -Eo '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
  [ -n "$DEVICE" ] || { echo "no booted simulator (boot one with: xcrun simctl boot <udid>)" >&2; exit 1; }
fi

if [ -n "$APP" ]; then
  xcrun simctl install "$DEVICE" "$APP"
  [ -n "$BUNDLE" ] || BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
fi

if [ -n "$BUNDLE" ]; then
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true   # fresh launch
  # shellcheck disable=SC2086
  xcrun simctl launch "$DEVICE" "$BUNDLE" $ARGS >/dev/null
fi

# Capture once per second until two consecutive frames match (UI settled), so we
# don't return a blank frame the app hadn't finished rendering yet.
prev=""
for _ in $(seq 1 8); do
  sleep 1
  xcrun simctl io "$DEVICE" screenshot "$OUT" >/dev/null 2>&1 || continue
  cur=$(shasum "$OUT" | cut -d' ' -f1)
  [ "$cur" = "$prev" ] && break
  prev="$cur"
done

echo "$OUT"
