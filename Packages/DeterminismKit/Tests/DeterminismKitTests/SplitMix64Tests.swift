import Testing
@testable import DeterminismKit

@Suite("SplitMix64 (DeterminismKit leaf)")
struct SplitMix64Tests {

    /// Frozen reference vector for seed = 0x0, byte-identical on macOS arm64
    /// and iPhone simulator arm64 (meetings/2026-05-17_phase0-gates.md §0.1).
    /// Pins the hoisted leaf to the same output as the pre-#446 engine copies.
    static let seedZero: [UInt64] = [
        0xE220_A839_7B1D_CDAF,
        0x6E78_9E6A_A1B9_65F4,
        0x06C4_5D18_8009_454F,
        0xF88B_B8A8_724C_81EC,
        0x1B39_896A_51A8_749B,
        0x53CB_9F0C_747E_A2EA,
        0x2C82_9ABE_1F45_32E1,
        0xC584_133A_C916_AB3C,
    ]

    @Test func seedZeroMatchesFrozenVector() {
        var rng = SplitMix64(seed: 0)
        for expected in Self.seedZero {
            #expect(rng.next() == expected)
        }
    }

    @Test func sameSeedSameSequence() {
        var rngA = SplitMix64(seed: 12_345)
        var rngB = SplitMix64(seed: 12_345)
        for _ in 0..<32 {
            #expect(rngA.next() == rngB.next())
        }
    }

    @Test func nextIntIsBoundedAndDeterministic() {
        var rngA = SplitMix64(seed: 99)
        var rngB = SplitMix64(seed: 99)
        for _ in 0..<64 {
            let valA = rngA.nextInt(upperBound: 9)
            let valB = rngB.nextInt(upperBound: 9)
            #expect(valA == valB)
            #expect((0..<9).contains(valA))
        }
    }

    @Test func shuffleInPlaceIsDeterministic() {
        var rngA = SplitMix64(seed: 7)
        var rngB = SplitMix64(seed: 7)
        var arrA = Array(0..<20)
        var arrB = Array(0..<20)
        rngA.shuffleInPlace(&arrA)
        rngB.shuffleInPlace(&arrB)
        #expect(arrA == arrB)
        #expect(arrA.sorted() == Array(0..<20))
    }
}
