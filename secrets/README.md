# `secrets/`

Local-only secrets store for CLI tooling (ASCRegister, etc.). This directory is
deny-by-default in git (`secrets/**` ignored; only `*.example` files and this
README are allowed).

## Layer 2 secrets (CLI tooling)

Build-time secrets (AdMob IDs) live in `Tuist/AdMob.xcconfig` — NOT here. See
`Tuist/AdMob.xcconfig.example` + project skill `build-time-secret-injection`
for the rationale.

## One-time setup

1. `cp secrets/.env.example secrets/.env`
2. Fill values from project memory:
   - `ASC_API_KEY_ID` / `ASC_API_ISSUER` / `ASC_API_SUDOKU_APP_ID` / `ASC_API_MS_APP_ID` — see memory `asc-api-credentials`
3. Move ASC API `.p8` cert into this folder:
   - `mv ~/GitHub/ASCAPI_AuthKey_*.p8 secrets/`
4. Verify gitignore is doing its job:
   - `git status secrets/` should show no untracked files (only `.env.example` + this README tracked)

## Daily use

`source secrets/.env` before invoking ASCRegister:

```bash
source secrets/.env
swift run --package-path Packages/SudokuKit ASCRegister iap plan \
  --key   secrets/ASCAPI_AuthKey_${ASC_API_KEY_ID}.p8 \
  --key-id "$ASC_API_KEY_ID" \
  --issuer "$ASC_API_ISSUER" \
  --app-id "$ASC_API_SUDOKU_APP_ID" \
  --xcstrings Sudoku/Resources/Localizable.xcstrings
```

## What goes here vs `Tuist/`

| Layer | Where | Examples |
|---|---|---|
| Build-time (Xcode consumes) | `Tuist/<Domain>.xcconfig` | AdMob App ID + Banner Unit ID (Info.plist `$()` substitution) |
| CLI tooling (shell consumes) | `secrets/.env` + `secrets/*.p8` | ASC API key + .p8 cert |

See `.claude/skills/build-time-secret-injection/SKILL.md` for the full rationale.
