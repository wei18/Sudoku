# Contributing

Thanks for your interest. This is a public portfolio monorepo for two
cross-platform Swift 6 games (Sudoku + Minesweeper) that also documents a
human + Claude-agent engineering workflow. Whether you're filing an issue or
opening a pull request, this guide reflects the **real** workflow used here.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Prerequisites

Tools are pinned and shared between dev machines and CI via
[mise](https://mise.jdx.dev) (single source of truth: [`.mise.toml`](.mise.toml)).
From the repo root:

```sh
mise install
```

This installs the pinned versions of:

- **tuist** — generates the Xcode project/workspace from `Project.swift`
- **swiftlint** — Swift linting
- **xcbeautify** — readable `xcodebuild` output
- **gitleaks** — secret scanning (pre-commit + CI)
- **lefthook** — git hook runner
- **LicensePlist** (macOS only) — generates the Acknowledgements `Settings.bundle`

> Note: SwiftFormat is **not** part of the pipeline — it was removed in favour
> of SwiftLint-only coverage. Don't add it back without discussion.

The Swift toolchain itself is provided by Xcode / Xcode Cloud, not by mise.
The deployment floor is iOS 26 / macOS 26.

### Activate the git hooks

```sh
lefthook install
```

This writes `.git/hooks/pre-commit` so the local checks below run on every
commit.

## Generating the Xcode project

The umbrella `Game.xcodeproj` / `Game.xcworkspace` are **generated and
gitignored** — `Project.swift` is the source of truth. Generate them with:

```sh
tuist generate
```

This produces the `Game` workspace at the repo root with two schemes
(`Sudoku`, `Minesweeper`). Never commit the generated `*.xcodeproj` /
`*.xcworkspace`.

## Running tests

Real code lives in local Swift packages under [`Packages/`](Packages/), so the
fastest loop is to test a package directly without generating the Xcode
project:

```sh
swift test --package-path Packages/SudokuCoreKit
```

Substitute any kit (e.g. `Packages/MinesweeperCoreKit`, `Packages/GameShellKit`,
`Packages/SudokuKit`). The full suite (including the app-level test plans) runs
through the generated workspace; Xcode Cloud is the primary CI track for that.

The test stack is [swift-testing](https://github.com/swiftlang/swift-testing)
(no XCTest) plus
[swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing);
CloudKit and Game Center are exercised through protocol fakes so the suite runs
on a clean runner.

## Pre-commit hooks

[`lefthook.yml`](lefthook.yml) runs these on commit (serialized — concurrent
mise invocations deadlock on mise's cache lock):

1. **gitleaks** (`mise run scan:secrets`) — blocks staged secrets.
2. **hygiene** (`mise run scan:hygiene`) — blocks secret-shaped files from
   entering history.
3. **swiftlint** (`mise run lint:swift`) — warn-only locally on staged
   `*.swift` files. PR CI runs the strict variant (`lint:swift_strict`), which
   fails on warnings.

Don't bypass with `--no-verify`: a secret leak in a public repo is treated as
already leaked. See [`SECURITY.md`](SECURITY.md).

## Pull requests

### PR titles must follow Conventional Commits — with a lowercase subject

The `Lint` CI workflow ([`.github/workflows/lint.yml`](.github/workflows/lint.yml))
validates the PR title as `type(scope): subject`. **This is the most common
trip-up:** the subject must not start with an uppercase letter — a lowercase
letter or a leading digit both pass.

```
feat(monetization): add remove-ads restore button   ✅
docs: add community health files                     ✅
Fix: Crash On Launch                                 ❌  (wrong type case + uppercase subject)
```

- Accepted types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`,
  `build`, `ci`, `perf`, `style`, `revert`.
- Scope is **optional** and unrestricted (e.g. `feat(monetization):`).
- Subject pattern: `^[a-z0-9].+$`.

The squash-merge commit takes the PR title, which is why the title — not the
individual commits — is what CI gates.

### Other CI checks

The same workflow also runs:

- **Markdown link check (lychee)** over changed files in `docs/` and
  `meetings/` — so keep links resolving (this is also enforced locally by
  lefthook on commit).
- **SwiftLint (strict)** on changed `*.swift` files.
- **L10n completeness** — all 7 locales present, no `<TRANSLATE>` placeholders.

CI must be green before merge.

### Merge style

PRs are **squash-merged** and the source **branch is deleted** after merge.
Keep one logical change per PR.

## Localization

These community-health files (this file, `SECURITY.md`, `CODE_OF_CONDUCT.md`,
issue/PR templates) are **English-only**, per GitHub convention. App-facing
strings are different: they follow the project's 7-locale flow
(`zh-Hant`, `en`, `ja`, `zh-Hans`, `es`, `th`, `ko`) in `Localizable.xcstrings`,
translated via the `ai-translated-localization` agent flow. The L10n CI gate
above enforces completeness.

## Repository layout

```
App/
├── Sudoku/                  # thin app shell: @main + DI composition root
└── Minesweeper/             # thin app shell (mirrors Sudoku except gameplay)
Packages/                    # all real code — local SwiftPM packages
docs/                        # spec layer (foundations, methodology, v1/, v2/, designs/, ...)
meetings/                    # dated decision logs (the "why" behind the docs)
.claude/skills/              # project-specific reusable Claude-agent skills
Project.swift                # Tuist source of truth for the generated Game project
.mise.toml                   # pinned tool versions + task definitions
lefthook.yml                 # pre-commit hooks
```

Cross-doc references use **repo-root paths** (e.g. ``docs/v1/design.md §How``),
not bare filenames — see [`docs/README.md`](docs/README.md).

## Spec-phase / collaboration conventions

This repo is spec-first. Product and technical design live under
[`docs/`](docs/README.md); the raw, dated decision records live in
[`meetings/`](meetings/). The collaboration model is a Leader / Developer state
machine documented in [`docs/methodology.md`](docs/methodology.md). If you're
proposing a non-trivial change, it helps to read the relevant `docs/` section
and the methodology first so the change aligns with the existing design.
