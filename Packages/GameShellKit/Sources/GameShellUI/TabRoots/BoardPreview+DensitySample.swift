// BoardPreview+DensitySample — deterministic representative-sample thumbnails
// for PRACTICE (#1021 Phase A, design.md §3.2: "縮圖用代表性樣本不是真實下一局
// (避免把抽題時機前移、踩到既有狀態機)").
//
// `BoardPreview.swift` stays untouched (forbidden list) — this is a purely
// additive extension file. `GameShellKit` is zero-dependency (Package.swift
// `dependencies: []`), so this cannot import `DeterminismKit`'s `SplitMix64`;
// `DensitySampleGenerator` below is a small INLINE reimplementation of the
// same public splitmix64 step, scoped `private` to this file, used only to
// scatter marks across a grid — it carries no seed-vector compatibility
// contract with the real puzzle generator and must never be mistaken for one.

public extension BoardPreview {
    /// Deterministic pseudo-random sample: `fillRatio` of the grid's cells
    /// (rounded to the nearest whole cell) are set to `mark`, the rest to
    /// `.empty`. Same `seed` (and same `columns`/`rows`/`fillRatio`/`mark`)
    /// always produces an identical `BoardPreview` — callers can regenerate
    /// the same sample thumbnail on every render without persisting one.
    ///
    /// Returns `nil` for non-positive dimensions, matching `BoardPreview
    /// .init`'s own degrade contract.
    static func densitySample(
        columns: Int,
        rows: Int,
        fillRatio: Double,
        mark: CellMark,
        seed: UInt64
    ) -> BoardPreview? {
        guard columns > 0, rows > 0 else { return nil }
        let total = columns * rows
        let fillCount = min(total, max(0, Int((Double(total) * fillRatio).rounded())))

        var indices = Array(0..<total)
        var generator = DensitySampleGenerator(seed: seed)
        // Fisher–Yates: deterministic under a fixed seed, uniform over which
        // `fillCount` cells get picked.
        if total > 1 {
            for index in stride(from: total - 1, to: 0, by: -1) {
                let swapIndex = Int(generator.next() % UInt64(index + 1))
                indices.swapAt(index, swapIndex)
            }
        }

        var cells = [CellMark](repeating: .empty, count: total)
        for index in indices.prefix(fillCount) {
            cells[index] = mark
        }
        return BoardPreview(columns: columns, rows: rows, cells: cells)
    }
}

/// A minimal inline splitmix64 step — NOT `DeterminismKit.SplitMix64`, no
/// shared seed-vector contract with it. Exists solely so `densitySample`
/// stays reproducible without pulling a dependency into this zero-dep
/// package.
private struct DensitySampleGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
