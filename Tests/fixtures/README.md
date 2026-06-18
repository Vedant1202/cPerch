# Test fixtures

Phase-1 readers (RegistryReader, TranscriptReader) and SessionMerger unit-test against
captured `~/.claude` JSON shapes.

- **Committed (safe):** small **synthetic** samples like `sample-registry.json` — made-up data,
  no real paths or message content. Safe to version.
- **Local (gitignored):** run [`../../scripts/capture-fixtures.sh`](../../scripts/capture-fixtures.sh)
  to snapshot **sanitized** copies of your real sessions into `local/` (home paths redacted,
  message text stripped). Never commit `local/`.

```bash
./scripts/capture-fixtures.sh   # → Tests/fixtures/local/{registry,transcripts}/
```
