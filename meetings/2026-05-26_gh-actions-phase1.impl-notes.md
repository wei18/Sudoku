# Impl Notes — GH Actions Phase 1 (2026-05-26)

Status: IN_PROGRESS
Owner: DevOps Automator (subagent)
Dispatched by: Leader
Started: 2026-05-26

## 設計決定 (Design decisions)

- **Runner choice for lint.yml = `macos-latest`** — Dispatch suggested `macos-latest` since ubuntu has no Swift toolchain by default. swiftlint + swiftformat are pure-Swift binaries managed via mise (aqua backend), so technically ubuntu could install them, but matching the dev/XCC environment (macOS + Xcode toolchain) is safer for parity. Trade is minutes cost (macOS = 10x ubuntu), but only runs on Swift-file PRs.
- **`mise install` via `jdx/mise-action@v2`** — Mirrors `ci_scripts/ci_post_clone.sh` pattern (which bootstraps mise + `mise install`). Action handles caching of the mise toolchain itself.
- **Changed-files diff base = `origin/${{ github.base_ref }}...HEAD`** — Three-dot form gives "files changed in this branch since divergence", which is what lint-on-changed-files semantics want. `fetch-depth: 0` required for diff to work.
- **PR title lint allows scopes** — Recent merged commits (`refactor(types):`, `refactor(gc-ids):`, `feat(settings):`) use `type(scope):`. Configured `action-semantic-pull-request` to permit (default behavior; no explicit scope whitelist needed — that would over-constrain).
- **lychee args scope** — Limited to `docs/**/*.md` and `meetings/**/*.md` per dispatch. Did NOT include `*.md` at repo root (e.g. README.md) — out of scope and root README is rarely edited in PRs.

## 偏離 (Deviations)

- **swiftformat `continue-on-error: true`** — Per dispatch §2 note: repo currently has 204/244 files non-compliant with swiftformat baseline. Strict mode would fail nearly every PR. Marked the step as advisory until either a baseline mass-format lands OR `.swiftformat` config relaxes rules. Inline comment in workflow points back to the parallel impl-notes referenced in dispatch.
- **swiftlint stays strict** (`--strict --quiet`) — Already enforced in `lefthook.yml` locally; CI mirror should match.

## 折衷 (Tradeoffs)

- **`action-semantic-pull-request@v5` vs writing own regex** — Picked the action. It's the canonical Conventional Commits PR-title linter (3k+ stars, maintained by `amannn`), handles edge cases (revert, breaking-change `!`, scopes), and only needs `pull-requests: read`. Writing a regex in shell would be ~15 lines but no value-add.
- **`lycheeverse/lychee-action@v2` vs `gaurav-nelson/github-action-markdown-link-check`** — Picked lychee. (a) Single Rust binary, fast on large `meetings/` tree; (b) supports glob; (c) `.lycheeignore` for known-flaky external links; (d) actively maintained.
- **`jdx/mise-action@v2` vs manual `curl mise.run | sh`** — Picked the action. Caches mise + tool installs across runs (`cache: true`), trimming each lint run by ~30-60s. Manual bootstrap would mirror `ci_post_clone.sh` exactly but with no caching benefit on GH-hosted runners.
- **No `actionlint` step** — Dispatch listed it as optional. Skipping for Phase 1: adds another tool dependency; YAML syntax validated via python3 `yaml.safe_load`. Can be added when first invalid workflow ships.

## 未決 (Open questions)

- **lychee external-link timeouts on first run** — apple.com / developer.apple.com sometimes 403 bots. If first PR CI run trips on these, Leader should add a `.lycheeignore` file with the offending hosts. Defaulting to no `.lycheeignore` to avoid pre-emptive suppression; we want to see what actually fails first.
- **Workflow on PRs from forks** — `pull_request` (not `pull_request_target`) used everywhere, which is the secure default but means fork PRs cannot read secrets (none needed here). If user later wants fork-PR coverage with secrets, will need `pull_request_target` plus careful checkout discipline.

## Pinned action versions

| Action | Pin | Reason |
|---|---|---|
| `actions/checkout` | `@v4` | Current stable; v5 not yet released. |
| `amannn/action-semantic-pull-request` | `@v5` | Current major; v5 stable since 2023. |
| `jdx/mise-action` | `@v2` | Current major; v2 introduced cache action. |
| `lycheeverse/lychee-action` | `@v2` | Current major. |

Sha-pinning skipped for Phase 1 (advisory checks, no secret exposure). Phase 2 (when bot token enters the picture) should pin to commit SHAs per `apple-public-repo-security` skill.

---

Status will flip to COMPLETE before final report.
