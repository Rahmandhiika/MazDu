import SwiftUI

private let menuScreenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let menuScreenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

/// D-063 item 1: Game Boy-style main menu, shown before `startSearching()` ever fires.
/// Reuses the exact shell/D-pad/circle components the race screen already has — the
/// only new behavior is that the D-pad's up/down press moves a list cursor once per
/// physical press instead of driving continuous movement.
struct MainMenuView: View {
    let onPlay: () -> Void

    @State private var selectedIndex = 0
    @State private var activeDirection: RaceViewModel.Direction?
    /// One press-and-release of the D-pad moves the cursor exactly once, no matter how
    /// many `touchesMoved` calls land inside that same press (see `DPadControl`) —
    /// re-armed on release.
    @State private var pressArmed = true
    /// Which "screen" `DeviceShellView` currently shows. A `fullScreenCover` to a whole
    /// separate `CreditsView` used to swap the entire device shell (buttons and all) with
    /// a slide transition — this instead swaps only the middle screen content within the
    /// same shell instance, the way a real handheld's screen redraws without the device
    /// itself changing.
    @State private var showingCredits = false
    @State private var creditsScrollOffset: CGFloat = 0
    @State private var creditsMaxScroll: CGFloat = 0

    private let items = ["PLAY", "CREDITS"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DeviceShellView {
                if showingCredits {
                    CreditsView(scrollOffset: creditsScrollOffset) { creditsMaxScroll = $0 }
                } else {
                    menuScreen
                }
            } controls: { scale in
                DPadControl(
                    scale: scale,
                    activeDirection: activeDirection,
                    onPress: handlePress,
                    onRelease: {
                        activeDirection = nil
                        pressArmed = true
                    }
                )
                if showingCredits {
                    TapButtonControl(hole: ShellLayout.circleHole, scale: scale, action: closeCredits)
                        .accessibilityLabel("Back")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { closeCredits() }
                } else {
                    TapButtonControl(hole: ShellLayout.circleHole, scale: scale, action: confirmSelection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    /// Walk-cycle column order, matching `RaceViewModel.walkCycleCols` — reused here
    /// (and by `MatchmakingLoadingScreen`) for small non-gameplay walk animations.
    private static let walkCols = [0, 1, 0, 3]

    private var menuScreen: some View {
        GeometryReader { geo in
            let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)

            ZStack {
                menuScreenGreen

                // Poster-style half-and-half background: each sprite independently
                // pinned to its own top screen corner (not an HStack — a fixed-size
                // HStack can't position children past its own bounds) and top-aligned
                // rather than centered, so the head sits up near the title and the body
                // is visible cascading down behind the menu list, per the user's own
                // "kepala naik biar badannya keliatan" direction.
                posterSprite(row: 6, scale: scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                posterSprite(row: 2, scale: scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                VStack(spacing: 8 * scale) {
                    ForEach(items.indices, id: \.self) { index in
                        row(for: index, scale: scale)
                    }
                }
                .foregroundStyle(menuScreenDark)
                .offset(y: 22 * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                showcaseStrip(scale: scale)
                    .padding(.top, 3 * scale)
            }
            .overlay(alignment: .bottom) {
                controlHint(scale: scale)
                    .padding(.bottom, 2 * scale)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Main menu. D-pad up down to select, circle to confirm. Current choice: \(items[selectedIndex]).")
        }
    }

    /// Face-side half of the full standing sprite (not just the head — the other half
    /// is mostly blank back-of-body, see `MazeView.playerHalfFrame`), pinned flush to
    /// its own screen edge and top-aligned. A tighter half-width crop can be zoomed in
    /// bigger while leaving a real gap in the middle for the menu list, instead of the
    /// two sprites colliding directly behind "PLAY".
    private func posterSprite(row: Int, scale: CGFloat) -> some View {
        MazeView.playerHalfFrame(row: row, keepRightHalf: row == 6, height: 16)
            .resizable()
            .interpolation(.none)
            .aspectRatio(8.0 / 16.0, contentMode: .fit)
            .frame(height: ShellLayout.mainScreenHole.height * scale)
            .opacity(0.55)
            .accessibilityHidden(true)
    }

    /// "player · MAZDU · player" as one fixed formation that walks right, then left,
    /// then right again — the whole group slides together (not two independent
    /// loops), reusing the exact back-and-forth idiom `MatchmakingLoadingScreen`'s
    /// `walkPreview` already uses (`sin` for smooth reversal, no hard loop reset).
    /// Both runners face/walk whichever direction the group is currently moving —
    /// `cos` of the same angle (the position function's derivative) gives that
    /// direction for free, with no separate state to track.
    private func showcaseStrip(scale: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: false)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let angle = seconds * 0.6
            let amplitude: CGFloat = 22 * scale
            let xOffset = amplitude * sin(angle)
            let movingRight = cos(angle) > 0
            let walkCol = Self.walkCols[Int(seconds * 8) % Self.walkCols.count]
            let runnerRow = movingRight ? 6 : 2

            HStack(spacing: 8 * scale) {
                runnerImage(col: walkCol, row: runnerRow, scale: scale)
                Text("MAZDU")
                    .font(.pixel(.item, scale: scale))
                    .foregroundStyle(menuScreenDark)
                runnerImage(col: walkCol, row: runnerRow, scale: scale)
            }
            .offset(x: xOffset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14 * scale)
        .clipped()
    }

    private func runnerImage(col: Int, row: Int, scale: CGFloat) -> some View {
        MazeView.playerFrame(col: col, row: row)
            .resizable()
            .interpolation(.none)
            .frame(width: 13 * scale, height: 13 * scale)
            .accessibilityHidden(true)
    }

    /// User's own sketch: symbol+label control legend pinned to the screen's bottom
    /// edge, centered as one compact group — up/down arrow (not the race screen's
    /// full 4-direction "✚", since the menu cursor only moves vertically) and a bold
    /// stroked circle (a plain "○" glyph stayed hairline-thin regardless of font weight,
    /// so it read as a different, thinner icon than the arrow right next to it — a real
    /// `Circle().strokeBorder` gives the same weight control text doesn't). The arrow is
    /// an SF Symbol, not a "↕" text glyph — `PixelFont`'s Press Start 2P doesn't contain
    /// that character, so it silently fell back to a mismatched system glyph.
    private func controlHint(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            HStack(spacing: 4 * scale) {
                Image(systemName: "arrow.up.and.down")
                Text("UP/DOWN")
            }
            HStack(spacing: 4 * scale) {
                Circle()
                    .strokeBorder(menuScreenDark, lineWidth: 1.2 * scale)
                    .frame(width: 7 * scale, height: 7 * scale)
                Text("OK")
            }
        }
        .font(.pixel(.hint, scale: scale))
        .foregroundStyle(menuScreenDark)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 2 * scale)
        .background(menuScreenGreen.opacity(0.85))
        .clipShape(Capsule())
    }

    /// The selected row's cursor is a small looping walk animation instead of a static
    /// triangle — both sides walk inward toward the label (left slot faces/walks right,
    /// right slot faces/walks left), reusing the exact gameplay sprite frames. Always
    /// rendered (even for the unselected row) at `opacity(0)` so both rows reserve the
    /// identical width and stay symmetric/centered regardless of which is selected.
    private func cursorSprite(facingRight: Bool, isVisible: Bool, scale: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8, paused: !isVisible)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let col = Self.walkCols[Int(seconds * 6) % Self.walkCols.count]
            MazeView.playerFrame(col: col, row: facingRight ? 6 : 2)
                .resizable()
                .interpolation(.none)
                .frame(width: 10 * scale, height: 10 * scale)
                .opacity(isVisible ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    private func row(for index: Int, scale: CGFloat) -> some View {
        let isSelected = index == selectedIndex
        return HStack(spacing: 4 * scale) {
            cursorSprite(facingRight: true, isVisible: isSelected, scale: scale)
            Text(items[index])
            cursorSprite(facingRight: false, isVisible: isSelected, scale: scale)
        }
        .font(.pixel(.item, scale: scale))
    }

    private func handlePress(_ direction: RaceViewModel.Direction) {
        activeDirection = direction
        guard pressArmed else { return }
        pressArmed = false
        if showingCredits {
            scrollCredits(direction)
            return
        }
        switch direction {
        case .up:
            selectedIndex = (selectedIndex - 1 + items.count) % items.count
            GameFeedback.shared.play(.uiSelect, haptic: .selection)
        case .down:
            selectedIndex = (selectedIndex + 1) % items.count
            GameFeedback.shared.play(.uiSelect, haptic: .selection)
        case .left, .right: break
        }
    }

    /// Same discrete one-step-per-press idiom as the cursor above — the D-pad's zone
    /// doubles as a scroll control while Credits is showing (see the accessibility
    /// elements `DPadControl` exposes for VoiceOver, which reach this the same way).
    private func scrollCredits(_ direction: RaceViewModel.Direction) {
        let step: CGFloat = 24
        switch direction {
        case .up: creditsScrollOffset = max(0, creditsScrollOffset - step)
        case .down: creditsScrollOffset = min(creditsMaxScroll, creditsScrollOffset + step)
        case .left, .right: break
        }
    }

    private func confirmSelection() {
        switch selectedIndex {
        case 0:
            GameFeedback.shared.play(.uiSelect, haptic: .light)
            onPlay()
        default:
            GameFeedback.shared.play(.uiSelect, haptic: .light)
            creditsScrollOffset = 0
            creditsMaxScroll = 0
            showingCredits = true
        }
    }

    private func closeCredits() {
        GameFeedback.shared.play(.uiSelect, haptic: .light)
        showingCredits = false
    }
}

#Preview {
    MainMenuView(onPlay: {})
}
