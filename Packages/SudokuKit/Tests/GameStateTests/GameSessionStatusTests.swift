import Foundation
import Testing
@testable import GameState

@Suite("GameSessionStatus state machine")
struct GameSessionStatusTests {

    @Test("Status has exactly the 5 design.md cases")
    func statusHasFiveCases() {
        let all = GameSessionStatus.allCases
        #expect(all.count == 5)
        #expect(Set(all) == Set([.idle, .playing, .paused, .completed, .abandoned]))
    }

    @Test("Status conforms to Sendable / Equatable / Hashable / Codable")
    func statusConformances() throws {
        // Equatable / Hashable
        var set: Set<GameSessionStatus> = []
        for status in GameSessionStatus.allCases {
            set.insert(status)
        }
        #expect(set.count == 5)

        // Codable roundtrip via JSON
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for status in GameSessionStatus.allCases {
            let data = try encoder.encode(status)
            let back = try decoder.decode(GameSessionStatus.self, from: data)
            #expect(back == status)
        }
    }

    // Legal transitions per design.md §How.5.3:
    // idle → playing (start)
    // playing → paused (pause)
    // paused → playing (resume)
    // playing → completed (complete)
    // playing → abandoned (abandon)
    // paused → abandoned (abandon)
    static let legalCases: [(GameSessionStatus, GameSessionTransition)] = [
        (.idle, .start),
        (.playing, .pause),
        (.paused, .resume),
        (.playing, .complete),
        (.playing, .abandon),
        (.paused, .abandon)
    ]

    @Test("All 6 legal transitions return true", arguments: legalCases)
    func legalTransitionsAreLegal(from: GameSessionStatus, transition: GameSessionTransition) {
        #expect(GameSessionStatus.isLegal(from: from, applying: transition))
    }

    @Test("All other (from, transition) pairs are illegal")
    func everyOtherPairIsIllegal() {
        let legal = Set(Self.legalCases.map { Pair($0.0, $0.1) })
        for from in GameSessionStatus.allCases {
            for transition in GameSessionTransition.allCases {
                let pair = Pair(from, transition)
                if !legal.contains(pair) {
                    #expect(
                        !GameSessionStatus.isLegal(from: from, applying: transition),
                        "Expected illegal: \(from) -applying-> \(transition)"
                    )
                }
            }
        }
    }

    private struct Pair: Hashable {
        let from: GameSessionStatus
        let transition: GameSessionTransition
        init(_ from: GameSessionStatus, _ transition: GameSessionTransition) {
            self.from = from
            self.transition = transition
        }
    }
}
