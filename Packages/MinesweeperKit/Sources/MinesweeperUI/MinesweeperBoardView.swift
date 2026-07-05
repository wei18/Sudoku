// MinesweeperBoardView — MVP SwiftUI board renderer.
//
// Renders an `MinesweeperGameViewModel` as a row-major grid of cell buttons:
//   - Tap = reveal OR flag, depending on the on-screen Reveal/Flag mode toggle
//     (#278 Tier-0 #3 — discoverable, works on iPhone tap + Mac click).
//   - Long-press (iOS) / secondary click via context menu (macOS) = toggle flag
//     (accelerators, available in either mode).
//
// The board grid is sized by a GeometryReader (#278 Tier-0 #1/#2): cell side is
// derived from the offered rect, fitting the NON-SQUARE board by its longer axis,
// and the board scrolls instead of shrinking below a tap-target floor.
//
// Win/lose overlay is plain Text on a translucent backdrop — no animation,
// no haptics, no localization (English inline per dispatch spec).

// swiftlint:disable file_length
// Over the 400 limit. The #297 snapshot seam + #329 mode threading + #434
// pause/resume (toolbar toggle + board-cover overlay) pushed a file that was
// already at the limit further over it; the view is cohesive (one board renderer +
// its layout/overlay) and extracting a helper for a test seam would be a larger,
// non-surgical change. Mirrors the SudokuUI/Board/GameViewModel.swift precedent.

public import SwiftUI
public import GameAudio
public import GameCenterClient
import GameShellUI
public import MinesweeperEngine
public import MonetizationCore
import MonetizationUI
internal import MinesweeperGameState
public import MinesweeperPersistence
public import Telemetry

public struct MinesweeperBoardView: View {

    @Environment(\.theme) private var theme
    // #298 #6 (Tier-1 leftover): drive the Mac 2-column side-rail layout. On
    // iPad/Mac (regular width) the board + a control rail sit side-by-side,
    // mirroring Sudoku's BoardView.macLayout; iPhone (compact) keeps the
    // vertical stack. swiftui-interaction-footguns: read `horizontalSizeClass`,
    // which is `.regular` on Mac, not a hardcoded `#if os(macOS)`.
    @Environment(\.horizontalSizeClass) private var sizeClass
    // #455 step 4: app-backgrounding is a save point (the other two are pause
    // and terminal reveal, both inside the VM). Mirrors Sudoku's
    // scenePhase-triggered flush (§How.5.5).
    @Environment(\.scenePhase) private var scenePhase
    // #615: dismisses the presenting fullScreenCover so the Completion overlay's
    // Close returns to the hub — mirrors Sudoku's BoardView.dismiss (close-to-hub).
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: MinesweeperGameViewModel
    // #278 Tier-0 #3: on-screen reveal/flag mode. View-local because it has no
    // engine semantics — it only routes which action a cell tap fires. Mirrors
    // Sudoku's pencil-mode toggle as a discoverable primary control.
    @State private var interactionMode: InteractionMode = .reveal
    // #292: the Completion overlay's VM. Held in `@State` so it survives the
    // board's recomputes (the status bar's 1 Hz TimelineView re-runs `body`
    // every second) — building it inline would reset its leaderboard-slice
    // fetch on every tick. Populated lazily the first time the board reaches a
    // terminal state, cleared on Retry. swiftui-interaction-footguns: a
    // recompute-rebuilt @Observable VM loses its loaded state + re-fires .task.
    @State private var completionViewModel: MinesweeperCompletionViewModel?
    // #681: the pre-first-tap `.idle` board has no exit — `PauseOverlayView` is
    // only mounted while `viewModel.isPaused` (== session `.paused`), and
    // `MinesweeperSession.pause()` deliberately no-ops unless `.playing` (mine
    // placement defers to the first reveal, so pausing an untouched board is
    // meaningless). Rather than force the session through an illegal
    // idle→paused transition, this is a view-local flag: the header button
    // shows the SAME overlay without touching session state at all. Resume just
    // hides it again (no session call); Leave still dismisses as normal.
    @State private var showIdleLeaveOverlay = false
    // U15 (2026-06-03): banner slot wiring. Optional so the merged MVP `init`
    // shapes (used by `#Preview` + tests) keep compiling without monetization.
    // Production callsites wire both via `LiveRouteFactory`.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    // #292: Game Center client forwarded into the Completion overlay's
    // leaderboard-slice VM. Optional so MVP / preview callsites stay no-op
    // (the slice degrades to the sign-in affordance, never blocking the win).
    private let gameCenter: (any GameCenterClient)?
    // #297: snapshot / preview seam. `true` skips the in-body ticker `.task` so
    // a pre-seeded board survives capture and no Completion overlay is drawn
    // over a loss board. Defaults `false` — production never sets it, so the
    // live refresh path is preserved. Pairs with `MinesweeperGameViewModel(seeded:)`.
    private let suppressTickerForSnapshot: Bool
    // #329: daily/practice classification, forwarded to the rebuilt VM on Retry
    // so a retried board keeps the same submit-gating as the original. The
    // `viewModel:` init path takes the VM's mode as already-decided (Retry uses
    // `viewModel.mode`); the `difficulty:seed:` init path threads it explicitly.
    // Defaults `.practice` — the most cautious (no daily submit) value.
    private let mode: GameMode
    // #330 P2: gameplay-audio seam, held at the board so it can (a) start the
    // looping BGM when the board appears and (b) be re-threaded into the VM that
    // Retry rebuilds in place. Defaults `NoopSoundPlaying` so preview / snapshot /
    // MVP callsites stay silent; production wires `LiveSoundPlayer` via the
    // route factory. The `viewModel:` init derives it from the supplied VM is NOT
    // possible (the VM keeps its player private), so callers that pass a built VM
    // also pass the same player for BGM/Retry — defaulting to Noop is safe.
    private let soundPlayer: any SoundPlaying
    // #652: Play Again CTA. When wired, the completion overlay shows "Play Again"
    // above Close. The closure receives the current difficulty so the caller can
    // dismiss and start a fresh board at the same level. `nil` → Close-only
    // (existing behavior; snapshot tests are unaffected).
    private let onPlayAgain: ((Difficulty) -> Void)?

    public init(
        viewModel: MinesweeperGameViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        onPlayAgain: ((Difficulty) -> Void)? = nil,
        suppressTickerForSnapshot: Bool = false,
        completionViewModelForSnapshot: MinesweeperCompletionViewModel? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.soundPlayer = soundPlayer
        self.onPlayAgain = onPlayAgain
        self.suppressTickerForSnapshot = suppressTickerForSnapshot
        // #388 / #315 snapshot seam: pre-seed the Completion overlay's VM so a
        // seeded terminal board renders WITH the overlay mounted (the in-body
        // `.task` that normally seeds it is skipped under
        // `suppressTickerForSnapshot`, and `.onChange` never fires because the
        // board mounts already-terminal — no transition). Defaults nil; the live
        // app always seeds via `.task` / `.onChange`, never this parameter.
        self._completionViewModel = State(initialValue: completionViewModelForSnapshot)
        self.mode = viewModel.mode
    }

    public init(
        difficulty: Difficulty = .beginner,
        seed: UInt64 = 0,
        mode: GameMode = .practice,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        onPlayAgain: ((Difficulty) -> Void)? = nil,
        store: MinesweeperSavedGameStore? = nil,
        recordName: String? = nil
    ) {
        self._viewModel = State(initialValue: MinesweeperGameViewModel(
            difficulty: difficulty,
            seed: seed,
            mode: mode,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            soundPlayer: soundPlayer,
            store: store,
            recordName: recordName
        ))
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.soundPlayer = soundPlayer
        self.onPlayAgain = onPlayAgain
        self.suppressTickerForSnapshot = false
        self.mode = mode
    }

    public var body: some View {
        // #298 #6: compact (iPhone) keeps the vertical stack; regular (iPad /
        // Mac) splits into a 2-column board + control rail, mirroring Sudoku's
        // BoardView.macLayout.
        Group {
            if sizeClass == .regular {
                macLayout
            } else {
                compactLayout
            }
        }
        // #298 #11: theme spacing scale. `.padding()` default is 16, identical
        // to `theme.spacing.medium`, so this is a value-preserving migration (no
        // snapshot churn).
        .padding(theme.spacing.medium)
        // #388: stretch the board's host frame to fill the whole screen BEFORE
        // attaching the Completion overlay. An `.overlay` is laid out within the
        // frame of the view it modifies — the root cause of the prior 16pt inset
        // was that the overlay was attached directly to the `.padding(16)` result,
        // which on iPhone is only as tall as the VStack's *intrinsic* height. So
        // the surface's own `.frame(maxHeight: .infinity)` had nothing to expand
        // into and the live exploded board showed through the border. Pinning to
        // `.infinity` here makes the modified view fill the screen, so the overlay
        // is proposed the full screen and the surface can reach every edge.
        //
        // Alignment stays `.center` — that is already how the playing board is
        // positioned by the host (see the recorded covered/mid-reveal baselines,
        // which sit vertically centered), so this frame is layout-neutral for the
        // playing state: the board keeps its 16pt padding and centered position.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // #292: the post-game Completion surface replaces the old inline
        // `terminalOverlay` (plain Text on material). It covers the whole board
        // on win/lose with the result hero + leaderboard slice + CTAs. Mounted
        // as a full-cover overlay (not a pushed route) because the board owns its
        // terminal state inline and has no completion AppRoute (route-pushed
        // Completion deferred — #386).
        // #518: `.ignoresSafeArea()` removed from the overlay call-site. The
        // background-only safe-area extension is now handled inside
        // `completionSurface()` via a `ZStack` split (background ignores safe
        // area; content remains within it). This keeps the hero icon below the
        // Dynamic Island / status bar safe area while the background colour still
        // fills behind the status bar and home indicator.
        .overlay {
            if viewModel.isTerminal, let completionViewModel {
                completionSurface(completionViewModel)
            }
            // Pause menu — full-screen so the mask hides the whole board and the
            // "Leave Game?" card is centred on the screen (not framed to the board
            // square). Merged close+pause: the only exit/pause affordance.
            // #681: also mounted for the pre-first-tap `.idle` board via
            // `showIdleLeaveOverlay` — same overlay, but Resume just hides the
            // local flag instead of calling `viewModel.resume()` (which would be
            // an illegal idle→paused→playing detour; `resume()` no-ops unless
            // `.paused` anyway, so this branch is required, not just tidier).
            if viewModel.isPaused || showIdleLeaveOverlay {
                PauseOverlayView(
                    onLeave: { dismiss() },
                    onResume: {
                        if viewModel.isPaused {
                            Task { await viewModel.resume() }
                        } else {
                            showIdleLeaveOverlay = false
                        }
                    }
                )
            }
        }
        // Build the Completion VM once when the board crosses into a terminal
        // state (and not on every TimelineView tick). Cleared by Retry below.
        .onChange(of: viewModel.isTerminal) { _, isTerminal in
            if isTerminal, completionViewModel == nil {
                completionViewModel = makeCompletionViewModel()
            } else if !isTerminal {
                completionViewModel = nil
            }
        }
        // #455 step 4: view-lifecycle save points.
        // #539: also pause so the elapsed clock doesn't accrue background time
        // (mirrors Sudoku). #548: pause ONLY on a real `.background` transition —
        // a transient `.inactive` (Control Center / Notification Center peek)
        // just persists, so a momentary glance doesn't force a tap-to-resume.
        // `pause()` calls `persistCurrentState()` internally; when not `.playing`
        // we fall back to a plain persist so the save point is never skipped.
        // VM self-guards, so these are no-ops where the persistence seam isn't wired.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Task {
                    if viewModel.status == .playing {
                        await viewModel.pause()
                    } else {
                        await viewModel.persistCurrentState()
                    }
                }
            case .inactive:
                Task { await viewModel.persistCurrentState() }
            default:
                break
            }
        }
        .onDisappear {
            Task { await viewModel.persistCurrentState() }
        }
        // #330 P2: start the looping background music when the board appears, and
        // stop it when the board goes away (the `.task` is cancelled on disappear).
        // The Live player auto-yields if another app is already playing audio, so
        // this never stomps the user's podcast / music. Skipped for seeded snapshot
        // boards so capture stays side-effect-free. The Noop player (preview / MVP)
        // makes both calls no-ops. NOTE: assets ship in P3 — `playMusic` is silent
        // until then (the Live player tolerates the missing track and logs).
        .task(id: ObjectIdentifier(viewModel)) {
            guard !suppressTickerForSnapshot else { return }
            // #446 part-2: the BGM track is the SHARED asset vended by GameAudioKit
            // under the canonical key "gameplay" (same bytes Sudoku uses); the Live
            // player falls back to `Bundle.module` to find it.
            soundPlayer.playMusic(key: "gameplay")
            // Keep the task alive so its cancellation (board disappear / VM swap)
            // is what stops the music — mirrors the ticker's lifetime-binding.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
            soundPlayer.stopMusic()
        }
        // #298 #9: single elapsed-mirror ticker, replacing the prior
        // TimelineView-nested-`.task` 1 Hz hack (which re-fired a fresh `.task`
        // on every timeline tick — swiftui-interaction-footguns: .task re-fire).
        // Mirrors Sudoku BoardView: one `.task(id:)` owning a `while
        // !Task.isCancelled { sleep }` loop, cancelled automatically on
        // disappear. Keyed on the VM's identity so Retry (which swaps the VM in
        // place at the same seed) restarts the loop with a fresh clock.
        .task(id: ObjectIdentifier(viewModel)) {
            // #297: skip the ticker for a seeded snapshot board (see property).
            guard !suppressTickerForSnapshot else { return }
            // Pull once immediately so the first frame isn't stale. The very
            // first snapshot could already be terminal (e.g. a board restored
            // into a finished state); `.onChange` only fires on a transition,
            // so seed the completion VM here too.
            await viewModel.refresh()
            if viewModel.isTerminal, completionViewModel == nil {
                completionViewModel = makeCompletionViewModel()
            }
            // Then poll once per second while the game is live. The elapsed
            // label re-renders because `refresh()` republishes the @Observable
            // snapshot (the in-board `clockLabel` reads it). Stop polling once
            // terminal (the clock is frozen) but keep the task alive so
            // cancellation stays tied to the view.
            while !Task.isCancelled {
                if viewModel.status == .playing {
                    await viewModel.refresh()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Compact (iPhone) layout

    private var compactLayout: some View {
        // Spacing literal preserved verbatim (12) from the pre-#298 VStack so the
        // recorded iPhone covered-board snapshots don't churn. The theme spacing
        // scale (#298 #11) is applied to the NEW Mac layout below; migrating the
        // compact literal would re-record baselines and is deferred to #11.
        VStack(spacing: 12) {
            statusBar
            boardGrid
            modeToggle
            bannerSlot
        }
    }

    // MARK: - Mac (regular) 2-column layout (#298 #6)
    //
    // Mirrors Sudoku's BoardView.macLayout (locked 2026-05-30): outer maxWidth
    // capped + centered, board on the left capped to a square, a ~260 pt control
    // rail on the right. MS's rail carries the status bar + the Reveal/Flag mode
    // toggle (MS has no digit pad), keeping the iPhone grid out of the wide Mac
    // detail pane (#298 critique: the board currently renders the iPhone stack
    // in the Mac detail).
    private var macLayout: some View {
        VStack(spacing: theme.spacing.medium) {
            HStack(alignment: .top, spacing: theme.spacing.large) {
                macBoardColumn
                controlRail
            }
            bannerSlot
        }
        .frame(maxWidth: Self.macOuterMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, theme.spacing.medium)
    }

    private static let macOuterMaxWidth: CGFloat = 900
    private static let macBoardMaxSide: CGFloat = 600
    private static let macRailWidth: CGFloat = 260

    private var macBoardColumn: some View {
        boardGrid
            .frame(maxWidth: Self.macBoardMaxSide, maxHeight: Self.macBoardMaxSide)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // The Mac control rail: status read-out + the Reveal/Flag toggle, stacked
    // vertically in a fixed-width column. The toggle keeps `.segmented` styling
    // (same control as iPhone) — only the placement changes.
    private var controlRail: some View {
        VStack(spacing: theme.spacing.medium) {
            statusBar
            modeToggle
            Spacer(minLength: 0)
        }
        .frame(width: Self.macRailWidth)
    }

    // MARK: - Banner slot
    //
    // Banner sits between the grid and the bottom edge. Mirrors Sudoku's
    // BoardView slot pattern. Suppressed during terminal states (win / lose) —
    // showing an ad on top of the Completion surface contradicts the moment's
    // tone, same way Sudoku suppresses banners during pause.
    @ViewBuilder
    private var bannerSlot: some View {
        // #434: also suppress the banner while paused — mirrors Sudoku, which
        // gates its banner behind `if !viewModel.isPaused` so the paused board
        // reads as a deliberate quiet state.
        if !viewModel.isTerminal, !viewModel.isPaused, let adProvider, let adGate {
            BannerSlotView(
                adProvider: adProvider,
                adGate: adGate,
                // Live provider conforms to `BannerViewProviding`; fakes / macOS
                // return nil → honest fallback. Cast keeps MinesweeperUI free of
                // an AdsAdMob import (§9.1).
                bannerHost: adProvider as? any BannerViewProviding,
                backgroundColor: theme.surface.placeholder.resolved,
                progressTint: theme.accent.primary.resolved,
                captionColor: theme.text.secondary.resolved,
                dismissTint: theme.accent.muted.resolved.opacity(0.7)
            )
        }
    }

    // MARK: - Status bar

    // #540: mirror Sudoku's header fix — keep the status bar robust at large /
    // accessibility text sizes WITHOUT reading `@Environment(\.dynamicTypeSize)`
    // (unreliable inside the modal). `ViewThatFits(in: .horizontal)` picks the
    // single-row HStack when it fits the actual offered width and falls back to
    // a two-row VStack when the enlarged labels would overflow. At default
    // sizes the single row always fits → snapshot baselines unchanged.
    private var statusBar: some View {
        // #540: cap the status bar's Dynamic Type at `.xLarge` so the mine
        // count / status / elapsed fields can't scale tall enough to clip off
        // the leading edge at accessibility sizes (mirrors Sudoku's board
        // header + digit-pad cap). Clamps only ABOVE `.xLarge`, so default
        // `.large` — and the committed MS snapshots — are byte-identical.
        ViewThatFits(in: .horizontal) {
            singleRowStatusBar
            twoRowStatusBar
        }
        .font(.subheadline)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    // Single row — identical structure to the pre-#540 status bar, so the
    // recorded MS snapshots stay byte-identical when this branch is chosen.
    private var singleRowStatusBar: some View {
        // #298 #9: plain HStack — the elapsed/flag/status fields are read
        // straight off the @Observable view model, which republishes when the
        // ticker loop (`.task(id:)` on the body) refreshes the snapshot each
        // second. No TimelineView, no nested `.task`.
        HStack {
            mineCountLabel
            Spacer()
            statusLabel
            Spacer()
            clockLabel
            pauseToggle
        }
    }

    // Two-row fallback: row 1 = mine count + status; row 2 = clock + pause.
    private var twoRowStatusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { mineCountLabel; Spacer(); statusLabel }
            HStack { clockLabel; Spacer(); pauseToggle }
        }
    }

    private var mineCountLabel: some View {
        Label("\(viewModel.remainingMineCount)", systemImage: "flag.fill")
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // The in-board elapsed clock, shown in the status bar. Since the board now
    // fills the screen height (#F3), the modal's floating timer capsule would
    // overlap the top mine rows on Intermediate/Expert — so Minesweeper no
    // longer feeds that capsule (see the ticker below) and surfaces the clock
    // here instead. mm:ss to match the rest of the app / Sudoku.
    private var clockLabel: some View {
        Label(
            String(format: "%d:%02d", viewModel.elapsedSeconds / 60, viewModel.elapsedSeconds % 60),
            systemImage: "clock"
        )
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    // MARK: - Pause / resume toggle (#434)

    // Mirrors Sudoku's BoardView toolbar toggle: a single button flipping
    // between Pause and Resume, icon-only on iPhone (compact) and icon + text
    // on Mac (regular). Hidden only in terminal states (won/lost — the
    // Completion overlay owns the exit there). #681: also rendered in `.idle`
    // (pre-first-tap) — that state has no timer to freeze, so tapping opens the
    // same overlay as a leave-confirm rather than calling `pause()` (which
    // no-ops on `.idle` by design). The board-cover overlay handles
    // resume-by-tapping-the-board; this is the explicit header control.
    @ViewBuilder
    private var pauseToggle: some View {
        if viewModel.status == .playing || viewModel.isPaused || viewModel.status == .idle {
            Button {
                if viewModel.isPaused {
                    Task { await viewModel.resume() }
                } else if viewModel.status == .idle {
                    showIdleLeaveOverlay = true
                } else {
                    Task { await viewModel.pause() }
                }
            } label: {
                if sizeClass == .regular {
                    Label(
                        viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                } else {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                }
            }
            // #647: expand tap target to ≥44×44 pt (HIG minimum) without
            // enlarging the visible glyph. `.contentShape(Rectangle())` makes
            // the full frame hit-testable under `.plain` button style.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(viewModel.isPaused ? "Resume" : "Pause")
            .accessibilityIdentifier("minesweeper.board.pauseToggle")
        }
    }

    private var statusText: String {
        switch viewModel.status {
        case .idle:    return "Ready"
        case .playing: return "Playing"
        case .paused:  return "Paused"
        case .won:     return "You won"
        case .lost:    return "Boom"
        }
    }

    // MARK: - Mode toggle (#278 Tier-0 #3)

    // Discoverable primary control for reveal vs flag. Modeled on Sudoku's
    // pencil-mode toggle (DigitPadView): a segmented control that routes which
    // action a cell tap fires. Works identically on iPhone (tap) and Mac
    // (click) — the previously invisible right-click/long-press are now just
    // accelerators on top of this.
    private var modeToggle: some View {
        Picker("Tap mode", selection: $interactionMode) {
            Label("Reveal", systemImage: "hand.tap").tag(InteractionMode.reveal)
            Label("Flag", systemImage: "flag.fill").tag(InteractionMode.flag)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Tap action mode")
        .accessibilityValue(interactionMode == .flag ? "Flag" : "Reveal")
    }

    // MARK: - Grid

    // Cell-side floor (pt). Below this the board scrolls rather than shrinking
    // cells into an un-tappable size (#278 Tier-0 #2). 32pt keeps a deliberate
    // reveal tap comfortable; flag taps are now mode-driven so no precision
    // long-press is required on small cells.
    private static let minCellSide: CGFloat = 32
    private static let cellSpacing: CGFloat = 2

    private var boardGrid: some View {
        // GeometryReader reports the offered rectangle; we derive a single
        // square cell side that fits the NON-SQUARE board by its longer axis
        // (Expert is 16×30), then floor it for crisp glyphs. Three branches:
        //   fits-both: center the floored grid in the offered rect — mirrors
        //     Sudoku BoardView's centered frame, avoids top-leading ScrollView drift.
        //   fill-height-scroll-horizontal: board is wider than the offered width
        //     but cells can still hit the tap-target floor at the offered height;
        //     fill height and scroll horizontally rather than shrinking.
        //   small-phone-fallback: cells would drop below the tap-target floor
        //     even at the offered height; fix cell side at the floor and scroll
        //     both axes (#278 Tier-0 #2).
        GeometryReader { geo in
            let rows = viewModel.rows
            let cols = viewModel.columns
            let spacing = Self.cellSpacing
            // Subtract the inter-cell gaps before dividing so the cells (not
            // the gaps) fill the offered box exactly.
            let availW = geo.size.width - spacing * CGFloat(cols - 1)
            let availH = geo.size.height - spacing * CGFloat(rows - 1)
            let fitted    = floor(min(availW / CGFloat(cols), availH / CGFloat(rows)))
            let heightFit = floor(availH / CGFloat(rows))
            if fitted >= Self.minCellSide {
                gridStack(rows: rows, cols: cols, cellSide: fitted, spacing: spacing)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            } else if heightFit >= Self.minCellSide {
                ScrollView(.horizontal) {
                    gridStack(rows: rows, cols: cols, cellSide: heightFit, spacing: spacing)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    gridStack(rows: rows, cols: cols, cellSide: Self.minCellSide, spacing: spacing)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // Fill all available height offered by the parent VStack so the board
        // expands into the space between the status bar and the mode toggle,
        // rather than reserving a square-ish aspect-ratio slot.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // #434 pause cover moved to the top-level body `.overlay` so the mask
        // covers the whole screen and the "Leave Game?" card is screen-centred.
    }

    private func gridStack(rows: Int, cols: Int, cellSide: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        MinesweeperCellButton(
                            cell: viewModel.cell(row: row, col: col),
                            row: row,
                            column: col,
                            side: cellSide,
                            mode: interactionMode,
                            // #298 #7: on a loss, surface every mine. The detonated
                            // cell is already `.revealed`; the rest are still hidden
                            // and the cell button paints them from `cell.isMine`.
                            revealMines: viewModel.status == .lost,
                            onReveal: {
                                Task { await viewModel.reveal(row: row, col: col) }
                            },
                            onToggleFlag: {
                                Task { await viewModel.toggleFlag(row: row, col: col) }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Completion overlay (#292)

    /// Construct the post-game VM from the current terminal snapshot. Called
    /// once per terminal transition (see `.onChange` / `.task` above) so the
    /// leaderboard-slice fetch + degrade state aren't reset by recomputes. The
    /// VM fetches the local-player-centred slice on a win, and stays hero-only
    /// on a loss.
    private func makeCompletionViewModel() -> MinesweeperCompletionViewModel {
        MinesweeperCompletionViewModel(
            didWin: viewModel.status == .won,
            elapsedSeconds: viewModel.elapsedSeconds,
            leaderboardId: MinesweeperLeaderboardID.daily(
                for: viewModel.session.difficulty
            ),
            gameCenter: gameCenter
        )
    }

    // The themed post-game surface. Retry rebuilds the session in place at the
    // SAME difficulty + seed, and clears the Completion VM so the next terminal
    // state rebuilds a fresh slice. Note: mine placement is deferred to the
    // first reveal, so the layout is determined by seed + opening tap — an
    // identical first tap reproduces the same board, a different one does not.
    //
    // #518: Background/content split for safe-area correctness (swiftui-interaction-
    // footguns: `.ignoresSafeArea` must wrap only the background layer, not the
    // content, to avoid the hero icon bleeding under the Dynamic Island). The ZStack
    // lets the background colour fill behind the status bar and home indicator while
    // the CompletionView content stays within the top/bottom safe area, centering
    // the card in the visible screen region.
    // #518: the GameModalContent top-chrome row (timer chip + ✕) is hidden while
    // this overlay is visible. That signal is driven by overlay presence via
    // `.onChange(of: completionViewModel != nil)` above — NOT isTerminal — so the
    // Close action (which clears the VM but leaves the game terminal) restores the
    // chrome and the user can leave the revealed board (CR #518-R2).
    @ViewBuilder
    private func completionSurface(_ completionViewModel: MinesweeperCompletionViewModel) -> some View {
        // #615: now uses the shared `CompletionOverlayScaffold` (GameShellUI) so MS
        // matches Sudoku — centred card, warm-paper background extended behind the
        // safe area, bottom-pinned accent Close. Close clears the overlay VM then
        // dismisses the presenting fullScreenCover so the player returns to the hub
        // (mirrors Sudoku's close-to-hub). Previously MS only cleared the VM and
        // revealed the boomed board, leaving the player trapped in the modal — the
        // divergence #615 surfaced. Retry / New Game / Leaderboard CTAs stay removed
        // at this injection site (SDD-003 Epic 4 spec note: "移除發生在各 app 的注入點").
        // #652: Play Again — dismiss current board then present a fresh game at the
        // same difficulty. Only rendered when `onPlayAgain` is wired by the factory.
        let difficulty = viewModel.session.difficulty
        CompletionOverlayScaffold(
            onClose: {
                self.completionViewModel = nil
                dismiss()
            },
            onPlayAgain: onPlayAgain.map { playAgain in
                {
                    self.completionViewModel = nil
                    dismiss()
                    playAgain(difficulty)
                }
            },
            card: {
                MinesweeperCompletionView(
                    viewModel: completionViewModel,
                    onClose: nil
                )
            }
        )
    }
}

// `InteractionMode` + `MinesweeperCellButton` were extracted to
// `MinesweeperCellButton.swift` (#292) to keep this file under the lint ceiling.

// MARK: - Preview

#Preview("Beginner 9x9") {
    MinesweeperBoardView(difficulty: .beginner, seed: 42)
        .frame(minWidth: 360, minHeight: 480)
}
// swiftlint:enable file_length
