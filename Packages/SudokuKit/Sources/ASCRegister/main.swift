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

// swiftlint:disable identifier_name cyclomatic_complexity function_body_length for_where

import Foundation

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
        let url = URL(fileURLWithPath: xcstringsPath)
        let parsed = try XCStringsParser.parse(fileURL: url)

        // Validate Config sanity.
        let lbIds = Config.allLeaderboardIds
        let achIds = Config.allAchievementShortIds
        let pointsSum = Config.totalAchievementPoints

        print("Config:")
        print("  leaderboards (\(lbIds.count)):")
        for id in lbIds { print("    - \(id)") }
        print("  achievements (\(achIds.count), points=\(pointsSum)):")
        for ach in Config.achievements {
            print("    - \(ach.fullId)  [\(ach.points)pt]")
        }

        // Validate xcstrings coverage for en + zh-Hant on every expected key.
        let expectedKeys = expectedXCStringsKeys()
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

        // 3. Plan.
        let actions = Reconciler.plan(
            config: .live,
            strings: strings,
            remote: remote
        )

        // 4. Print plan summary; in `apply` also execute.
        print("Plan: \(actions.count) action(s)")
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

    private static func execute(_ action: Action, client: ASCClient, detailId: String) async throws {
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
        }
    }

    private static func expectedXCStringsKeys() -> [String] {
        var keys: [String] = []
        for lb in Config.leaderboards {
            keys.append("gc.leaderboard.\(lb.difficulty).daily.title")
        }
        for ach in Config.achievements {
            keys.append(ach.titleKey)
            keys.append(ach.descriptionKey)
            keys.append(ach.unearnedDescriptionKey)
        }
        return keys
    }

    private static func printUsage() {
        print("""
        Usage:
          ASCRegister validate  --xcstrings <path>
          ASCRegister plan      --key <p8> --key-id <id> --issuer <id> --app-id <id> --xcstrings <path>
          ASCRegister apply     --key <p8> --key-id <id> --issuer <id> --app-id <id> --xcstrings <path>
          ASCRegister inspect   --key <p8> --key-id <id> --issuer <id> --app-id <id> --leaderboard <vendor-id>
        """)
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

    internal var description: String {
        switch self {
        case .missingFlag(let f): return "missing required flag: \(f)"
        case .cannotReadFile(let p): return "cannot read file: \(p)"
        case .validationFailed: return "validation failed"
        }
    }
}

// MARK: - Top-level entry

await ASCRegisterCLI.run()
