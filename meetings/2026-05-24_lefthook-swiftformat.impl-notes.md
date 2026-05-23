# lefthook: add swiftformat --lint pre-commit step

## Scope
Per `docs/foundations.md §Backlog`: pre-commit ran swiftlint + gitleaks only;
format drift slipped through to CI. Added `swiftformat --lint` (report-only)
so drift fails the commit locally without mutating staged files.

## Change
`lefthook.yml` — new `swiftformat` command under `pre-commit:`, parallel to
`swiftlint`. Uses `mise exec swiftformat --` to pin to the same version as CI
(swiftformat 0.54 in `.mise.toml`). `--lint` flag = report-only; non-zero exit
on drift. `stage_fixed: false` because nothing is auto-fixed.

User remediation on failure: `mise exec -- swiftformat .` then re-stage.

## Verify
- `mise exec -- swiftformat --version` → `0.54.6` (matches `.mise.toml`
  pin `swiftformat = "0.54"`)
- YAML structure eyeballed; commands are siblings under
  `pre-commit.commands`; `parallel: true` already set on the block
- No `.swiftformat` config file present — swiftformat uses defaults
  (intentional, per task constraint)

## Files touched
- `lefthook.yml` (+6 / -0)

## §未決
- Should we ship a `.swiftformat` rules file to make the lint deterministic
  across swiftformat minor versions? Currently relying on defaults +
  `swiftformat = "0.54"` mise pin. Park in `foundations.md §Backlog` for a
  follow-up if defaults bite us.
- swiftformat and swiftlint can disagree (e.g. trailing comma rules). If
  conflicts surface, document the precedence in `foundations.md §7`.
