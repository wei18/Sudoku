// Board fixtures that render no ads. Every board builds a banner slot, and a
// slot mounted without `\.bannerSession` in its environment asserts in DEBUG
// (#1058), so boards hosted by snapshot suites inject
// `BannerSessionModel.disabled`.

import SwiftUI
import MonetizationUI
@testable import SudokuUI

@MainActor
func adFreeBoard(_ viewModel: GameViewModel) -> some View {
    BoardView(viewModel: viewModel).environment(\.bannerSession, .disabled)
}
