// SnapshotBlankBaselineGuardTests — no committed baseline may be blank.
//
// #1022 recorded a baseline with **zero opaque pixels** and every gate stayed
// green: `swift test` compares a blank capture against a blank reference and
// finds them identical, the drift gate only fires on CHANGE, and the orphan
// gate only proves a recording test exists. A blank PNG is a perfectly
// self-consistent lie.
//
// The trigger is a real defect in the capture path, not in the app: **tinted
// Liquid Glass blanks the entire `NSHostingView` + `cacheDisplay` capture** —
// not just the tinted control, the whole image, background included. Measured
// through this exact path (opaque-pixel counts on a 300×200 orange ground):
//
//   no glass at all                          26800
//   .buttonStyle(.glass), untinted           26800
//   .buttonStyle(.glassProminent)                0
//   .buttonStyle(.glass) + .tint                 0
//   .glassEffect(.regular.tint(_))               0
//   .glassEffect(.regular.tint(_).interactive)   0
//
// So it is TINT, not the prominent style and not `GlassEffectContainer` — an
// untinted glass button renders the rest of the screen fine (the glass itself
// is invisible, #1054's separate blind spot). Any fixture that puts a tinted
// glass control on screen therefore cannot be captured at all here. On device
// the same build renders correctly; the app is fine.
//
// This test is the cheap standing guard: it is content-agnostic, needs no
// per-fixture bookkeeping, and fails loudly the moment a blank lands. The
// broader "a mapped baseline can be stale or wrong while every gate is green"
// problem is #1057.

#if canImport(AppKit)
import AppKit
import Foundation
import Testing

@Suite("Snapshot baselines — none may be blank")
struct SnapshotBlankBaselineGuardTests {

    @Test("Every committed snapshot baseline has opaque pixels")
    func noCommittedBaselineIsBlank() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
        let blanks = try SnapshotBlankScan.blankBaselines(under: root)
        #expect(
            blanks.isEmpty,
            """
            Blank baseline(s) — zero opaque pixels, so the recorded PNG shows nothing:
            \(blanks.map { "  \($0)" }.joined(separator: "\n"))
            A tinted Liquid Glass control blanks this capture path entirely (see this
            file's header). Do NOT re-record: either the fixture must avoid putting a
            tinted glass control on screen, or its coverage belongs somewhere other
            than a pixel snapshot.
            """
        )
    }
}

/// Shared scan, kept separate from the `@Suite` so Minesweeper's identical
/// guard can use the same implementation without duplicating the pixel walk.
enum SnapshotBlankScan {
    /// Relative paths of every `.png` under `root` whose pixels are entirely
    /// transparent. Samples on a stride — a genuinely blank capture is blank
    /// everywhere, and a full walk over ~5.7M-pixel iPad frames is needlessly
    /// slow for a guard that runs on every test invocation.
    static func blankBaselines(under root: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var blanks: [String] = []
        for case let url as URL in walker where url.pathExtension == "png" {
            guard let image = NSImage(contentsOf: url),
                  let rep = image.representations.first as? NSBitmapImageRep else { continue }
            if isBlank(rep) {
                blanks.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
            }
        }
        return blanks.sorted()
    }

    private static func isBlank(_ rep: NSBitmapImageRep) -> Bool {
        let strideStep = 7
        for row in Swift.stride(from: 0, to: rep.pixelsHigh, by: strideStep) {
            for column in Swift.stride(from: 0, to: rep.pixelsWide, by: strideStep) {
                if let color = rep.colorAt(x: column, y: row), color.alphaComponent != 0 {
                    return false
                }
            }
        }
        return true
    }
}
#endif
