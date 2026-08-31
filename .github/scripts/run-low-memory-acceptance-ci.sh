#!/usr/bin/env bash
set -euo pipefail

# CI-only transport shim for the 1536 MiB API 35 AVD.
# The acceptance assertions and the 12-minute A-C wall clock remain in
# run-low-memory-acceptance.sh unchanged. This wrapper only gives Android's
# post-boot services time to settle and makes APK installation less stressful
# on the low-memory guest.

real_adb="$(command -v adb)"
real_timeout="$(command -v gtimeout || command -v timeout)"
shim_dir="$PWD/.ci-low-memory-bin"
mkdir -p "$shim_dir"

cat > "$shim_dir/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${REAL_ADB:?REAL_ADB is required}"

if [[ "${1:-}" == "install" ]]; then
  shift
  exec "$REAL_ADB" install --no-streaming "$@"
fi

exec "$REAL_ADB" "$@"
EOF

cat > "$shim_dir/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${REAL_TIMEOUT:?REAL_TIMEOUT is required}"

args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" != "60s" ]]; then
    continue
  fi
  for ((j = i + 1; j + 1 < ${#args[@]}; j++)); do
    if [[ "${args[$j]}" == "adb" && "${args[$((j + 1))]}" == "install" ]]; then
      args[$i]="180s"
      break 2
    fi
  done
done

exec "$REAL_TIMEOUT" "${args[@]}"
EOF

chmod +x "$shim_dir/adb" "$shim_dir/timeout"
export REAL_ADB="$real_adb"
export REAL_TIMEOUT="$real_timeout"
export PATH="$shim_dir:$PATH"

printf 'Low-memory AVD boot completed; allowing post-boot services to settle for 90 seconds.\n'
sleep 90

exec bash .github/scripts/run-low-memory-acceptance.sh
