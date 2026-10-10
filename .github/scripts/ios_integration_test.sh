#!/usr/bin/env bash
# Runs the example's integration tests on the booted iOS simulator $1.
#
# Every test has its own timeout, so a hang inside the plugin fails a named
# test. A run that produces no result at all (the app never connects to the
# tool, which happens occasionally on fresh simulators) is stopped after a
# deadline and retried once. The app's log is printed after every attempt.
set -uo pipefail

udid="$1"
cd "$(dirname "$0")/../../example"

# macOS has no `timeout`; perl's alarm sends SIGALRM (exit status 142).
with_deadline() {
  perl -e 'alarm shift @ARGV; exec @ARGV or die "exec: $!"' "$@"
}

status=1
for attempt in 1 2; do
  log_file="$RUNNER_TEMP/simulator-$attempt.log"
  xcrun simctl spawn "$udid" log stream --style compact \
    --predicate 'process == "Runner"' > "$log_file" 2>&1 &
  log_pid=$!

  echo "::group::Attempt $attempt"
  with_deadline 900 flutter test integration_test -d "$udid"
  status=$?
  echo "::endgroup::"

  kill "$log_pid" 2> /dev/null || true
  echo "::group::Simulator log (attempt $attempt)"
  grep -E "flutter|Flutter|extension_bridge|ExtensionBridge|error|Error|crash" "$log_file" | tail -n 400
  echo "::endgroup::"

  if [ "$status" -ne 142 ]; then
    break
  fi
  echo "::warning::flutter test produced no result within 15 minutes (attempt $attempt)."
done

exit "$status"
