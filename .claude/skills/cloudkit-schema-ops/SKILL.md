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

The token is the secret; the task passes it to `xcrun cktool save-token` as a
**positional argument** (cktool rejects stdin piping in non-interactive mode —
see Live-run gotchas) and a trap purges it from cktool's keychain store on exit.
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
- `.ckdb` files are **not secrets** (schema definitions, no tokens) → committed. They are seeded by the user (needs the live token + a populated Dev container) and were intentionally absent from the #337 PR.

## Safety gate — Production promotion is user-owned, Console-only, irreversible

**cktool cannot push schema to Production** (verified live 2026-06-10):
`import-schema` rejects `--environment production` with *"endpoint not applicable
in the environment 'production'"*, and no promote subcommand exists. The dev→prod
promotion happens ONLY in CloudKit Console:

1. Bring Development in sync: `mise run ck:schema deploy --app <app> --env development`.
2. Console → container → environment **Development** → Schema →
   **"Deploy Schema Changes to Production…"** → review the field/index diff → Deploy.

CloudKit Production fields/indexes are **add-only** (Apple rule): once deployed
they can never be removed. The Console requirement keeps this naturally
user-owned — the Leader prepares `.ckdb` + Dev deploy; the user clicks the button.

`export` / `validate` / `deploy --env development` are reversible and freely runnable.

## Live-run gotchas (first real-token run, 2026-06-10 — all bit us)

1. **`save-token` takes the token as a positional argument only.** Piping via
   stdin fails non-interactively with *"Interaction was required"*. Brief argv
   exposure is accepted; the EXIT trap purges the keychain entry.
2. **`validate-schema` REQUIRES `--environment`** — omitting it is a hard error.
3. **`import-schema` is Development-only; Production promote is Console-only**
   (see safety gate above). The original #337 task scripted a production import
   that could never have worked — it was never live-tested. Smoke-test ops
   scripts with real credentials before trusting them.
4. **Just-in-time schema exists ONLY in Development.** Debug builds auto-create
   record types/fields on first write in Dev; Production never does. Corollary:
   any field the code writes that was never JIT-seeded in Dev *before* the last
   Console promote is **missing in Production**, and live writes of it fail
   (caught only by error funnels). Found this way: Sudoku Production's
   `MonetizationState` lacked `lastShownDate` / `dismissedDate` /
   `lastSeenWallClock` — banner-dismiss persistence was silently broken in prod.
   **Audit method:** `export-schema --environment production` to a temp file and
   diff against the full field set the code can write.
5. **JIT sprays `QUERYABLE SEARCHABLE SORTABLE` on every field** it creates.
   Hand-written `.ckdb` should declare the **minimal** index set instead (e.g.
   only the field a `statusEquals` query needs as `QUERYABLE`) — because prod
   indexes are add-only, start minimal and extend later.
6. **`deploy` is a declarative import** — the `.ckdb` can be hand-authored
   outright (no Dashboard clicking, no seed build required); use an exported
   file as the syntax template (system `"___*"` fields + `GRANT` block included).

## Idempotency

- `export`: re-running overwrites `cloudkit/<app>.ckdb` with current Dev schema.
- `deploy`: CloudKit import is declarative — re-applying the same `.ckdb` is a no-op.

## See also

- [[apple-dev-skills:build-time-secret-injection]] — the `secrets/.env` Layer-2 pattern the token reuses.
- [[apple-dev-skills:apple-public-repo-security]] — why the token is a per-deploy secret (stricter class than build-time IDs).
- [[asc-ops-handoff]] — sibling user-owned-vs-Leader-orderable deploy split for App Store Connect.
- [[mise-task-operations]] — the ops-task index this task belongs to.
- `cloudkit/README.md` + `docs/foundations.md §7.7.2` — the workflow + container/record-type table.
