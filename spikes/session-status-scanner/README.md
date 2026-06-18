# Archived spike — session-status scanner

Throwaway probe (2026-06-17/18) that validated the cPerch status heuristic against real
`~/.claude` data and proved the CLT + SwiftPM toolchain end-to-end. **Not part of the v0 build** —
kept for reference; the validated logic graduates into `CPerchCore` proper.

What it proved:
- Claude's registry status enum (`busy`/`shell`/`idle`/`waiting`) + `kill -0` liveness + transcript
  fallback correctly classify running / needs-input / concluded.
- `swift build` works on Command Line Tools alone (no full Xcode).

Run it (from the `cPerch/` dir):

```bash
swift run --package-path spikes/session-status-scanner CPerchScan
```

See [`../../docs/ideas/cperch.md`](../../docs/ideas/cperch.md) for the refined base camp.
