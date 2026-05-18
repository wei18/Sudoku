// Frozen `(clues, solution)` strings for PuzzleGenerator.generate(seed: 0, ...)
// across all three difficulties.
//
// These strings ARE the cross-architecture determinism contract per
// design.md §How.4.6. Any drift (Xcode major upgrade, Swift toolchain upgrade,
// algorithm change) must be caught by the test suite here. Bumping
// GeneratorVersion is the only legitimate reason for these strings to change.

enum PuzzleGeneratorSnapshots {
    // Captured 2026-05-19 on macOS arm64 (Xcode 26.5 toolchain). These strings
    // ARE the cross-architecture determinism contract; any drift must be
    // investigated, not papered over.
    static let easySeed0Clues =
        "2.85.3.17.519.7.6.7.9.1843..26.74.91......25..34.2...6..579....17.4865..49....67."
    static let easySeed0Solution =
        "248563917351947862769218435526874391817639254934125786685792143173486529492351678"
    static let mediumSeed0Clues =
        "..85.3.17..19.7.6.7.9.1.43..26..4..1......25..3..2...6...79....17..86...49.....7."
    static let mediumSeed0Solution =
        "248563917351947862769218435526874391817639254934125786685792143173486529492351678"
    static let hardSeed0Clues =
        "..85.3.17...9.7.6.7...1.43...6..4..1......25..3..2.......7.....1...86...49.....7."
    static let hardSeed0Solution =
        "248563917351947862769218435526874391817639254934125786685792143173486529492351678"
}
