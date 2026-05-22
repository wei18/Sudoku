# Impl notes — Xcode Cloud `tuist generate` in post-clone

Date: 2026-05-22 (Xcode Cloud build #2 ran UTC 2026-05-22 06:53)
Branch: `fix/ci-xcode-cloud-tuist-generate`
Issue: #86
File touched: `ci_scripts/ci_post_clone.sh` (only)

## Change

Appended after the gitleaks block:

```bash
# 3) Generate Xcode workspace via Tuist (repo does not commit .xcworkspace)
mise exec -- tuist install
mise exec -- tuist generate --no-open
```

## Why this ordering

1. `mise install` (step 1) provisions the `tuist` binary pinned in `.mise.toml`.
2. gitleaks scan (step 2) stays before any artifact generation — a secret leak still fails the build before we materialize derived files.
3. `tuist install` resolves plugins/external deps (currently a no-op for this repo — see §未決).
4. `tuist generate --no-open` materializes `Sudoku.xcworkspace` + `Sudoku.xcodeproj`. `--no-open` suppresses `Xcode.app` launch on the CI image.

## Repo Tuist config confirmed

- `/Users/zw/GitHub/Wei18/Sudoku-spec/Project.swift` — present.
- No `Tuist/Package.swift`, no `Tuist.swift`, no `Workspace.swift`. `Tuist/` directory only holds `Signing.xcconfig{,.example}`.
- Implication: `tuist install` has nothing to resolve today but is kept for forward-compat (cheap no-op, idiomatic Tuist flow).

## Verification

- `bash -n ci_scripts/ci_post_clone.sh` → blocked (Bash permission denied in sandbox).
- Manual visual review only; script not executed locally.
- Real validation: next Xcode Cloud run after merge.

## §未決 / Backlog

- **Cache `Derived/` between Xcode Cloud builds?** `tuist generate` is fast on a clean checkout but Xcode Cloud workflow cache could shave seconds. Defer until build-time pain is measurable → `docs/foundations.md` §Backlog.
- **`Tuist/Package.swift` for external SPM deps via Tuist?** Not in scope; current `Packages/` directory suggests local packages only. Revisit when first remote SPM dep enters.
- **Should `tuist install` be dropped given no plugins?** Keep for now — explicit > implicit, and Tuist docs recommend the pair.
