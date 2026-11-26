import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = MatchViewModel()

    private let screenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
    private let screenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.showOpponentQuitAlert {
                opponentQuitScreen
            } else {
                switch viewModel.phase {
                case .menu:
                    menuScreen
                case .searching, .connected:
                    lobbyScreen
                case .readyCheck, .secondReady:
                    readyCheckScreen
                case .introTour:
                    introTourScreen
                case .countdown:
                    countdownScreen
                case .racing:
                    raceScreen
                case .finished:
                    resultScreen
                case .stats:
                    statsScreen
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: viewModel.multipeer.isConnected) { _, isConnected in
            if isConnected {
                Task {
                    await viewModel.handlePeerFound()
                }
            } else {
                viewModel.handlePeerLost()
            }
        }
        .onAppear { syncAudioForScenePhase(scenePhase) }
        .onChange(of: viewModel.phase) { _, phase in syncMusic(for: phase) }
        .onChange(of: scenePhase) { _, nextScenePhase in
            syncAudioForScenePhase(nextScenePhase)
        }
    }

    private func syncAudioForScenePhase(_ nextScenePhase: ScenePhase) {
        switch nextScenePhase {
        case .active:
            GameFeedback.shared.setApplicationIsActive(true)
            syncMusic(for: viewModel.phase)
        case .inactive, .background:
            GameFeedback.shared.setApplicationIsActive(false)
        @unknown default:
            GameFeedback.shared.setApplicationIsActive(false)
        }
    }

    private func syncMusic(for phase: MatchViewModel.Phase) {
        switch phase {
        case .menu:
            GameFeedback.shared.playMusic(.menu)
        case .racing:
            GameFeedback.shared.playMusic(.race)
        default:
            GameFeedback.shared.playMusic(nil)
        }
    }

    private var menuScreen: some View {
        MainMenuView(onPlay: { viewModel.selectPlay() })
    }

    private var lobbyScreen: some View {
        let isCancelable = viewModel.phase == .searching
        return DeviceShellView {
            MatchmakingLoadingScreen(status: viewModel.connectionStatusText, showsCancelHint: isCancelable)
        } controls: { scale in
            if isCancelable {
                TapButtonControl(hole: ShellLayout.diamondHole, scale: scale) {
                    GameFeedback.shared.play(.uiSelect, haptic: .light)
                    viewModel.backToMenuFromSearching()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyCheckScreen: some View {
        ReadyCheckView(
            opponentName: viewModel.opponentDisplayName,
            localReady: viewModel.localReady,
            opponentReady: viewModel.opponentReady,
            showsGuide: viewModel.phase == .secondReady,
            onToggleReady: { viewModel.toggleReady() },
            onBack: { viewModel.backToMenuFromReadyCheck() }
        )
    }

    private var introTourScreen: some View {
        Group {
            if let raceViewModel = viewModel.raceViewModel {
                IntroTourView(
                    maze: raceViewModel.maze,
                    points: raceViewModel.introTourPoints,
                    isItemAvailable: raceViewModel.isItemAvailable,
                    onFinished: { viewModel.finishIntroTour() }
                )
            }
        }
    }

    private var countdownScreen: some View {
        Group {
            if let raceViewModel = viewModel.raceViewModel {
                CountdownView(
                    maze: raceViewModel.maze,
                    spawnPosition: raceViewModel.spawnPosition,
                    isItemAvailable: raceViewModel.isItemAvailable,
                    onComplete: { viewModel.startRacing() }
                )
            }
        }
    }

    private var opponentQuitScreen: some View {
        OpponentQuitAlertView(onAcknowledge: { viewModel.acknowledgeOpponentQuit() })
    }

    private var raceScreen: some View {
        Group {
            if let raceViewModel = viewModel.raceViewModel {
                RaceView(
                    viewModel: raceViewModel,
                    onActivate: { viewModel.handleActivate($0) },
                    topLeftHUD: { TimerHUD(timeRemaining: viewModel.timeRemaining) },
                    topRightHUD: {
                        VsArrowHUD(
                            standing: viewModel.opponentStanding,
                            accessibilityText: viewModel.opponentIndicatorText
                        )
                    }
                )
            }
        }
    }

    private var resultScreen: some View {
        DeviceShellView {
            GeometryReader { geo in
                let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)

                Text(viewModel.resultText ?? "")
                    .font(.pixel(.item, scale: scale))
                    .foregroundStyle(screenDark)
                    .multilineTextAlignment(.center)
                    .padding(8 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(screenGreen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statsScreen: some View {
        FinishStatsView(
            title: viewModel.finishTitle,
            localStats: viewModel.ownStats,
            opponentStats: viewModel.opponentStats,
            isWaitingForOpponent: viewModel.localWantsRematch,
            onRematch: { viewModel.chooseRematch() },
            onMainMenu: { viewModel.chooseMainMenuFromStats() }
        )
    }
}

/// Placeholder pending its own redesign pass (D-063 item 2) — just the status text for
/// now, stripped of the scanner/walk-preview/win-conditions/control-hints design.
private struct MatchmakingLoadingScreen: View {
    let status: String
    let showsCancelHint: Bool

    private let screenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
    private let screenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

    var body: some View {
        GeometryReader { geo in
            let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)

            VStack(spacing: 10 * scale) {
                Spacer(minLength: 0)

                Text(status.uppercased())
                    .font(.pixel(.item, scale: scale))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8 * scale)

                Spacer(minLength: 0)

                if showsCancelHint {
                    cancelHint(scale: scale)
                }
            }
            .foregroundStyle(screenDark)
            .padding(.bottom, 4 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(screenGreen)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(showsCancelHint ? "\(status) Diamond to cancel and go back to the menu." : status)
        }
    }

    /// Same rotated-square diamond glyph as `ReadyCheckView.controlHint` — only shown
    /// while `.searching` (no peer yet); hidden once matched (`.connected`), since
    /// backing out after a peer connects goes through the ready-check gate's diamond
    /// instead, which notifies the opponent.
    private func cancelHint(scale: CGFloat) -> some View {
        HStack(spacing: 4 * scale) {
            Rectangle()
                .strokeBorder(screenDark, lineWidth: 1.2 * scale)
                .frame(width: 5 * scale, height: 5 * scale)
                .rotationEffect(.degrees(45))
            Text("CANCEL")
        }
        .font(.pixel(.hint, scale: scale))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Shared LCD look for the topLeft/topRight HUD slots — bright green background, dark
/// content, matching `RaceView`'s mini-screen treatment (D-056 real-device feedback: the
/// original dark-overlay look read as too dark and everything on it as too small).
private let topSlotGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let topSlotDark = Color(red: 0.027, green: 0.094, blue: 0.129)

/// D-055 topLeftHole: race timer. Blinks once under `GameConfig.HUD.timerBlinkThreshold`.
private struct TimerHUD: View {
    let timeRemaining: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: GameConfig.HUD.timerBlinkInterval, paused: false)) { context in
            let isLow = timeRemaining < GameConfig.HUD.timerBlinkThreshold
            let phase = Int(context.date.timeIntervalSinceReferenceDate / GameConfig.HUD.timerBlinkInterval) % 2 == 0
            HStack(spacing: 4) {
                Image("timer_icon")
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 22, height: 22)
                Text("\(Int(timeRemaining))s")
                    .font(.pixel(13))
            }
            .foregroundStyle(isLow && !phase ? Color.red.opacity(0.85) : topSlotDark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(topSlotGreen)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(timeRemaining)) seconds left")
        }
    }
}

/// D-055 topRightHole: opponent standing indicator. The native asset points up; flipped
/// vertically (to point down) when the opponent is ahead — more progress means further
/// down the maze (see `MatchViewModel.OpponentStanding`) — same trick as
/// `MazeObstacle.spriteFlippedHorizontally`. Bounces on every change.
/// D-058: paired with a short text label (point 6) — the arrow alone wasn't legible
/// enough as "who's ahead" at a glance.
private struct VsArrowHUD: View {
    let standing: MatchViewModel.OpponentStanding
    let accessibilityText: String

    @State private var bounce = false

    /// The slot is only 38×14pt, so the visible affordance matches the timer: one large
    /// icon plus one large short label. The arrow itself communicates above/below, while
    /// VoiceOver provides the full sentence via `accessibilityLabel`.
    private var standingLabel: String {
        switch standing {
        case .ahead, .behind: return "ENEMY"
        case .level: return "TIED"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image("vs_arrow_icon")
                .resizable()
                .interpolation(.none)
                .frame(width: 16, height: 16)
                .scaleEffect(x: 1, y: standing == .ahead ? -1 : 1)
                .scaleEffect(bounce ? 1.15 : 1)
            Text(standingLabel)
                .font(.pixel(10))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(topSlotDark)
        .opacity(standing == .level ? 0.5 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(topSlotGreen)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .onChange(of: standing) { _, _ in
            bounce = true
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 10).delay(GameConfig.HUD.vsArrowBounceDuration)) {
                bounce = false
            }
        }
        .animation(.interpolatingSpring(stiffness: 300, damping: 10), value: bounce)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

#Preview {
    ContentView()
}
