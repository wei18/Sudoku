# Settings Redesign Option A + Receipt Strip — impl notes

**Date**: 2026-05-25
**Branch**: worktree-agent-ab425890f18be2113
**Base**: origin/main @ dfead9a
**Dispatch**: Leader → Developer; Option A surgical fix + AdsRemovedRow receipt strip
**Skills loaded**: swiftui-expert-skill, swiftui-interaction-footguns, swift6-concurrency, swift-testing-baseline, karpathy-guidelines, agent-impl-notes-log

## Decisions in flight

- **Snapshot regen mechanism**: `SnapshotConfig.swift` uses `.missing` record mode (only re-records when baseline PNG is absent). Plan: delete the 2 existing PNGs after code change, then run tests once to regenerate, commit new PNGs.
- **AdsRemovedRow placement**: keep inline in `SettingsView.swift` alongside `RemoveAdsRow` and `RestorePurchasesRow`. No separate file — matches existing layout.
- **Icon tint for About rows**: per Designer §3 row tint `.secondary`. Apply at `Label` color level via `.foregroundStyle(.secondary)` on the icon — keep label text in default primary so VoiceOver and readability are unaffected.
- **Storage Clear cache icon**: `trash`. Destructive role stays system-red.

## Considered alternatives

- Using `LabeledContent` for the receipt strip (would mirror About rows): rejected — Designer mockup shows symmetric HStack with trailing "Active" secondary text, not a value-column label. HStack reads more like a status badge.
- Promoting AdsRemovedRow to its own file: rejected — sibling rows live in same file (RemoveAdsRow, RestorePurchasesRow). Stay consistent (karpathy §3 surgical).

## Open questions for Leader

- None. Scope clearly defined in §3 table.

## Deviations from proposal §3

- (filled at end)
