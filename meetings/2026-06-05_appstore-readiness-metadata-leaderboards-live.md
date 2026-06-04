# 2026-06-05 — App Store readiness goes LIVE: metadata + v2.3.5 + MS leaderboards, copy rewrite, README

Continuation session. Headline: the first real `metadata apply` pushed **both apps' full App Store listings to ASC across all 7 locales**, Sudoku's ASC + app version was aligned to **2.3.5**, **Minesweeper's 3 per-difficulty daily Game Center leaderboards were created via API**, the listing copy was rewritten for accuracy + ASO, and the README became a bilingual portfolio README. Along the way the `metadata` command — previously only `plan`-tested — was hardened against **five** mutation-path bugs surfaced by live apply. Leader + many dispatched Developer / Reviewer / App-Store-Optimizer / Content-Creator subagents, worktree-isolated, each gated through review.

---

## Phase A — RemindersKit Phase 2 (recovered from a stall) — MERGED

The prior session's Phase 2 dispatch hit a session limit mid-flight. Recovery:
- **Chunk 1** (primer UI in GameShellUI) had landed clean on a branch (`bb9446a`) — CR'd (APPROVE-WITH-NITS), merged as **#323**.
- **Chunks 2+3** (Sudoku U1 wiring + telemetry) re-dispatched fresh on top → **#325** (CR APPROVE). Value moment = the Daily completion-screen affordance, Daily-gated via the existing `!puzzleId.hasPrefix("practice-")` discriminator. `ReminderSettingsStore` (UserDefaults, default 9 AM) is the **#321 seam**. 6 new `TelemetryEvent` cases with `kind: String` payload (keeps TelemetryKit leaf-pure). `ReminderNotificationDelegate` confines UserNotifications to AppComposition. **Note:** the feature is "shipped but dormant" — no production `solve→.completion` nav exists yet, so the primer is correct-when-it-lands. SudokuKit 176 / TelemetryKit 29 / RemindersKit 12 / GameShellKit 13 green.

## Phase B — CaptureGuardKit RFC redesigned, then parked

User supplied a banking/authenticator screenshot-blackout article. RFC redesigned (**#326**) then **parked to backlog** per user:
- Two user decisions: **surface-scoped** (secure-layer reparent confined to the guarded game-surface view's layer, not the whole window — "擋遊戲畫面就好") + **both mechanisms** (secure-layer blackout for real screenshot/recording + `snapshotView` override for app-switcher). Type renamed `SecureWindowBlackout`→`SecureSurfaceBlackout`. Second-camera bypass dropped from the doc (user: obvious).
- Surfaced + corrected: the `snapshotView` override alone does NOT black out a hardware screenshot/recording — only the secure-layer trick does. Phase 1 NOT dispatched; #286 stays `backlog`.

## Phase C — Minesweeper daily Game Center leaderboards — MERGED + LIVE in ASC

- **Correction captured to memory** ([[ascregister-creates-gc-via-api]]): ASCRegister already creates GC leaderboards/achievements via the ASC API (`createLeaderboard` POST) — Leader had previously (wrongly) told the user to hand-create them in the CK/ASC web UI. Only IAP product *creation* is genuinely manual (#200).
- **#328**: MS gets 3 recurring-daily leaderboards `com.wei18.minesweeper.leaderboard.{easy,medium,hard}.daily.v1` mirroring Sudoku (difficulty `.beginner→easy` etc.; titles keep real names). GC `Config` made app-aware (`Config.GCApp` + `--app`). Superseded #291's old non-recurring `…besttime.v1` ids. CR APPROVE-WITH-NITS. Follow-up #329 (gate MS submit to daily-only — currently all-wins).
- **Created live in ASC**: merged the 3 title keys into `Minesweeper/Resources/Localizable.xcstrings`, GC `plan --app minesweeper` confirmed **MS already has a gameCenterDetail** (no web-UI enable needed), then `apply` created 3 leaderboards + 6 localizations (en-US + zh-Hant). 5 other locales staged `<TRANSLATE>` for a later translation pass.

## Phase D — The `metadata apply` saga (the big one) — both apps LIVE

The `metadata` command (#310) had only ever been `plan`-tested (read-only). The first real `apply` surfaced **five** mutation-path bugs, each fixed in turn (all CR-gated):

1. **Field-length not validated** (user explicitly asked to prevent this) → `MetadataFieldLimits` + pre-flight validation in `load()` (runs during `plan`, fails loud listing all violations). **#327**
2. **`whatsNew` rejected on first version** (ASC blocks release notes on a 1.0 submission) → reconciler drops whatsNew when no released version exists; wired via `snapshotMetadata` reading `appVersionState`. **#327** + a one-line main.swift wiring follow-up.
3. **Category mapping wrong** — sent the sub-category (`GAMES_PUZZLE`) as `primaryCategory`; ASC needs the genre (`GAMES`) there → full 6-slot mapping (primary/secondary category + 2 subcategories each). **#332**
4. **version-loc CREATE-vs-UPDATE mis-classification** — `?include=` side-load truncated → missed an existing `es-ES` loc → 409 duplicate → snapshot now fetches via paginated relationship endpoints + a 409-duplicate self-heal (CREATE→PATCH). **#332**
5. **Trailing-newline mismatch** — the validator trims a block-scalar's trailing `\n` for its check (170 ok) but apply *sends* it (171) → ASC 409. Worked around by trimming the copy; tool fix tracked in **#333**.

Plus a **data** fix (not a tool bug): the YAML set `secondary_category: "Games"` — ASC forbids the same genre as both primary and secondary. User chose Sudoku=Puzzle+Board, MS=Board+Puzzle, secondary dropped.

**Result:** both apps' name / subtitle / description / keywords / promo / categories are LIVE on ASC across all 7 locales. (Known minor: `plan` still shows version-locs as UPDATE every run — no field-level drift compare; tracked in #333.)

## Phase E — Version alignment to 2.3.5

User: "ASC & App 版號 & 文案直接採用最新版" → "對其 SPEC 版本 2.3.5". Sudoku ships the latest monetized build (banner SDK lands at v2.3.5), NOT ad-free.
- **App version**: Sudoku `Info.plist` `1.0.0 → 2.3.5` (MS stays 1.0.0 — separate v1 app).
- **ASC version**: built a new `ASCRegister metadata set-version` capability (**#334**, fails-closed on released/locked versions, idempotent) and ran it → Sudoku's editable ASC version renamed `1.0 → 2.3.5`.

## Phase F — Listing copy rewrite (accuracy + ASO) — applied

- **ASO review** (App Store Optimizer → `docs/app-store/metadata/COPY-REVIEW.md`): two P1 accuracy risks flagged.
- **Verified against code**: MS has **no SavedGame flow** (`MinesweeperAppComposition/Live.swift`) → the "Resume any time — saves are automatic" claim is false. Sudoku ships the removable banner (latest version) → "No ads" is false.
- **Rewrite** (**#335**): Sudoku "No ads" → accurate "no tracking + optional banner removable via one-time IAP" framing (mirroring MS); MS resume claims removed in all 7 locales; ASO keyword optimization (drop name-dupes, fix `puzzle`→`puzle` es, fill CJK budget incl. `ナンプレ`); whats_new refreshed to 2.3.5. All char-validated within caps. Re-applied to ASC (after trimming MS es-ES promo for the trailing-newline edge).

## Phase G — README → bilingual portfolio README — MERGED

**#336**: rewrote the repo README as a polished portfolio/developer README — English primary (`README.md`) + `README.zh-Hant.md` with a language switcher. Showcases both apps + the shared architecture + the Leader/Developer AI-collaboration methodology. Fact-corrected: **11** SPM packages (was "9" — adds RemindersKit + ASCRegisterKit). Leader corrected the agent's stale MS status (gameplay built per #293, not "in development"; MS has no saved-game flow). (A rebase made the branch push non-ff, so the MS-status fix was re-applied directly on main.)

## Phase H — Backlog + docs housekeeping

- **#329** MS GC submit → gate to daily-only (mirror Sudoku) before v1 GA.
- **#330** game audio (music + SFX + volume) — hard constraint: `.ambient`/`mixWithOthers` so it never interrupts the user's streaming audio.
- **#331** SettingsKit — shared settings framework (screen, feature toggles, version, notices, permissions) consolidating #287/#321/#330/#286.
- **#333** metadata tool follow-ups (version-loc drift, trailing-newline payload, URLProtocol test harness).
- **#337** automate CloudKit schema Dev→Production deploy via `xcrun cktool` (verified feasible: `export-schema`/`validate-schema`/`import-schema --environment production`; needs a one-time CK management token + a committed `.ckdb`). Replaces the user-owned CK Dashboard step — same arc as the GC-leaderboard automation.
- **MS readiness doc refreshed**: pending-feature flags marked GC leaderboards + Daily as wired (were pre-#293-build-out); only saved-game resume remains unwired.
- Email treated as secret (yaml `null`, `.env`-injected) like phone — GitHub noreply doesn't receive mail.

## Cross-cutting decisions / memory
- New memory [[ascregister-creates-gc-via-api]] (GC = API-created, not manual; corrected a wrong Leader claim) + [[asc-metadata-field-limits]] (caps + whatsNew-first-version rule).
- **Live mutating ASC ops are Leader-run with user authorization**: `metadata apply` + GC leaderboard `apply` + `set-version` were run by the Leader (secrets/.env creds, never printed); `metadata apply` ≠ GC leaderboard apply (the user authorized them separately).
- **MS iCloud**: container `iCloud.com.wei18.minesweeper`, writes only `MonetizationState` (Remove-Ads mirror), no game saves; schema-to-Production deploy is user-owned (until #337).
- A stalled subagent's broken WIP is not worth salvaging — preserve on a branch, re-dispatch fresh (the category/dedup fix).
- Read-only reviewers keep slipping `git checkout -- .` (benign no-ops here) — keep forbidding mutating git in CR prompts.
