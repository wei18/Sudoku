// PreflightTests — pure unit coverage for Preflight.swift's PASS/BLOCK/
// MANUAL-VERIFY evaluation (the submission preflight gate, ops issue: nothing
// in the repo tracked ASC submission prerequisites). No network — every case
// feeds a synthetic snapshot straight to `Preflight.evaluate*`, mirroring
// ReconcilerTests' pure-function coverage style.

internal import Testing
@testable import ASCRegister

@Suite("Preflight evaluation")
internal struct PreflightTests {

    // MARK: - App-level

    private static func appLevel(
        contentRights: Bool = true,
        priceSchedule: Bool = true,
        ageRatingMissing: [String] = [],
        submissions: [ReviewSubmissionSummary] = [],
        iapProductId: String? = nil,
        iapState: String? = nil,
        iapScreenshot: Bool? = nil
    ) -> AppLevelSnapshot {
        AppLevelSnapshot(
            contentRightsDeclarationSet: contentRights,
            priceScheduleExists: priceSchedule,
            ageRatingMissingFields: ageRatingMissing,
            reviewSubmissions: submissions,
            iapProductId: iapProductId,
            iapState: iapState,
            iapReviewScreenshotPresent: iapScreenshot
        )
    }

    @Test("all-green app-level snapshot has zero BLOCK rows")
    internal func appLevelAllGreen() {
        let rows = Preflight.evaluateAppLevel(Self.appLevel())
        #expect(rows.filter { $0.status == .block }.isEmpty)
        // App Privacy is always MANUAL-VERIFY — never silently PASS.
        #expect(rows.contains { $0.item == "App Privacy questionnaire" && $0.status == .manualVerify })
    }

    @Test("no app price schedule → BLOCK (STATE_ERROR.APP_PRICING_REQUIRED)")
    internal func missingPriceScheduleBlocks() {
        let rows = Preflight.evaluateAppLevel(Self.appLevel(priceSchedule: false))
        let row = rows.first { $0.item == "app price schedule" }
        #expect(row?.status == .block)
        #expect(row?.detail.contains("APP_PRICING_REQUIRED") == true)
    }

    @Test("contentRightsDeclaration never answered → BLOCK")
    internal func missingContentRightsBlocks() {
        let rows = Preflight.evaluateAppLevel(Self.appLevel(contentRights: false))
        #expect(rows.first { $0.item == "contentRightsDeclaration" }?.status == .block)
    }

    @Test("ageRatingDeclaration with every expected field missing → BLOCK, names them all")
    internal func emptyAgeRatingBlocks() {
        let rows = Preflight.evaluateAppLevel(
            Self.appLevel(ageRatingMissing: Preflight.expectedAgeRatingFields.sorted())
        )
        let row = rows.first { $0.item == "ageRatingDeclaration" }
        #expect(row?.status == .block)
        #expect(row?.detail.contains("missing \(Preflight.expectedAgeRatingFields.count)") == true)
    }

    /// The CR finding this whole change exists for: someone answers 3 of ~24
    /// fields and stops. The OLD `attributes.count > 0` logic read this as a
    /// clean PASS — a false pass a submission gate must never produce.
    @Test("ageRatingDeclaration PARTIALLY answered → still BLOCK, names only the still-missing fields")
    internal func partiallyAnsweredAgeRatingStillBlocks() {
        // Picked so none is a substring of another expected field name
        // (e.g. "gambling" ⊂ "gamblingSimulated" would false-positive the
        // `contains` check below) — a pure test-fixture concern, not a
        // production code issue.
        let answered: [String] = ["advertising", "contests", "parentalControls"]
        let stillMissing = Preflight.expectedAgeRatingFields.subtracting(answered)
        let rows = Preflight.evaluateAppLevel(Self.appLevel(ageRatingMissing: stillMissing.sorted()))
        let row = rows.first { $0.item == "ageRatingDeclaration" }
        #expect(row?.status == .block)
        // Every still-missing field is named; none of the 3 answered fields are.
        for field in stillMissing { #expect(row?.detail.contains(field) == true) }
        for field in answered { #expect(row?.detail.contains(field) == false) }
    }

    @Test("ageRatingDeclaration with an UNKNOWN extra key present → still PASS (schema drift tolerated)")
    internal func unknownAgeRatingKeyDoesNotBlock() {
        // `ageRatingMissing: []` — every EXPECTED field is answered; an extra
        // key ASC might add later is invisible to this snapshot shape by
        // construction (only ABSENCE of an expected key is tracked), which is
        // exactly the "don't fail on keys you don't know about" requirement.
        let rows = Preflight.evaluateAppLevel(Self.appLevel(ageRatingMissing: []))
        #expect(rows.first { $0.item == "ageRatingDeclaration" }?.status == .pass)
    }

    @Test("a non-COMPLETE reviewSubmission is a stray → BLOCK, annotated as app-wide")
    internal func strayReviewSubmissionBlocks() {
        let rows = Preflight.evaluateAppLevel(Self.appLevel(submissions: [
            ReviewSubmissionSummary(id: "rs-1", platform: "IOS", state: "READY_FOR_REVIEW"),
        ]))
        let row = rows.first { $0.item.hasPrefix("reviewSubmissions clean") }
        #expect(row?.status == .block)
        #expect(row?.item.contains("app-wide") == true)
        #expect(row?.detail.contains("READY_FOR_REVIEW") == true)
        #expect(row?.detail.contains("IOS") == true)
    }

    @Test("a COMPLETE reviewSubmission is not a stray → PASS")
    internal func completeReviewSubmissionPasses() {
        let rows = Preflight.evaluateAppLevel(Self.appLevel(submissions: [
            ReviewSubmissionSummary(id: "rs-1", platform: "IOS", state: "COMPLETE"),
        ]))
        #expect(rows.first { $0.item.hasPrefix("reviewSubmissions clean") }?.status == .pass)
    }

    @Test("IAP registered but review screenshot missing → BLOCK; row absent when no IAP configured")
    internal func iapReviewScreenshotRow() {
        let missing = Preflight.evaluateAppLevel(Self.appLevel(
            iapProductId: "com.wei18.sudoku.iap.remove_ads", iapState: "READY_TO_SUBMIT", iapScreenshot: false
        ))
        #expect(missing.first { $0.item == "IAP review screenshot" }?.status == .block)

        let present = Preflight.evaluateAppLevel(Self.appLevel(
            iapProductId: "com.wei18.sudoku.iap.remove_ads", iapState: "READY_TO_SUBMIT", iapScreenshot: true
        ))
        #expect(present.first { $0.item == "IAP review screenshot" }?.status == .pass)

        let noIAP = Preflight.evaluateAppLevel(Self.appLevel())
        #expect(!noIAP.contains { $0.item == "IAP review screenshot" })
    }

    // MARK: - Version-level

    private static func version(
        versionId: String? = "v-1",
        state: String = "PREPARE_FOR_SUBMISSION",
        copyright: String? = "2026 Wei18",
        releaseType: String? = "MANUAL",
        buildAttached: Bool = true,
        reviewDetailExists: Bool = true,
        reviewDetailContactComplete: Bool = true,
        missingSlots: [String] = []
    ) -> VersionSnapshot {
        VersionSnapshot(
            platform: "IOS", versionId: versionId, versionString: "2.6", versionState: state,
            isEditable: SetVersionResolver.editableVersionStates.contains(state),
            copyright: copyright, releaseType: releaseType, buildAttached: buildAttached,
            reviewDetailExists: reviewDetailExists, reviewDetailContactComplete: reviewDetailContactComplete,
            missingScreenshotSlots: missingSlots
        )
    }

    @Test("all-green version snapshot has zero BLOCK rows")
    internal func versionAllGreen() {
        let rows = Preflight.evaluateVersion(Self.version(), expectedCopyright: "2026 Wei18")
        #expect(rows.filter { $0.status == .block }.isEmpty)
    }

    @Test("no appStoreVersion at all → single BLOCK row, no further checks")
    internal func missingVersionShortCircuits() {
        let rows = Preflight.evaluateVersion(Self.version(versionId: nil), expectedCopyright: nil)
        #expect(rows.count == 1)
        #expect(rows[0].status == .block)
        #expect(rows[0].item.contains("appStoreVersion exists"))
    }

    @Test("releaseType AFTER_APPROVAL → BLOCK (would silently auto-release)")
    internal func afterApprovalReleaseTypeBlocks() {
        let rows = Preflight.evaluateVersion(Self.version(releaseType: "AFTER_APPROVAL"), expectedCopyright: nil)
        let row = rows.first { $0.item.contains("releaseType") }
        #expect(row?.status == .block)
        #expect(row?.detail.contains("auto-releases") == true)
    }

    @Test("no build attached → BLOCK")
    internal func noBuildAttachedBlocks() {
        let rows = Preflight.evaluateVersion(Self.version(buildAttached: false), expectedCopyright: nil)
        #expect(rows.first { $0.item.contains("build attached") }?.status == .block)
    }

    @Test("empty copyright → BLOCK, and names the app-meta.yaml value as the fix")
    internal func emptyCopyrightBlocksAndNamesFix() {
        let rows = Preflight.evaluateVersion(Self.version(copyright: nil), expectedCopyright: "2026 Wei18")
        let row = rows.first { $0.item.contains("copyright") }
        #expect(row?.status == .block)
        #expect(row?.detail.contains("2026 Wei18") == true)
    }

    @Test("no appStoreReviewDetail record → BLOCK; contact-complete row is skipped entirely")
    internal func missingReviewDetailSkipsContactRow() {
        let rows = Preflight.evaluateVersion(Self.version(reviewDetailExists: false), expectedCopyright: nil)
        #expect(rows.first { $0.item.contains("appStoreReviewDetail exists") }?.status == .block)
        #expect(!rows.contains { $0.item.contains("contact complete") })
    }

    @Test("appStoreReviewDetail exists but contact incomplete → BLOCK")
    internal func incompleteContactBlocks() {
        let rows = Preflight.evaluateVersion(
            Self.version(reviewDetailExists: true, reviewDetailContactComplete: false), expectedCopyright: nil
        )
        #expect(rows.first { $0.item.contains("contact complete") }?.status == .block)
    }

    @Test("a version that is not in an editable state → BLOCK")
    internal func lockedVersionBlocks() {
        let rows = Preflight.evaluateVersion(Self.version(state: "READY_FOR_SALE"), expectedCopyright: nil)
        #expect(rows.first { $0.item.contains("appStoreVersion editable") }?.status == .block)
    }

    @Test("missing screenshot slots → BLOCK, names every gap")
    internal func missingScreenshotsBlock() {
        let rows = Preflight.evaluateVersion(
            Self.version(missingSlots: ["en-US/APP_IPHONE_67", "ja/APP_IPAD_PRO_3GEN_129"]),
            expectedCopyright: nil
        )
        let row = rows.first { $0.item.contains("screenshots complete") }
        #expect(row?.status == .block)
        #expect(row?.detail.contains("en-US/APP_IPHONE_67") == true)
        #expect(row?.detail.contains("ja/APP_IPAD_PRO_3GEN_129") == true)
    }
}
