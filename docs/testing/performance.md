# Scan performance evidence

## Current evidence

The existing scanner cancellation regression test runs against a controlled
fixture and completed in the 2026-09-21 full verification. It proves that a
cancelled scan stops enumeration; it is not a 100,000-entry stress benchmark.

## Not yet measured

The plan 08 synthetic `FileSystemClient` and its 100,000-entry cancellation
test have not been implemented yet. Consequently, no throughput, p50/p95 UI
response, cancellation-latency, or peak-memory values are recorded here.
Those figures must be gathered from the deterministic synthetic fixture and a
logged-in UI session before plan 08 can be completed.
