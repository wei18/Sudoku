// `ASCRegister preflight` — READ-ONLY submission readiness gate + optional
// `--fix` for the handful of items that are safe to auto-fill (copyright,
// releaseType, attaching the newest processed build). Wires
// ASCClient+Preflight.swift's GETs to Preflight.swift's pure PASS/BLOCK
// evaluation. See `mise-tasks/preflight/submission` for the bash entry point
// and `.claude/skills/asc-ops-handoff/SKILL.md` for the ops writeup.
//
// Split from main.swift to keep that file's `type_body_length` / actor body
// from growing further (mirrors the ASCClient+*.swift file-split precedent).

import Foundation

extension ASCRegisterCLI {

    // MARK: - Entry point

    internal static func runPreflight(args: [String]) async throws {
        let opts = Options.parse(args)
        let keyPath = try opts.required("key")
        let keyId = try opts.required("key-id")
        let issuer = try opts.required("issuer")
        let appName = try opts.required("app")
        let metadataDir = opts["metadata-dir"] ?? "docs/app-store/metadata"
        let isFix = opts.has("fix")

        guard let app = MetadataApp(rawValue: appName) else {
            throw CLIError.invalidValue(flag: "--app", value: appName, allowed: MetadataApp.allCases.map(\.rawValue))
        }
        let platform = try parsePlatform(opts)
        let config = try MetadataConfig.load(app: app, metadataDir: metadataDir)

        guard let appId = opts["app-id"] ?? config.appMeta.appleId else {
            print("preflight: app '\(app.rawValue)' has no apple_id in app-meta.yaml and no --app-id given "
                + "— no ASC app to check. Create the app in ASC first (user-owned), then re-run with --app-id.")
            return
        }

        let keyURL = URL(fileURLWithPath: keyPath)
        guard let pem = try? String(contentsOf: keyURL, encoding: .utf8) else {
            throw CLIError.cannotReadFile(keyPath)
        }
        // GETs run regardless of mode; `mode` only gates the `--fix` PATCHes
        // via `mutate()` — .plan there would print-and-skip, .apply sends.
        let client = ASCClient(auth: ASCClient.Auth(keyId: keyId, issuerId: issuer, keyPEM: pem), mode: .apply)

        print("=== preflight: \(app.rawValue) app-id \(appId) --platform \(platform.rawValue) "
            + "\(isFix ? "(--fix ENABLED)" : "(read-only)") ===")

        let appLevel = try await fetchAppLevelSnapshot(client: client, appId: appId, app: app)
        var allRows = Preflight.evaluateAppLevel(appLevel)

        let versionsResponse = try await client.listAppStoreVersions(appId: appId)
        let outcome = PlatformVersionResolver.resolve(
            versions: platformVersions(from: versionsResponse.data), filter: platform, versionFilter: nil
        )
        var versionSnapshots: [VersionSnapshot] = []
        for resolved in outcome.resolved {
            versionSnapshots.append(try await fetchVersionSnapshot(
                client: client, resolved: resolved, config: config
            ))
        }
        for skipped in outcome.skipped {
            versionSnapshots.append(VersionSnapshot(
                platform: skipped.platform, versionId: nil, versionString: nil, versionState: nil,
                isEditable: false, copyright: nil, releaseType: nil, buildAttached: false,
                reviewDetailExists: false, reviewDetailContactComplete: false, missingScreenshotSlots: []
            ))
        }

        for snapshot in versionSnapshots.sorted(by: { $0.platform < $1.platform }) {
            allRows.append(contentsOf: Preflight.evaluateVersion(snapshot, expectedCopyright: config.appMeta.copyright))
        }

        printReport(allRows)

        if isFix {
            try await applyFix(
                client: client, versionSnapshots: versionSnapshots, appId: appId, config: config
            )
        }

        if allRows.contains(where: { $0.status == .block }) {
            throw CLIError.validationFailed
        }
    }

    /// Print the PASS/BLOCK/MANUAL-VERIFY table, widest-item-aligned.
    private static func printReport(_ rows: [PreflightRow]) {
        let width = rows.map(\.item.count).max() ?? 0
        for row in rows {
            let padded = row.item.padding(toLength: width, withPad: " ", startingAt: 0)
            print("\(row.status.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(padded)  \(row.detail)")
        }
        let blocks = rows.filter { $0.status == .block }.count
        let manual = rows.filter { $0.status == .manualVerify }.count
        print("--- \(rows.count) check(s): \(blocks) BLOCK, \(manual) MANUAL-VERIFY, "
            + "\(rows.count - blocks - manual) PASS ---")
    }

    // MARK: - App-level fetch

    private static func fetchAppLevelSnapshot(
        client: ASCClient, appId: String, app: MetadataApp
    ) async throws -> AppLevelSnapshot {
        let appResource = try await client.getApp(appId: appId)
        let contentRightsSet = !(appResource.attributes["contentRightsDeclaration"] ?? "").isEmpty

        let priceSchedule = try await client.getAppPriceSchedule(appId: appId)

        let appInfos = try await client.listAppInfos(appId: appId)
        var ageRatingAnswered = 0
        if let editableInfo = editableAppInfo(from: appInfos) {
            if let declaration = try await client.getAgeRatingDeclaration(appInfoId: editableInfo.id) {
                ageRatingAnswered = declaration.attributes.count
            }
        }

        let reviewSubmissions = try await client.listReviewSubmissions(appId: appId)
            .map { ReviewSubmissionSummary(
                id: $0.id, platform: $0.attributes["platform"] ?? "?", state: $0.attributes["state"] ?? "?"
            ) }

        var iapProductId: String?
        var iapState: String?
        var iapScreenshotPresent: Bool?
        let bundlePrefix = "com.wei18.\(app.rawValue)."
        if let iap = Config.iaps.first(where: { $0.productId.hasPrefix(bundlePrefix) }) {
            let bundle = try await client.listIAPs(appId: appId)
            if let resource = bundle.data.first(where: { $0.attributes["productId"] == iap.productId }) {
                iapProductId = iap.productId
                iapState = resource.attributes["state"]
                iapScreenshotPresent = try await client.getIAPReviewScreenshot(iapId: resource.id) != nil
            } else {
                // Registered in Config but not yet created in ASC — surfaced
                // as MISSING rather than silently absent from the report.
                iapProductId = iap.productId
                iapState = "NOT_CREATED"
                iapScreenshotPresent = false
            }
        }

        return AppLevelSnapshot(
            contentRightsDeclarationSet: contentRightsSet,
            priceScheduleExists: priceSchedule != nil,
            ageRatingAnsweredCount: ageRatingAnswered,
            reviewSubmissions: reviewSubmissions,
            iapProductId: iapProductId,
            iapState: iapState,
            iapReviewScreenshotPresent: iapScreenshotPresent
        )
    }

    /// Same editable-state preference as `snapshotMetadata` (ASCClient+Metadata
    /// callers): prefer an appInfo in an editable state, else the first.
    private static func editableAppInfo(from appInfos: APICollectionWithIncluded) -> APIResource? {
        let editableStates: Set<String> = [
            "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW",
        ]
        return appInfos.data.first { info in
            let state = info.attributes["state"] ?? info.attributes["appStoreState"] ?? ""
            return editableStates.contains(state)
        } ?? appInfos.data.first
    }

    // MARK: - Per-platform version fetch

    private static func fetchVersionSnapshot(
        client: ASCClient,
        resolved: PlatformVersionResolver.Resolved,
        config: MetadataConfig
    ) async throws -> VersionSnapshot {
        let version = resolved.version
        let isEditable = SetVersionResolver.editableVersionStates.contains(version.state)

        let build = try await client.getAttachedBuild(versionId: version.id)
        let reviewDetail = try await client.getAppStoreReviewDetail(versionId: version.id)
        let contactComplete = reviewDetail.map { detail in
            !(detail.attributes["contactEmail"] ?? "").isEmpty
                && !(detail.attributes["contactFirstName"] ?? "").isEmpty
                && !(detail.attributes["contactLastName"] ?? "").isEmpty
                && !(detail.attributes["contactPhone"] ?? "").isEmpty
        } ?? false

        let missingSlots = try await missingScreenshotSlots(
            client: client, versionId: version.id, platformToken: resolved.platform, config: config
        )

        // `copyright` is app-level (attributes.copyright on appStoreVersion,
        // shared read via getAttachedBuild/getAppStoreReviewDetail's sibling —
        // reuse the `versions` collection already fetched by the caller would
        // need threading through; simplest correct read is one extra GET of
        // just this version's own attributes.
        let versionResource = try await client.getResource(
            path: "/v1/appStoreVersions/\(version.id)?fields[appStoreVersions]=copyright,releaseType"
        )

        return VersionSnapshot(
            platform: resolved.platform,
            versionId: version.id,
            versionString: version.versionString,
            versionState: version.state,
            isEditable: isEditable,
            copyright: versionResource.attributes["copyright"],
            releaseType: versionResource.attributes["releaseType"],
            buildAttached: build != nil,
            reviewDetailExists: reviewDetail != nil,
            reviewDetailContactComplete: contactComplete,
            missingScreenshotSlots: missingSlots
        )
    }

    /// For every locale that carries listing text (per app-meta's committed
    /// YAML), check its ASC version-localization has a COMPLETE screenshot for
    /// every device class in scope for `platformToken`. A locale with listing
    /// text but no matching version-localization at all is reported as a gap
    /// for every in-scope device class.
    private static func missingScreenshotSlots(
        client: ASCClient,
        versionId: String,
        platformToken: String,
        config: MetadataConfig
    ) async throws -> [String] {
        let requiredDevices = ScreenshotDevice.allCases.filter { device in
            device.platform.ascTokens.contains(platformToken)
        }
        guard !requiredDevices.isEmpty else { return [] }

        let locs = try await client.listVersionLocalizations(versionId: versionId)
        let locByLocale = Dictionary(uniqueKeysWithValues: locs.compactMap { loc -> (String, APIResource)? in
            guard let locale = loc.attributes["locale"] else { return nil }
            return (locale, loc)
        })

        var missing: [String] = []
        for listing in config.listings {
            guard let loc = locByLocale[listing.locale] else {
                missing.append(contentsOf: requiredDevices.map { "\(listing.locale)/\($0.displayType) (no version-localization)" })
                continue
            }
            let sets = try await client.listScreenshotSets(versionLocalizationId: loc.id)
            let completeDisplayTypes = Set(sets.data.compactMap { set -> String? in
                let shotIds = sets.relationships[set.id]?["appScreenshots"] ?? []
                let hasComplete = shotIds.contains { id in
                    sets.included.first { $0.id == id }?.attributes["assetDeliveryState"] == "COMPLETE"
                }
                return hasComplete ? set.attributes["screenshotDisplayType"] : nil
            })
            for device in requiredDevices where !completeDisplayTypes.contains(device.displayType) {
                missing.append("\(listing.locale)/\(device.displayType)")
            }
        }
        return missing
    }

    // MARK: - `--fix`

    /// Push the handful of items that are safe to auto-fill: `copyright`
    /// (from app-meta.yaml), `releaseType=MANUAL`, and attaching the newest
    /// VALID build for that platform. Never touches pricing/availability, age
    /// rating, content rights, or review-contact details (decisions or PII —
    /// see the dispatch brief). Skips a version this couldn't resolve
    /// (`versionId == nil`) entirely.
    private static func applyFix(
        client: ASCClient, versionSnapshots: [VersionSnapshot], appId: String, config: MetadataConfig
    ) async throws {
        var recentBuilds: APICollectionWithIncluded?
        for snapshot in versionSnapshots {
            guard let versionId = snapshot.versionId else { continue }
            let fixCopyright: String? = {
                guard let want = config.appMeta.copyright, !want.isEmpty else { return nil }
                return (snapshot.copyright ?? "").isEmpty ? want : nil
            }()
            let fixReleaseType: String? = snapshot.releaseType == "MANUAL" ? nil : "MANUAL"

            var attachBuildId: String?
            if !snapshot.buildAttached {
                if recentBuilds == nil {
                    recentBuilds = try await client.listRecentBuildsWithPlatform(appId: appId)
                }
                attachBuildId = newestValidBuild(in: recentBuilds, platformToken: snapshot.platform)?.id
            }

            guard fixCopyright != nil || fixReleaseType != nil || attachBuildId != nil else {
                print("--fix [\(snapshot.platform)]: nothing to fix.")
                continue
            }
            _ = try await client.fixAppStoreVersion(
                versionId: versionId, copyright: fixCopyright, releaseType: fixReleaseType,
                attachBuildId: attachBuildId
            )
            var applied: [String] = []
            if let fixCopyright { applied.append("copyright=\"\(fixCopyright)\"") }
            if let fixReleaseType { applied.append("releaseType=\(fixReleaseType)") }
            if let attachBuildId { applied.append("build=\(attachBuildId)") }
            print("--fix [\(snapshot.platform)]: applied \(applied.joined(separator: ", ")). "
                + "Re-run without --fix to verify.")
        }
    }

    /// Newest `VALID` build whose `preReleaseVersion.platform` matches
    /// `platformToken`, from a `listRecentBuildsWithPlatform` response
    /// (already sorted `-uploadedDate` by the caller's GET).
    private static func newestValidBuild(
        in collection: APICollectionWithIncluded?, platformToken: String
    ) -> APIResource? {
        guard let collection else { return nil }
        let prereleaseById = Dictionary(uniqueKeysWithValues: collection.included.map { ($0.id, $0) })
        return collection.data.first { build in
            guard build.attributes["processingState"] == "VALID" else { return false }
            guard let prereleaseId = collection.relationships[build.id]?["preReleaseVersion"]?.first else {
                return false
            }
            return prereleaseById[prereleaseId]?.attributes["platform"] == platformToken
        }
    }
}
