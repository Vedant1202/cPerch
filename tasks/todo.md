# cPerch v0 — Task List

See [plan.md](plan.md) for full detail (acceptance + verify per task).
Legend: ⏸ sequential · ⇉ parallel (own agent) · 🔒 checkpoint · (deps)

## Phase 0 — Scaffold + Contracts ⏸ — blocks everything
- [x] **P0** Package.swift (CPerchCore + CPerchApp + tests) · Models + record types + `SessionProviding` · stub `SessionStore` · minimal menu-bar dot (walking skeleton) · fixtures + capture script · swift-testing via `scripts/test.sh`
- [x] 🔒 **Freeze contracts** — approved; Phase 1 fanned out to 7 parallel agents

## Phase 1 — Parallel fan-out ⇉ (deps: P0) — done via 7 parallel agents
- [x] **P1-A** ProcessScanner + tests — CPerchCore *(injectable process source)* — 8 tests
- [x] **P1-B** RegistryReader + tests — CPerchCore — 4 tests
- [x] **P1-C** TranscriptReader + tests — CPerchCore — 5 tests
- [x] **P1-G** SessionMerger (dedup/merge) + tests — CPerchCore — 9 tests
- [x] **P1-D** Roster + MenuBar UI (aggregate dot, design tokens) vs stub — CPerchApp
- [x] **P1-E** Jumper — terminal Apple Events + desktop activate, never duplicate — CPerchApp
- [x] **P1-F** Notifier — UNUserNotificationCenter, coalesce, DND-aware — CPerchApp
- [x] **S1** claude:// route spike — `chat`/`project` open routes exist (`claude://…/chat/<uuid>`, UUID-gated → else `/recents`); exact-chat desktop jump viable at zero permission cost, pending sessionId↔conversationId check (P3/P4). v0 keeps activate-app baseline.
- [x] 🔒 **Checkpoint** — integrated build green · 30 CPerchCore tests green · UI/jump/notify built (manual visual verify deferred to P3/P4)

## Phase 2 — SessionStore ✓ (deps: P1-A,B,C,G)
- [x] **P2** Real wiring (A+B+C+G) + FSEvents/poll refresh + concluded retention (3h/cap10) + `blockedSince` tracking + terminal-app resolution + `--print` debug — 9 helper tests
- [x] 🔒 **Checkpoint** — `--print` on live machine: this session shows 🔵 running (correct cwd/host/preview); concluded retention applied; 39 tests green

## Phase 3 — App integration ✓ (deps: P2 + P1-D,E,F)
- [x] **P3** Real SessionStore → menu bar · wired Jumper + Notifier · build.sh → ad-hoc-signed CPerch.app. Fixed: UNUserNotificationCenter needs a bundle id (Notifier guards + build.sh signs).
- [x] 🔒 **Checkpoint** — CPerch.app launches clean (pid alive, real data, no crash); dot + roster live

## Phase 4 — Hardening + daily-driver ⏳ (deps: P3)
- [x] **P4a** Dedup validated headless (`--print` clean — no dupes/ghosts); live multi-session + cwd-collision = checklist item
- [x] **P4b** Debounce/coalesce values set (FSEvents 0.5s · poll 3s · stalled 120s · coalesced banners); live flap-tuning = checklist item
- [x] **P4c** Footprint ✓ (~49 MB / ~1%); manual checklist written ([docs/v0-acceptance-checklist.md](../docs/v0-acceptance-checklist.md)); S1 deep-link mapping resolved (cliSessionId↔desktop sessionId — fast-follow)
- [x] 🔒 **v0 sign-off** — maintainer approved after dry run; automated checks green (39 tests · build · --print · footprint). **v0 complete.**
```
