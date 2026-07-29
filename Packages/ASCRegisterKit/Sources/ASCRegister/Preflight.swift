// Preflight — pure PASS/BLOCK/MANUAL-VERIFY evaluation for the submission
// preflight gate (`ASCRegister preflight`, `mise run preflight:submission`).
//
// Born from a real submission attempt (2026-07-28) that hit NINE ASC-side
// prerequisites one at a time, each discovered only when a mutating call was
// already rejected: releaseType left at the auto-release default, no build
// attached, empty copyright, no price schedule (STATE_ERROR.APP_PRICING_
// REQUIRED), an unanswered age rating questionnaire, no content rights
// declaration, a missing App Review contact record, screenshots present for
// only 2 of 7 locales, and a stray non-cancellable reviewSubmission. This
// file is the pure, unit-testable evaluation core; ASCClient+Preflight.swift
// does the (read-only) fetching and main.swift's `runPreflight` wires the two
// together plus the `--fix` writes.
//
// No I/O here — every function is fed a snapshot struct so the PASS/BLOCK
// decisions are testable without a live API (mirrors Reconciler.plan /
// SetVersionResolver.choose).

import Foundation

// MARK: - Row / status

internal enum PreflightStatus: String, Sendable, Equatable {
    case pass = "PASS"
    case block = "BLOCK"
    case manualVerify = "MANUAL-VERIFY"
}

internal struct PreflightRow: Sendable, Equatable {
    internal let item: String
    internal let status: PreflightStatus
    internal let detail: String
}

// MARK: - Snapshots (fed by ASCClient+Preflight.swift GETs)

internal struct ReviewSubmissionSummary: Sendable, Equatable {
    internal let id: String
    internal let platform: String
    internal let state: String
}

/// Facts that live on the App / AppInfo resource — NOT per platform version.
internal struct AppLevelSnapshot: Sendable, Equatable {
    internal let contentRightsDeclarationSet: Bool
    internal let priceScheduleExists: Bool
    /// Expected `ageRatingDeclaration` fields (`Preflight.expectedAgeRatingFields`)
    /// with NO value in the fetched declaration — empty means fully answered.
    internal let ageRatingMissingFields: [String]
    internal let reviewSubmissions: [ReviewSubmissionSummary]
    internal let iapProductId: String?
    internal let iapState: String?
    internal let iapReviewScreenshotPresent: Bool?
}

/// Facts scoped to ONE platform's `appStoreVersion`.
internal struct VersionSnapshot: Sendable, Equatable {
    internal let platform: String   // ASC token, e.g. "IOS" / "MAC_OS"
    internal let versionId: String?
    internal let versionString: String?
    internal let versionState: String?
    internal let isEditable: Bool
    internal let copyright: String?
    internal let releaseType: String?
    internal let buildAttached: Bool
    internal let reviewDetailExists: Bool
    internal let reviewDetailContactComplete: Bool
    /// `"<locale>/<screenshotDisplayType>"` entries with no COMPLETE asset,
    /// restricted to locales that carry listing text (a locale with no
    /// storefront copy is out of scope for this version, not a gap).
    internal let missingScreenshotSlots: [String]
}

// MARK: - Evaluation

internal enum Preflight {

    /// A `reviewSubmissions` state counts as safely out of the way once it
    /// reaches `COMPLETE` — every other documented state (including the
    /// transitional `CANCELING`/`COMPLETING`) still blocks creating a new
    /// submission per the live 2026-07-28 finding (a `READY_FOR_REVIEW` MS
    /// submission could be neither deleted nor cancelled outside an in-review
    /// state).
    internal static let terminalReviewStates: Set<String> = ["COMPLETE"]

    /// The exact `ageRatingDeclaration` field set both apps successfully
    /// PATCHed on 2026-07-28 — 13 enum descriptors + 11 booleans. Pinned
    /// explicitly (CR finding, PR #970) rather than "any field answered":
    /// `attributes.count > 0` reads a PARTIAL fill (someone answers 3 of ~25
    /// and stops) as a clean PASS, which is a false pass a submission gate
    /// must not produce. BLOCK names every field still absent; an unknown key
    /// in the payload (schema drift) is ignored, never causes a false BLOCK —
    /// only the ABSENCE of an expected key blocks.
    internal static let expectedAgeRatingFields: Set<String> = [
        // Enum descriptors (NONE / INFREQUENT_OR_MILD / FREQUENT_OR_INTENSE, …).
        "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated",
        "gunsOrOtherWeapons", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
        "sexualContentGraphicAndNudity", "sexualContentOrNudity", "horrorOrFearThemes",
        "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
        "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic",
        // Booleans.
        "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
        "parentalControls", "ageAssurance", "socialMedia", "socialMediaAgeRestricted",
        "unrestrictedWebAccess", "userGeneratedContent", "advertising",
    ]

    /// App-level rows: contentRightsDeclaration, price schedule, age rating,
    /// stray reviewSubmissions, IAP review screenshot, App Privacy
    /// (always MANUAL-VERIFY — Apple exposes no API for it).
    internal static func evaluateAppLevel(_ snap: AppLevelSnapshot) -> [PreflightRow] {
        var rows: [PreflightRow] = []

        rows.append(PreflightRow(
            item: "contentRightsDeclaration",
            status: snap.contentRightsDeclarationSet ? .pass : .block,
            detail: snap.contentRightsDeclarationSet
                ? "set" : "never answered on the App resource — required before submit"
        ))

        rows.append(PreflightRow(
            item: "app price schedule",
            status: snap.priceScheduleExists ? .pass : .block,
            detail: snap.priceScheduleExists
                ? "price schedule present"
                : "no price schedule set — ASC refuses submission with "
                    + "STATE_ERROR.APP_PRICING_REQUIRED (web UI: Pricing and Availability)"
        ))

        rows.append(PreflightRow(
            item: "ageRatingDeclaration",
            status: snap.ageRatingMissingFields.isEmpty ? .pass : .block,
            detail: snap.ageRatingMissingFields.isEmpty
                ? "all \(Preflight.expectedAgeRatingFields.count) expected field(s) answered"
                : "missing \(snap.ageRatingMissingFields.count)/\(Preflight.expectedAgeRatingFields.count): "
                    + snap.ageRatingMissingFields.joined(separator: ", ")
        ))

        // App-wide, not scoped to the `--platform` filter this run was given —
        // a stray on one platform still blocks creating a NEW submission on
        // any platform, so the row (and its detail) says so explicitly.
        let strays = snap.reviewSubmissions.filter { !Preflight.terminalReviewStates.contains($0.state) }
        rows.append(PreflightRow(
            item: "reviewSubmissions clean (app-wide, not platform-scoped)",
            status: strays.isEmpty ? .pass : .block,
            detail: strays.isEmpty
                ? "no in-flight/stray submission on any platform"
                : "stray submission(s) block creating ANY new reviewSubmission for this app, "
                    + "regardless of --platform: "
                    + strays.map { "\($0.platform):\($0.state) (id=\($0.id))" }.joined(separator: "; ")
        ))

        if let productId = snap.iapProductId {
            let present = snap.iapReviewScreenshotPresent == true
            rows.append(PreflightRow(
                item: "IAP review screenshot",
                status: present ? .pass : .block,
                detail: "\(productId) state=\(snap.iapState ?? "?") screenshot="
                    + (present ? "present" : "MISSING")
            ))
        }

        rows.append(PreflightRow(
            item: "App Privacy questionnaire",
            status: .manualVerify,
            detail: "Apple exposes NO ASC REST API for App Privacy — verify by hand against "
                + "PrivacyInfo.xcprivacy before submitting"
        ))

        return rows
    }

    /// Per-platform rows: version exists + editable, releaseType, build
    /// attached, copyright, appStoreReviewDetail existence + contact
    /// completeness, screenshot coverage. A missing version short-circuits
    /// the rest of the per-platform rows — nothing else is meaningful
    /// without one.
    internal static func evaluateVersion(_ snapshot: VersionSnapshot, expectedCopyright: String?) -> [PreflightRow] {
        guard let versionId = snapshot.versionId else {
            return [PreflightRow(
                item: "[\(snapshot.platform)] appStoreVersion exists",
                status: .block,
                detail: "no appStoreVersion found for platform \(snapshot.platform)"
            )]
        }

        var rows: [PreflightRow] = [PreflightRow(
            item: "[\(snapshot.platform)] appStoreVersion editable",
            status: snapshot.isEditable ? .pass : .block,
            detail: "id=\(versionId) version=\(snapshot.versionString ?? "?") state=\(snapshot.versionState ?? "?")"
        )]

        rows.append(PreflightRow(
            item: "[\(snapshot.platform)] releaseType",
            status: snapshot.releaseType == "MANUAL" ? .pass : .block,
            detail: "releaseType=\(snapshot.releaseType ?? "nil") (want MANUAL — AFTER_APPROVAL "
                + "silently auto-releases the instant Apple approves)"
        ))

        rows.append(PreflightRow(
            item: "[\(snapshot.platform)] build attached",
            status: snapshot.buildAttached ? .pass : .block,
            detail: snapshot.buildAttached ? "build attached" : "no build attached to this version"
        ))

        let copyrightOK = !(snapshot.copyright ?? "").isEmpty
        var copyrightDetail = "copyright=\"\(snapshot.copyright ?? "")\""
        if !copyrightOK, let expectedCopyright {
            copyrightDetail += " — app-meta.yaml has \"\(expectedCopyright)\" (run --fix to push it)"
        }
        rows.append(PreflightRow(
            item: "[\(snapshot.platform)] copyright", status: copyrightOK ? .pass : .block, detail: copyrightDetail
        ))

        rows.append(PreflightRow(
            item: "[\(snapshot.platform)] appStoreReviewDetail exists",
            status: snapshot.reviewDetailExists ? .pass : .block,
            detail: snapshot.reviewDetailExists
                ? "record exists" : "no App Review contact record at all — create it (user-owned, PII)"
        ))
        if snapshot.reviewDetailExists {
            rows.append(PreflightRow(
                item: "[\(snapshot.platform)] appStoreReviewDetail contact complete",
                status: snapshot.reviewDetailContactComplete ? .pass : .block,
                detail: snapshot.reviewDetailContactComplete
                    ? "contact name/email/phone present" : "missing contact name, email, or phone"
            ))
        }

        rows.append(PreflightRow(
            item: "[\(snapshot.platform)] screenshots complete",
            status: snapshot.missingScreenshotSlots.isEmpty ? .pass : .block,
            detail: snapshot.missingScreenshotSlots.isEmpty
                ? "every locale with listing text has every required device class"
                : "missing: \(snapshot.missingScreenshotSlots.joined(separator: ", "))"
        ))

        return rows
    }
}
