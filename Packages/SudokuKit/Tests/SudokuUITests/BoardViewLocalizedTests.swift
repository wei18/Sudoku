// BoardViewLocalizedTests — per-locale BoardView "inProgress" snapshots.
//
// Store-screenshot redesign (feat/store-screenshots-cb): `BoardView`'s
// ASC-spec board slot now sources a PER-LOCALE baseline (see
// `scripts/build-ascspec-screenshots.py`'s SLOTS matrix) instead of
// compositing a translated caption over the English screenshot. Split out
// of BoardViewTests.swift — with those tests, it pushed the file over
// SwiftLint's file_length ceiling — into this extension file (same target,
// same @Suite via `extension BoardViewTests`).

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import SudokuGameState
import SudokuPersistence
import SudokuEngine

#if canImport(AppKit)
@MainActor
extension BoardViewTests {

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud), arguments: SnapshotLocales.storeLocales)
    func snapshotInProgress_iPhone_light_localized(_ locale: String) throws {
        let viewModel = try makeViewModel(
            clues: Self.inProgressClues,
            userCells: [
                (row: 0, col: 2, digit: 4),
                (row: 0, col: 3, digit: 6),
                (row: 4, col: 4, digit: 5),
            ],
            errorCells: [
                (row: 0, col: 2)
            ],
            selection: GridCoordinate(row: 4, column: 4),
            elapsedSeconds: 201
        )
        let host = hostingView(
            BoardView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            locale: .init(identifier: locale),
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Board-iPhone-light-inProgress-\(locale)")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud), arguments: SnapshotLocales.storeLocales)
    func snapshotInProgress_iPad_light_localized(_ locale: String) throws {
        let viewModel = try makeViewModel(
            clues: Self.inProgressClues,
            userCells: [
                (row: 0, col: 2, digit: 4),
                (row: 0, col: 3, digit: 6),
                (row: 4, col: 4, digit: 5),
            ],
            errorCells: [
                (row: 0, col: 2)
            ],
            selection: GridCoordinate(row: 4, column: 4),
            elapsedSeconds: 201
        )
        let host = hostingView(
            BoardView(viewModel: viewModel),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            locale: .init(identifier: locale),
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Board-iPad-light-inProgress-\(locale)")
        }
    }
}
#endif
