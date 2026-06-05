// ASCRegister — Game Center bootstrap CLI.
//
// Usage:
//   ASCRegister validate --xcstrings <path>
//   ASCRegister plan     --key <p8> --key-id <id> --issuer <id> --app-id <id> --xcstrings <path>
//   ASCRegister apply    --key <p8> --key-id <id> --issuer <id> --app-id <id> --xcstrings <path>
//
// `validate` runs purely locally: checks Config IDs match the production
// constants by inspection (covered by ConfigConsistencyTests) and that the
// xcstrings file parses + contains at least en + zh-Hant for every gc.* key.
//
// `plan` and `apply` both hit ASC; `plan` is dry-run (no mutations).
//
// No external deps — `swift-argument-parser` is deliberately avoided per
// dispatch constraints. The argv parser below is intentionally simple.

import Foundation

// swiftlint:disable identifier_name cyclomatic_complexity for_where file_length

// Top-level entry point. `main.swift` is special: it runs as the program's
// entry, so we can't use `@main` here (the two are mutually exclusive).
// `await` is allowed at top level since Swift 5.5.

internal enum ASCRegisterCLI {

    internal static func run() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let sub = args.first else {
            printUsage()
            exit(2)
        }
        let rest = Array(args.dropFirst())
        do {
            switch sub {
            case "validate":
                try runValidate(args: rest)
            case "plan":
                try await runRemote(args: rest, mode: .plan)
            case "apply":
                try await runRemote(args: rest, mode: .apply)
            case "inspect":
                try await runInspect(args: rest)
            case "iap":
                // `iap` is a nested subcommand (mirrors `leaderboard` /
                // `achievement` naming; issue #200 Phase 1.a).
                let subSub = rest.first ?? ""
                let rest2 = Array(rest.dropFirst())
                switch subSub {
                case "plan":  try await runIAPRemote(args: rest2, mode: .plan)
                case "apply": try await runIAPRemote(args: rest2, mode: .apply)
                default:
                    FileHandle.standardError.write(Data("Unknown iap subcommand: \(subSub)\n".utf8))
                    printUsage()
                    exit(2)
                }
            case "metadata":
                // App-listing metadata (issue #310). Nested subcommand,
                // mirrors `iap`. Reads docs/app-store/metadata YAML and
                // reconciles appInfoLocalizations + appStoreVersionLocalizations
                // + appInfos categories against ASC.
                let subSub = rest.first ?? ""
                let rest2 = Array(rest.dropFirst())
                switch subSub {
                case "plan":  try await runMetadataRemote(args: rest2, mode: .plan)
                case "apply": try await runMetadataRemote(args: rest2, mode: .apply)
                case "set-version": try await runMetadataSetVersion(args: rest2)
                default:
                    FileHandle.standardError.write(Data("Unknown metadata subcommand: \(subSub)\n".utf8))
                    printUsage()
                    exit(2)
                }
            case "-h", "--help", "help":
                printUsage()
            default:
                FileHandle.standardError.write(Data("Unknown subcommand: \(sub)\n".utf8))
                printUsage()
                exit(2)
            }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(1)
        }
    }

    // MARK: - validate

    private static func runValidate(args: [String]) throws {
        let opts = Options.parse(args)
        guard let xcstringsPath = opts["xcstrings"] else {
            throw CLIError.missingFlag("--xcstrings")
        }
        // Optional `--app` (defaults to sudoku) selects the leaderboard set to
        // validate xcstrings coverage against.
        let appName = opts["app"] ?? Config.GCApp.sudoku.rawValue
        guard let gcApp = Config.GCApp(rawValue: appName) else {
            throw CLIError.invalidValue(
                flag: "--app", value: appName, allowed: Config.GCApp.allCases.map(\.rawValue)
            )
        }
        let url = URL(fileURLWithPath: xcstringsPath)
        let parsed = try XCStringsParser.parse(fileURL: url)

        // Validate Config sanity.
        let leaderboards = Config.leaderboards(for: gcApp)
        let lbIds = leaderboards.map(\.id)
        let achIds = Config.allAchievementShortIds
        let pointsSum = Config.totalAchievementPoints

        print("Config (\(gcApp.rawValue)):")
        print("  leaderboards (\(lbIds.count)):")
        for id in lbIds { print("    - \(id)") }
        print("  achievements (\(achIds.count), points=\(pointsSum)):")
        for ach in Config.achievements {
            print("    - \(ach.fullId)  [\(ach.points)pt]")
        }

        // Validate xcstrings coverage for en + zh-Hant on every expected key.
        let expectedKeys = expectedXCStringsKeys(leaderboards: leaderboards)
        var missing: [(String, String)] = []  // (locale, key)
        for locale in ["en", "zh-Hant"] {
            for key in expectedKeys {
                if parsed[locale]?[key] == nil {
                    missing.append((locale, key))
                }
            }
        }
        if missing.isEmpty {
            print("xcstrings: en + zh-Hant coverage OK (\(expectedKeys.count) keys each)")
        } else {
            print("xcstrings: MISSING entries:")
            for (loc, k) in missing {
                print("  - [\(loc)] \(k)")
            }
            throw CLIError.validationFailed
        }
    }

    // MARK: - plan / apply

    private static func runRemote(args: [String], mode: ASCClient.Mode) async throws {
        let opts = Options.parse(args)
        let keyPath = try opts.required("key")
        let keyId = try opts.required("key-id")
        let issuer = try opts.required("issuer")
        let appId = try opts.required("app-id")
        let xcstringsPath = try opts.required("xcstrings")

        let keyURL = URL(fileURLWithPath: keyPath)
        guard let pem = try? String(contentsOf: keyURL, encoding: .utf8) else {
            throw CLIError.cannotReadFile(keyPath)
        }
        let strings = try XCStringsParser.parse(fileURL: URL(fileURLWithPath: xcstringsPath))

        // `--app` selects the per-app leaderboard set (mirrors the metadata
        // command, #310). Defaults to `sudoku` so existing call sites are
        // unaffected. Achievements + IAPs are not app-split (see Config.GCApp).
        let appName = opts["app"] ?? Config.GCApp.sudoku.rawValue
        guard let gcApp = Config.GCApp(rawValue: appName) else {
            throw CLIError.invalidValue(
                flag: "--app", value: appName, allowed: Config.GCApp.allCases.map(\.rawValue)
            )
        }

        let client = ASCClient(
            auth: ASCClient.Auth(keyId: keyId, issuerId: issuer, keyPEM: pem),
            mode: mode
        )

        // 1. Resolve the gameCenterDetail id for this app.
        let detail = try await client.getGameCenterDetail(appId: appId)
        let detailId = detail.id

        // 2. Snapshot remote state.
        let remoteLBs = try await client.listLeaderboards(detailId: detailId)
        let remoteAchs = try await client.listAchievements(detailId: detailId)
        var remote = RemoteState()
        for lb in remoteLBs {
            if let vendor = lb.attributes["vendorIdentifier"] {
                remote.leaderboards[vendor] = lb.id
                let locs = try await client.listLeaderboardLocalizations(leaderboardId: lb.id)
                for loc in locs {
                    if let l = loc.attributes["locale"] {
                        remote.leaderboardLocalizations[
                            RemoteState.LocalizationKey(vendorId: vendor, locale: l)
                        ] = loc.id
                    }
                }
            }
        }
        for ach in remoteAchs {
            if let vendor = ach.attributes["vendorIdentifier"] {
                remote.achievements[vendor] = ach.id
                let locs = try await client.listAchievementLocalizations(achievementId: ach.id)
                for loc in locs {
                    if let l = loc.attributes["locale"] {
                        remote.achievementLocalizations[
                            RemoteState.LocalizationKey(vendorId: vendor, locale: l)
                        ] = loc.id
                    }
                }
            }
        }

        // 3. Plan. `--app` selects the leaderboard set; the achievement / IAP
        // slices are app-agnostic (see Config.GCApp). For `--app minesweeper`
        // the reconciler will also emit achievement actions from the (Sudoku)
        // achievement config — but MS's GC detail has none, so they surface as
        // CREATE actions. To keep `--app minesweeper` strictly leaderboard-
        // scoped, filter to leaderboard actions when targeting a non-sudoku app.
        let allActions = Reconciler.plan(
            config: .live(for: gcApp),
            strings: strings,
            remote: remote
        )
        let actions: [Action] = (gcApp == .sudoku)
            ? allActions
            : allActions.filter { action in
                switch action {
                case .createLeaderboard, .updateLeaderboard, .leaderboardUnchanged,
                     .createLeaderboardLocalization, .updateLeaderboardLocalization,
                     .leaderboardLocalizationUnchanged:
                    return true
                default:
                    return false
                }
            }

        // 4. Print plan summary; in `apply` also execute.
        print("Plan: \(actions.count) action(s) for \(gcApp.rawValue)")
        for action in actions {
            print("  \(describe(action))")
        }
        if mode == .apply {
            for action in actions {
                try await execute(action, client: client, detailId: detailId)
            }
            print("Applied.")
        }
    }

    private static func execute(
        _ action: Action,
        client: ASCClient,
        detailId: String,
        appId: String = ""
    ) async throws {
        switch action {
        case .createLeaderboard(let cfg):
            let startDate = LeaderboardConfig.nextRecurrenceStartDateUTC()
            _ = try await client.createLeaderboard(
                detailId: detailId,
                config: cfg,
                startDate: startDate
            )
        case .updateLeaderboard(let id, let cfg):
            _ = try await client.updateLeaderboard(leaderboardId: id, config: cfg)
        case .leaderboardUnchanged:
            break
        case .createLeaderboardLocalization(let vendorId, let locale, let title):
            // We need the ASC id for the leaderboard — look it up.
            // (In practice the caller already has it via remote state; for
            // simplicity we re-resolve here.)
            let lbs = try await client.listLeaderboards(detailId: detailId)
            if let lb = lbs.first(where: { $0.attributes["vendorIdentifier"] == vendorId }) {
                _ = try await client.createLeaderboardLocalization(
                    leaderboardId: lb.id, locale: locale, title: title
                )
            }
        case .updateLeaderboardLocalization(let locId, _, let title):
            _ = try await client.updateLeaderboardLocalization(localizationId: locId, title: title)
        case .leaderboardLocalizationUnchanged:
            break
        case .createAchievement(let cfg):
            _ = try await client.createAchievement(detailId: detailId, config: cfg)
        case .updateAchievement(let id, let cfg):
            _ = try await client.updateAchievement(achievementId: id, config: cfg)
        case .achievementUnchanged:
            break
        case .createAchievementLocalization(let vendorId, let locale, let title, let desc, let unearned):
            let achs = try await client.listAchievements(detailId: detailId)
            if let ach = achs.first(where: { $0.attributes["vendorIdentifier"] == vendorId }) {
                _ = try await client.createAchievementLocalization(
                    achievementId: ach.id,
                    locale: locale,
                    title: title,
                    description: desc,
                    unearnedDescription: unearned
                )
            }
        case .updateAchievementLocalization(let locId, _, let title, let desc, let unearned):
            _ = try await client.updateAchievementLocalization(
                localizationId: locId,
                title: title,
                description: desc,
                unearnedDescription: unearned
            )
        case .achievementLocalizationUnchanged:
            break
        case .updateIAP(let id, let product):
            _ = try await client.updateIAP(iapId: id, config: product)
        case .iapUnchanged:
            break
        case .createIAPLocalization(let iapId, _, let locale, let name, let description):
            // `iapId` is threaded through from RemoteState at plan time —
            // no per-action GET, no reliance on the defaulted `appId`.
            _ = try await client.createIAPLocalization(
                iapId: iapId, locale: locale, name: name, description: description
            )
        case .updateIAPLocalization(let locId, _, let name, let description):
            _ = try await client.updateIAPLocalization(
                localizationId: locId, name: name, description: description
            )
        case .iapLocalizationUnchanged:
            break
        }
    }

    private static func describe(_ action: Action) -> String {
        switch action {
        case .createLeaderboard(let c): return "CREATE leaderboard \(c.id)"
        case .updateLeaderboard(_, let c): return "UPDATE leaderboard \(c.id)"
        case .leaderboardUnchanged(let id): return "OK     leaderboard \(id)"
        case .createLeaderboardLocalization(let v, let l, _): return "CREATE leaderboard-loc \(v) [\(l)]"
        case .updateLeaderboardLocalization(_, let l, _): return "UPDATE leaderboard-loc [\(l)]"
        case .leaderboardLocalizationUnchanged(let v, let l): return "OK     leaderboard-loc \(v) [\(l)]"
        case .createAchievement(let c): return "CREATE achievement \(c.fullId)"
        case .updateAchievement(_, let c): return "UPDATE achievement \(c.fullId)"
        case .achievementUnchanged(let id): return "OK     achievement \(id)"
        case .createAchievementLocalization(let v, let l, _, _, _): return "CREATE achievement-loc \(v) [\(l)]"
        case .updateAchievementLocalization(_, let l, _, _, _): return "UPDATE achievement-loc [\(l)]"
        case .achievementLocalizationUnchanged(let v, let l): return "OK     achievement-loc \(v) [\(l)]"
        case .updateIAP(_, let p): return "UPDATE iap \(p.productId)"
        case .iapUnchanged(let p, _): return "OK     iap \(p)"
        case .createIAPLocalization(_, let p, let l, _, _): return "CREATE iap-loc \(p) [\(l)]"
        case .updateIAPLocalization(_, let l, _, _): return "UPDATE iap-loc [\(l)]"
        case .iapLocalizationUnchanged(let p, let l): return "OK     iap-loc \(p) [\(l)]"
        }
    }

    private static func expectedXCStringsKeys(
        leaderboards: [LeaderboardConfig] = Config.leaderboards
    ) -> [String] {
        var keys: [String] = []
        for lb in leaderboards {
            keys.append(lb.titleKey)
        }
        for ach in Config.achievements {
            keys.append(ach.titleKey)
            keys.append(ach.descriptionKey)
            keys.append(ach.unearnedDescriptionKey)
        }
        for iap in Config.iaps {
            keys.append(iap.nameKey)
            keys.append(iap.descriptionKey)
        }
        return keys
    }

    // swiftlint:disable line_length
    private static func printUsage() {
        print("""
        Usage:
          ASCRegister validate  --xcstrings <path> [--app <sudoku|minesweeper>]
          ASCRegister plan      --key <p8> --key-id <id> --issuer <id> --app-id <id> --xcstrings <path> [--app <sudoku|minesweeper>]
          ASCRegister apply     --key <p8> --key-id <id> --issuer <id> --app-id <id> --xcstrings <path> [--app <sudoku|minesweeper>]
          ASCRegister inspect   --key <p8> --key-id <id> --issuer <id> --app-id <id> --leaderboard <vendor-id>
          ASCRegister iap plan  --key <p8> --key-id <id> --issuer <id> --app-id <id> --xcstrings <path>
          ASCRegister iap apply --key <p8> --key-id <id> --issuer <id> --app-id <id> --xcstrings <path>
          ASCRegister metadata plan  --key <p8> --key-id <id> --issuer <id> --app <sudoku|minesweeper> [--app-id <id>] [--version <s>] [--platform ios|macos|all] [--metadata-dir <dir>]
          ASCRegister metadata apply --key <p8> --key-id <id> --issuer <id> --app <sudoku|minesweeper> [--app-id <id>] [--version <s>] [--platform ios|macos|all] [--metadata-dir <dir>]
          ASCRegister metadata set-version --key <p8> --key-id <id> --issuer <id> --app <sudoku|minesweeper> --version <string> [--platform ios|macos|all] [--app-id <id>]
        """)
    }
    // swiftlint:enable line_length

    // MARK: - metadata plan / apply (issue #310)
    // swiftlint:disable function_body_length

    /// App-listing metadata reconcile. Reads the `--app` subtree under
    /// `--metadata-dir`, snapshots remote ASC metadata (appInfos +
    /// appStoreVersions + appCategories), diffs per field, prints the plan,
    /// and in `apply` executes the per-field PATCH/POST.
    ///
    /// `--app-id` is optional: it defaults to the `apple_id` in the app's
    /// `app-meta.yaml`. Minesweeper omits `apple_id` (no ASC record yet), so
    /// `metadata plan --app minesweeper` exits cleanly with a notice rather
    /// than 404-crashing.
    private static func runMetadataRemote(args: [String], mode: ASCClient.Mode) async throws {
        let opts = Options.parse(args)
        let keyPath = try opts.required("key")
        let keyId = try opts.required("key-id")
        let issuer = try opts.required("issuer")
        let appName = try opts.required("app")
        let metadataDir = opts["metadata-dir"] ?? "docs/app-store/metadata"

        guard let app = MetadataApp(rawValue: appName) else {
            throw CLIError.invalidValue(flag: "--app", value: appName, allowed: MetadataApp.allCases.map(\.rawValue))
        }

        let config = try MetadataConfig.load(app: app, metadataDir: metadataDir)

        // App ID: explicit flag wins, else the YAML's apple_id.
        guard let appId = opts["app-id"] ?? config.appMeta.appleId else {
            // Minesweeper path: no ASC app record yet. Exit cleanly (the
            // dispatch brief expects a graceful note, not a crash).
            print("metadata: app '\(app.rawValue)' has no apple_id in app-meta.yaml "
                + "and no --app-id given — no ASC app to reconcile against. "
                + "Create the app in ASC first (user-owned), then re-run with --app-id.")
            return
        }

        let keyURL = URL(fileURLWithPath: keyPath)
        guard let pem = try? String(contentsOf: keyURL, encoding: .utf8) else {
            throw CLIError.cannotReadFile(keyPath)
        }
        let client = ASCClient(
            auth: ASCClient.Auth(keyId: keyId, issuerId: issuer, keyPEM: pem),
            mode: mode
        )

        // 1. Resolve the category catalog (human label → ASC id token).
        //    Printed so the plan pass surfaces Apple's real id tokens
        //    (plan §7 UNCONFIRMED resolution).
        let categoryCatalog: APICollectionWithIncluded
        do {
            categoryCatalog = try await client.listAppCategories()
            printCategoryCatalog(categoryCatalog)
        } catch {
            FileHandle.standardError.write(Data("warn: listAppCategories failed: \(error)\n".utf8))
        }

        let platform = try parsePlatform(opts)

        // 2. Snapshot remote metadata state. The appInfo slice (name / subtitle
        //    / categories) is platform-INDEPENDENT — appInfos are not per
        //    platform — so it is snapshotted once. The appStoreVersion slice is
        //    per platform (IOS + MAC_OS), so a separate snapshot is taken for
        //    each editable platform version in scope.
        let base: MetadataRemoteState
        let platformVersions: [PlatformVersionSnapshot]
        do {
            base = try await snapshotMetadata(client: client, appId: appId)
            platformVersions = try await snapshotPlatformVersions(
                client: client, appId: appId, filter: platform, versionFilter: opts["version"]
            )
        } catch let ASCClient.ClientError.httpStatus(code, path, body) where code == 404 {
            print("metadata: ASC returned 404 for \(path) — app id \(appId) not found "
                + "(MS app likely not created yet). Body: \(body)")
            return
        }

        // 3. Plan. The appInfo-loc + category actions come from the base state
        //    (its `versionId` is nil → reconciler emits no version-loc actions).
        //    The version-loc actions are planned PER platform version, each with
        //    only `versionId` populated so the reconciler emits version-loc
        //    actions for that platform alone.
        let appInfoActions = MetadataReconciler.plan(config: config, remote: base)
        var platformActions: [(platform: String, actions: [MetadataAction])] = []
        for pv in platformVersions {
            let perPlatform = MetadataRemoteState(
                versionId: pv.versionId,
                versionLocalizations: pv.versionLocalizations,
                hasReleasedVersion: pv.hasReleasedVersion
            )
            platformActions.append((pv.platform, MetadataReconciler.plan(config: config, remote: perPlatform)))
        }

        let totalCount = appInfoActions.count + platformActions.reduce(0) { $0 + $1.actions.count }
        print("Plan: \(totalCount) metadata action(s) for \(app.rawValue) (app-id \(appId), "
            + "--platform \(platform.rawValue))")
        for action in appInfoActions {
            print("  \(describeMetadata(action))")
        }
        for entry in platformActions {
            print("  [\(entry.platform)] (version-loc):")
            for action in entry.actions {
                print("    \(describeMetadata(action))")
            }
        }
        if platformVersions.isEmpty {
            print("  (no editable platform version in scope — version-loc copy not pushed)")
        }

        // 4. Apply (user-owned — only when explicitly requested).
        if mode == .apply {
            for action in appInfoActions {
                try await executeMetadata(action, client: client)
            }
            for entry in platformActions {
                for action in entry.actions {
                    try await executeMetadata(action, client: client)
                }
            }
            print("Applied.")
        }
    }

    /// Rename the editable App Store version's `versionString` (#310), across
    /// ALL editable platform versions by default (platform-aware). GETs the
    /// app's appStoreVersions (now carrying `platform`), groups by platform via
    /// `PlatformVersionResolver`, and PATCHes each editable platform version's
    /// `versionString` to `--version`. `--platform ios|macos|all` (default
    /// `all`) narrows the scope. Idempotent per platform: a version already at
    /// the target prints "already <x>, no change" and is not mutated. A platform
    /// with no editable version prints a warning and is skipped (renaming
    /// existing versions is in scope; creating a missing one is OUT). Does NOT
    /// touch listing/localization metadata.
    private static func runMetadataSetVersion(args: [String]) async throws {
        let opts = Options.parse(args)
        let keyPath = try opts.required("key")
        let keyId = try opts.required("key-id")
        let issuer = try opts.required("issuer")
        let appName = try opts.required("app")
        let target = try opts.required("version")
        let metadataDir = opts["metadata-dir"] ?? "docs/app-store/metadata"

        guard let app = MetadataApp(rawValue: appName) else {
            throw CLIError.invalidValue(flag: "--app", value: appName, allowed: MetadataApp.allCases.map(\.rawValue))
        }
        let platform = try parsePlatform(opts)

        // App ID: explicit flag wins, else the YAML's apple_id (same resolution
        // as `runMetadataRemote`).
        let config = try MetadataConfig.load(app: app, metadataDir: metadataDir)
        guard let appId = opts["app-id"] ?? config.appMeta.appleId else {
            print("metadata set-version: app '\(app.rawValue)' has no apple_id in app-meta.yaml "
                + "and no --app-id given — no ASC app to rename a version on.")
            return
        }

        let keyURL = URL(fileURLWithPath: keyPath)
        guard let pem = try? String(contentsOf: keyURL, encoding: .utf8) else {
            throw CLIError.cannotReadFile(keyPath)
        }
        // set-version always mutates when a rename is needed — use .apply so the
        // PATCH is actually sent (the idempotent no-change path exits earlier).
        let client = ASCClient(
            auth: ASCClient.Auth(keyId: keyId, issuerId: issuer, keyPEM: pem),
            mode: .apply
        )

        // GET versions, rename each editable platform version in scope.
        let versions = try await client.listAppStoreVersions(appId: appId)
        try await applySetVersion(
            client: client,
            platformVersions: Self.platformVersions(from: versions.data),
            filter: platform,
            target: target
        )
    }

    /// Resolve the editable version per platform (honoring `filter`) and PATCH
    /// each one's `versionString` to `target`. Idempotent per platform; warns
    /// (does not throw) for a platform with no editable version. `internal` so
    /// the URLProtocol-stub harness can drive the multi-platform rename offline.
    internal static func applySetVersion(
        client: ASCClient,
        platformVersions: [PlatformVersionResolver.PlatformVersion],
        filter: MetadataPlatform,
        target: String
    ) async throws {
        let outcome = PlatformVersionResolver.resolve(
            versions: platformVersions, filter: filter, versionFilter: nil
        )

        // Warn (don't crash) for each platform that has no editable version.
        for skip in outcome.skipped {
            let msg = "warn: metadata set-version: platform \(skip.platform) skipped — \(skip.reason)\n"
            FileHandle.standardError.write(Data(msg.utf8))
        }
        if outcome.resolved.isEmpty {
            print("metadata set-version: no editable platform version in scope "
                + "(--platform \(filter.rawValue)); nothing renamed.")
            return
        }

        for r in outcome.resolved {
            let chosen = r.version
            // Idempotent per platform: already at target → no mutation.
            if chosen.versionString == target {
                print("metadata set-version [\(r.platform)]: already \(target), no change "
                    + "(version id=\(chosen.id), state=\(chosen.state)).")
                continue
            }
            print("metadata set-version [\(r.platform)]: renaming version id=\(chosen.id) "
                + "state=\(chosen.state) \(chosen.versionString) → \(target)")
            _ = try await client.setVersionString(versionId: chosen.id, versionString: target)
            print("Applied [\(r.platform)]: \(chosen.versionString) → \(target)")
        }
    }

    /// Parse the optional `--platform ios|macos|all` flag (default `all`).
    private static func parsePlatform(_ opts: Options) throws -> MetadataPlatform {
        let raw = opts["platform"] ?? MetadataPlatform.all.rawValue
        guard let platform = MetadataPlatform(rawValue: raw) else {
            throw CLIError.invalidValue(
                flag: "--platform", value: raw, allowed: MetadataPlatform.allCases.map(\.rawValue)
            )
        }
        return platform
    }

    /// Map decoded ASC `appStoreVersions` resources to the pure resolver's
    /// platform-tagged value type. A version with no `platform` attribute is
    /// tagged `"IOS"` so single-platform apps (the legacy shape) keep working.
    internal static func platformVersions(
        from data: [APIResource]
    ) -> [PlatformVersionResolver.PlatformVersion] {
        data.map { v in
            PlatformVersionResolver.PlatformVersion(
                platform: v.attributes["platform"] ?? "IOS",
                version: SetVersionResolver.Version(
                    id: v.id,
                    versionString: v.attributes["versionString"] ?? "",
                    state: v.attributes["appVersionState"] ?? v.attributes["appStoreState"] ?? ""
                )
            )
        }
    }

    /// Per-platform `appStoreVersion` snapshot (the platform-specific slice of
    /// `MetadataRemoteState`). One is produced per editable platform version in
    /// scope so version-loc copy is pushed to EVERY platform, not just one.
    internal struct PlatformVersionSnapshot: Sendable, Equatable {
        internal let platform: String   // ASC token, e.g. "IOS"
        internal let versionId: String
        internal let versionLocalizations: [String: MetadataRemoteState.VersionLocRemote]
        internal let hasReleasedVersion: Bool
    }

    /// One GET pass that builds the platform-INDEPENDENT slice of
    /// `MetadataRemoteState`: picks the editable appInfo, indexes its
    /// localizations, reads current category relationship ids. The
    /// appStoreVersion slice is built separately, per platform, by
    /// `snapshotPlatformVersions`.
    private static func snapshotMetadata(
        client: ASCClient,
        appId: String
    ) async throws -> MetadataRemoteState {
        var remote = MetadataRemoteState()

        // appInfos + localizations + category relationships.
        let appInfos = try await client.listAppInfos(appId: appId)
        // Pick the editable appInfo: prefer one whose state is an editable
        // value; fall back to the first. The real state enum value is printed
        // below so plan §7's "which appInfo is editable" resolves at run time.
        let editableStates: Set<String> = [
            "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW",
        ]
        let chosenAppInfo = appInfos.data.first { info in
            let state = info.attributes["state"] ?? info.attributes["appStoreState"] ?? ""
            return editableStates.contains(state)
        } ?? appInfos.data.first

        if let info = chosenAppInfo {
            remote.appInfoId = info.id
            print("appInfo chosen: id=\(info.id) "
                + "state=\(info.attributes["state"] ?? info.attributes["appStoreState"] ?? "?") "
                + "(of \(appInfos.data.count) appInfos)")
            let rels = appInfos.relationships[info.id] ?? [:]
            // All six category slots side-loaded so drift compares the genre +
            // both sub-categories, not just the two genres (issue #310).
            remote.categoryIds = MetadataCategoryIds(
                primary: rels["primaryCategory"]?.first,
                primarySubOne: rels["primarySubcategoryOne"]?.first,
                primarySubTwo: rels["primarySubcategoryTwo"]?.first,
                secondary: rels["secondaryCategory"]?.first,
                secondarySubOne: rels["secondarySubcategoryOne"]?.first,
                secondarySubTwo: rels["secondarySubcategoryTwo"]?.first
            )
            // Capture appInfo-locs via the paginated relationship endpoint so
            // an existing locale beyond the side-load page is not missed →
            // classified as UPDATE not CREATE (issue #310, same risk as
            // version-locs below).
            for loc in try await client.listAppInfoLocalizations(appInfoId: info.id) {
                guard loc.type == "appInfoLocalizations",
                      let locale = loc.attributes["locale"] else { continue }
                remote.appInfoLocalizations[locale] = MetadataRemoteState.AppInfoLocRemote(
                    id: loc.id,
                    name: loc.attributes["name"],
                    subtitle: loc.attributes["subtitle"],
                    privacyPolicyUrl: loc.attributes["privacyPolicyUrl"]
                )
            }
        }

        return remote
    }
    // swiftlint:enable function_body_length

    /// Build one `PlatformVersionSnapshot` per editable platform version in
    /// scope. One ASC app holds a SEPARATE `appStoreVersion` per platform
    /// (IOS + MAC_OS); the old code picked just one, so copy/renames landed on a
    /// single platform. This GETs the per-platform versions, groups them via
    /// `PlatformVersionResolver` (honoring `--platform` and `--version`), and
    /// for each chosen version captures its version-locs via the paginated
    /// relationship endpoint. A platform with no editable version is warned
    /// about and omitted (not an error).
    ///
    /// `hasReleasedVersion` is computed app-wide (ANY platform released → not a
    /// first submission) so `whatsNew` gating matches the prior behavior.
    internal static func snapshotPlatformVersions(
        client: ASCClient,
        appId: String,
        filter: MetadataPlatform,
        versionFilter: String?
    ) async throws -> [PlatformVersionSnapshot] {
        let versions = try await client.listAppStoreVersions(appId: appId)
        // App-wide released flag (mirrors the prior single-state snapshot): on a
        // first submission (none released) the Reconciler drops `whatsNew`.
        let hasReleased = versions.data.contains { v in
            let state = v.attributes["appVersionState"] ?? v.attributes["appStoreState"] ?? ""
            return MetadataRemoteState.releasedAppStoreStates.contains(state)
        }

        let outcome = PlatformVersionResolver.resolve(
            versions: Self.platformVersions(from: versions.data),
            filter: filter,
            versionFilter: versionFilter
        )
        for skip in outcome.skipped {
            let msg = "warn: metadata: platform \(skip.platform) has no editable version — "
                + "version-loc copy not pushed for it (\(skip.reason))\n"
            FileHandle.standardError.write(Data(msg.utf8))
        }

        var snapshots: [PlatformVersionSnapshot] = []
        for r in outcome.resolved {
            let v = r.version
            print("appStoreVersion chosen [\(r.platform)]: id=\(v.id) "
                + "version=\(v.versionString) state=\(v.state) "
                + "(of \(versions.data.count) versions across platforms)")
            // Capture EVERY existing version-loc via the version's own paginated
            // relationship endpoint, not the truncatable `?include=` side-load
            // (issue #310 — the live `es-ES` was missed → CREATE → 409 dup).
            var locs: [String: MetadataRemoteState.VersionLocRemote] = [:]
            for loc in try await client.listVersionLocalizations(versionId: v.id) {
                guard loc.type == "appStoreVersionLocalizations",
                      let locale = loc.attributes["locale"] else { continue }
                locs[locale] = MetadataRemoteState.VersionLocRemote(
                    id: loc.id,
                    description: loc.attributes["description"],
                    keywords: loc.attributes["keywords"],
                    promotionalText: loc.attributes["promotionalText"],
                    whatsNew: loc.attributes["whatsNew"],
                    marketingUrl: loc.attributes["marketingUrl"],
                    supportUrl: loc.attributes["supportUrl"]
                )
            }
            snapshots.append(PlatformVersionSnapshot(
                platform: r.platform,
                versionId: v.id,
                versionLocalizations: locs,
                hasReleasedVersion: hasReleased
            ))
        }
        return snapshots
    }

    /// Print the resolved ASC category catalog (genre id → subcategory ids),
    /// so the plan pass records the real id tokens (plan §7).
    private static func printCategoryCatalog(_ catalog: APICollectionWithIncluded) {
        let subsById = Dictionary(uniqueKeysWithValues: catalog.included.map { ($0.id, $0) })
        let games = catalog.data.first { $0.id == "GAMES" } ?? catalog.data.first { $0.id.hasPrefix("GAMES") }
        print("appCategories (top-level genres): \(catalog.data.map(\.id).sorted())")
        if let games {
            let subIds = catalog.relationships[games.id]?["subcategories"] ?? []
            let resolved = subIds.compactMap { subsById[$0]?.id }.sorted()
            print("appCategories GAMES subcategories: \(resolved)")
        }
    }

    private static func describeMetadata(_ action: MetadataAction) -> String {
        switch action {
        case .createAppInfoLoc(_, let l, _):      return "CREATE appInfo-loc      [\(l)]"
        case .updateAppInfoLoc(_, let l, _):      return "UPDATE appInfo-loc      [\(l)]"
        case .appInfoLocUnchanged(let l):         return "OK     appInfo-loc      [\(l)]"
        case .createVersionLoc(_, let l, _):      return "CREATE version-loc      [\(l)]"
        case .updateVersionLoc(_, let l, _):      return "UPDATE version-loc      [\(l)]"
        case .versionLocUnchanged(let l):         return "OK     version-loc      [\(l)]"
        case .updateCategories(_, let c):
            let primary = [c.primary, c.primarySubOne, c.primarySubTwo].compactMap { $0 }.joined(separator: "/")
            let secondary = [c.secondary, c.secondarySubOne, c.secondarySubTwo].compactMap { $0 }.joined(separator: "/")
            return "UPDATE categories       primary=[\(primary)] secondary=[\(secondary)]"
        case .categoriesUnchanged:                return "OK     categories"
        }
    }

    private static func executeMetadata(_ action: MetadataAction, client: ASCClient) async throws {
        switch action {
        case .createAppInfoLoc(let appInfoId, let locale, let listing):
            try await createOrUpdateAppInfoLoc(
                client: client, appInfoId: appInfoId, locale: locale, listing: listing
            )
        case .updateAppInfoLoc(let locId, _, let listing):
            _ = try await client.updateAppInfoLocalization(
                localizationId: locId,
                name: listing.name, subtitle: listing.subtitle,
                privacyPolicyUrl: listing.privacyPolicyUrl
            )
        case .appInfoLocUnchanged:
            break
        case .createVersionLoc(let versionId, let locale, let listing):
            try await createOrUpdateVersionLoc(
                client: client, versionId: versionId, locale: locale, listing: listing
            )
        case .updateVersionLoc(let locId, _, let listing):
            _ = try await client.updateVersionLocalization(
                localizationId: locId,
                description: listing.description, keywords: listing.keywords,
                promotionalText: listing.promotionalText, whatsNew: listing.whatsNew,
                marketingUrl: listing.marketingUrl, supportUrl: listing.supportUrl
            )
        case .versionLocUnchanged:
            break
        case .updateCategories(let appInfoId, let categories):
            _ = try await client.updateAppInfoCategories(
                appInfoId: appInfoId, categories: categories
            )
        case .categoriesUnchanged:
            break
        }
    }

    // `internal` (not `private`) so the URLProtocol-stub harness can drive the
    // real CREATE→PATCH 409 self-heal end-to-end offline (issue #333) rather
    // than re-implementing the orchestration in the test.
    //
    /// CREATE a version-loc, falling back to PATCH on a 409-DUPLICATE. A stale
    /// snapshot (or a race) can plan a CREATE for a locale ASC already holds;
    /// ASC then rejects with `409 ATTRIBUTE.INVALID.DUPLICATE` (the live
    /// `es-ES` case, issue #310). We re-fetch the version's locs, find the
    /// existing id for that locale, and switch to UPDATE — so a wedged apply
    /// self-heals instead of aborting before the remaining locales run.
    internal static func createOrUpdateVersionLoc(
        client: ASCClient,
        versionId: String,
        locale: String,
        listing: ListingLocale
    ) async throws {
        do {
            _ = try await client.createVersionLocalization(
                versionId: versionId, locale: locale,
                description: listing.description, keywords: listing.keywords,
                promotionalText: listing.promotionalText, whatsNew: listing.whatsNew,
                marketingUrl: listing.marketingUrl, supportUrl: listing.supportUrl
            )
        } catch let ASCClient.ClientError.httpStatus(code, _, body)
            where code == 409 && ASCClient.isDuplicateValueError(body: body) {
            let existing = try await client.listVersionLocalizations(versionId: versionId)
                .first { $0.attributes["locale"] == locale }
            guard let existing else { throw ASCClient.ClientError.httpStatus(code: code, path: locale, body: body) }
            FileHandle.standardError.write(Data(
                "warn: version-loc \(locale) already exists (409 dup) — switching CREATE→UPDATE id=\(existing.id)\n".utf8
            ))
            _ = try await client.updateVersionLocalization(
                localizationId: existing.id,
                description: listing.description, keywords: listing.keywords,
                promotionalText: listing.promotionalText, whatsNew: listing.whatsNew,
                marketingUrl: listing.marketingUrl, supportUrl: listing.supportUrl
            )
        }
    }

    // `internal` for the same offline-harness reason as `createOrUpdateVersionLoc`.
    //
    /// CREATE an appInfo-loc, falling back to PATCH on a 409-DUPLICATE.
    /// Same defensive self-heal as `createOrUpdateVersionLoc` (issue #310).
    internal static func createOrUpdateAppInfoLoc(
        client: ASCClient,
        appInfoId: String,
        locale: String,
        listing: ListingLocale
    ) async throws {
        do {
            _ = try await client.createAppInfoLocalization(
                appInfoId: appInfoId, locale: locale,
                name: listing.name, subtitle: listing.subtitle,
                privacyPolicyUrl: listing.privacyPolicyUrl
            )
        } catch let ASCClient.ClientError.httpStatus(code, _, body)
            where code == 409 && ASCClient.isDuplicateValueError(body: body) {
            let existing = try await client.listAppInfoLocalizations(appInfoId: appInfoId)
                .first { $0.attributes["locale"] == locale }
            guard let existing else { throw ASCClient.ClientError.httpStatus(code: code, path: locale, body: body) }
            FileHandle.standardError.write(Data(
                "warn: appInfo-loc \(locale) already exists (409 dup) — switching CREATE→UPDATE id=\(existing.id)\n".utf8
            ))
            _ = try await client.updateAppInfoLocalization(
                localizationId: existing.id,
                name: listing.name, subtitle: listing.subtitle,
                privacyPolicyUrl: listing.privacyPolicyUrl
            )
        }
    }

    // MARK: - iap plan / apply

    /// Phase 1.a (issue #200) — drives only the IAP slice of the
    /// reconciler. Does not touch leaderboards or achievements, so we
    /// skip the GC RemoteState snapshot work and submit a snapshot with
    /// just the IAP products populated.
    private static func runIAPRemote(args: [String], mode: ASCClient.Mode) async throws {
        let opts = Options.parse(args)
        let keyPath = try opts.required("key")
        let keyId = try opts.required("key-id")
        let issuer = try opts.required("issuer")
        let appId = try opts.required("app-id")
        let xcstringsPath = try opts.required("xcstrings")

        let keyURL = URL(fileURLWithPath: keyPath)
        guard let pem = try? String(contentsOf: keyURL, encoding: .utf8) else {
            throw CLIError.cannotReadFile(keyPath)
        }
        let strings = try XCStringsParser.parse(fileURL: URL(fileURLWithPath: xcstringsPath))

        let client = ASCClient(
            auth: ASCClient.Auth(keyId: keyId, issuerId: issuer, keyPEM: pem),
            mode: mode
        )

        // 1. Snapshot remote IAP state for every configured product. One
        // GET pulls IAPs + their localizations via `?include=` (proposal
        // §3.1); we then index by productId for Config matching and re-
        // attach each localization to its parent IAP using the response's
        // relationship pointers.
        var remote = RemoteState()
        let bundle = try await client.listIAPs(appId: appId)
        let byProductId = Dictionary(
            uniqueKeysWithValues: bundle.data.compactMap { resource -> (String, APIResource)? in
                guard let pid = resource.attributes["productId"] else { return nil }
                return (pid, resource)
            }
        )
        let includedById = Dictionary(
            uniqueKeysWithValues: bundle.included.map { ($0.id, $0) }
        )
        for product in Config.iaps {
            guard let resource = byProductId[product.productId] else {
                // Product not in ASC. Reconciler will skip it; surfaces as
                // empty plan + apply-time 404 if user tries to PATCH.
                FileHandle.standardError.write(Data(
                    "warn: IAP \(product.productId) not found in ASC; create it in the web UI first\n".utf8
                ))
                continue
            }
            let familyShareable: Bool? = resource.attributes["familySharable"].flatMap { value in
                switch value {
                case "true", "1": return true
                case "false", "0": return false
                default: return nil
                }
            }
            remote.iaps[product.productId] = RemoteState.IAPRemoteAttributes(
                id: resource.id,
                referenceName: resource.attributes["name"],
                reviewNote: resource.attributes["reviewNote"],
                familyShareable: familyShareable
            )

            // Re-attach side-loaded localizations to this IAP via the
            // relationship pointer map.
            let locIds = bundle.relationships[resource.id]?["inAppPurchaseLocalizations"] ?? []
            for locId in locIds {
                guard let loc = includedById[locId],
                      loc.type == "inAppPurchaseLocalizations",
                      let locale = loc.attributes["locale"]
                else { continue }
                let key = RemoteState.LocalizationKey(
                    vendorId: product.productId, locale: locale
                )
                remote.iapLocalizations[key] = RemoteState.IAPLocalizationRemoteAttributes(
                    id: loc.id,
                    name: loc.attributes["name"],
                    description: loc.attributes["description"]
                )
            }
        }

        // 2. Plan + (optionally) execute.
        let actions = Reconciler.plan(
            config: .live,
            strings: strings,
            remote: remote
        )
        // Filter to IAP-scoped actions only — `runIAPRemote` snapshots IAP
        // state but leaves remote.leaderboards / remote.achievements empty,
        // so the Reconciler emits noisy GC CREATE actions that must NOT
        // execute under `iap apply` (they'd 409 against existing ASC
        // catalog or worse, create duplicates).
        let iapActions = actions.filter { action in
            switch action {
            case .updateIAP, .iapUnchanged,
                 .createIAPLocalization, .updateIAPLocalization, .iapLocalizationUnchanged:
                return true
            default:
                return false
            }
        }
        print("Plan: \(iapActions.count) IAP action(s) (filtered from \(actions.count) total — GC noise dropped)")
        for action in iapActions {
            print("  \(describe(action))")
        }
        if mode == .apply {
            // IAP execute paths self-contain their ASC ids (iapId /
            // localizationId / existingId threaded through actions at plan
            // time). detailId is unused for IAP; appId currently unused too
            // (kept for parity with GC execute signature).
            for action in iapActions {
                try await execute(action, client: client, detailId: "", appId: appId)
            }
            print("Applied.")
        }
    }

    // MARK: - inspect

    /// GET an existing ASC leaderboard by vendor identifier and print its
    /// full attribute dictionary, one `key=value` line per attribute. Lets
    /// operators read Apple's real schema in one request instead of
    /// discovering required fields through iterative 4xx responses (issue
    /// #22 motivation).
    private static func runInspect(args: [String]) async throws {
        let opts = Options.parse(args)
        let keyPath = try opts.required("key")
        let keyId = try opts.required("key-id")
        let issuer = try opts.required("issuer")
        let appId = try opts.required("app-id")
        let vendorId = try opts.required("leaderboard")

        let keyURL = URL(fileURLWithPath: keyPath)
        guard let pem = try? String(contentsOf: keyURL, encoding: .utf8) else {
            throw CLIError.cannotReadFile(keyPath)
        }

        let client = ASCClient(
            auth: ASCClient.Auth(keyId: keyId, issuerId: issuer, keyPEM: pem),
            mode: .plan  // inspect performs GETs only; plan-mode is fine.
        )

        let detail = try await client.getGameCenterDetail(appId: appId)
        let leaderboards = try await client.listLeaderboards(detailId: detail.id)
        guard let match = leaderboards.first(where: { $0.attributes["vendorIdentifier"] == vendorId }) else {
            let found = leaderboards.compactMap { $0.attributes["vendorIdentifier"] }.sorted()
            FileHandle.standardError.write(Data(
                "No leaderboard found with vendorIdentifier=\(vendorId).\nKnown vendor IDs: \(found)\n".utf8
            ))
            exit(1)
        }
        print("id=\(match.id)")
        print("type=\(match.type)")
        for key in match.attributes.keys.sorted() {
            // swiftlint:disable:next force_unwrapping
            print("\(key)=\(match.attributes[key]!)")
        }
    }
}

// MARK: - Argv parsing

internal struct Options: Sendable {
    private var values: [String: String]

    private init(_ values: [String: String]) { self.values = values }

    internal subscript(key: String) -> String? { values[key] }

    internal func required(_ key: String) throws -> String {
        guard let v = values[key] else { throw CLIError.missingFlag("--\(key)") }
        return v
    }

    internal static func parse(_ args: [String]) -> Options {
        var out: [String: String] = [:]
        var i = 0
        while i < args.count {
            let token = args[i]
            if token.hasPrefix("--"), i + 1 < args.count {
                let key = String(token.dropFirst(2))
                out[key] = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        return Options(out)
    }
}

internal enum CLIError: Error, CustomStringConvertible {
    case missingFlag(String)
    case cannotReadFile(String)
    case validationFailed
    case invalidValue(flag: String, value: String, allowed: [String])

    internal var description: String {
        switch self {
        case .missingFlag(let f): return "missing required flag: \(f)"
        case .cannotReadFile(let p): return "cannot read file: \(p)"
        case .validationFailed: return "validation failed"
        case .invalidValue(let flag, let value, let allowed):
            return "invalid value for \(flag): '\(value)' (allowed: \(allowed.joined(separator: ", ")))"
        }
    }
}

// MARK: - Top-level entry

await ASCRegisterCLI.run()

// swiftlint:enable identifier_name cyclomatic_complexity for_where file_length
