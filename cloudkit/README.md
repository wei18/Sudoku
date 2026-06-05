# `cloudkit/`

Committed CloudKit schema source of truth — one `.ckdb` per app:

| File | Container | Record types |
|---|---|---|
| `sudoku.ckdb` | `iCloud.com.wei18.sudoku` | `SavedGame`, `PersonalRecord` |
| `minesweeper.ckdb` | `iCloud.com.wei18.minesweeper` | `MonetizationState` (no SavedGame — no save flow yet) |

These files are produced and deployed by `mise run ck:schema …`
(`mise-tasks/ck/schema`, GitHub issue #337). See `docs/foundations.md §7.7.2`.

## Workflow

```bash
# 0. one-time (user): generate a CloudKit management token in
#    CloudKit Dashboard → Settings → Tokens, put it in secrets/.env
#    (CK_MANAGEMENT_TOKEN) along with CK_TEAM_ID. See secrets/.env.example.

# 1. seed: run a debug build so it writes to the Development container, then:
mise run ck:schema export --app sudoku           # → cloudkit/sudoku.ckdb
git add cloudkit/sudoku.ckdb                       # commit as source of truth

# 2. pre-flight:
mise run ck:schema validate --app sudoku

# 3. deploy to Development (freely runnable):
mise run ck:schema deploy --app sudoku --env development

# 4. deploy to PRODUCTION — USER-OWNED, gated:
mise run ck:schema deploy --app sudoku --env production --i-am-sure
```

The `.ckdb` files are **not** secrets (they are schema definitions, no tokens),
so they are committed. The management token is the secret and lives only in
`secrets/.env` (gitignored).

> The `.ckdb` files are seeded by the user (step 1 needs the live token + a
> populated Development container). They are intentionally absent from the
> issue #337 PR, which adds only the tooling + docs.
