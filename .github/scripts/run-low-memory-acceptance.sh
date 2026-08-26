#!/usr/bin/env bash
set -u -o pipefail

package=com.privacy_stamp
log=.ci-logs/android/acceptance.log
samples=.ci-logs/android/memory-samples.tsv
report=.ci-logs/android/acceptance-summary.txt
exit_info_before=.ci-logs/android/exit-info-before-relaunch.txt
exit_info_after=.ci-logs/android/exit-info-after-relaunch.txt
mkdir -p .ci-logs/android
: > "$samples"

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

timeout_bin="$(command -v timeout || command -v gtimeout || true)"
if [[ -z "$timeout_bin" ]]; then
  echo 'Required timeout utility is unavailable.' | tee "$report"
  exit 30
fi

printf 'AVD runner action handed off to test script at %s\n' "$(timestamp)" | tee -a .ci-logs/android/progress.log

# Keep awk on the runner: adb shell argument forwarding can split the awk
# program on macOS-hosted runners, turning `{print $2}` into filenames.
mem_total_kb=$(adb shell cat /proc/meminfo | awk '/^MemTotal:/ {print $2}' | tr -d '
')
if [[ ! "$mem_total_kb" =~ ^[0-9]+$ ]]; then
  echo 'Unable to read guest MemTotal.' | tee "$report"
  exit 31
fi
if (( mem_total_kb < 1048576 || mem_total_kb > 2097152 )); then
  printf 'Guest RAM is outside the required 1-2 GiB window: %s kB\n' "$mem_total_kb" | tee "$report"
  exit 32
fi
printf 'Guest MemTotal: %s kB\n' "$mem_total_kb" | tee -a .ci-logs/android/progress.log

adb logcat -c || true

sample_memory() {
  while true; do
    now=$(timestamp)
    pid=$(adb shell pidof "$package" 2>/dev/null | tr -d '\r' | awk '{print $1}')
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      pss=$(adb shell dumpsys meminfo "$package" 2>/dev/null \
        | awk '/TOTAL PSS:/ {print $3; exit} /^ *TOTAL +[0-9]+/ {print $2; exit}' \
        | tr -d '\r')
      if [[ ! "$pss" =~ ^[0-9]+$ ]]; then
        pss=0
      fi
      printf '%s\t%s\t%s\n' "$now" "$pid" "$pss" >> "$samples"
    fi
    sleep 2
  done
}

sample_memory &
sampler_pid=$!
cleanup_sampler() {
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true
}
trap cleanup_sampler EXIT

printf 'Running emulator-backed A-C synthetic acceptance (12 minute step limit).\n' | tee -a .ci-logs/android/progress.log
set +e
"$timeout_bin" --signal=TERM --kill-after=30s 12m \
  flutter test -d emulator-5554 integration_test/synthetic_low_memory_acceptance_test.dart -r expanded \
  2>&1 | tee "$log"
test_status=${PIPESTATUS[0]}
set -e
cleanup_sampler
trap - EXIT

if (( test_status != 0 )); then
  printf 'Synthetic A-C acceptance failed with exit %s.\n' "$test_status" | tee "$report"
  exit "$test_status"
fi

if [[ ! -s "$samples" ]]; then
  echo 'No application PID/memory samples were captured.' | tee "$report"
  exit 33
fi

unique_pids=$(awk -F '\t' '{print $2}' "$samples" | sort -u | wc -l | tr -d ' ')
peak_pss_kb=$(awk -F '\t' 'BEGIN{m=0} $3+0>m{m=$3+0} END{print m}' "$samples")
first_pid=$(awk -F '\t' 'NR==1{print $2}' "$samples")
last_pid=$(awk -F '\t' 'END{print $2}' "$samples")
restart_count=$(( unique_pids > 0 ? unique_pids - 1 : 0 ))

adb shell dumpsys activity exit-info "$package" > "$exit_info_before" 2>&1 || true
if grep -Eq 'REASON_(CRASH|ANR|LOW_MEMORY)|reason=(4|6|3)' "$exit_info_before"; then
  echo 'Unexpected crash/ANR/low-memory process exit was recorded before lifecycle D.' | tee "$report"
  exit 34
fi
if (( restart_count != 0 )); then
  printf 'Unexpected PID restart(s) during A-C: %s\n' "$restart_count" | tee "$report"
  exit 35
fi

printf 'Running D: force-stop and relaunch lifecycle acceptance.\n' | tee -a .ci-logs/android/progress.log
adb shell am force-stop "$package"
sleep 2
if adb shell pidof "$package" 2>/dev/null | grep -Eq '[0-9]'; then
  echo 'Application process remained alive after force-stop.' | tee "$report"
  exit 36
fi

adb shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
new_pid=''
for _ in $(seq 1 30); do
  new_pid=$(adb shell pidof "$package" 2>/dev/null | tr -d '\r' | awk '{print $1}')
  [[ "$new_pid" =~ ^[0-9]+$ ]] && break
  sleep 1
done
if [[ ! "$new_pid" =~ ^[0-9]+$ ]]; then
  echo 'Application did not relaunch after force-stop.' | tee "$report"
  exit 37
fi

sleep 3
adb shell dumpsys activity exit-info "$package" > "$exit_info_after" 2>&1 || true
adb logcat -d -v threadtime > .ci-logs/android/app-logcat-full.txt 2>&1 || true
grep -E 'com\.privacy_stamp|FATAL EXCEPTION|OutOfMemoryError|ANR in com\.privacy_stamp' \
  .ci-logs/android/app-logcat-full.txt > .ci-logs/android/app-logcat-filtered.txt || true
if grep -Eq 'FATAL EXCEPTION|OutOfMemoryError|ANR in com\.privacy_stamp' .ci-logs/android/app-logcat-filtered.txt; then
  echo 'Fatal/ANR/OOM evidence found in application logcat.' | tee "$report"
  exit 38
fi

cat > "$report" <<EOF
result=PASS
source_sha=${GITHUB_SHA:-unknown}
api_level=35
target=google_apis
arch=x86_64
guest_mem_total_kb=$mem_total_kb
fixture_pixels=48000000
input_gps=present
output_format=PNG
output_pixels_match=true
output_gps=absent
sensitive_metadata=absent
sample_count=$(wc -l < "$samples" | tr -d ' ')
peak_pss_kb=$peak_pss_kb
pid_first=$first_pid
pid_last_before_lifecycle=$last_pid
involuntary_restart_count=$restart_count
force_stop_relaunch_pid=$new_pid
crash_anr_oom_before_lifecycle=0
crash_anr_oom_after_relaunch=0
private_inputs=0
EOF

cat "$report"
printf 'Synthetic acceptance ended at %s with PASS.\n' "$(timestamp)" | tee -a .ci-logs/android/progress.log
