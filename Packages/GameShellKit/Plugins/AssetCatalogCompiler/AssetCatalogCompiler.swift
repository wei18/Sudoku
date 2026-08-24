import Foundation
import PackagePlugin

/// Makes a target's `*.xcassets` color sets resolvable under the SwiftPM CLI
/// (`swift build` / `swift test`) on macOS by compiling them with `actool`.
///
/// Why (#1032): the SwiftPM CLI only COPIES `.xcassets` resources — it never
/// runs `actool` and it writes no `Info.plist` into the resource bundle. CoreUI
/// needs BOTH an `Assets.car` at the bundle's resource root AND a
/// `CFBundleIdentifier`, so `Color(name, bundle: .module)` resolved to nothing
/// and every themed view rendered blank in `swift test` snapshot suites.
/// This plugin emits both files as build-command outputs; SwiftPM treats
/// non-source plugin outputs as `.copy` resources and lands them in the
/// target's bundle root.
///
/// Xcode (and therefore the Tuist-generated app builds) compiles catalogs and
/// writes the bundle `Info.plist` itself, so the plugin only activates under
/// the SwiftPM CLI's work-directory layout (see the guard below).
///
/// Usage — on a target whose `resources:` already `.process` the catalog:
/// `plugins: [.plugin(name: "AssetCatalogCompiler", package: "GameShellKit")]`.
@main
struct AssetCatalogCompiler: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        #if os(macOS)
        // Opt in ONLY under the SwiftPM CLI, recognised by its work-directory
        // layout `<scratch>/plugins/outputs/<package>/<target>/…`. Xcode hosts
        // plugins under `…/Intermediates.noindex/BuildToolPluginIntermediates/`
        // (Xcode 26; older: `SourcePackages/plugins/`) and already compiles the
        // catalog itself — a second `Assets.car` there fails the app build with
        // "Multiple commands produce … Assets.car" (verified via xcodebuild).
        // Fail-safe direction: an unrecognised layout means no-op (blank
        // snapshots, documented in CLAUDE.md), never a broken app build.
        let workDirectory = context.pluginWorkDirectoryURL
        guard workDirectory.path(percentEncoded: false).contains("/plugins/outputs/") else { return [] }
        guard let module = target as? SourceModuleTarget else { return [] }
        let catalogs = module.sourceFiles
            .filter { $0.url.pathExtension == "xcassets" }
            .map(\.url)
        guard !catalogs.isEmpty else { return [] }

        let assetsCar = workDirectory.appending(path: "Assets.car")
        let infoPlist = workDirectory.appending(path: "Info.plist")
        let bundleIdentifier = "\(context.package.displayName).\(target.name).resources"

        var actoolArguments = ["actool"]
        actoolArguments += catalogs.map { $0.path(percentEncoded: false) }
        actoolArguments += [
            "--compile", workDirectory.path(percentEncoded: false),
            "--output-format", "human-readable-text",
            "--platform", "macosx",
            "--minimum-deployment-target", "26.0", // every consumer declares `.macOS(.v26)`
            "--target-device", "mac",
            "--warnings", "--errors",
        ]

        // Both files must be produced BY a build command: SwiftPM caches the
        // plugin's plan, so anything written here at plan time is not
        // regenerated on incremental builds and the bundle copy step fails
        // with "Info.plist doesn't exist in file system".
        return [
            .buildCommand(
                displayName: "Compile \(catalogs.map(\.lastPathComponent).joined(separator: ", ")) with actool",
                executable: URL(filePath: "/usr/bin/xcrun"),
                arguments: actoolArguments,
                inputFiles: catalogs.flatMap(Self.files(under:)),
                outputFiles: [assetsCar]
            ),
            .buildCommand(
                displayName: "Write \(target.name) resource-bundle Info.plist (\(bundleIdentifier))",
                executable: URL(filePath: "/usr/libexec/PlistBuddy"),
                // `Clear dict` makes the command idempotent on an existing file.
                arguments: [
                    "-c", "Clear dict",
                    "-c", "Add :CFBundleIdentifier string \(bundleIdentifier)",
                    "-c", "Add :CFBundlePackageType string BNDL",
                    infoPlist.path(percentEncoded: false),
                ],
                inputFiles: [],
                outputFiles: [infoPlist]
            ),
        ]
        #else
        // No actool off macOS; the catalog stays a plain copied resource.
        return []
        #endif
    }

    /// Every regular file inside `directory`, so editing any `Contents.json`
    /// re-runs actool.
    private static func files(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [directory] }
        var files: [URL] = []
        for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            files.append(url)
        }
        return files.isEmpty ? [directory] : files
    }
}
