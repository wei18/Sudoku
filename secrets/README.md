# `secrets/`

Local-only secrets store for CLI tooling (ASCRegister, etc.). This directory is
deny-by-default in git (`secrets/**` ignored; only `*.example` files and this
README are allowed).

## Layer 2 secrets (CLI tooling)

Build-time values that Xcode consumes live in the gitignored `Tuist/*.xcconfig`
files (templates: `Tuist/*.xcconfig.example`). `mise run tf:upload` writes
`Tuist/AdMob.xcconfig` and `Tuist/AppStore.xcconfig` from the keys in
`secrets/.env`. The pattern is described in the plugin skill
`apple-dev-skills:build-time-secret-injection`.

## One-time setup

1. `cp secrets/.env.example secrets/.env`
2. Fill in the values. They are not stored in the repo; the project owner supplies them:
   - `ASC_API_KEY_PATH` / `ASC_API_KEY_ID` / `ASC_API_ISSUER_ID` — the App Store Connect API key (ASC → Users and Access → Keys)
   - `ASC_APP_ID_SUDOKU` / `ASC_APP_ID_MINESWEEPER` — the numeric ASC app ids
   - `SUDOKU_ADMOB_APP_ID` / `SUDOKU_ADMOB_BANNER_UNIT_ID` and the `MINESWEEPER_` pair — production AdMob ids, used only for release builds
   - `CK_MANAGEMENT_TOKEN` / `CK_TEAM_ID` (CloudKit schema deploy, issue #337) — generate the management token in CloudKit Dashboard → Settings → Tokens; see `docs/foundations.md §7.7.2`
3. Move the ASC API `.p8` key file into this folder, at the path `ASC_API_KEY_PATH` names.
4. Verify gitignore is doing its job:
   - `git status secrets/` should show no untracked files (only `.env.example` + this README tracked)

## Daily use

`source secrets/.env` before invoking ASCRegister:

```bash
source secrets/.env
swift run --package-path Packages/ASCRegisterKit ASCRegister iap plan \
  --key    "$ASC_API_KEY_PATH" \
  --key-id "$ASC_API_KEY_ID" \
  --issuer "$ASC_API_ISSUER_ID" \
  --app-id "$ASC_APP_ID_SUDOKU" \
  --xcstrings App/Sudoku/Resources/Localizable.xcstrings
```

## What goes here vs `Tuist/`

| Layer | Where | Examples |
|---|---|---|
| Build-time (Xcode consumes) | `Tuist/<Domain>.xcconfig` | AdMob App ID + Banner Unit ID (Info.plist `$()` substitution) |
| CLI tooling (shell consumes) | `secrets/.env` + `secrets/*.p8` | ASC API key + .p8 file, CloudKit management token, the values `tf:upload` renders into the xcconfig files |

Which steps use these secrets and who may run them: `.claude/skills/asc-ops-handoff/SKILL.md`.
