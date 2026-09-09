#!/usr/bin/env bash
# Builds DogAnimationExperiment for all manifest-declared devices, then
# builds and runs the Toybox.Test suite on fenix7s. Mirrors the sequence
# that was otherwise hand-typed into the terminal every session.
#
# Restarts the Connect IQ simulator fresh before the test run -- a
# leftover instance has been observed to hang monkeydo indefinitely.
#
# Usage: scripts/build.sh
# Override the SDK location with CONNECTIQ_SDK_HOME if auto-detection
# picks the wrong one (e.g. multiple SDK versions installed).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/DogAnimationExperiment"
DEV_KEY="$ROOT_DIR/keys/developer_key"
DEVICES=(fenix7pro fenix7pronowifi fenix7s fenix7spro fenix8solar47mm)

if [ -z "${CONNECTIQ_SDK_HOME:-}" ]; then
    CONNECTIQ_SDK_HOME=$(find "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" -maxdepth 1 -iname "connectiq-sdk-*" -type d 2>/dev/null | sort | tail -1)
fi
if [ -z "$CONNECTIQ_SDK_HOME" ] || [ ! -x "$CONNECTIQ_SDK_HOME/bin/monkeyc" ]; then
    echo "Could not find a Connect IQ SDK. Set CONNECTIQ_SDK_HOME to its install directory." >&2
    exit 1
fi
if [ ! -f "$DEV_KEY" ]; then
    echo "Developer key not found at $DEV_KEY." >&2
    exit 1
fi

MONKEYC="$CONNECTIQ_SDK_HOME/bin/monkeyc"
MONKEYDO="$CONNECTIQ_SDK_HOME/bin/monkeydo"

cd "$APP_DIR"

# Sequential, not parallel: the resource compiler has been observed to fail
# intermittently ("A critical error has occurred") when multiple device
# builds run concurrently against the same jungle file.
for device in "${DEVICES[@]}"; do
    echo "=== $device ==="
    "$MONKEYC" -w -f monkey.jungle -d "$device" -o "bin/DogAnimationExperiment-$device.prg" -y "$DEV_KEY"
done

echo "=== test build (fenix7s) ==="
"$MONKEYC" -t -f monkey.jungle -d fenix7s -o bin/DogAnimationExperimentTest.prg -y "$DEV_KEY"

# A simulator instance left over from a previous run/command has been
# observed to leave monkeydo hanging indefinitely rather than connecting or
# failing fast -- always start from a clean one rather than reusing
# whatever's running.
echo "=== restarting simulator ==="
osascript -e 'quit app "ConnectIQ"' >/dev/null 2>&1 || true
sleep 2
open -a "$CONNECTIQ_SDK_HOME/bin/ConnectIQ.app"
sleep 8

echo "=== running tests (fenix7s) ==="
# monkeydo -t's own exit code isn't reliable pass/fail signal (observed
# non-zero even on a full pass) -- key off the printed summary line instead.
set +e
TEST_OUTPUT=$("$MONKEYDO" bin/DogAnimationExperimentTest.prg fenix7s -t 2>&1)
set -e
echo "$TEST_OUTPUT"
if ! echo "$TEST_OUTPUT" | grep -q "^PASSED "; then
    echo "Tests did not report PASSED -- treating as a failure." >&2
    exit 1
fi
