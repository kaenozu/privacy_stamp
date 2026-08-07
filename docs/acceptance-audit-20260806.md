# Privacy Stamp acceptance audit — 2026-08-06

This audit records the evidence available from the exact `origin/main` commit
`3bf624c8a95aec10556147dd3b4fc6e44feba219`. It does not close the remaining
human acceptance or release gates.

## Scope and decision

- Issue #14 automation work is already merged into `main`; no runner rewrite is
  required in this audit.
- The runner is ready to start Issue #12's final private-data acceptance: it
  requires a GPS-bearing JPEG with at least 40 million pixels, samples process
  memory during export, fails closed on PID/process/runtime evidence problems,
  and keeps human assertions separate.
- Issue #12 remains `BLOCKER`: the private GPS JPEG, low-memory AVD, Android UI
  interaction, and local output inspection were not run here.
- Issue #4 remains `BLOCKER`: the production application ID, formal signing,
  AAB, Play distribution, and release approval were not changed or verified.

## Evidence executed on this branch

| Check | Result | Evidence |
| --- | --- | --- |
| PowerShell runner syntax parse | PASS | `Invoke-PrivacyStampHighResolutionAcceptance.ps1` parsed with `Set-StrictMode` |
| Synthetic acceptance helper suite | PASS | `Test-PrivacyStampAcceptanceEvidence.ps1` |
| Dart formatting | PASS | 23 files inspected, 0 changed |
| Flutter analyzer | PASS | `flutter analyze --fatal-infos`; no issues |
| Flutter tests | PASS | 59 tests passed, 0 failed, 0 skipped |
| Git diff check | PASS | No whitespace errors after this document was added |

The Flutter dependency resolver reported eight newer packages that are
incompatible with the current constraints. No dependency update was made.

## Runner contract re-audit

The merged runner and helper tests cover the following fail-closed boundaries:

- final input contract is GPS-bearing JPEG and at least 40MP;
- zero or multiple output candidates are not accepted;
- baseline device paths stay in memory and are not written to the report;
- at least two memory samples and a stable monitored PID are required;
- PID changes, missing samples, process death, FATAL, OOM, ANR, and low-memory
  kill evidence block acceptance;
- output pixel count and sensitive PNG metadata are inspected;
- picker cancel, orientation, mask, back/discard, relaunch, and temporary-file
  checks require explicit operator confirmations.

The report contract is limited to privacy-safe facts. Private paths, filenames,
image bytes, GPS values, raw logcat, and confirmation tokens must not be copied
to GitHub, CI artifacts, commits, or pull requests.

## Not run / residual risk

- **BLOCKER — private runtime:** no private GPS-bearing 48MP JPEG was accessed;
  no image was copied into the repository or evidence directory.
- **BLOCKER — device acceptance:** no low-memory AVD was created, wiped, or
  driven; no picker, mask, orientation, export, lifecycle, or output inspection
  was performed.
- **BLOCKER — production release:** no production ID, keystore, signing secret,
  AAB, Play Console operation, deployment, or permission change was performed.
- **NOT RUN — build artifacts:** debug/release APK and Web builds were not
  started in this audit because shared Android/Gradle resources were already in
  use and the static/synthetic gates were sufficient for this documentation
  slice.
- **RESIDUAL RISK:** static and synthetic evidence cannot establish real-device
  OOM/ANR behavior, visual mask correctness, orientation correctness, or
  absence of orphan files in a real user flow.

## Next ordered action

On an operator-controlled clean low-memory AVD, run the documented runner with a
repository-external GPS-bearing JPEG and complete every confirmation token only
after the corresponding UI action is observed. Record only the resulting
privacy-safe `PASS` or `BLOCKER` summary; keep Issue #12 open until all PASS
criteria are evidenced.

## Issue #12 local Android acceptance attempt — 2026-08-07

### Baseline

- Exact main SHA: `3bf624c8a95aec10556147dd3b4fc6e44feba219`
- Acceptance branch SHA: `a9ed64935268c5c5ace23290b83a96fabf5fbfeb`
- Runner SHA: `a9ed64935268c5c5ace23290b83a96fabf5fbfeb`
- Android API: 35
- AVD RAM: 1536 MB (configured; AVD not created because the run was blocked)
- Flutter: 3.44.0 (stable)
- Dart: 3.12.0
- Java: OpenJDK 17.0.19 (Temurin)

### Input contract

- Format: JPEG (required contract)
- Pixel dimensions: not evaluated (no private input available)
- Pixel count: not evaluated
- GPS present before export: not evaluated
- Private path recorded: false

### Output contract

- Format: not evaluated
- Pixel dimensions: not evaluated
- Pixel count matches input: not evaluated
- GPS present after export: not evaluated
- Sensitive metadata present: not evaluated
- Output candidates: not evaluated
- Source overwritten: not evaluated

### Runtime evidence

- Memory samples: not evaluated
- Peak total PSS: not evaluated
- Peak total RSS: not evaluated
- Peak Java heap: not evaluated
- Peak native heap: not evaluated
- Process restart count: not evaluated
- Process alive after export: not evaluated
- OOM: not evaluated
- ANR: not evaluated
- Fatal exception: not evaluated
- Fatal signal: not evaluated
- Process death: not evaluated
- Low-memory kill: not evaluated

### Human UI assertions

- Orientation: not evaluated
- Pan/zoom: not evaluated
- Center mask: not evaluated
- Edge mask: not evaluated
- Mask move/resize: not evaluated
- Visible mask burn-in: not evaluated
- Picker cancel: not evaluated
- Back/discard: not evaluated
- Force-stop/relaunch: not evaluated
- Stale callback: not evaluated
- Orphan temporary files: not evaluated

### Quality gates (executed before the private-input gate)

- PowerShell syntax: PASS (all three runner files parsed with `Set-StrictMode`)
- Synthetic helper tests: PASS (`Test-PrivacyStampAcceptanceEvidence.ps1`)
- Dart format: PASS (23 files inspected, 0 changed)
- Flutter analyze: PASS (`flutter analyze --fatal-infos`, no issues)
- Flutter tests: PASS (59 passed, 0 failed, 0 skipped)
- Android debug build: NOT RUN (blocked at private-input gate)
- Git diff check: PASS (no whitespace errors)

### Decision

- **BLOCKER: valid private input unavailable** — the operator reported no
  repository-external GPS-bearing 48MP-or-larger JPEG was available for this
  attempt. No image was copied into the repository, and no AVD was created or
  driven.
- Residual risks: all Issue #12 runtime, UI, lifecycle, and output criteria
  remain unevidenced; the low-memory AVD and Android UI interaction were not
  exercised in this attempt.
