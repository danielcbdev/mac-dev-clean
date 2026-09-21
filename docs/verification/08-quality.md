# Plan 08 quality verification

**Date:** 2026-09-21
**Branch:** `feat/localization-accessibility`
**Toolchain:** Xcode 27.0 (27A266a), macOS 27.0 (26A428), Apple M4, 24 GiB RAM

## Completed checks

```bash
MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
```

Exit status: 0. Package tests, the Debug application build, unsigned Release
build, cleanup-boundary check, localization fixtures and catalog check, static
policy fixtures and check, lint, and whitespace check all passed. UI tests were
not run because `MACDEVCLEAN_SKIP_UI_TESTS=1` was set for the known local runner
limitation.

```bash
swift test --package-path Packages/MacDevCleanCore --filter ScanPerformanceTests
```

Exit status: 0. Two tests passed in 1.080 seconds:

- deterministic cancellation after the first 256-entry batch of a lazily
  represented 100,000-entry Node tree, with no more than two batches read;
- an owned real-file fixture of 5,000 one-byte files, scanned in 1.079 seconds
  including fixture creation and cleanup.

The integrated package-test run included 70 passing `ScanningTests` in 1.298
seconds, including both performance regressions.

## Known omissions

- The direct UI command below built and launched on 2026-09-21, but its first
  five tests failed waiting for `scan.start`; the run was interrupted after
  104 seconds because every launch had the same inaccessible-window symptom.
  It exited 75 with `** TEST INTERRUPTED **`, not a pass.

  ```bash
  xcodebuild -workspace MacDevClean.xcworkspace -scheme MacDevClean \
    -destination 'platform=macOS' -derivedDataPath .build/xcode \
    -only-testing:MacDevCleanUITests test
  ```

- The normal Debug app did expose its accessibility tree during a limited
  manual inspection, but this does not reproduce the XCUITest launch context.
  Therefore no runtime p50/p95 navigation response, Cancel latency, peak
  memory, or complete 100,000-entry throughput was measured. Those are not
  represented as passing checks.
