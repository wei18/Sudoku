# Impl notes — #311 App Store screenshots sourced from snapshot baselines

Branch: `feat/appstore-screenshots-from-snapshots-311`

## Goal
Wire a repeatable mechanism mapping committed snapshot-test baseline PNGs →
App Store submission screenshot slots, so store screenshots derive from the
snapshot baselines (single source of truth) instead of hand capture.

## Hard finding (blocks "submission-ready" claim)
Measured baseline PNG dimensions via `file`:
- iPhone snapshots: **786 × 1704** (393×852 pt @2x) — `SnapshotLayouts.iPhone`.
- Mac snapshots: **1800 × 1200** (900×600 pt @2x) — `SnapshotLayouts.mac`.
- All baselines are **RGBA** (have an alpha channel).

ASC 2026 screenshot spec (WebSearch, Apple ASC Help):
- iPhone 6.9": 1320×2868 / 1290×2796 / 1260×2736, **exact, zero tolerance**.
- iPad 13": 2064×2752 / 2048×2732.
- Mac: min 1280×800, larger OK, aspect respected.
- **No alpha channel allowed**; PNG/JPEG RGB only.

Therefore the snapshot PNGs do **NOT** meet ASC submission specs:
- iPhone 786×1704 ≪ 1290×2796 (and exact-match enforced) → FAIL.
- Mac 1800×1200 is ≥ min and could pass dimension-wise, BUT alpha channel → FAIL.
- iPad: no iPad baselines exist at all.

Decision: scope #311 to **"wire the pipeline + document the gap"** per the
issue's own caveat ("or add a marketing-frame pass"). Do NOT claim
submission-ready screenshots. The symlink pipeline gives a single source of
truth for *previews*; a later marketing-frame/upscale pass (separate issue)
converts them to ASC-exact RGB assets.

## Mechanism chosen
- `mise-tasks/store/screenshots` (task `store:screenshots`), styled on the
  `ck/schema` precedent (#337). Subcommands: `sync` (create symlinks),
  `clean`, `list` (print the mapping).
- Output tree: `docs/app-store/screenshots/<app>/<device>/<locale>/NN-screen.png`
  — symlinks (relative) into the `__Snapshots__` baselines. No duplicate PNGs.
- Mapping declared inside the script (one `map` line per slot). Only the
  screens/locales that have a baseline today are wired; missing ones are
  printed as gaps, not faked.
- The staging tree's symlinks are committed (git stores them as link entries,
  not PNG copies), with a README marking them NON-SUBMISSION-SPEC.

## Why symlinks over copies / over a generated tree
Issue explicitly prefers symlinks; keeps the baseline the single source of
truth — re-recording snapshots auto-updates the store preview with no copy step.

## Open questions for Leader/User
- iPad screenshots: no baselines exist. iPad slot is ASC-required if the app
  declares iPad support. Out of scope here; needs either iPad snapshot fixtures
  or the marketing-frame pass. Flagged, not solved.
- The marketing-frame/upscale pass (snapshot → ASC-exact RGB, device frame,
  overlay copy from screenshot-strategy.md) is the real submission path. Should
  be its own issue under #236; routed to backlog.
