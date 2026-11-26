import SwiftUI

private let statsScreenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let statsScreenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

/// D-063 item 7: shown a couple seconds after the plain win/lose/draw text
/// (`ContentView.resultScreen`) — see `MatchViewModel.endMatch`/`transitionToStats`.
/// WINNER/SERI title, KAMU/LAWAN stat boxes (obstacle hits, skill-use count, shield
/// blocks, final progress), then a "main lagi?"/"main menu" selector — same D-pad
/// up/down + circle-confirm list pattern as `MainMenuView`, from the user's own mockup.
/// Picking "main lagi" locks in immediately (not a toggle) and swaps the selector for a
/// wait message until the opponent also picks it; picking "main menu" reuses the same
/// quit-notify pattern as the ready-check gate's diamond (`OpponentQuitAlertView`).
struct FinishStatsView: View {
    let title: String
    let localStats: MatchViewModel.MatchStats?
    let opponentStats: MatchViewModel.MatchStats?
    let isWaitingForOpponent: Bool
    let onRematch: () -> Void
    let onMainMenu: () -> Void

    @State private var selectedIndex = 0
    @State private var activeDirection: RaceViewModel.Direction?
    /// Same discrete one-step-per-press tracking as `MainMenuView` — re-armed on release.
    @State private var pressArmed = true

    private let items = ["PLAY AGAIN?", "MAIN MENU"]
    private static let walkCols = [0, 1, 0, 3]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DeviceShellView {
                statsScreen
            } controls: { scale in
                if !isWaitingForOpponent {
                    DPadControl(
                        scale: scale,
                        activeDirection: activeDirection,
                        onPress: handlePress,
                        onRelease: {
                            activeDirection = nil
                            pressArmed = true
                        }
                    )
                    TapButtonControl(hole: ShellLayout.circleHole, scale: scale, action: confirmSelection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var statsScreen: some View {
        GeometryReader { geo in
            let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)

            VStack(spacing: 5 * scale) {
                Text(title)
                    .pixelTitle(scale: scale)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6 * scale) {
                    statBox(label: "YOU", stats: localStats, scale: scale)
                    statBox(label: "ENEMY", stats: opponentStats, scale: scale)
                }

                Spacer(minLength: 2 * scale)

                if isWaitingForOpponent {
                    Text("WAITING FOR\nENEMY...")
                        .font(.pixel(.body, scale: scale))
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 4 * scale) {
                        ForEach(items.indices, id: \.self) { index in
                            row(for: index, scale: scale)
                        }
                    }
                }

                Spacer(minLength: 0)

                if !isWaitingForOpponent {
                    controlHint(scale: scale)
                }
            }
            .foregroundStyle(statsScreenDark)
            .padding(.top, 10 * scale)
            .padding(.horizontal, 6 * scale)
            .padding(.bottom, 4 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(statsScreenGreen)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityText: String {
        let base = "\(title.replacingOccurrences(of: "\n", with: " ")). You: \(statSummary(localStats)). Enemy: \(statSummary(opponentStats))."
        if isWaitingForOpponent {
            return base + " Waiting for the enemy to choose play again or main menu."
        }
        return base + " D-pad up down to select, circle to confirm. Current choice: \(items[selectedIndex])."
    }

    private func statSummary(_ stats: MatchViewModel.MatchStats?) -> String {
        guard let stats else { return "no data yet" }
        return "freeze \(stats.freezeUsed), darken \(stats.darkenUsed), switch \(stats.switchUsed), \(stats.shieldBlocks) shield blocks, \(stats.stuns) stuns taken, progress \(stats.progress)"
    }

    private func statBox(label: String, stats: MatchViewModel.MatchStats?, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1.5 * scale) {
            Text(label)
                .font(.pixel(.label, scale: scale))
                .frame(maxWidth: .infinity, alignment: .center)
            statLine("FREEZE", stats?.freezeUsed, scale: scale)
            statLine("DARKEN", stats?.darkenUsed, scale: scale)
            statLine("SWITCH", stats?.switchUsed, scale: scale)
            statLine("SHIELD", stats?.shieldBlocks, scale: scale)
            statLine("STUN", stats?.stuns, scale: scale)
            statLine("PROG", stats?.progress, scale: scale)
        }
        .padding(4 * scale)
        .frame(maxWidth: .infinity)
        .background(statsScreenDark.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
    }

    private func statLine(_ label: String, _ value: Int?, scale: CGFloat) -> some View {
        HStack(spacing: 2 * scale) {
            Text(label)
            Spacer(minLength: 2 * scale)
            Text(value.map(String.init) ?? "-")
        }
        .font(.pixel(.hint, scale: scale))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    /// Matches the main-menu cursor: two sprites walk inward toward the label. Invisible
    /// sprites retain their slots, keeping both choices centered when selection changes.
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            cursorSprite(facingRight: false, isVisible: isSelected, scale: scale)
        }
        .font(.pixel(.item, scale: scale))
    }

    private func controlHint(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            HStack(spacing: 4 * scale) {
                Image(systemName: "arrow.up.and.down")
                Text("UP/DOWN")
            }
            HStack(spacing: 4 * scale) {
                Circle()
                    .strokeBorder(statsScreenDark, lineWidth: 1.2 * scale)
                    .frame(width: 7 * scale, height: 7 * scale)
                Text("OK")
            }
        }
        .font(.pixel(.hint, scale: scale))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func handlePress(_ direction: RaceViewModel.Direction) {
        activeDirection = direction
        guard pressArmed else { return }
        pressArmed = false
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

    private func confirmSelection() {
        switch selectedIndex {
        case 0:
            GameFeedback.shared.play(.uiSelect, haptic: .light)
            onRematch()
        default:
            GameFeedback.shared.play(.uiSelect, haptic: .light)
            onMainMenu()
        }
    }
}

#Preview {
    FinishStatsView(
        title: "WINNER\nIPHONE",
        localStats: .init(freezeUsed: 2, darkenUsed: 1, switchUsed: 0, shieldBlocks: 1, stuns: 2, progress: 24),
        opponentStats: .init(freezeUsed: 0, darkenUsed: 1, switchUsed: 1, shieldBlocks: 0, stuns: 4, progress: 20),
        isWaitingForOpponent: false,
        onRematch: {},
        onMainMenu: {}
    )
}
