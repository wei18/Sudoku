# Setup — first-time clone + deferred Phase 1 items

Status: **DRAFT** — Phase 1 bootstrap (2026-05-17).
Audience: a new contributor (or future-you) cloning this repo.

This file covers two things:

1. **Local dev setup** — what to run after `git clone`.
2. **Phase 1 deferred items** — UI-only / web-portal-only steps that the bootstrap automation could not perform; you must do these by hand before Phase 2.

---

## 1. Local dev setup

### 1.1 Prerequisites

- macOS 15+ with **Xcode 26.5** installed.
- [`mise`](https://mise.jdx.dev) — version manager. Install:
  ```sh
  curl https://mise.run | sh
  ```
- Optional but recommended: shell activation per mise docs (`eval "$(~/.local/bin/mise activate zsh)"`).

### 1.2 First-clone steps

```sh
git clone https://github.com/Wei18/Sudoku.git
cd Sudoku

# 1) Install pinned CLI tools (swiftlint, swiftformat, xcbeautify, gitleaks, lefthook).
mise install

# 2) Activate git hooks (writes .git/hooks/pre-commit).
#    Note: use the aqua-namespaced tool name so mise resolves the pinned version
#    instead of trying to install a separate "latest" lefthook from its core registry.
mise exec aqua:evilmartians/lefthook -- lefthook install

# 3) Verify the SwiftPM package builds + tests pass.
swift build --package-path Packages/SudokuKit
swift test  --package-path Packages/SudokuKit
```

### 1.3 Secrets storage (local)

Real PEMs / API keys live **outside** the repo, under `~/.config/sudoku/` with `chmod 600`. Refer to `.gitignore` for the full denylist; never `git add` anything matching `*.p8` / `*.p12` / `*.pem` / `.env`.

The lefthook `hygiene` command (see `lefthook.yml`) and the `ci_post_clone.sh` script enforce this at commit time and in Xcode Cloud respectively.

---

## 2. Phase 1 deferred items (you must do these manually)

These steps require Apple Developer portal / App Store Connect / GitHub UI / Xcode UI access and cannot be done from the CLI by the implementation automation.

### 2.1 Step 1.4 — Create `App/Sudoku.xcodeproj` in Xcode

The bootstrap created the App source files (`App/SudokuApp.swift`, `App/Info.plist`, `App/Sudoku.entitlements`, `App/Assets.xcassets/`) but **not** the Xcode project file. Create it manually:

1. Xcode → File → New → Project → **App** (multiplatform).
2. Product name: `Sudoku`. Bundle ID: `com.wei18.sudoku`.
3. Save inside `App/` (so the project lives at `App/Sudoku.xcodeproj`).
4. **Replace** the auto-generated `App.swift` / `ContentView.swift` with the existing `App/SudokuApp.swift`. Delete the auto-generated `Info.plist` / `Assets.xcassets` and reference the ones already in `App/`.
5. Project settings → Signing & Capabilities:
   - Set the entitlements file to `App/Sudoku.entitlements`.
   - Add capability: **iCloud** (Services: CloudKit; container: `iCloud.com.wei18.sudoku`).
   - Add capability: **Game Center**.
6. Add the local SwiftPM package: File → Add Package Dependencies → Add Local → select `Packages/SudokuKit`.
   - Link the App target against the `SudokuUI` library (and any other libraries the App's composition root needs in later phases).
7. Build for both destinations to verify:
   ```sh
   xcodebuild -scheme Sudoku -destination "platform=iOS Simulator,name=iPhone 16 Pro" build
   xcodebuild -scheme Sudoku -destination "platform=macOS,arch=arm64"               build
   ```

### 2.2 Step 1.5 — Xcode Cloud workflows (App Store Connect UI)

Source: `docs/foundations.md §4`. The `ci_scripts/` files are already committed; you only need to wire the workflows.

In App Store Connect → Xcode Cloud, create **three workflows**:

| Workflow | Trigger | Actions | Xcode | Tests |
|---|---|---|---|---|
| **PR CI** | Pull request open / push. Enable **"Merge with base branch before building"**. | Build + Test | 26.5 | Run unit / integration fakes / snapshot tests |
| **Main CI** | Merge to `main`. | Build + Archive + **upload internal TestFlight** | 26.5 | None (skipped; PR CI validated pre-merge) |
| **Release** | Git tag matching `v*`. | Build + upload to App Store Connect (manual submit). | 26.5 | None |

Each workflow runs `ci_scripts/ci_post_clone.sh` automatically (Xcode Cloud convention) — that script invokes `mise install` and gitleaks. No further configuration needed there.

### 2.3 Step 1.6 — GitHub repo (public)

The Phase 1 bootstrap deliberately did **not** push to GitHub. When you are ready:

1. Create a public repo `Wei18/Sudoku` (or push this existing repo there).
2. Settings → **Code security and analysis**:
   - Enable **Secret scanning alerts**.
   - Enable **Push protection**.
3. Settings → Branches → Add branch-protection rule on `main`:
   - Require a PR before merging.
   - Require **at least 1 reviewer** (your second account, or self-approve after open period — your call).
   - Require status check: **Xcode Cloud PR CI**.
   - Optionally enable "Require branches to be up to date before merging" to close the §4 race-condition window.
4. Smoke test: try pushing a fake PEM header to a side branch and confirm GitHub blocks it.

### 2.4 Step 1.7 — App Store Connect bundle ID + entitlements

1. Apple Developer Center → Identifiers → register **`com.wei18.sudoku`** (App ID).
   - Capabilities: iCloud (CloudKit), Game Center.
2. CloudKit Dashboard:
   - Create container **`iCloud.com.wei18.sudoku`**.
   - Both Public + Private DB scopes (Public reserved for future use).
   - No record types yet — schema lands in Phase 5.
3. App Store Connect → My Apps → New App (iOS) and another for macOS:
   - Bundle ID: `com.wei18.sudoku`.
   - Enable Game Center for both records.
4. Verify automatic provisioning succeeds in Xcode (Signing & Capabilities → "Automatically manage signing").

---

## 3. Verification checklist (Phase 1 gate)

Run all of these locally before declaring Phase 1 closed:

- [ ] `git ls-files | grep -E '\.(p8|p12|pem|env)$'` — empty output.
- [ ] `mise install` — exits 0.
- [ ] `mise exec aqua:evilmartians/lefthook -- lefthook install` — writes `.git/hooks/pre-commit`.
- [ ] `swift build --package-path Packages/SudokuKit` — clean (0 warnings).
- [ ] `swift test  --package-path Packages/SudokuKit` — 7 smoke tests pass.
- [ ] `xcodebuild -scheme Sudoku -destination "platform=iOS Simulator,name=iPhone 16 Pro" build` — clean. *(After deferred 2.1.)*
- [ ] `xcodebuild -scheme Sudoku -destination "platform=macOS,arch=arm64" build` — clean. *(After deferred 2.1.)*
- [ ] Xcode Cloud PR CI passes on a no-op PR. *(After deferred 2.2 + 2.3.)*
- [ ] A fake-PEM-header commit on a side branch is blocked by GitHub Push Protection. *(After deferred 2.3.)*
