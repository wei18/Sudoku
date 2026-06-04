# Impl Notes — RemindersKit foundation (#287) (2026-06-04)

Status: COMPLETE
Owner: Developer (subagent, isolated worktree)
Dispatched by: Leader
Started: 2026-06-04

Scope: Phase 1/2 of `meetings/2026-06-03_notification-reminders-proposal.md` —
package + value types + protocol seams + Live/Noop/Fake + tests. NO app wiring,
NO primer UI.

## 設計決定 (Design decisions)

- **Platform floor = iOS 26 / macOS 26** — Proposal Q7 *leans* iOS 18 / macOS 15,
  but the dispatch task and every sibling Kit (`TelemetryKit`, `PersistenceKit`,
  `GameShellKit`) pin `.iOS(.v26)/.macOS(.v26)`. Followed the task + sibling
  convention for build consistency in this monorepo. Recorded as a deviation
  from the proposal's lean; final call is Leader's (no API here needs 26).

- **`ReminderContent.categoryId` optional** — proposal §4.4 lists `categoryId`
  but foreground-presentation category routing is Phase 2 (delegate). Modeled as
  `String?` (nil = no category) so the foundation type is complete without
  forcing every caller to invent a category id now.

- **`ReminderSchedule.onDate` → one-shot `UNCalendarNotificationTrigger`** with
  `repeats: false`; `dailyAt` → repeating calendar trigger; `after` →
  `UNTimeIntervalNotificationTrigger(repeats: false)`. Matches §3.1 / §4.4.

- **Live mapping: identifier-scoped replacement** — `schedule` does
  `removePendingNotificationRequests(withIdentifiers: [kind.rawValue])` then
  `add(_:)`; NEVER `removeAllPendingNotificationRequests` on the schedule path
  (§3.2 64-limit/race discipline). `cancelAll` is the only place a bulk remove is
  acceptable (teardown, §3.4) and it removes only our known kind identifiers, not
  a system-wide `removeAll`.

- **`sound: Bool` on content** — true → `.default`, false → nil. Sound only
  attached if granted is a Phase-2 delegate/settings concern; foundation just
  honors the flag.

## 偏離 (Deviations)

- **Platform floor** — see Design decision above (iOS 26 vs proposal's lean of 18).

## 折衷 (Tradeoffs)

- **No `Telemetry` dependency** — per task + proposal §4.6, host injects the
  callback. Left a documented seam comment in the Live scheduler; no dep added.

- **`UNUserNotificationCenter` fetched per-call, not stored** — `UNUserNotificationCenter`
  is non-`Sendable`, so storing it broke the `Sendable` struct conformance under
  Swift 6 complete checking. `.current()` is a cheap singleton accessor, so the
  Live impls expose it via a computed `center` property and fetch per call. This
  avoids `@unchecked Sendable` / `@preconcurrency import` entirely — cleaner than
  suppressing the warning. Fakes are `actor`s for the same data-race-free goal.

- **Fakes are `actor`s** — recording mutable call history behind a `Sendable`
  async protocol; actor isolation is the lowest-ceremony data-race-free choice.
  `FakeReminderScheduler.pending` reconstructs the Live center's observable
  last-write-wins state for identifier-scoped-replacement assertions.

## 未決 (Open questions)

- **Platform floor** — confirm iOS 26 / macOS 26 (matched siblings + task) vs the
  proposal's iOS 18 / macOS 15 lean. Default picked: 26. Risk if wrong: a one-line
  Package.swift change, no source impact.
