# 2026-06-09 — GameAudio P1/P2 · Minesweeper TestFlight QA fixes · Ops skills

Session id: `40a126ae-7790-487f-82eb-d68b74043bd7`
Mode: AI Collaboration Mode (Leader/Developer + background sub-agents)

## Goal
Continue v2.5 work: clean up dead nav (#427), build the shared game-audio system (#330), run the first real local→TestFlight uploads, and fix the Minesweeper TestFlight QA bugs the user found — keeping Sudoku/Minesweeper parity throughout.

## Decisions
1. **#427 / NewGameView** — deleted the orphaned `.newGame` AppRoute case **and** retired `NewGameView` itself (verified fully unreachable: root is `MinesweeperHomeView`, Practice hub builds `.board` directly). (#428)
2. **GameAudio (#330) shape** — new independent package `GameAudioKit` (engine: `GameAudio` + `GameAudioTesting`); settings UI/model live in `SettingsKit` (mirrors reminders). `AudioEvent` is game-agnostic (`soundKey`+`haptic`+`channel`); per-app event constants live with each app.
3. **GameAudio behaviour** — iOS `AVAudioSession.ambient` + `.mixWithOthers`; **BGM default ON but auto-pauses when `isOtherAudioPlaying`** (never hijacks the user's audio); **haptics only on meaningful events** (complete/error/win, flood/explosion/win) never on taps, with a Settings toggle. **Master mute = audio-only; haptics governed independently by `hapticsEnabled`.**
4. **Audio assets** — no text-to-audio model available; use **procedural numpy synthesis** → WAV → `afconvert` (`build/audio-demos/gen_palettes.py`, gitignored). Default palette **zen-wood** for both apps (user dropped the "audition 6 sets" idea).
5. **Phasing** — P1 seam (#429) → P2-foundation: order-preserving NSLock fakes + haptic/mute contract + settings polish + zh-Hant "Sound"→聲音 (#431) → P2 per-app gameplay triggers (#439 MS, #440 Sudoku) → P3 zen-wood assets (#444; BGM re-encoded to AAC/caf 711KB→51KB, SFX kept WAV). **Audio now audible; #330 CLOSED.**
6. **Ops skills (#430)** — every ops mise-task now has a corresponding skill: 4 new (`local-testflight-upload`, `cloudkit-schema-ops`, `appstore-screenshot-pipeline`, `acknowledgements-generation`) + a keystone **`mise-task-operations`** index. Rule adopted: **check `mise tasks ls` + `.claude/skills/` before grepping the repo for an ops pipeline.**
7. **TestFlight** — first real local upload via `mise run tf:upload`; both apps uploaded (iOS). User owns the upload (gated `--i-am-sure`); approved running it. **No re-upload until the user requests** (will ask after a progress point).
8. **#432 IAP "product not found"** — fixed on **both** apps: MS IAP had 0 localizations, Sudoku had 2 of 7; ran live `ASCRegister iap apply` (user-approved) to create all 7 each. Two ASCRegister bugs fixed en route: es description >55 chars (ASC IAP limit) and **IAP localizations need bare `th`/`ko`** (not GC's `th-TH`/`ko-KR`) → added `Config.ascIAPLocaleCode`. (#436, #438)
9. **#433 acks empty** — `tf:upload` now runs `gen:acknowledgements` in the right order (install→generate→archive); also fixed a latent `license_plist` `outputPath` bug that broke acks for **both** apps; added `Minesweeper.storekit` + scheme wiring (Sudoku already had one). (#437)
10. **#434 pause/resume** — MS gained parity; extracted a **shared `GameShellUI.PauseOverlayView`** (Sudoku refactored onto it — verified lossless, no Sudoku snapshot drift), per the no-duplication rule. (#435)
11. **Real shared banner (#441)** — the real `GADBannerView` was *not* missing on iOS (only the macOS path threw); the gap was the view-crossing seam. Added `BannerViewProviding.bannerView(for:) -> AnyView?` (SwiftUI type, SDK confined to AdsAdMob), one shared `MonetizationUI.BannerSlotView` for both apps, and `#if DEBUG` test-IDs / Release prod-IDs (user-approved). (#443)

## Rejected alternatives
- **Audition 6 audio palettes (2 apps × 3)** — user chose "先預設一組" → zen-wood default; skip the audition gate.
- **AI text-to-audio generation** — no such tool in this environment; used procedural numpy synthesis instead (SFX synthesise well; BGM is simple/ambient — revisit an external service only if the user dislikes it).
- **Changing `Config.ascLocaleCode` globally for th/ko** — rejected (it's correctly GC-tuned and pinned by tests); added an IAP-specific mapper instead.
- **Deleting `NewGameView` later / keeping it** — rejected; verified dead and removed now.

## Hand-offs (sub-agents dispatched)
- GameAudioKit P1 (→ #429); P2-foundation (→ #431); P2-Sudoku (→ #440); P2-Minesweeper (→ #439).
- #433 acks+storekit (→ #437); #434 pause/resume (→ #435).
- 2 skill-drafting agents (returned text; Leader wrote the `.claude/skills/` files — subagents can't write `.claude/`).
- Code-Reviewer agents: #429 reviewed APPROVE-WITH-NITS; #435 review was Bash-sandbox-blocked → Leader did the review (lossless-snapshot + leak checks).

## Open questions
- **IAP submission**: both Remove-Ads IAPs may still need a review screenshot in the ASC web UI (user-owned) before App Store submission.
- **TestFlight re-upload**: #433 (acks) + #434 (pause/resume) only surface in a fresh build; #432 is server-side. Awaiting user's go.
- Sudoku full `swift test` hits a pre-existing `signal 11` in a snapshot-test bundle path (unrelated to this session's changes) — worth a separate look.

## Next session
All of this session's feature work is merged (#330 audio CLOSED, banner #441 CLOSED, #432/#433/#434 fixed both apps). Next: **TestFlight re-upload when the user requests** (a fresh build carries pause/resume + acks + audible audio + the real banner); add IAP **review screenshots** in the ASC web UI (user-owned) before App Store submission; investigate the pre-existing snapshot `signal 11`.
