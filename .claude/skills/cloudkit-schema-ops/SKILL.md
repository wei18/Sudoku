---
name: cloudkit-schema-ops
description: Export, validate, and deploy the CloudKit schema for Sudoku / Minesweeper via the `mise run ck:schema …` task (wraps `xcrun cktool`). Codifies the `.ckdb` source-of-truth workflow, the `CK_MANAGEMENT_TOKEN` / `CK_TEAM_ID` auth from `secrets/.env`, and the user-owned Production-deploy gate. Invoke when changing a CloudKit record type / index, when a Persistence schema change needs to reach a CloudKit container, before a Production schema deploy, or when asked "how do I push the CloudKit schema / what is `ck:schema` / why is the .ckdb committed".
---

# CloudKit Schema Ops

The `mise-tasks/ck/schema` task (GitHub issue #337) makes the CloudKit
Development → Production schema deploy a commit-trackable, Leader-orderable step,
mirroring how ASCRegister made ASC metadata / Game Center deploys scriptable. It
wraps `xcrun cktool`. The schema source of truth is one `.ckdb` per app under
`cloudkit/` (`cloudkit/<app>.ckdb`).

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

The token is the secret; the task pipes it to `xcrun cktool save-token` via stdin
(never argv) and a trap purges it from cktool's keychain store on exit. Container
IDs (`iCloud.com.wei18.sudoku`, `iCloud.com.wei18.minesweeper`) are public and
hardcoded in the task.

## Invocations

```bash
# 1. Export the live Development schema → cloudkit/<app>.ckdb (overwrites).
#    Seed step: run a debug build first so it provisions the Dev container.
mise run ck:schema export   --app sudoku|minesweeper

# 2. Pre-flight: validate the committed .ckdb against the container.
mise run ck:schema validate --app sudoku|minesweeper

# 3. Deploy to Development (freely runnable, reversible).
mise run ck:schema deploy   --app sudoku|minesweeper --env development

# 4. Deploy to PRODUCTION — user-owned, gated (see below).
mise run ck:schema deploy   --app sudoku|minesweeper --env production --i-am-sure
```

`--app` is required (`sudoku` | `minesweeper`). `--env` defaults to `development`.
`export` and `validate` ignore `--env`.

## Inputs / outputs

- **Input**: `secrets/.env` creds; the live container (`export`) or `cloudkit/<app>.ckdb` (`validate` / `deploy`).
- **Output**: `export` writes/overwrites `cloudkit/<app>.ckdb` — review the git diff, then **commit it as the schema source of truth**. `deploy` mutates the named container's schema (import is `--validate`'d).
- `.ckdb` files are **not secrets** (schema definitions, no tokens) → committed. They are seeded by the user (needs the live token + a populated Dev container) and were intentionally absent from the #337 PR.

## Safety gate — Production deploy is user-owned and irreversible

`deploy --env production` is gated behind `--i-am-sure`; without it the task
aborts (exit 2). CloudKit Production indexes are **add-only** (Apple rule): once a
field is indexed in Production it can never be removed. Before deploying:

1. Confirm in CloudKit Dashboard that the `.ckdb` diff is intended.
2. Treat this as a user-owned action — Leader does not run a Production deploy
   unsupervised; surface it as a user decision the same way ASC submissions are.

`export` / `validate` / `deploy --env development` are reversible and freely runnable.

## Idempotency

- `export`: re-running overwrites `cloudkit/<app>.ckdb` with current Dev schema.
- `deploy`: CloudKit import is declarative — re-applying the same `.ckdb` is a no-op.

## See also

- [[build-time-secret-injection]] — the `secrets/.env` Layer-2 pattern the token reuses.
- [[apple-public-repo-security]] — why the token is a per-deploy secret (stricter class than build-time IDs).
- [[asc-ops-handoff]] — sibling user-owned-vs-Leader-orderable deploy split for App Store Connect.
- [[mise-task-operations]] — the ops-task index this task belongs to.
- `cloudkit/README.md` + `docs/foundations.md §7.7.2` — the workflow + container/record-type table.
