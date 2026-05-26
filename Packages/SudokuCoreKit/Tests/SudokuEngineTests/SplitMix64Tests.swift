import Testing
@testable import SudokuEngine

@Suite("SplitMix64")
struct SplitMix64Tests {

    @Test func seedZeroFirst16MatchPhase0Reference() {
        var rng = SplitMix64(seed: 0)
        for (index, expected) in SplitMix64Reference.seedZero.enumerated() {
            let value = rng.next()
            #expect(value == expected, "seed=0 idx \(index)")
        }
    }

    @Test func seedFortyTwoFirst16MatchPhase0Reference() {
        var rng = SplitMix64(seed: 0x2A)
        for (index, expected) in SplitMix64Reference.seedFortyTwo.enumerated() {
            let value = rng.next()
            #expect(value == expected, "seed=42 idx \(index)")
        }
    }

    @Test func independentInstancesProduceIdenticalSequences() {
        var rngA = SplitMix64(seed: 12_345)
        var rngB = SplitMix64(seed: 12_345)
        for _ in 0..<64 {
            #expect(rngA.next() == rngB.next())
        }
    }

    @Test func differentSeedsProduceDifferentFirstValue() {
        var rngA = SplitMix64(seed: 1)
        var rngB = SplitMix64(seed: 2)
        #expect(rngA.next() != rngB.next())
    }

    @Test func nextIntIsBoundedAndDeterministic() {
        var rngA = SplitMix64(seed: 99)
        var rngB = SplitMix64(seed: 99)
        for _ in 0..<32 {
            let valA = rngA.nextInt(upperBound: 9)
            let valB = rngB.nextInt(upperBound: 9)
            #expect(valA == valB)
            #expect((0..<9).contains(valA))
        }
    }

    @Test func shuffleIsDeterministicForSameSeed() {
        var rngA = SplitMix64(seed: 7)
        var rngB = SplitMix64(seed: 7)
        var arrA = Array(1...20)
        var arrB = Array(1...20)
        rngA.shuffleInPlace(&arrA)
        rngB.shuffleInPlace(&arrB)
        #expect(arrA == arrB)
        // Still a permutation.
        #expect(arrA.sorted() == Array(1...20))
    }
}
