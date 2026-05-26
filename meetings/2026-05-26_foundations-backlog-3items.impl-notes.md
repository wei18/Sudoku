# Impl Notes — foundations §Backlog 3 items (2026-05-26)

Status: COMPLETE (with 2 of 3 items blocked on Leader pre-flight)
Owner: Senior Developer (subagent)
Dispatched by: Leader
Started: 2026-05-26T00:00Z

Scope: 3 logically independent changesets dispatched in one subagent run.

- **Item 1** — swiftformat → lefthook pre-commit (FULL IMPL, `--lint` mode)
- **Item 2** — Module split (Telemetry/GameCenterClient/Persistence → independent pkgs): **PROPOSAL DOC ONLY**, no refactor
- **Item 3** — LicensePlist auto-acknowledgements (FULL IMPL)

3 separate commit chains; final commits must pass hooks; mid-chain `--no-verify` WIP allowed per methodology §10.

## 設計決定 (Design decisions)

- **Item 1 baseline measured** — `swiftformat --lint Packages/ App/` (with `--swiftversion 6.2`) reports **204/244 files non-compliant**; running auto-format produces `204 files changed, 1766 insertions(+), 1858 deletions(-)` — total churn ≈ 3,624 LOC.
- **Item 1 path B chosen instead of A** — Prompt suggested "Option A: one-time auto-format commit before adding hook". Hard constraint in the prompt overrides: *"if violation count > ~50 LOC, ABORT + report and ask Leader rather than mass-format"*. 3,624 LOC is two orders of magnitude over threshold. **ABORTED auto-format**; reporting back to Leader to choose between (i) accept mass-format anyway, (ii) author `.swiftformat` config that relaxes rules to current style, (iii) defer hook entirely.
- **Item 1 partial deliverable** — Will NOT modify `lefthook.yml` or `.mise.toml` in this dispatch. Documenting status in impl-notes + final report only. swiftformat is already pinned in `.mise.toml` (`swiftformat = "0.54"`), so the tooling foundation is already in place; only the hook activation is blocked on the baseline decision.

## 偏離 (Deviations)

- **Item 1 deviation from spec** — Spec said "Pick A; mass-format commits get less review attention but the diff is mechanical". I chose neither A nor B and instead deferred via the explicit ABORT clause. Rationale: 3,624 LOC mass-format would be impossible to review meaningfully, and the repo has clearly been on a swiftlint-only diet — applying default swiftformat rules retrofitting onto post-hoc style is a policy call (which style wins?), not a mechanical fix. This is a Leader/User decision.

## 折衷 (Tradeoffs)

- **Item 2 module split — proposal verdict shape** — Considered: (a) flat "do it now" recommendation, (b) "defer" recommendation, (c) nuanced "defer split but extract Telemetry first as no-cost win since it has zero Apple-framework imports". Will lean toward (c) in the proposal — Telemetry is uniquely cheap (pure values + protocol) and provides build-time independence today, while GameCenter/Persistence carry Apple-framework cost that doesn't pay off until a 2nd consumer exists.
- **Item 3 LicensePlist mise registry** — Need to verify mise has a working backend (`aqua:mono0926/LicensePlist` or `ubi:mono0926/LicensePlist`). Will test both.
- **Item 3 SwiftUI vs Settings.bundle** — Per spec, settled on SwiftUI display row in `SettingsView.swift` About section. Reason: the app already owns its Settings via SwiftUI Form; Settings.bundle is the older iOS pattern and would split L10n + theming.

### Item 3 — sandbox-driven scope reduction (final)

Original spec wanted full SwiftUI integration. Subagent sandbox blocked:
- `mise install` (network) — cannot install license-plist binary
- `chmod +x` (denied) — cannot mark script executable
- Therefore `scripts/generate-acknowledgements.sh` cannot actually be exercised
- Therefore `App/Resources/Acknowledgements/Acknowledgements.md` cannot be generated
- Therefore bundling it in `Project.swift` would reference a missing file
- Therefore adding a `SettingsView` row + new `AcknowledgementsView` would test against an empty/missing resource and fail snapshot tests

Trade-off: ship only the foundational tooling (script + mise pin) plus a detailed integration plan doc at `meetings/2026-05-26_licenseplist-integration.md` covering exact follow-up steps. The follow-up PR can be authored in 1 dispatch once Leader does the install + chmod + run pre-flight.

This deviates from the spec's "step 4 — Decide integration" + "step 5 — extend SettingsView" but the deviation is forced by sandbox restrictions, not preference. Recorded here so Leader has a clear handoff.

## 未決 (Open questions)

- **Item 1 — Leader decision required (load-bearing, BLOCKS Item 1 commit)**: 3 paths:
  1. Accept mass-format: I do one mechanical commit (3,624 LOC, 204 files) + add hook in a 2nd commit. Review effort: skim only.
  2. Author `.swiftformat` config that disables `hoistPatternLet`, `redundantInternal`, `trailingCommas`, `indent`, `wrapMultilineStatementBraces`, `blankLinesAtStartOfScope`, `elseOnSameLine` (the rules driving today's violations) to make current code pass; add hook after. Smaller diff, but pins us to current style permanently — defeats the point of adopting swiftformat.
  3. Defer entirely; bump the foundations backlog trigger ("3+ format reviews") higher and revisit later.
- **Item 3 — `MarkdownView` source choice** — If a `Text(LocalizedStringKey(markdown))` works (SwiftUI native), great. If the bundled markdown is too large or has unsupported syntax (LicensePlist often emits long Apache 2.0 license bodies), may need to fall back to scrollable `Text` wrapped in `ScrollView`. Default plan: render the bundled `.md` as `ScrollView { Text(...).textSelection(.enabled) }` inside a `NavigationStack`-pushed view. **Resolved**: documented in `meetings/2026-05-26_licenseplist-integration.md` as the follow-up PR template; uses `AttributedString(markdown:options:)` with `.inlineOnlyPreservingWhitespace` to preserve license-text whitespace.

## Final delivery summary

- **Item 1 (swiftformat hook)**: BLOCKED on Leader decision (3-path question above). Zero file changes. Baseline measured + recorded.
- **Item 2 (module-split proposal)**: COMPLETE. Delivered `meetings/2026-05-26_module-split-proposal.md` (Defer-primary, Telemetry-only-optional verdict). Committed.
- **Item 3 (LicensePlist)**: PARTIAL. Delivered `.mise.toml` entry + `scripts/generate-acknowledgements.sh` + `meetings/2026-05-26_licenseplist-integration.md` follow-up plan. SwiftUI integration deferred to follow-up PR (blocked on sandbox-denied `mise install` + `chmod`).
