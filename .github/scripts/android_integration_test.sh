#!/usr/bin/env bash
# Runs the example's integration tests on the running Android emulator.
#
# Every test has its own timeout, so a hang inside the plugin fails a named
# test. A run that produces no result at all (the app never connects to the
# tool, which happens occasionally on fresh emulators) is stopped after a
# deadline and retried once. logcat is printed after every attempt.
set -uo pipefail

cd "$(dirname "$0")/../../example"

status=1
for attempt in 1 2; do
  echo "::group::Attempt $attempt"
  adb logcat -c || true
  timeout 900 flutter test integration_test
  status=$?
  echo "::endgroup::"

  echo "::group::logcat (attempt $attempt)"
  adb logcat -d -v time |
    grep -E "flutter|Flutter|ExtensionBridge|extension_bridge|AndroidRuntime|FATAL|ActivityTaskManager" |
    tail -n 400
  echo "::endgroup::"

  if [ "$status" -ne 124 ]; then
    break
  fi
  echo "::warning::flutter test produced no result within 15 minutes (attempt $attempt)."
done

exit "$status"
