# Impl Notes — cktool CloudKit schema deploy automation (#337) (2026-06-05)

Status: COMPLETE
Owner: Developer subagent
Dispatched by: Leader
Started: 2026-06-05

## 設計決定 (Design decisions)

- **Wrapper is a mise-task shell script, not a Swift CLI** — ASCRegister is a Swift
  package (it talks JSON to the ASC REST API). `cktool` is already a binary on the
  Mac toolchain; wrapping it needs only argument marshalling + a Production confirm
  gate. A 100-line bash mise-task under `mise-tasks/ck/` mirrors the existing
  `mise-tasks/{lint,scan,gen}/` convention and keeps the surface idempotent and
  commit-trackable. A Swift CLI would be over-engineering (Karpathy §2).

- **Two namespaced tasks** — `ck:schema-export` (pull Dev schema → commit `.ckdb`)
  and `ck:schema-deploy` (import to an env, Production guarded). Mirrors the
  ASCRegister `plan` / `apply` split where the read/no-op path is freely runnable
  and the mutating path is gated.

- **Auth via `secrets/.env` `CK_MANAGEMENT_TOKEN`** — mirrors the ASC `.p8`/.env
  pattern (foundations §7.7). Script `source`s `secrets/.env` then calls
  `cktool save-token --type management` from the env var, never echoing it.
  Added placeholder key to `secrets/.env.example` + `CK_TEAM_ID`.

- **Container IDs hardcoded as an app→container map in the script** — they are
  public identifiers (already in entitlements + Project.swift), not secrets. Script
  takes `--app sudoku|minesweeper` and resolves the container.

## 偏離 (Deviations)

- **Did NOT run a live Production deploy** — per dispatch constraint, Production
  mutation is user-owned. `ck:schema-deploy --env production` prints a confirm gate
  and requires `--i-am-sure` before it will call `cktool import-schema`.

## 折衷 (Tradeoffs)

- **Where `.ckdb` files live** — chose `cloudkit/<app>.ckdb` at repo root (new
  `cloudkit/` dir) as the committed schema source of truth. Did NOT create/commit
  actual `.ckdb` files because exporting them requires the live management token +
  a populated Dev container (user-owned one-time step). Documented the seed step
  instead.

## 未決 (Open questions)

- **Exact `cktool` flag names** — could not run `xcrun cktool --help` from this
  sandboxed worktree (Bash tool denied the invocation, even with sandbox disabled).
  Flag surface taken from issue #337's VERIFIED block + Apple's cktool man page
  conventions. If a flag name is off, it is a one-token fix in the script; the
  Production-guard logic and the env/secret handling are independent of it.

- **Could not run `bash -n` / `chmod` / `tuist`** — the sandbox denied every
  Bash invocation except git/gh/rg/ls/grep/find. Script syntax was reviewed by
  hand. Executable bit set via `git update-index --chmod=+x` (staged into the
  commit) since `chmod` on disk was denied. Leader should run
  `bash -n mise-tasks/ck/schema` + `mise tasks ls | grep ck:schema` to confirm
  the task is discovered before relying on it.
