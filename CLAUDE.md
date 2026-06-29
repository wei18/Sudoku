# CLAUDE.md — agent operating guide for this repo

Two shipping Apple-platform games — **Sudoku** and **Minesweeper** (both v2.6, synced versioning) — built
spec-first by an AI Leader/Developer workflow on shared modules. (A third game,
Tiles2048 / SDD-004, was prototyped then **removed** 2026-06-29 to keep MS + Sudoku
the focus; SDD-004 is abandoned.) This file is the distilled operating
knowledge for agents; deeper truth lives in the pointers below, not here.

## Prime directive: the mirror principle

The two apps differ **only** in gameplay screens and resources. Everything else —
view layout, navigation (push/present), buttons, **and source code** — must be one
shared implementation. When MS needs something Sudoku has, extract a shared
parameterized target (the `GameAppKit` / `GameShellKit` / `SettingsKit` pattern);
never copy-paste-and-adapt. Every cross-app drift so far (#448: phantom button,
dead banner, missing resume) lived in hand-written per-app wrappers.

## Architecture in one breath

```
leaf cores (Foundation-only, portable):  SudokuCoreKit · MinesweeperCoreKit · TimeKit · DeterminismKit
seams (restricted framework imports):    PersistenceKit(CloudKit) · GameCenterKit(GameKit) · RemindersKit(UserNotifications)
                                         GameAudioKit(AVFoundation) · AppMonetizationKit(AdMob/StoreKit) · TelemetryKit(OSLog)
shared UI (GameShellKit = ZERO deps):    GameShellUI · SettingsUI(SettingsKit)
shared composition (deps allowed):       GameAppKit — GameRootViewModel<Route> · GameRoot · ResumePill · ResumeCandidate
apps (thin shells):                      SudokuKit · MinesweeperKit  →  App/Sudoku · App/Minesweeper (Tuist-generated)
tooling:                                 ASCRegisterKit (standalone CLI; deliberately does NOT depend on the cores)
```

Key seams agents get wrong:
- `GameShellKit` is **deliberately zero-dependency**. Anything needing Persistence /
  GameCenter / Telemetry goes in `GameAppKit`, not the shell.
- Resume is game-agnostic via `ResumeCandidate<Route>` + an injected `fetchResume`
  closure — per-game persistence stays per-game (`MinesweeperPersistence` returns an
  MS-native summary; the shared `SavedGameSummary` is Sudoku-typed, don't force it).
- The deterministic RNG (`SplitMix64`) drives puzzle/board generation. Changes there
  are **determinism-critical**: frozen seed vectors must not move.

## Workflow contract

- **Leader coordinates; Developers implement.** Dispatch impl to subagents with
  `model: "sonnet"` (coding) or `"haiku"` (mechanical edits). **Probe subagent write
  capability first** (one cheap haiku write-test) — some harness versions deny all
  subagent file writes; if denied, the Leader implements inline and read-only agents
  do verification.
- **Code Reviewer is mandatory** when a diff is >50 LOC **OR** touches
  Persistence / AppComposition / MonetizationCore / AdsAdMob / IAPStoreKit2 /
  Project.swift / PrivacyInfo.xcprivacy. The 50-LOC rule applies to doc-only PRs too.
  Round-1 cosmetic findings: Leader applies inline; substantive: re-dispatch.
- Dispatch prompts carry 5 elements: scope+verifiable target · files to read ·
  skills to invoke · return format · verification criteria. Forbid heredocs and
  destructive git in reviewer prompts.
- Upkeep audit issues (label `audit`): triage first — many findings re-detect
  already-tracked items (screenshots → #236) or established won't-fixes (intentional
  snapshot equalities, `moduleAnchor()` smoke anchors, guarded test fixtures).
  Post the triage comment before fixing anything.

## Build / test / verify

```bash
swift test --package-path Packages/<Kit>     # ALWAYS absolute or repo-relative path; cd does not persist across Bash calls
mise tasks ls                                # ops entry point — check BEFORE hand-rolling any infra command
mise run scan:l10n                           # L10n gate: 7 locales complete + fixture byte-sync (CI-enforced)
tuist generate                               # workspace; new sibling packages are auto-discovered via the umbrella Kits
```

- Verify with `swift test`, not SourceKit: post-edit `new-diagnostics` ("no such
  module X") in fresh/cross-target files are usually **stale noise**.
- Snapshot baselines are committed; suites failing on PNGs = behavior changed —
  STOP and investigate, don't re-record to make tests pass.
- Don't trust "it compiles": tests that construct `.live()` run in an
  **unentitled runner** — eager `CKContainer.default()` crashes with an uncatchable
  ObjC `CKException`. CloudKit resolution must stay lazy (see `PrivateCKGatewayFactory`).

## Hard gates (user-owned — prepare, never execute unprompted)

- **TestFlight upload**: `mise run tf:upload <app> <platform> --i-am-sure`.
- **CloudKit Production schema**: cktool **cannot** push prod; promotion is the
  Console button only ("Deploy Schema Changes to Production…"). `.ckdb` files in
  `cloudkit/` are the committed source of truth; prod fields/indexes are add-only.
  JIT schema exists **only in Development** — a field the code writes but prod
  lacks fails silently behind error funnels.
- ASC submissions / IAP / signing — see `asc-ops-handoff` skill.
- Production AdMob/ASC identifiers never appear in code, comments, or PR diffs —
  memory + `secrets/.env` + xcconfig `$()` substitution only.

## Conventions that bite

- Commits: `git commit --no-gpg-sign -F <msgfile>` (signing hangs; heredocs are
  blocked by hooks). End body with the `Co-Authored-By: Claude …` trailer.
- PR titles: Conventional Commits, **subject starts lowercase** (CI validates).
- SwiftLint runs `--strict` in CI: `file_length` 400 (Live.swift sits at the
  ceiling — extract `Live+Feature.swift` instead of growing it), `identifier_name`
  ≥3 chars (no `vm`), no `TODO` without an issue reference.
- Swift 6 strict concurrency + `InternalImportsByDefault` everywhere; new shared
  types are `Sendable`; `@Sendable` closures can't capture MainActor statics
  (mark test fixtures `nonisolated`).
- The **app-root composition bootstrap** (`GameRoot` / `MakeGameApp`) goes in
  `.onAppear { Task { … } }`, not `.task` — that is where the Xcode 26 `.task`
  lowering broke the arm64 device Release link (#361). Leaf-view one-shot `.task`
  bootstraps (Settings / Daily hub / banner) are **fine** — an arm64 device Release
  archive links them clean (verified #607, Sudoku Release build 202606260559). So
  don't blanket-ban `.task`: it's the idiomatic choice for view-lifecycle async
  work. If a device-Release archive ever fails to link an opaque `.task` descriptor,
  move that one site to `.onAppear { Task }`.
- After merging from a worktree, `git fetch && git reset --hard origin/main` on the
  main checkout and verify clean (worktree index bleed is real).
- L10n: user-visible strings need all 7 locales (`ai-translated-localization`
  skill); test fixtures regenerate via `gen:l10n_fixture` / `gen:privacy_fixture`,
  never hand-edit.

## Where truth lives

| What | Where |
|---|---|
| Every ops/release pipeline | `.claude/skills/mise-task-operations` (index) + the owning skill |
| Project skills | `.claude/skills/` — 8 project-bound skills (flat) + the `apple-dev-skills` plugin submodule (26 portable skills, namespace `apple-dev-skills:`, wired via `.claude/settings.json`); committed, public |
| Architecture & decisions | `docs/foundations.md` · `docs/v1/design.md` · `docs/superpowers/specs/` |
| Design prototypes | `docs/designs/*.prototype.html` — re-tag build-status when features ship (recurring audit finding) |
| Collaboration patterns | `docs/methodology.md` · `meetings/*.md` |
| Session memory | `~/.claude/projects/<this-repo>/memory/` — feedback rules are binding |

When in doubt: read the Sudoku implementation of the same surface first — it is the
reference shape for everything Minesweeper mirrors.
