# impl-notes — swift-issue-reporting pilot (#178)

## Scope
Pilot `reportIssue(_:)` at 2 Tier-1 invariant sites + document the rule. Leader-approved adoption.

## Decisions
- **Package identity**: `xctest-dynamic-overlay` (pointfreeco), product `IssueReporting`. Already in `Packages/SudokuKit/Package.resolved` at version `1.9.0` (rev `dfd70507def84cb5fb821278448a262c6ff2bbad`), transitive via swift-snapshot-testing. Adding as DIRECT dep with `from: "1.9.0"` to match resolved — avoids version churn.
- **Targets**: `IssueReporting` product added to `SudokuUI` (SudokuKit) + `MinesweeperUI` (MinesweeperKit) only. Deliberate allowance under swiftpm-modularization restricted-imports — treated like a logger / invariant-reporting tool.

## Site conversions
1. SudokuUI/Board/GameViewModel.swift:221 + :248 — `assertionFailure(...)` → `reportIssue(...)` in the preview/test path catch blocks. Keep do/catch + comment intent.
2. MinesweeperUI/MinesweeperGameViewModel.swift reveal(:82) + toggleFlag catches — add `reportIssue("...: \(error)")` INSIDE existing catch. Keep non-fatal swallow (reportIssue is non-fatal in release). No `chord` method exists in this VM — only `reveal` + `toggleFlag`, so 2 catch sites converted.

## Doc rule
foundations.md §3 Testing — add rule: expected runtime failure (network/CloudKit/catalog) → ErrorReporter + telemetry; impossible state / violated invariant → reportIssue. Cross-ref #178.

## Open questions
- None. The MS spec mentioned "chord catches" but no chord method exists yet; scoped to the 2 real catch sites.
