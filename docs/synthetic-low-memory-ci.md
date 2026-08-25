# Synthetic low-memory CI acceptance

Issue #17 uses a deterministic repository fixture rather than private photos for release-gating Android acceptance.

The CI job runs on GitHub's standard Intel macOS runner because the previously attempted Ubuntu hosted runner exposed no usable KVM and left the API 35 x86_64 emulator offline until boot timeout. The acceptance contract itself is unchanged:

- Android API 35, Google APIs, x86_64;
- guest RAM must measure between 1 and 2 GiB (configured at 1536 MiB);
- deterministic 48 MP JPEG with synthetic GPS metadata;
- select, display, pan, zoom, manual mask, and PNG export;
- picker cancel, discard/pause/resume, and force-stop/relaunch;
- output pixel count equals input, GPS absent, sensitive PNG metadata absent;
- PID and peak PSS recorded, with zero involuntary restart, crash, ANR, OOM, or low-memory kill.

The pull-request run proves the candidate branch and must pass on the exact PR head. Issue #17 is not complete until the same workflow passes again after merge on the then-current clean `main`, so the evidence Source SHA is the accepted main SHA.
