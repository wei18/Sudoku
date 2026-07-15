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
// #720 G3: `LastSelectionStore` backs the tap-mode persistence below.
// MinesweeperUI already depends on GameAppKit for `GameRootViewModel`, so this
// is not a new module edge.
internal import GameAppKit

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
    // #762 PR3: content-tier spacing (two-tier contract, design-system.md
    // §Spacing scale). Each wraps a self-contained content flow (the Mac
    // control rail's own stack / the mode-toggle chip's label / the two-row
    // status-bar fallback), mirroring GameShellUI's `PracticeHubShellView`
    // main-content-stack and `HomeModeCard.cardPadding` precedents (PR1) —
    // NOT screen margins, card-outer gaps, or board-cell geometry, which stay
    // structural per the contract and are called out at their call sites below.
    @ScaledSpacing(.medium) private var railContentGap
    @ScaledSpacing(.small) private var toggleChipPadding
    @ScaledSpacing(.extraSmall) private var twoRowStatusGap

    @State private var viewModel: MinesweeperGameViewModel
    // #278 Tier-0 #3: on-screen reveal/flag mode. View-local because it has no
    // engine semantics — it only routes which action a cell tap fires. Mirrors
    // Sudoku's pencil-mode toggle as a discoverable primary control.
    // #720 G3: seeded from `UserDefaults` (via `LastSelectionStore`) instead of
    // always starting at `.reveal`, so the player's last tap-mode choice
    // survives opening a new board.
    // #796: the seed read moved out of this property initializer (which ran
    // against `Self.tapModeStore`, hard-wired to `UserDefaults.standard`) and
    // into both `init` bodies below, so it can read the injected
    // `tapModeDefaults` instead. The swiftpm test host's persistent defaults
    // domain otherwise leaks a prior run's `tapMode` value into every
    // snapshot recording — see `tapModeDefaults` below. `internal` (not
    // `private`), mirroring `tapModeKey` below, so
    // `MinesweeperBoardViewTapModeTests` can assert the injected store
    // actually seeds this value without a live SwiftUI render tree.
    @State var interactionMode: InteractionMode
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
    // #815: pinch-to-zoom committed scale, composed ON TOP of the #764
    // `cellSizing` ladder result (never inside it — `cellSizing` stays a pure
    // floor/branch decision with its own frozen unit tests). Applies only to
    // the two SCROLL branches (`heightFitScrollHorizontal` /
    // `pinnedFloorScrollBoth`) — see the design note on `pinchToZoomGesture`
    // below for why the `fitted` branch (Beginner, typically) is excluded.
    // Deliberately view-local `@State`, never written to `UserDefaults`:
    // #815 scope requires zoom to reset per board session, not persist. It IS
    // reset explicitly on a VM-identity change (new board) — see the
    // `ObjectIdentifier`-keyed `.onChange` in `body` below, mirroring the
    // existing VM-identity-keyed ticker/BGM `.task(id:)`s.
    @State private var zoomScale: CGFloat = 1.0
    // Live in-gesture magnification factor. `@GestureState` auto-resets to
    // 1.0 the instant the pinch ends or is cancelled, so `pinchToZoomGesture`
    // below has exactly one commit point (`.onEnded`) and can never leak a
    // stale in-flight value into the next gesture.
    @GestureState private var pinchMagnification: CGFloat = 1.0
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
    // #796: the store backing the tap-mode toggle's seed/persist round trip
    // (#720 G3). Defaults `.standard` so every production call site compiles
    // and behaves unchanged; snapshot/ASC-screenshot tests MUST pass an
    // isolated `UserDefaults(suiteName:)` instead — the swiftpm test host's
    // shared `.standard` domain otherwise leaks a prior run's `tapMode` key
    // into deterministic recordings (found during #786's re-record).
    private let tapModeDefaults: UserDefaults

    public init(
        viewModel: MinesweeperGameViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        onPlayAgain: ((Difficulty) -> Void)? = nil,
        suppressTickerForSnapshot: Bool = false,
        completionViewModelForSnapshot: MinesweeperCompletionViewModel? = nil,
        tapModeDefaults: UserDefaults = .standard
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
        self.tapModeDefaults = tapModeDefaults
        self._interactionMode = State(initialValue: Self.interactionMode(
            fromRawValue: Self.tapModeStore(defaults: tapModeDefaults).load()
        ))
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
        recordName: String? = nil,
        personalRecordStore: MinesweeperPersonalRecordStore? = nil,
        tapModeDefaults: UserDefaults = .standard
    ) {
        self._viewModel = State(initialValue: MinesweeperGameViewModel(
            difficulty: difficulty,
            seed: seed,
            mode: mode,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            soundPlayer: soundPlayer,
            store: store,
            recordName: recordName,
            personalRecordStore: personalRecordStore
        ))
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.soundPlayer = soundPlayer
        self.onPlayAgain = onPlayAgain
        self.suppressTickerForSnapshot = false
        self.mode = mode
        self.tapModeDefaults = tapModeDefaults
        self._interactionMode = State(initialValue: Self.interactionMode(
            fromRawValue: Self.tapModeStore(defaults: tapModeDefaults).load()
        ))
    }

    // MARK: - Overlay-active predicate (#763)

    /// True whenever this board's own Pause/idle-leave or Completion overlay
    /// is up. MUST track the EXACT same condition as the `.overlay { … }`
    /// mounted in `body` — it feeds the `.preference` published right after
    /// that overlay, which `RootShellView` uses to mask + disable the macOS
    /// sidebar (see `BoardModalOverlayActivePreferenceKey`).
    var isModalOverlayActive: Bool {
        (viewModel.isTerminal && completionViewModel != nil) || viewModel.isPaused || showIdleLeaveOverlay
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
        // #762 PR3 re-tier: structural (screen edge inset for the whole board
        // host) — stays fixed per the two-tier contract, especially since the
        // `.frame(maxHeight: .infinity)` + overlay geometry below is written
        // against this exact inset (see the comment there). Correctly a
        // `theme.spacing.*` token already; no change.
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
        // #763: publish whether the overlay above is up, so the macOS split-view
        // shell (RootShellView) can also mask + disable the sidebar — this
        // overlay's `.ignoresSafeArea()` only fills the detail column there, not
        // the whole split view. MUST track the exact same condition as `.overlay`
        // above; see `isModalOverlayActive` below.
        .preference(key: BoardModalOverlayActivePreferenceKey.self, value: isModalOverlayActive)
        // Build the Completion VM once when the board crosses into a terminal
        // state (and not on every TimelineView tick). Cleared by Retry below.
        .onChange(of: viewModel.isTerminal) { _, isTerminal in
            if isTerminal, completionViewModel == nil {
                completionViewModel = makeCompletionViewModel()
            } else if !isTerminal {
                completionViewModel = nil
            }
        }
        // #815: zoom resets per board session — a new VM identity means a new
        // board (fresh game, Play Again, or a loader-driven Retry), so drop
        // any pinch-to-zoom the player left on the previous board rather than
        // carrying it forward. Mirrors the VM-identity-keyed `.task(id:)`s
        // below (ticker / BGM), which restart on the exact same signal.
        .onChange(of: ObjectIdentifier(viewModel)) { _, _ in
            zoomScale = 1.0
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
        // #762 PR3 re-tier: structural (top-level screen scaffold — mirrors
        // `macLayout`'s analogous outer `VStack` below, both separating the
        // board's major regions from the banner slot). Structural spacing MUST
        // route through a token or named constant, never a bare literal, so
        // this off-scale value (12 — no matching `SpacingTokens` tier) moves
        // into `compactStackGap` unchanged; zero pixel/snapshot diff.
        VStack(spacing: Self.compactStackGap) {
            statusBar
            boardGrid
            modeToggle
            bannerSlot
        }
    }

    // spacing-exempt: 12pt predates the 5-tier `SpacingTokens` scale — see the
    // re-tier comment on `compactLayout` above for why this stays a fixed
    // named constant instead of `theme.spacing.*` (#762 PR3).
    private static let compactStackGap: CGFloat = 12

    // MARK: - Mac (regular) 2-column layout (#298 #6)
    //
    // Mirrors Sudoku's BoardView.macLayout (locked 2026-05-30): outer maxWidth
    // capped + centered, board on the left capped to a square, a ~260 pt control
    // rail on the right. MS's rail carries the status bar + the Reveal/Flag mode
    // toggle (MS has no digit pad), keeping the iPhone grid out of the wide Mac
    // detail pane (#298 critique: the board currently renders the iPhone stack
    // in the Mac detail).
    private var macLayout: some View {
        // #762 PR3 re-tier: all three `theme.spacing.*` uses below are
        // structural — the outer `VStack` gap is the chrome seam to the
        // banner slot (mirrors `compactLayout`'s equivalent seam above), the
        // `HStack` gap is the board-vs-control-rail column split (a
        // structural layout division, not text/icon-adjacent content), and
        // the trailing `.padding` is the Mac screen edge inset
        // (design-system.md §Spacing scale pairing table). Correctly
        // `theme.spacing.*` tokens already; no change.
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
    // vertically in a fixed-width column. #724: the toggle is the same single
    // icon button as iPhone — only the placement changes.
    private var controlRail: some View {
        // #762 PR3 re-tier: content tier — this is the rail's own main
        // content stack (statusBar + modeToggle), mirroring GameShellUI's
        // `PracticeHubShellView` content-stack precedent (PR1), not a
        // screen-margin or card-outer gap. The fixed rail WIDTH is untouched
        // (this spacing only affects the vertical gap, which the trailing
        // `Spacer` absorbs), so scaling it carries no overflow risk.
        VStack(spacing: railContentGap) {
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
                // #688 item 2: was `theme.surface.placeholder.resolved` — the
                // "card" placeholder tone reads as a mismatched seam against
                // the page background (audit-ms-01, dark mode). Match the
                // page background instead so an empty/loading slot is
                // invisible; mirrors the same fix in `GameHomeView`.
                backgroundColor: theme.surface.background.resolved,
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
        // #762 PR3 re-tier: content tier (gap between the two label rows) —
        // 4 matches `SpacingTokens.extraSmall`. Safe to scale: the parent
        // `statusBar` already clamps `dynamicTypeSize` to `.xLarge` (see
        // above), which caps `ScaledSpacing`'s own multiplier at 1.05×.
        VStack(alignment: .leading, spacing: twoRowStatusGap) {
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
                if viewModel.status == .idle {
                    // #681 CR: label/behavior match — in `.idle` the tap opens
                    // the Leave confirm, not a pause, so show ✕ / "Leave"
                    // (reusing the pause overlay's own `leave.game.leave` key
                    // from the app catalog; no new string).
                    if sizeClass == .regular {
                        Label("leave.game.leave", systemImage: "xmark")
                    } else {
                        Image(systemName: "xmark")
                    }
                } else if sizeClass == .regular {
                    Label(
                        pauseToggleTitle,
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
            .accessibilityLabel(
                viewModel.status == .idle
                    ? Text("leave.game.leave")
                    : Text(pauseToggleTitle)
            )
            .accessibilityIdentifier("minesweeper.board.pauseToggle")
        }
    }

    // #741: the Mac-regular `Label` title and the accessibility label both
    // showed the same Resume/Pause word via a bare ternary literal — that
    // expression resolves to a runtime `String`, not a `LocalizedStringKey`,
    // so it bypassed the catalog entirely (same bug class as the mode-toggle
    // strings #731 already fixed below). Reuses the "Pause"/"Resume" keys
    // #434 already added for this same toolbar toggle.
    private var pauseToggleTitle: String {
        viewModel.isPaused
            ? String(localized: "Resume", bundle: .main)
            : String(localized: "Pause", bundle: .main)
    }

    private var statusText: String {
        // #741: this switch fed bare English literals straight into `Text`
        // (a runtime `String`, not a `LocalizedStringKey` literal, so it
        // bypassed the catalog entirely). "You won" / "Boom" reuse the keys
        // #421 already added for the Completion screen's hero title.
        switch viewModel.status {
        case .idle:    return String(localized: "Ready", bundle: .main)
        case .playing: return String(localized: "Playing", bundle: .main)
        case .paused:  return String(localized: "Paused", bundle: .main)
        case .won:     return String(localized: "You won", bundle: .main)
        case .lost:    return String(localized: "Boom", bundle: .main)
        }
    }

    // MARK: - Tap-mode persistence (#720 G3)

    // Reuses the same `LastSelectionStore` seam GameAppKit already provides
    // for the Practice-difficulty gaps (G1 Sudoku / G2 Minesweeper) rather
    // than inventing a bespoke UserDefaults wrapper — MinesweeperUI already
    // has the GameAppKit dependency (`GameRootViewModel`), so this needs no
    // new module edge. `tapModeKey` + `interactionMode(fromRawValue:)` /
    // `rawValue(for:)` are `internal` (not `private`) so
    // `MinesweeperBoardViewTapModeTests` can exercise the exact round trip
    // production uses without a live SwiftUI render tree.
    static let tapModeKey = "com.wei18.minesweeper.board.tapMode"

    // #796: parameterized over the injected `defaults` (was a fixed
    // `.standard` computed property) so both `init`s and `modeToggle` below
    // read/write through the SAME store this instance was constructed with,
    // instead of always touching the shared `UserDefaults.standard` domain.
    static func tapModeStore(defaults: UserDefaults) -> LastSelectionStore {
        LastSelectionStore(key: tapModeKey, fallback: "reveal", defaults: defaults)
    }

    static func interactionMode(fromRawValue rawValue: String) -> InteractionMode {
        rawValue == "flag" ? .flag : .reveal
    }

    static func rawValue(for mode: InteractionMode) -> String {
        mode == .flag ? "flag" : "reveal"
    }

    // MARK: - Mode toggle (#278 Tier-0 #3, #724, #767)

    // Discoverable primary control for reveal vs flag. #724: the segmented
    // Picker (two always-visible options) was replaced with a single icon
    // toggle button — same role (routes which action a cell tap fires), half
    // the footprint. #767 (audit N2): an icon-only button gave sighted users
    // no in-context hint of which mode was active or what a tap would do —
    // the mode name was VoiceOver-only. The label now pairs the icon with
    // the same "Reveal"/"Flag" text already in the catalog (#742), so the
    // active mode reads without opening the a11y tree. Tapping flips to the
    // other mode. Long-press-to-flag (MinesweeperCellButton, unchanged)
    // still works as the accelerator in `.reveal` mode.
    private var modeToggle: some View {
        Button {
            interactionMode = interactionMode == .reveal ? .flag : .reveal
            // #720 G3: persist the new mode so the next board open reopens
            // in it. #796: through this instance's injected store, not the
            // shared `.standard` domain.
            Self.tapModeStore(defaults: tapModeDefaults).save(Self.rawValue(for: interactionMode))
        } label: {
            Label {
                Text(modeToggleModeName)
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: interactionMode == .flag ? "flag.fill" : "hand.tap.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            // #767: `accent.muted` is a background-only token (design-system.md
            // §Color) — text/icon on top must be `text.primary` to hold
            // contrast, mirroring the pattern already used wherever
            // `accent.muted` backs content elsewhere in the app.
            // #786 item 3: reveal mode was `.white` on `accent.primary`, which
            // hard-fails AA in dark mode (white on 0x7FAFCF = 2.35:1). No
            // `text.*` token passes there either — their dark variants are all
            // light inks (text.primary 0xEEF1F4 → 2.07:1) because the accent
            // ramp flips light↔dark opposite to the text ramp. The correct
            // on-accent ink is the theme's surface color: `surface.primary`
            // (0xFFFFFF light / 0x1C2026 dark) = 5.70:1 light / 6.96:1 dark —
            // both AA. Light mode renders byte-identically (still white).
            .foregroundStyle(
                interactionMode == .flag
                    ? theme.text.primary.resolved
                    : theme.surface.primary.resolved
            )
            // #786 item 1 (#780 review): was a hard-coded `12` literal.
            // `SpacingTokens` names no 12 step (8/16/24/32), so this snaps to
            // `small` (8): closer to the chip's #724 "half the footprint"
            // intent than `medium` (16), which the design-system pairing
            // table reserves for card-level internal padding. The
            // `.frame(minWidth: 44, minHeight: 44)` below guarantees the HIG
            // tap-target floor independent of this padding value.
            // #762 PR3 re-tier: content tier — wraps this chip's own
            // icon/text label (mirrors `HomeModeCard.cardPadding`), and the
            // `.frame(minWidth:minHeight:)` floor below only ever grows past
            // 44pt as padding scales, never shrinks below it.
            .padding(.horizontal, toggleChipPadding)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        // swiftui-interaction-footguns: theme tint doesn't auto-propagate to
        // system controls — apply `.tint` explicitly. #767: flag mode
        // previously borrowed `status.warning` for its tint, which reads as
        // "something is wrong" for a routine mode switch and isn't a
        // status-signal use per design-system.md's token table. Flag mode
        // now uses `accent.muted` — still color-distinct from reveal's
        // `accent.primary`, but out of the status-token family.
        .tint(interactionMode == .flag ? theme.accent.muted.resolved : theme.accent.primary.resolved)
        .accessibilityLabel(Text(String(format: modeToggleLabelFormat, modeToggleModeName)))
        .accessibilityValue(Text(modeToggleModeName))
        .accessibilityHint(Text(modeToggleHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("minesweeper.board.tapModeToggle")
    }

    // #731: the mode name and the a11y strings around the toggle were bare
    // English literals never extracted to the catalog. `modeToggleModeName`
    // mirrors "Reveal"/"Flag" (also the label's %@ substitution and the
    // standalone accessibility value); `modeToggleLabelFormat` mirrors
    // `ResumeTitle`'s "Resume %@" pattern — a catalog format key resolved via
    // `String(format:)` rather than string interpolation, so both the prefix
    // and the mode name localize.
    private var modeToggleModeName: String {
        interactionMode == .flag
            ? String(localized: "Flag", bundle: .main)
            : String(localized: "Reveal", bundle: .main)
    }

    private var modeToggleLabelFormat: String {
        String(localized: "Tap mode: %@", bundle: .main)
    }

    private var modeToggleHint: String {
        String(localized: "Double tap to switch tap mode", bundle: .main)
    }

    // MARK: - Grid

    // Cell-side floor (pt), per difficulty. Below this the board scrolls
    // rather than shrinking cells into an un-tappable size (#278 Tier-0 #2).
    // #764: Intermediate (16×16) and Expert (16×30) had inherited Beginner's
    // 32pt floor, below the 44pt HIG touch target — undocumented and, unlike
    // Beginner, not a deliberate reviewed trade-off. Beginner's floor stays
    // 32 because its 36pt-fitted exception (design-system.md §Touch/mouse
    // targets) already clears 32 on every supported width, so it never
    // touches this floor in practice — raising it would risk pushing that
    // documented case into a scroll branch it doesn't use today. Intermediate/
    // Expert already land in the pinned-floor scroll branch on any 375pt-wide
    // phone, so raising their floor to 44 only lengthens the scroll — it does
    // not change which branch fires. Flag taps are mode-driven so no
    // precision long-press is required on small cells.
    nonisolated static func minCellSide(for difficulty: Difficulty) -> CGFloat {
        switch difficulty {
        case .beginner: return 32
        case .intermediate, .expert: return 44
        }
    }
    private static let cellSpacing: CGFloat = 2

    // MARK: - Grid sizing ladder (pure, testable)

    // Extracted from `boardGrid` below so the three-branch decision can be
    // unit-tested without hosting a SwiftUI view (see
    // MinesweeperBoardCellSizingTests). Branches mirror the prior inline
    // comment 1:1:
    //   fitted: both axes fit at/above the floor — center the floored grid,
    //     mirrors Sudoku BoardView's centered frame, avoids top-leading
    //     ScrollView drift.
    //   heightFitScrollHorizontal: board is wider than the offered width but
    //     cells still clear the floor at the offered height; fill height and
    //     scroll horizontally rather than shrinking.
    //   pinnedFloorScrollBoth: cells would drop below the floor even at the
    //     offered height; fix cell side at the floor and scroll both axes
    //     (#278 Tier-0 #2).
    enum CellSizingBranch: Equatable {
        case fitted
        case heightFitScrollHorizontal
        case pinnedFloorScrollBoth
    }

    struct CellSizingResult: Equatable {
        let branch: CellSizingBranch
        let cellSide: CGFloat
    }

    nonisolated static func cellSizing(
        availW: CGFloat,
        availH: CGFloat,
        rows: Int,
        cols: Int,
        floor minCellSide: CGFloat
    ) -> CellSizingResult {
        let fitted = floor(min(availW / CGFloat(cols), availH / CGFloat(rows)))
        let heightFit = floor(availH / CGFloat(rows))
        if fitted >= minCellSide {
            return CellSizingResult(branch: .fitted, cellSide: fitted)
        } else if heightFit >= minCellSide {
            return CellSizingResult(branch: .heightFitScrollHorizontal, cellSide: heightFit)
        } else {
            return CellSizingResult(branch: .pinnedFloorScrollBoth, cellSide: minCellSide)
        }
    }

    // MARK: - Pinch-to-zoom (#815, pure, testable)

    // Zoom composes ON TOP of `cellSizing` above: the ladder still picks the
    // branch + its floor/fitted cellSide exactly as #764 pinned it, and zoom
    // only rescales the RESULT. `zoomedCellSide` and `clampZoomScale` are
    // extracted as pure `nonisolated static` functions (same shape as
    // `cellSizing`) so the clamp/rounding behavior is unit-testable without a
    // hosted view — see `MinesweeperBoardZoomTests`.
    //
    // Range: 0.5×–2.0×, applied as a multiplier on the ladder's chosen
    // cellSide (NOT on the raw floor). 0.5× approximates a whole-board
    // overview for the boards that actually reach a scroll branch —
    // Intermediate/Expert's pinned 44pt floor runs roughly 1.3–2× their
    // natural "fits-in-viewport" size on a typical phone width (#764's own
    // 375pt fixtures: Intermediate/Expert's fitted cellSide before the floor
    // clamp lands well under 44). An exact fit-to-screen bound would need a
    // second geometry pass re-deriving the true fitted cellSide on every
    // gesture frame — more coupling than this pure helper should carry for a
    // user-triggered escape hatch. 2.0× is a conservative upper bound (HIG
    // targets are already met at 1×; zooming in past 2× has diminishing
    // value on a board this size and risks scrolling many screens to reveal
    // one enlarged corner). The 44pt HIG floor stays the DEFAULT (1.0×) —
    // zooming below it is an explicit, session-only user choice, matching
    // design-system.md's "MS BoardView cell" touch-target row (the ladder's
    // 44pt is a default-presentation floor, not a hard interaction minimum).
    nonisolated static let minZoomScale: CGFloat = 0.5
    nonisolated static let maxZoomScale: CGFloat = 2.0

    nonisolated static func clampZoomScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minZoomScale), maxZoomScale)
    }

    /// The actual rendered cell side after applying a (clamped) zoom scale to
    /// the ladder's chosen `baseCellSide`. Floored, mirroring `cellSizing`'s
    /// own flooring, for crisp glyph rendering (`MinesweeperCellButton`
    /// derives its glyph size straight from `side`).
    nonisolated static func zoomedCellSide(baseCellSide: CGFloat, zoomScale: CGFloat) -> CGFloat {
        floor(baseCellSide * clampZoomScale(zoomScale))
    }

    // Mechanism decision (#815): `MagnifyGesture` driving a REAL cellSide
    // change (fed back through the same `gridStack` every other branch
    // already uses) — NOT `.scaleEffect`, and NOT a `UIScrollView`
    // representable.
    //   - vs `.scaleEffect`: a visual transform would leave
    //     `MinesweeperCellButton`'s actual `.frame(width:height:)` and
    //     glyph size (`side * 0.55`) at the pre-zoom size, so digits/mines
    //     would blur under magnification instead of re-rendering crisp, and
    //     the ScrollView's content size would need a second manual
    //     `.frame(width:height:)` override to stay scrollable to the
    //     enlarged extent. Recomputing the real cellSide gets both content
    //     size AND crisp rendering for free from the SAME layout pass the
    //     three-branch ladder already does.
    //   - vs a `UIScrollView`/`NSScrollView` representable: would fork the
    //     rendering path per-platform (no `UIScrollView` on macOS), breaking
    //     the shared SwiftUI code path this view otherwise keeps identical
    //     across iOS/iPadOS/macOS. `MagnifyGesture` is a cross-platform
    //     SwiftUI API (two-finger pinch on iOS/iPadOS, trackpad pinch on
    //     macOS) — one gesture, one code path.
    //   - Trade-off accepted: because the content size grows via real
    //     relayout rather than a UIScrollView's `zoomScale` +
    //     `contentOffset` pair, the pinch does NOT anchor to the gesture's
    //     centroid — SwiftUI's `ScrollView` keeps its current content
    //     offset as the content grows, so zoom visually grows from the
    //     content's current top-leading scroll position, not from under the
    //     player's fingers. Implementing true centroid-anchoring would mean
    //     hand-rolling scroll-offset adjustment every gesture frame — exactly
    //     the complexity a `UIScrollView` representable gives for free, at
    //     the cost of the cross-platform fork above. Given MS boards are
    //     modest in extent (≤16×30 cells) and the same two-finger drag pans
    //     immediately after a pinch, this is judged an acceptable
    //     simplification; revisit with a `ScrollViewReader`/`scrollPosition`
    //     offset correction if it reads as disorienting in practice.
    //   - Gesture disambiguation: `MagnifyGesture` requires two simultaneous
    //     touch points, which structurally cannot fire from the same
    //     single-finger touch that drives a cell's `Button` tap/long-press —
    //     touch count alone disambiguates pinch from tap, so no
    //     `.exclusively` combinator is needed against the cell buttons.
    //     Attachment is `.simultaneousGesture` (not bare `.gesture`) — the
    //     idiomatic pinch-inside-ScrollView form (CR round 2): it lets the
    //     magnify recognizer run alongside the ScrollView's own pan/drag
    //     recognizers instead of competing with them, where a bare
    //     `.gesture` risks losing recognition to the scroll drag entirely.
    //   - Fitted-branch policy: NOT applied to `.fitted` (Beginner in
    //     practice). Zoom exists to let the player inspect a board that
    //     doesn't fully fit on screen; the fitted branch by definition
    //     already shows the whole board at/above the floor, so there is
    //     nothing off-screen to reveal and wrapping it in a scrollable/
    //     zoomable container would only churn its long-settled centered
    //     presentation (design-system.md's documented 36pt Beginner
    //     exception) for no functional gain.
    private var pinchToZoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                zoomScale = Self.clampZoomScale(zoomScale * value.magnification)
            }
    }

    // #815: visible gap between the board's own content and the ScrollView's
    // native scroll-indicator bar in both scroll branches, via
    // `.contentMargins(_:for: .scrollContent)` (iOS 17+/macOS 14+, within
    // this repo's iOS 18/macOS 15 floor). `.scrollContent` — not
    // `.scrollIndicators` — is the correct lever (CR round 2): it insets the
    // CONTENT away from the container edge the indicator hugs, so the gap
    // opens between board and bar; margining the indicator placement instead
    // would push the bar INTO the content, the opposite of the ask. Edge
    // choice: `.all`, not just the bottom/trailing edges the indicators
    // occupy — the inset shows whenever the player scrolls the board to ANY
    // extreme, and clearing only two edges would read as the grid sitting
    // flush at top/leading but floating at bottom/trailing, an asymmetry
    // with no upside for a 4pt inset. Structural — board-geometry chrome,
    // not text/icon-adjacent content — so it stays a fixed `theme.spacing.*`
    // token rather than a `@ScaledSpacing` one, mirroring `cellSpacing`'s
    // own fixed-constant treatment just above.
    private var scrollIndicatorClearance: CGFloat { theme.spacing.extraSmall }

    private var boardGrid: some View {
        // GeometryReader reports the offered rectangle; we derive a single
        // square cell side that fits the NON-SQUARE board by its longer axis
        // (Expert is 16×30), then floor it for crisp glyphs. See
        // `cellSizing(availW:availH:rows:cols:floor:)` above for the branch logic.
        GeometryReader { geo in
            let rows = viewModel.rows
            let cols = viewModel.columns
            let spacing = Self.cellSpacing
            // Subtract the inter-cell gaps before dividing so the cells (not
            // the gaps) fill the offered box exactly.
            let availW = geo.size.width - spacing * CGFloat(cols - 1)
            let availH = geo.size.height - spacing * CGFloat(rows - 1)
            let sizing = Self.cellSizing(
                availW: availW,
                availH: availH,
                rows: rows,
                cols: cols,
                floor: Self.minCellSide(for: viewModel.session.difficulty)
            )
            // #815: zoom applies ONLY in the two scroll branches below — see
            // the design note on `pinchToZoomGesture` above for why `.fitted`
            // (this branch) is excluded. `sizing.cellSide` here is exactly
            // #764's ladder result, untouched.
            let effectiveCellSide = Self.zoomedCellSide(
                baseCellSide: sizing.cellSide,
                zoomScale: zoomScale * pinchMagnification
            )
            switch sizing.branch {
            case .fitted:
                gridStack(rows: rows, cols: cols, cellSide: sizing.cellSide, spacing: spacing)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            case .heightFitScrollHorizontal:
                ScrollView(.horizontal) {
                    gridStack(rows: rows, cols: cols, cellSide: effectiveCellSide, spacing: spacing)
                }
                .contentMargins(.all, scrollIndicatorClearance, for: .scrollContent)
                .frame(width: geo.size.width, height: geo.size.height)
                .simultaneousGesture(pinchToZoomGesture)
            case .pinnedFloorScrollBoth:
                ScrollView([.horizontal, .vertical]) {
                    gridStack(rows: rows, cols: cols, cellSide: effectiveCellSide, spacing: spacing)
                }
                .contentMargins(.all, scrollIndicatorClearance, for: .scrollContent)
                .frame(width: geo.size.width, height: geo.size.height)
                .simultaneousGesture(pinchToZoomGesture)
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
    /// once per terminal transition (see `.onChange` / `.task` above) so its
    /// state survives recomputes.
    private func makeCompletionViewModel() -> MinesweeperCompletionViewModel {
        MinesweeperCompletionViewModel(
            didWin: viewModel.status == .won,
            elapsedSeconds: viewModel.elapsedSeconds,
            leaderboardId: MinesweeperLeaderboardID.daily(
                for: viewModel.session.difficulty
            )
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
