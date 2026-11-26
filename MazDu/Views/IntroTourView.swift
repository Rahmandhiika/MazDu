import SwiftUI

private let tourScreenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let tourScreenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

/// D-063 item 4: showcase tour shown after both players ready up and before racing
/// starts for real. Camera pans between 3 real points of interest in the actual
/// generated maze — spawn, finish, and the nearest obstacle (which also introduces the
/// Roll pickup) — holding at each with a caption, then gliding to the next. Not a
/// flythrough of the solution route: showing the real shortest path would spoil the
/// maze's own challenge (live feedback from testing the first version of this tour).
/// Drone view for beats 2/3 (finish, obstacle) — no player sprite. Beat 1 (spawn) shows
/// the player standing there instead, since "INI POSISI KAMU" pointed at nothing on an
/// empty tile otherwise (real-device playtest feedback, 2026-09-24). Skippable (circle)
/// at any time; the natural end and the skip both call the same `onFinished`, which
/// `MatchViewModel.finishIntroTour` guards against a duplicate call.
struct IntroTourView: View {
    let maze: Maze
    /// Exactly 3 points, from `RaceViewModel.introTourPoints`: spawn, finish, nearest obstacle.
    let points: [CGPoint]
    /// From `RaceViewModel.isItemAvailable` — without this the obstacle beat's dice
    /// pickup sprite never renders (defaults to `[]` if omitted), even though its own
    /// caption tells the player to grab it.
    let isItemAvailable: [Bool]
    let onFinished: () -> Void

    @State private var startDate = Date()

    private let captions = [
        "THIS IS YOUR SPOT",
        "GOAL: FINISH HERE",
        "OBSTACLE! GRAB DICE TO ROLL A SKILL"
    ]

    private var totalDuration: Double {
        3 * GameConfig.IntroTour.holdDuration + 2 * GameConfig.IntroTour.panDuration
    }

    /// Camera position, current caption, and whether the caption should be showing
    /// (hidden while panning between points) at `elapsed` seconds into the tour.
    private func state(at elapsed: Double) -> (position: CGPoint, caption: String, captionVisible: Bool) {
        guard points.count == 3 else { return (points.first ?? .zero, "", false) }
        let hold = GameConfig.IntroTour.holdDuration
        let pan = GameConfig.IntroTour.panDuration
        let t0 = hold, t1 = t0 + pan, t2 = t1 + hold, t3 = t2 + pan

        if elapsed < t0 {
            return (points[0], captions[0], true)
        } else if elapsed < t1 {
            return (lerp(points[0], points[1], (elapsed - t0) / pan), "", false)
        } else if elapsed < t2 {
            return (points[1], captions[1], true)
        } else if elapsed < t3 {
            return (lerp(points[1], points[2], (elapsed - t2) / pan), "", false)
        } else {
            return (points[2], captions[2], true)
        }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let clamped = min(max(t, 0), 1)
        return CGPoint(x: a.x + (b.x - a.x) * clamped, y: a.y + (b.y - a.y) * clamped)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DeviceShellView {
                GeometryReader { geo in
                    let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)

                    ZStack(alignment: .bottom) {
                        TimelineView(.animation) { context in
                            let elapsed = context.date.timeIntervalSince(startDate)
                            let s = state(at: elapsed)
                            MazeView(
                                maze: maze,
                                cameraPosition: s.position,
                                spriteCell: (col: 0, row: 0),
                                elapsedTime: context.date.timeIntervalSinceReferenceDate,
                                isPlayerVisible: elapsed < GameConfig.IntroTour.holdDuration,
                                isItemAvailable: isItemAvailable
                            )
                            .overlay(alignment: .top) {
                                captionBanner(text: s.caption, visible: s.captionVisible, scale: scale)
                                    .padding(.top, 8 * scale)
                            }
                        }

                        skipHint(scale: scale)
                            .padding(.bottom, 4 * scale)
                    }
                }
            } controls: { scale in
                TapButtonControl(hole: ShellLayout.circleHole, scale: scale, action: onFinished)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: .seconds(totalDuration))
            onFinished()
        }
    }

    private func captionBanner(text: String, visible: Bool, scale: CGFloat) -> some View {
        Text(text)
            .font(.pixel(.body, scale: scale))
            .foregroundStyle(tourScreenDark)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4 * scale)
            .background(tourScreenGreen.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: visible)
    }

    private func skipHint(scale: CGFloat) -> some View {
        HStack(spacing: 4 * scale) {
            Circle().strokeBorder(tourScreenDark, lineWidth: 1.2 * scale).frame(width: 7 * scale, height: 7 * scale)
            Text("SKIP")
        }
        .font(.pixel(.hint, scale: scale))
        .foregroundStyle(tourScreenDark)
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 2 * scale)
        .background(tourScreenGreen.opacity(0.85))
        .clipShape(Capsule())
        .accessibilityLabel("Circle to skip the maze tour.")
    }
}

#Preview {
    let vm = RaceViewModel(seed: 1)
    return IntroTourView(maze: vm.maze, points: vm.introTourPoints, isItemAvailable: vm.isItemAvailable, onFinished: {})
}
