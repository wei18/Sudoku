# 2026-06-15 — v2.6 ASC submission push · App Store screenshots · dual-model collaboration policy

Session id: `49980bb7-1c95-469e-be12-3535d3065c2f`
Mode: AI Collaboration Mode (Leader/Developer + background sub-agents); agent teams enabled

## Goal
Push the first two games (Sudoku + Minesweeper, v2.6) toward App Store submission and fix
problems found in testing — explicitly prioritized by the user over Game 3 (Tiles2048,
parked in #501). Adopt a dual-model collaboration policy for judgment work. Produce the
ASC submission assets that are Leader-orderable, leaving only the user-owned Submit.

## Decisions
1. **Dual-model policy for judgment work** — code review / plan / review / research and any
   design debate now run **two concurrent agents (Sonnet 4.6 + Haiku 4.5)**, same prompt,
   both report to the Leader who reconciles (union of real issues; Leader breaks ties).
   Cap 2 concurrent for these. Implementation tasks stay single-agent (sonnet default /
   haiku mechanical). Review/research agents need `isolation: "worktree"` for reliable
   Bash. Enabled experimental agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in
   `~/.claude/settings.json`); documented in global `~/CLAUDE.md`. (繁中 replies, English
   internal artifacts.)
2. **TestFlight = production** — user policy: TF builds carry prod AdMob + prod CloudKit
   (TF treated as a prod-equivalent RC), not test ads. `tf:upload` auto-render from
   `secrets/.env` is correct; closed the "TF should default to test ads" report (#495) as
   by-design.
3. **v2.6 listing metadata + Game Center → production ASC** — pushed name/subtitle/keywords/
   description for both apps (iOS), registered GC leaderboards + achievements. User
   authorized pushing submission materials to production ASC.
4. **GC locale codes converge on bare `th`/`ko`** — Game Center leaderboard-localization
   apply hit live `LOCALE_INVALID` on region-suffixed `th-TH`/`ko-KR`. Fixed
   `Config.ascLocaleCode` to emit bare `th`/`ko` (region forms `en-US`/`es-ES` are still
   accepted by GC); `ascIAPLocaleCode` now fully delegates to `ascLocaleCode` (the IAP/GC
   split from 2026-06-09 is gone). Tests + the ENTITY_ERROR recipe doc updated. (#503)
5. **App Store screenshots = marketing-frame pass from snapshot baselines** — composite the
   committed 786×1704 UI-test baselines into clean device frames on on-brand backgrounds
   with strategy-doc caption copy → ASC-spec **1290×2796 RGB no-alpha** PNGs. Pure
   Python/Pillow, N-app parameterized (`SLOTS`/`COPY` dicts), repeatable via
   `mise run store:screenshots build-ascspec`. Scope this pass: iPhone 6.9", both apps,
   en + zh-Hant. (#311 → PR #504)
6. **Per-locale fonts (CJK tofu fix)** — SFNS.ttf has **zero CJK glyphs**, so every zh-Hant
   caption first rendered as solid tofu blocks while passing the dimension/mode gate.
   Added a locale-aware `font_for()` — CJK locales (zh-Hant/zh-Hans/ja/ko) load Hiragino
   Sans GB (PingFang preferred if present; covers Han + Latin so "20 步 undo" mixed strings
   render in one font). Caught by Leader eyeballing, not by the agent's "18 passed". (PR #504)
7. **ASC-spec screenshots live in their own tree** — the generator first wrote to
   `screenshots/<app>/iphone-6.9/ascspec/<locale>/`, but the uploader (`ScreenshotDiscovery`)
   walks `<screenshots-dir>/<app>/<device>/<locale>/` with no `ascspec` segment — it would
   have uploaded the 786×1704 RGBA preview symlinks. Relocated to
   `docs/app-store/screenshots-ascspec/<app>/iphone-6.9/<locale>/` (own top-level tree,
   matches the uploader contract; preview symlinks under `screenshots/` untouched). Upload
   with `--screenshots-dir docs/app-store/screenshots-ascspec`. (PR #505)
8. **iPhone screenshots uploaded to ASC** — 18 PNGs (Sudoku 5×2, MS 4×2; en+zh-Hant) pushed
   to production ASC via `ASCRegister metadata screenshots --i-am-sure`, display type
   `APP_IPHONE_67` (1290×2796). Dry-run plan verified before each `--i-am-sure`. Other 5
   locales fall back to en in ASC (allowed). Default locale without `--locale` is en-only;
   ran per-locale.
9. **iPad screenshots are the last Leader-orderable submission gate** — both apps are
   universal (`destinations: [.iPhone, .iPad, .mac]`), so ASC requires iPad 13" screenshots
   (2064×2752). No iPad snapshot baselines exist yet; `ASCScreenshotRender.swift` already
   defines the iPad pixel size. Opened **#506** (baselines + generator `ipad-13` arm),
   framed as shared-pipeline work that benefits every future game (north-star). Dispatched
   a Developer. iPad does NOT block until the user is ready to Submit, but Submit can't pass
   without it. Recorded the v2.6 rollup as a comment on #132.

## Rejected alternatives
- **Unpark Tiles2048 (Game 3) to chase the "many games" north-star now** — rejected; the
  user explicitly sequenced "ship first 2 games + fix tests, then Game 3". User instruction
  overrides the standing goal. The shared screenshot/submission pipeline (and #506's iPad
  arm) is the north-star's "shared modules scale to many games" dimension advanced without
  unparking.
- **Direct on-device ASC screenshot render (NSHostingView.cacheDisplay)** — prior attempt
  collapsed to all-identical images; the marketing-frame-from-baselines route is the
  working path.
- **Replace the preview symlinks in-place with ASC-spec PNGs** — rejected; the previews are
  a separate documented convenience covering more locales/screens. Gave ASC-spec assets
  their own tree instead.
- **Edit #132's v2.5 checklist to v2.6** — rejected (don't rewrite the historical tracker);
  posted a v2.6 status comment instead.

## Hand-offs (sub-agents dispatched)
- #311 screenshot marketing-frame pass → agent `aac1d148…` (sonnet, worktree): built the
  generator, hit + fixed the CJK tofu on a second pass (PR #504).
- #506 iPad screenshots (baselines + generator arm) → agent `a182bdeb…` (sonnet, worktree,
  background): mirror the iPhone pipeline at iPad 13"; eyeball-verify zh-Hant glyphs before
  commit; STOP-and-report if iPad layout renders as a stretched phone. **In flight.**

## Open questions
- Does v2.6 ship the **Mac** app too, or iPhone+iPad only? (Mac is a separate ASC track;
  Mac baselines exist at 1800×1200 but no Mac screenshot pass was run.)
- After #506: confirm whether the other 5 locales should get real screenshots or keep the
  en fallback for v2.6.
- #487 (snapshot tolerance absorbs whole new UI elements) is the same honesty-gap class as
  the tofu bug — queue it in the "fix test problems" priority.

## Leftover follow-ups
- Sudoku's 3 new GC achievements have only en + zh-Hant localizations (other 5 are
  `<TRANSLATE>`).
- New memory: `feedback/generated-asset-eyeball-glyphs-not-dims.md` — verify generated image
  content by eyeballing per locale, never dimension/mode checks alone.
