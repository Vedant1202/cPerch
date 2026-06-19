## Summary

<!-- What does this change, and why? Keep it focused. -->

## Related issue

<!-- e.g. Closes #123 -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor / cleanup
- [ ] Docs / build / CI

## How was this tested?

- [ ] `swift build` is clean (no new warnings)
- [ ] `./scripts/test.sh` passes (note the count: ___)
- [ ] Built and ran `dist/CPerch.app`
- [ ] Verified on-device where relevant (roster / jump / notifications / accessibility)

## Checklist

- [ ] New logic in `CPerchCore` has unit tests, and `CPerchCore` stays Foundation-only
- [ ] No network calls; any `~/.claude` access stays **read-only**
- [ ] No new TCC permission (no Accessibility, no Input Monitoring)
- [ ] Docs updated if behavior changed (README / `docs/`)

## Screenshots

<!-- For UI changes, a before/after helps. -->
