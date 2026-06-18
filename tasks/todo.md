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

## Phase 2 — SessionStore ⏸ (deps: P1-A,B,C,G)
- [ ] **P2** Real wiring (A+B+C+G) + FSEvents/poll refresh + concluded retention + aggregate state + `--print` debug mode
- [ ] 🔒 **Checkpoint** — core emits correct [Session] headless on the live machine

## Phase 3 — App integration ⏸ (deps: P2 + P1-D,E,F)
- [ ] **P3** Real store → app · wire Notifier + Jumper · build.sh → CPerch.app (LSUIElement + AppleEvents usage + icon)
- [ ] 🔒 **Checkpoint** — app runs in the bar with real sessions

## Phase 4 — Hardening + daily-driver ⏸ (deps: P3)
- [ ] **P4a** S2 dedup validation on live multi-session (unregistered terminal + cwd collision)
- [ ] **P4b** S3 debounce/coalesce tuning (no flapping)
- [ ] **P4c** Manual UI checklist + footprint check · fold S1 if positive
- [ ] 🔒 **v0 sign-off** — all 8 SPEC acceptance criteria met
```
