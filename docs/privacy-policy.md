# Sudoku — Privacy Policy

Last updated: 2026-05-20
Applies to: Sudoku for iPhone and Mac, version 1.0 and later.

This is the public privacy policy for the Sudoku App developed by Wei (`@wei18` on GitHub). It mirrors the declarations in [`App/Resources/PrivacyInfo.xcprivacy`](../App/Resources/PrivacyInfo.xcprivacy). If the two ever disagree, the manifest is the source of truth and this document will be updated to match.

## Short version

- We do not collect personal information.
- We do not use any third-party analytics, advertising, or tracking SDKs.
- We do not operate our own servers. Your saves and statistics live in your own iCloud Private Database, accessible only by you and not by us.
- Game Center scores and achievements are handled by Apple under Apple's own privacy terms.
- No advertising identifier (IDFA) is requested; no App Tracking Transparency prompt appears.

## Data we collect

**None linked to you. None not linked to you. None tracked.**

In Apple's App Store privacy taxonomy:

- **Data Linked to You**: None.
- **Data Not Linked to You**: None.
- **Data Used to Track You**: None.

This is reflected in the App Store privacy label and in `PrivacyInfo.xcprivacy`:

- `NSPrivacyTracking` = `false`
- `NSPrivacyTrackingDomains` = empty
- `NSPrivacyCollectedDataTypes` = empty
- `NSPrivacyAccessedAPITypes` = empty

## Where your gameplay data lives

- **CloudKit Private Database (your iCloud account)**: in-progress board states, completed puzzle records, per-difficulty statistics, and preferences. Apple stores this in the iCloud account you are signed into on the device. We have no access to it. You can delete it at any time via *Settings → [Your Name] → iCloud → Manage Account Storage → Sudoku*.
- **Game Center (Apple)**: when you complete a Daily puzzle, your time is submitted to Apple's Game Center as a leaderboard score, and matching achievements may unlock. This is mediated entirely by Apple under Apple's Game Center privacy practices. You can disable Game Center for the App in *Settings → Game Center*.
- **On-device only**: undo/redo history, current session timer state.

## Diagnostics handled by Apple

The App relies on platform-level diagnostic channels that Apple operates. We do not run our own. You can opt out of each via the iOS / macOS Settings app.

- **MetricKit / Power & Performance**: aggregated crash, hang, launch time, and energy data. Visible to us only via App Store Connect's *Power & Performance* dashboard, in anonymized form. Controlled by *Settings → Privacy & Security → Analytics & Improvements → Share With App Developers*.
- **TestFlight beta crash reports** (TestFlight builds only): standard Apple beta diagnostics.
- **sysdiagnose**: only uploaded when you explicitly share one via Feedback Assistant. Private string interpolation in our logs is redacted by Apple before sharing.

## Third-party services

None embedded. We do not integrate Firebase, Mixpanel, Adjust, AppsFlyer, Sentry, Crashlytics, TelemetryDeck, or any analogous SDK. You can verify this in the open-source repository at <https://github.com/wei18/Sudoku> by searching for `import` statements.

## Children

The App does not knowingly collect any data, from children or from anyone. Age-appropriate; rating 4+.

## Changes to this policy

If we change data practices in a future version, we will update this document and the `PrivacyInfo.xcprivacy` manifest together in the same release, and note the change in the App Store *What's New* text for that version.

## Contact

- Issues and questions: <https://github.com/wei18/Sudoku/issues>
- Source code (this policy and the privacy manifest both live in the repo): <https://github.com/wei18/Sudoku>
