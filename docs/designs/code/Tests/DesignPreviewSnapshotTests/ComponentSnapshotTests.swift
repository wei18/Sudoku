// Snapshots for atomic components. Covers SnapshotMatrix §3 (17 cases).

import XCTest
import SwiftUI
import SnapshotTesting
@testable import DesignPreviewKit

@MainActor
final class ComponentSnapshotTests: XCTestCase {

    private func assertComponentSnapshot(
        _ view: some View,
        size: CGSize = DeviceSize.component,
        colorScheme: ColorScheme = .light,
        locale: Locale = Locale(identifier: "en"),
        dynamicTypeSize: DynamicTypeSize = .large,
        named: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let host = hostingView(
            view.padding(),
            size: size,
            colorScheme: colorScheme,
            locale: locale,
            dynamicTypeSize: dynamicTypeSize
        )
        if let failure = verifySnapshot(
            of: host,
            as: .image(precision: snapshotPrecision, perceptualPrecision: snapshotPerceptualPrecision),
            named: named,
            snapshotDirectory: snapshotDirectory(forTestFile: file),
            file: file,
            testName: "ComponentSnapshots",
            line: line
        ) {
            XCTFail(failure, file: file, line: line)
        }
    }

    // ModeCard
    func test_modeCard_light_en() {
        assertComponentSnapshot(
            VStack(spacing: 12) {
                ModeCard(title: "Daily", subtitle: "3 puzzles today", symbol: "calendar")
                ModeCard(title: "Practice", subtitle: "Mixed difficulty pool", symbol: "dice")
            },
            size: CGSize(width: 393, height: 220),
            named: "modeCard_light_en"
        )
    }
    func test_modeCard_dark_en() {
        assertComponentSnapshot(
            VStack(spacing: 12) {
                ModeCard(title: "Daily", subtitle: "3 puzzles today", symbol: "calendar")
                ModeCard(title: "Practice", subtitle: "Mixed difficulty pool", symbol: "dice")
            },
            size: CGSize(width: 393, height: 220),
            colorScheme: .dark,
            named: "modeCard_dark_en"
        )
    }

    // PuzzleCard
    func test_puzzleCard_light_en_done() {
        assertComponentSnapshot(
            PuzzleCard(difficultyLabel: "Easy", completedTime: "4:11"),
            size: CGSize(width: 393, height: 150),
            named: "puzzleCard_light_en_done"
        )
    }
    func test_puzzleCard_light_en_pending() {
        assertComponentSnapshot(
            PuzzleCard(difficultyLabel: "Medium", completedTime: nil),
            size: CGSize(width: 393, height: 150),
            named: "puzzleCard_light_en_pending"
        )
    }
    func test_puzzleCard_dark_en_done() {
        assertComponentSnapshot(
            PuzzleCard(difficultyLabel: "Easy", completedTime: "4:11"),
            size: CGSize(width: 393, height: 150),
            colorScheme: .dark,
            named: "puzzleCard_dark_en_done"
        )
    }

    // DigitPad
    func test_digitPad_light_en() {
        assertComponentSnapshot(
            DigitPad(),
            size: CGSize(width: 500, height: 120),
            named: "digitPad_light_en"
        )
    }
    func test_digitPad_dark_en() {
        assertComponentSnapshot(
            DigitPad(),
            size: CGSize(width: 500, height: 120),
            colorScheme: .dark,
            named: "digitPad_dark_en"
        )
    }

    // ShimmerCard
    func test_shimmerCard_light_en() {
        assertComponentSnapshot(
            ShimmerCard(),
            size: CGSize(width: 393, height: 220),
            named: "shimmerCard_light_en"
        )
    }
    func test_shimmerCard_dark_en() {
        assertComponentSnapshot(
            ShimmerCard(),
            size: CGSize(width: 393, height: 220),
            colorScheme: .dark,
            named: "shimmerCard_dark_en"
        )
    }

    // LeaderboardRow
    func test_leaderboardRow_light_en_default() {
        assertComponentSnapshot(
            LeaderboardRow(entry: .init(rank: 1, name: "alice", time: "3:48", isMe: false)),
            size: CGSize(width: 393, height: 80),
            named: "leaderboardRow_light_en_default"
        )
    }
    func test_leaderboardRow_light_en_me() {
        assertComponentSnapshot(
            LeaderboardRow(entry: .init(rank: 17, name: "you", time: "4:11", isMe: true)),
            size: CGSize(width: 393, height: 80),
            named: "leaderboardRow_light_en_me"
        )
    }
    func test_leaderboardRow_dark_en_me() {
        assertComponentSnapshot(
            LeaderboardRow(entry: .init(rank: 17, name: "you", time: "4:11", isMe: true)),
            size: CGSize(width: 393, height: 80),
            colorScheme: .dark,
            named: "leaderboardRow_dark_en_me"
        )
    }
    func test_leaderboardRow_light_en_AX3() {
        assertComponentSnapshot(
            LeaderboardRow(entry: .init(rank: 17, name: "you", time: "4:11", isMe: true)),
            size: CGSize(width: 393, height: 200),
            dynamicTypeSize: .accessibility3,
            named: "leaderboardRow_light_en_AX3"
        )
    }

    // ResumePill
    func test_resumePill_light_en() {
        assertComponentSnapshot(
            ResumePill(difficultyLabel: "Easy", elapsed: "3:21"),
            size: CGSize(width: 393, height: 100),
            named: "resumePill_light_en"
        )
    }
    func test_resumePill_dark_ja() {
        assertComponentSnapshot(
            ResumePill(difficultyLabel: "Easy", elapsed: "3:21"),
            size: CGSize(width: 393, height: 100),
            colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "resumePill_dark_ja"
        )
    }

    // GeneratorExhaustedAlert
    func test_generatorExhaustedAlert_daily_light_en() {
        assertComponentSnapshot(
            GeneratorExhaustedAlert(surface: .daily),
            size: CGSize(width: 393, height: 320),
            named: "generatorExhaustedAlert_daily_light_en"
        )
    }
    func test_generatorExhaustedAlert_practice_dark_en() {
        assertComponentSnapshot(
            GeneratorExhaustedAlert(surface: .practice),
            size: CGSize(width: 393, height: 320),
            colorScheme: .dark,
            named: "generatorExhaustedAlert_practice_dark_en"
        )
    }
}
