#!/usr/bin/env bash
# Runs the example's integration tests on the running emulator and prints the
# relevant part of logcat, so failures and hangs can be diagnosed from the log.
set -uo pipefail

cd "$(dirname "$0")/../../example"

adb logcat -c || true
timeout 1200 flutter test integration_test --timeout 120s
status=$?

echo "::group::logcat"
adb logcat -d -v time | grep -E "flutter|Flutter|ExtensionBridge|AndroidRuntime|FATAL|ActivityTaskManager|extension_bridge" | tail -n 400
echo "::endgroup::"

exit $status
