#!/usr/bin/env bash
set -euo pipefail

# android-emulator-runner creates the AVD before invoking this hook. On some
# macOS runners, the ram-size input is not reflected in the generated config,
# so enforce the contract immediately before launch.
config_file="$(find "${ANDROID_AVD_HOME:?}" -maxdepth 2 -name config.ini -print -quit)"
if [[ -z "$config_file" || ! -f "$config_file" ]]; then
  printf 'Unable to locate generated AVD config under %s\n' "$ANDROID_AVD_HOME" >&2
  exit 1
fi

set_config() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$config_file"; then
    sed -i.bak "s/^${key}=.*/${key}=${value}/" "$config_file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$config_file"
  fi
}

set_config hw.ramSize 1536
set_config hw.heapSize 256
printf 'Low-memory AVD config: %s\n' "$config_file"
grep -E '^(hw\.ramSize|hw\.heapSize)=' "$config_file"
