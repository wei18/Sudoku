# 2026-06-20 → 06-24 — GameCenter pipeline (#579 umbrella) + test-infra & L10n hardening

Session id: `12634fe7-d639-4f8e-b5c2-4c62daa6f31f`
Mode: AI Collaboration Mode (Leader/Developer) + dual-model CR; multi-day, multi-thread.

## Goal
Started as "fix #552 (PersonalRecord best-time multi-device clobber)"; investigation cascaded into discovering the entire Sudoku completion→Telemetry→GameCenter pipeline was unwired, so the real scope became the **#579 umbrella** (scores + achievements actually working), followed by a run of clean headless follow-ups (snapshot gate, upkeep audit, a11y, L10n) and an idb cross-app UX audit.

## Decisions (user-confirmed / Leader-ACCEPTed)
1. **Reframe #552 before coding.** Tracing the call chain showed PersonalRecord's *write* path was dead code, the achievement evaluator (`GameCenterSink`) was never wired into the live `Telemetry` sinks, and `LiveGameCenterClient`'s GK terminal was a stub. So #552 was unreachable; the fix had to start upstream. → filed umbrella **#579** + sub-items #578/#552/#580.
2. **Wire Sudoku GC via the sink pattern** (the existing-but-unwired `GameCenterSink`/`AchievementEvaluator`), not the VM-direct-submit pattern MS/2048 use — it's the only path supporting achievements, and it's a wiring gap not missing logic. Convergence of MS/2048 deferred.
3. **Ship the umbrella in slices:** phase 1+2 (#581, pipeline wiring via a late-binding non-blocking `DeferredSink`) → #578 (#583, PersonalRecord write) → #552 (#584, scoped etag optimistic concurrency) → #580 (#582, GK terminal). User chose: merge plumbing as it lands; #582 is device-gated (merged, awaiting on-device sandbox-GC verify).
4. **Snapshot gate (#487/#517 → #586):** content suites use strict `.image`, AA-heavy board suites keep `.tolerantImage` (mirror Sudoku, which was already strict). Catches new labels; closes the loose-tolerance gap.
5. **#475 upkeep: triage first, then fix the clean doc-drift cluster (#588);** defer screenshots → #236, file the real correctness-adjacent finding (#587).
6. **#587:** the Completion state-snapshot variants are vestigial (SDD-003 Epic 4 hardcoded `state: .hidden`, removing the leaderboard zone) → remove them, keep the meaningful guards.
7. **#473:** given board cells become non-interactive `.isStaticText` (no Button wrapper) so VoiceOver stops announcing dead buttons.
8. **#516 copy slice only (#591):** localize the Practice hint; the offline-save copy needs *conditional* logic (deferred).
9. **#594:** add a `scan:l10n` shared-code **dotted-key** gate (zero false positives) + fix the Tiles2048 leave-game dialog it revealed; **#597** guard tuist `os=["macos"]` to unblock all Linux CI.

## Rejected alternatives
- **Accessibility-tree text extraction** for a non-pixel snapshot gate — empty on both bare and windowed `NSHostingView` headlessly (SwiftUI builds AX lazily). Dead end; chose strict pixels instead.
- **Implementing #552's optimistic concurrency against the dead write path** — defensive code for an unreachable scenario; rejected until the write was wired.
- **Static `NSKeyedUnarchiver.unarchivedObject(ofClass:)`** for the #552 etag rehydrate — can't decode an `encodeSystemFields` partial archive → silently drops the etag on real CloudKit. Reverted to `fc557b8`'s instance-unarchiver + `CKRecord(coder:)`.
- **Gating English-phrase shared keys** in #594 — app-conditional false positives; scoped to dotted keys, filed #598 for the rest.

## Hand-offs (sub-agents)
- Developers (sonnet, worktree): phase 1+2 wiring, #578, #552, #475 doc cluster. One #552 Developer dropped connection mid-task → resumed via SendMessage to finish.
- Dual-Sonnet CR on every CR-mandatory path (Persistence/AppComposition) — caught 4 real bugs the author/first-reviewer missed: completion-path blocking, sink read-before-write off-by-one, the GK terminal stub, and the #552 unarchiver defect.
- idb sim audit (Leader-driven): all three apps; found the Tiles2048 raw-key bug → #593/#594.

## Open questions / deferred
- **#582** GK terminal — on-device sandbox-GC smoke (user-owned) before closing #579.
- **#595** MS "N mines" L10n gap; **#598** English-phrase shared-key gaps (fold into #501 2048 ship / MS L10n pass).
- #516 offline-save conditional copy; #510 XCUITest E2E; #286 CaptureGuardKit (proposal).

## Next session
Re-read all `meetings/`, `memory/`, and session logs for this project, then audit and update (add / delete / change) the project's `.claude/skills/` — keep them consistent with what actually shipped this session (GC pipeline now wired, snapshot gate strategy, the new `scan:l10n` shared-key gate, the mise macOS-tool guard).
