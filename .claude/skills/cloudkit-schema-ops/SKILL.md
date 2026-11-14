---
name: cloudkit-schema-ops
description: Export, validate, and deploy the CloudKit schema for Sudoku / Minesweeper via the `mise run ck:schema …` task (wraps `xcrun cktool`). Codifies the `.ckdb` source-of-truth workflow, the `CK_MANAGEMENT_TOKEN` / `CK_TEAM_ID` auth from `secrets/.env`, and the user-owned Production-deploy gate. Invoke when changing a CloudKit record type / index, when a Persistence schema change needs to reach a CloudKit container, before a Production schema deploy, or when asked "how do I push the CloudKit schema / what is `ck:schema` / why is the .ckdb committed". This is the repo-specific procedure; the general pattern and its reasons are in apple-dev-skills:cloudkit-schema-source-of-truth. Not for the Swift persistence code that reads and writes the records.
---

# CloudKit Schema Ops

The `mise-tasks/ck/schema` task wraps `xcrun cktool`. The schema source of truth
is one committed file per app: `cloudkit/sudoku.ckdb` and `cloudkit/minesweeper.ckdb`.
An agent may export, validate and deploy to Development. Only the user promotes
to Production.

## When to invoke

- A Persistence change adds/edits a CloudKit record type, field, or index.
- You need to push schema to a container (`development` or `production`).
- Before any Production schema deploy (read the safety gate below first).
- Asked why `.ckdb` is committed but the token isn't.

## Prerequisites (one-time, user-owned)

The two credentials live in `secrets/.env` (gitignored; see `secrets/.env.example`):

- `CK_MANAGEMENT_TOKEN` — a CloudKit **management** token. User generates it in
  CloudKit Dashboard → Settings → Tokens → Create Token (Management).
- `CK_TEAM_ID` — the 10-char Apple Developer Team ID.

The token is the secret. The task hands it to `xcrun cktool save-token` and
removes it from cktool's keychain store on exit.
Container IDs (`iCloud.com.wei18.sudoku`, `iCloud.com.wei18.minesweeper`) are
public and hardcoded in the task.

## Invocations

```bash
# 1. Export the live Development schema → cloudkit/<app>.ckdb (overwrites).
#    Seed step: run a debug build first so it provisions the Dev container.
mise run ck:schema export   --app sudoku|minesweeper

# 2. Pre-flight: validate the committed .ckdb against the container.
mise run ck:schema validate --app sudoku|minesweeper

# 3. Deploy to Development (freely runnable, reversible).
mise run ck:schema deploy   --app sudoku|minesweeper --env development

# 4. Promote to PRODUCTION — user-owned, CONSOLE-ONLY (not scriptable; see below).
#    `deploy --env production` prints the Console steps and exits.
```

`--app` is required (`sudoku` | `minesweeper`). `--env` defaults to `development`.
`export` ignores `--env` (always Development); `validate` honors it.

## Inputs / outputs

- **Input**: `secrets/.env` creds; the live container (`export`) or `cloudkit/<app>.ckdb` (`validate` / `deploy`).
- **Output**: `export` writes/overwrites `cloudkit/<app>.ckdb` — review the git diff, then **commit it as the schema source of truth**. `deploy` mutates the named container's schema (import is `--validate`'d).
- `.ckdb` files are **not secrets** (schema definitions, no tokens), so they are committed.

## Safety gate — Production promotion is user-owned, Console-only, irreversible

**cktool cannot push schema to Production.** `import-schema` rejects
`--environment production`, and no promote subcommand exists.
`mise run ck:schema deploy --env production` prints the Console steps and exits
with code 2. The promotion happens only in CloudKit Console:

1. Bring Development in sync: `mise run ck:schema deploy --app <app> --env development`.
2. Console → container → environment **Development** → Schema →
   **"Deploy Schema Changes to Production…"** → review the field/index diff → Deploy.

CloudKit Production fields and indexes are **add-only**: once deployed they can
never be removed. The agent prepares the `.ckdb` and the Development deploy; the
user clicks the button.

`export` / `validate` / `deploy --env development` are reversible and freely runnable.

## Rules when you edit a schema

These need your action:

1. **Production has no just-in-time schema.** A Debug build creates record types
   and fields on first write in Development only. A field the code writes that
   Production lacks fails at runtime, and only the error funnels show it. Before
   asking the user to promote, export the Production schema to a temporary file
   and compare it with every field the code can write:
   `xcrun cktool export-schema --environment production …`.
2. **Declare the smallest index set.** A just-in-time field gets
   `QUERYABLE SEARCHABLE SORTABLE`. In a hand-written `.ckdb`, declare only the
   index a query needs (for example `QUERYABLE` on the one field a predicate
   filters on). Production indexes cannot be removed later.
3. **You may write the `.ckdb` by hand.** `deploy` is a declarative import, so no
   Dashboard clicks and no seed build are needed. Use an exported file as the
   syntax template, including the system `"___*"` fields and the `GRANT` block.

The task already handles these; do not work around them:

- `cktool save-token` takes the token as a positional argument only. Piping it on
  stdin fails when not interactive.
- `cktool validate-schema` requires `--environment`.
- `cktool import-schema` works for Development only.

## Idempotency

- `export`: re-running overwrites `cloudkit/<app>.ckdb` with current Dev schema.
- `deploy`: CloudKit import is declarative — re-applying the same `.ckdb` is a no-op.

## See also

- [[apple-dev-skills:build-time-secret-injection]] — the `secrets/.env` Layer-2 pattern the token reuses.
- [[apple-dev-skills:apple-public-repo-security]] — why the token is a per-deploy secret (stricter class than build-time IDs).
- [[asc-ops-handoff]] — sibling user-owned-vs-Leader-orderable deploy split for App Store Connect.
- [[mise-task-operations]] — the ops-task index this task belongs to.
- `cloudkit/README.md` + `docs/foundations.md §7.7.2` — the workflow + container/record-type table.
