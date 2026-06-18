# cPerch — decision log

A running record of the significant decisions and findings, with the *why* — so future sessions and
agents don't re-derive them. ADR-lite; newest at the bottom. Append as you go.

## D1 — Build fresh, not fork so-agentbar · 2026-06-17
**Decision:** Build cPerch from scratch rather than fork/extend [so-agentbar](https://github.com/sotthang/so-agentbar).
**Why:** The goal is a focused, minimal, beautifully Claude-native tool we fully own. so-agentbar is
mature but feature-sprawling (usage tracking, Codex, pixel pets, system monitor). ~70% of the work
overlaps, but the durable edge we want — multi-source reliability + a *true* window-focus — is
additive and worth owning cleanly. Trade-off accepted: we re-earn source breadth over time.

## D2 — Detection: multi-source, not transcript-only · 2026-06-17
**Decision:** Detect via process-scan + registry (`~/.claude/sessions/<pid>.json` `status` enum) +
transcript, merged — not so-agentbar's single transcript-only signal.
**Why:** so-agentbar infers everything from the `.jsonl` (timing + permission-mode heuristics): it
can't see crashes (only a 5-min idle timeout), suppressed transcripts, or give exact needs-input. Our
layers add ground truth — `kill -0` liveness, Claude's own `busy/shell/idle/waiting` status — with the
transcript as fallback. Cost: dedup/merge complexity (so-agentbar has none), mitigated by a frozen
`sessionId` spine.
**Evidence (dev machine):** registry saw 2 sessions; the transcript layer surfaced 10 of 12; the
desktop session had no `status` field (version skew) → transcript fallback genuinely needed.

## D3 — "Calm Conscience" + single aggregate dot · 2026-06-18
**Decision:** Silent by default; one Claude-colored aggregate dot at rest (most-urgent-wins:
orange needs-input / blue running / dim idle); surface only when it's your move. Not a dashboard.
**Why:** The job isn't monitoring — it's *not having to*.

## D4 — Notifications: lean on macOS; banner only on needs-input · 2026-06-18
**Decision:** Post via standard `UNUserNotificationCenter` (macOS handles Focus/DND for free); banner
ONLY on a →needs-input transition; new-agent/concluded silent (opt-in toggle); coalesce simultaneous.
**Why:** DND on → the always-visible dot is the badge; DND off → a small banner. Banners for every
agent spin-up = noise. Calm.

## D5 — Hooks deferred to opt-in "precise mode", not v0 · 2026-06-18
**Decision:** No hooks in v0; detection stays zero-config and read-only. Hooks become a later,
transparent, opt-in toggle.
**Why:** Hooks edit the user's *global* `~/.claude/settings.json`, run code in every session, and can
block Claude (`Stop` hook) — a much bigger trust ask that breaks the "read-only, can't touch your
sessions" soul. OS privacy is fine; the cost is *trust*, not permissions.

## D6 — Permissions: zero-TCC detection; tiered jump; never the heavy ones · 2026-06-18
**Decision:** Detection needs NO TCC permission (`~/.claude` is a home dotfolder, not a protected
location; app is non-sandboxed). Jump is tiered: Tier 0 activate-app (none) → Tier 1 Apple Events /
Automation (per-app prompt, terminals) → **avoid** Tier 2 Accessibility (blanket "control your
computer"). No network, no Keychain in v0.
**Why:** Identity = trust through restraint. Accessibility is the only "overkill" grant — avoided.
Usage/quota tracking is out because it needs Keychain + network + an unofficial OAuth API (so-agentbar's
lane). **Constraint:** must stay non-sandboxed (App Store sandbox blocks `~/.claude` reads + window control).

## D7 — Native Swift, CLT + SwiftPM, no full Xcode · 2026-06-17
**Decision:** AppKit `NSStatusItem` + SwiftUI; Command Line Tools + SwiftPM; ship via GitHub Releases
(unsigned zip first, notarize later). Two targets: `CPerchCore` (pure) + `CPerchApp`.
**Why:** Leanest path for a macOS-only utility; the reference app is native Swift too. CLT confirmed
sufficient to compile, sign, and notarize — full Xcode (~7GB) not required.

## D8 — Testing: swift-testing via `scripts/test.sh`; tools 6.0 / language v5 · 2026-06-18
**Decision:** Unit-test `CPerchCore` with **swift-testing** (`import Testing`) run via
`./scripts/test.sh`; manual UI verification for `CPerchApp`. Package is swift-tools-version 6.0 with
language mode pinned to v5.
**Why:** XCTest ships only with full Xcode — **absent under the CLT**. swift-testing's
`Testing.framework` *is* in the CLT but outside default search/runtime paths, so the script points
`-F`/`-rpath` at it (paths derived from `xcode-select -p`, so it's portable). tools-version 6.0 is
required for swift-testing's SPM integration; language v5 avoids strict-concurrency churn in the AppKit
code for now (can adopt Swift 6 mode later).

## D9 — Contract-first parallel build · 2026-06-18
**Decision:** Freeze the shared contracts (Models, source records, `SessionProviding`) in P0, then fan
Phase 1 out to parallel agents owning disjoint files.
**Why:** A menu-bar app shares one core; the only safe way to parallelize is to lock the seams first.
**Validated:** 7 agents ran blind in isolated clones with zero conflicts; integrated build + 30 tests
green. (Worktree isolation needs the *session* at the git root — ours is a subdir — so clean `git clone`s
were used as manual isolation, reconverged by copying disjoint files + one integrated build.)

## D10 — claude:// exact-chat jump: viable, fast-follow (S1) · 2026-06-18
**Decision:** v0 desktop jump = activate-the-app; exact-chat deep-link is a fast-follow.
**Why:** The `claude://` scheme has `OpenConversation`/`chat` + `OpenProject`/`project` routes
(`claude://…/chat/<uuid>`, UUID-gated → else `/recents`) at zero permission cost. But it takes a
*conversationId* — unconfirmed whether that equals the Code `sessionId` we hold. Verify live in P3/P4
before relying on it; the `/recents` fallback makes trying it harmless.

## D11 — Run as a signed bundle; Notifier guards the bare-binary case · 2026-06-18
**Decision:** cPerch runs as `CPerch.app` (assembled + **ad-hoc code-signed** by `build.sh`), not a
bare `swift run` binary. `Notifier` guards on a bundle id so a bare binary still launches (with
notifications disabled); `--print` and dev runs work unsigned.
**Why:** `UNUserNotificationCenter.current()` throws an *uncatchable* `NSException` unless the process
is a real bundle with a `CFBundleIdentifier` (and is code-signed). Caught at P3 launch — the bare
`.build/debug/CPerchApp` crashed in `Notifier.init`. Fix: `build.sh` ad-hoc signs the bundle, and the
guard (`Bundle.main.bundleIdentifier != nil`) keeps bare `swift run` / `--print` crash-free.
