#!/usr/bin/env bash
#
# Run the UIKit editor tests on the canonical iOS simulator.
#
# ProseKit's UITextInput/UIView tests are only validated on one simulator so
# runs are reproducible. Machines commonly have several "iPhone 17 Pro"
# simulators installed with different iOS versions, so we pin the OS here and
# resolve to a concrete device id at runtime.
#
# Override with:  DEVICE_NAME=... OS_VERSION=... scripts/test-ios.sh [extra xcodebuild args]
set -euo pipefail

# Exported so the Python helper below can read them via os.environ, both for the
# documented default invocation and when the caller overrides them.
export DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
export OS_VERSION="${OS_VERSION:-26.1}"
SCHEME="${SCHEME:-ProseKit-Package}"

# Resolve the concrete udid for the pinned device + OS so we never accidentally
# target a same-named simulator running a different iOS version.
udid="$(
  xcrun simctl list devices available --json \
    | /usr/bin/python3 -c '
import json, sys, os
data = json.load(sys.stdin)
name = os.environ["DEVICE_NAME"]
want = "iOS " + os.environ["OS_VERSION"]
for runtime, devices in data["devices"].items():
    # runtime looks like com.apple.CoreSimulator.SimRuntime.iOS-26-1
    key = runtime.split(".")[-1].replace("iOS-", "iOS ").replace("-", ".")
    if key == want:
        for d in devices:
            if d["name"] == name:
                print(d["udid"])
                sys.exit(0)
sys.exit(1)
'
)" || {
  echo "error: no available '$DEVICE_NAME' simulator on $OS_VERSION found." >&2
  echo "       Install it via Xcode > Settings > Components, or override DEVICE_NAME/OS_VERSION." >&2
  exit 1
}

echo "Testing on $DEVICE_NAME ($OS_VERSION) — id=$udid"
exec xcodebuild test \
  -scheme "$SCHEME" \
  -destination "id=$udid" \
  "$@"
