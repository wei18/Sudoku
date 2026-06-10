# `cloudkit/`

Committed CloudKit schema source of truth — one `.ckdb` per app:

| File | Container | Record types |
|---|---|---|
| `sudoku.ckdb` | `iCloud.com.wei18.sudoku` | `SavedGame`, `PersonalRecord`, `MonetizationState` |
| `minesweeper.ckdb` | `iCloud.com.wei18.minesweeper` | `MonetizationState`, `SavedGame` (#455 resume) |

These files are produced and deployed by `mise run ck:schema …`
(`mise-tasks/ck/schema`, GitHub issue #337). See `docs/foundations.md §7.7.2`.

## Workflow

```bash
# 0. one-time (user): generate a CloudKit management token in
#    CloudKit Dashboard → Settings → Tokens, put it in secrets/.env
#    (CK_MANAGEMENT_TOKEN) along with CK_TEAM_ID. See secrets/.env.example.

# 1. seed: EITHER run a debug build (Development JIT-creates types/fields on
#    first write — JIT never happens in Production!) and export…
mise run ck:schema export --app sudoku           # → cloudkit/sudoku.ckdb
#    …OR hand-edit the .ckdb directly (deploy is a declarative import); use
#    cloudkit/sudoku.ckdb as the syntax template. Commit as source of truth.

# 2. pre-flight:
mise run ck:schema validate --app sudoku

# 3. deploy to Development (freely runnable, declarative):
mise run ck:schema deploy --app sudoku --env development

# 4. promote to PRODUCTION — USER-OWNED, CONSOLE-ONLY (2026-06-10: cktool
#    import-schema rejects production, and no promote subcommand exists):
#    CloudKit Console → container → Development → Schema
#    → "Deploy Schema Changes to Production…" → review diff → Deploy.
#    Production indexes/fields are ADD-ONLY — they can never be removed.
```

The `.ckdb` files are **not** secrets (they are schema definitions, no tokens),
so they are committed. The management token is the secret and lives only in
`secrets/.env` (gitignored).

> The `.ckdb` files are seeded by the user (step 1 needs the live token + a
> populated Development container). They are intentionally absent from the
> issue #337 PR, which adds only the tooling + docs.
