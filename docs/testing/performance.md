# Scan performance evidence

## Current evidence

On 2026-09-21, the focused command below passed on Apple M4 hardware with
24 GiB RAM, macOS 27.0 (26A428) and Xcode 27.0 (27A266a):

```bash
swift test --package-path Packages/MacDevCleanCore --filter ScanPerformanceTests
```

It ran two tests in 1.080 seconds:

- `SyntheticFileSystem(count: 100_000)` represents a valid Node project using
  lazily generated metadata and no file contents. After its first 256-entry
  payload batch, the test cancels the real `DeveloperScanner` through
  `PerformanceHarness`; the blocked I/O is released and the observed payload
  reads stay at or below 512 entries.
- An owned `FixtureTree` with 5,000 one-byte files was created and scanned in
  1.079 seconds. That duration includes fixture creation and cleanup, so it is
  evidence of regression coverage, not a scanner-throughput promise.

The test suite deliberately does not assert wall-clock thresholds, because
those are not portable across CI hardware. It also does not allocate a
100,000-file fixture on disk.

## Not yet measured

No peak-memory sampling, full 100,000-entry completion throughput,
cancellation-latency distribution, or p50/p95 UI response samples are recorded.
The local XCUITest runner cannot expose the application window to the
accessibility interface, so navigation and Cancel responsiveness during a live
100,000-entry scan require a working logged-in UI environment. These are
remaining plan 08 measurements, not passed checks.
