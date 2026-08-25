#!/usr/bin/env bash
set -u -o pipefail

log=.ci-logs/android/acceptance.log
printf 'AVD runner action handed off to test script at %s\n' "$(date --iso-8601=seconds)" | tee -a .ci-logs/android/progress.log
printf 'Waiting for emulator-backed synthetic acceptance (10 minute step limit).\n' | tee -a .ci-logs/android/progress.log

set +e
timeout --signal=TERM --kill-after=30s 10m \
  flutter test -d emulator-5554 integration_test/synthetic_low_memory_acceptance_test.dart -r expanded \
  2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

printf 'Synthetic acceptance ended at %s with exit %s.\n' \
  "$(date --iso-8601=seconds)" "$status" | tee -a .ci-logs/android/progress.log
exit "$status"
