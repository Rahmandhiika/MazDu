import SwiftUI

private let countdownGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let countdownDark = Color(red: 0.027, green: 0.094, blue: 0.129)

/// D-063 item 6: synced countdown shown after both players ready up a second time
/// (post intro-tour), right before racing starts for real. "3" → "2" → "1" → "MULAI",
/// each held `GameConfig.Countdown.stepDuration`, sliding straight down out of view as
/// the next one slides down into place — not a cut or a cross-fade, per the user's own
/// "turun" framing. No new network message: each device runs this locally once it
/// notices both sides are ready, same looseness as every other phase handoff here.
///
/// D-082: backdrop is the real maze at the player's spawn point (matches what `.racing`
/// looks like the instant this view hands off), not a flat color card — the user
/// explicitly didn't want a full-screen text block here. The digit/word itself has no
/// background box either — legibility over the maze's own mixed light/dark tiles comes
/// from a hard-edged dark outline (8 offset copies behind the light fill) instead of a
/// soft `.shadow`, which blurred into the pale floor tiles and nearly disappeared there.
struct CountdownView: View {
    let maze: Maze
    let spawnPosition: CGPoint
    let isItemAvailable: [Bool]
    let onComplete: () -> Void

    @State private var index = 0
    private let steps = ["3", "2", "1", "GO!"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DeviceShellView {
                GeometryReader { geo in
                    let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)

                    ZStack {
                        MazeView(
                            maze: maze,
                            cameraPosition: spawnPosition,
                            spriteCell: (col: 0, row: 0),
                            isItemAvailable: isItemAvailable
                        )

                        outlinedStep(scale: scale)
                            .id(index)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                            .accessibilityLabel(steps[index] == "GO!" ? "Go" : "Countdown \(steps[index])")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .task {
            GameFeedback.shared.play(.countdownTick, haptic: .light)
            for nextIndex in steps.indices.dropFirst() {
                try? await Task.sleep(for: .seconds(GameConfig.Countdown.stepDuration))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { index = nextIndex }
                if steps[nextIndex] == "GO!" {
                    GameFeedback.shared.play(.countdownGo, haptic: .success)
                    GameFeedback.shared.playMusic(.race)
                } else {
                    GameFeedback.shared.play(.countdownTick, haptic: .light)
                }
            }
            try? await Task.sleep(for: .seconds(GameConfig.Countdown.stepDuration))
            guard !Task.isCancelled else { return }
            onComplete()
        }
    }

    /// A hard 1px-per-direction outline (8 offset dark copies behind the light fill) —
    /// the pixel font's blocky strokes need a crisp edge, not a blurred `.shadow`, to
    /// stay readable against both the maze's near-black wall tiles and its pale floor.
    private func outlinedStep(scale: CGFloat) -> some View {
        let offset = 1.5 * scale
        let offsets: [(CGFloat, CGFloat)] = [
            (-offset, -offset), (0, -offset), (offset, -offset),
            (-offset, 0), (offset, 0),
            (-offset, offset), (0, offset), (offset, offset)
        ]
        return ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(steps[index])
                    .font(.pixel(16 * scale))
                    .foregroundStyle(countdownDark)
                    .offset(x: offsets[i].0, y: offsets[i].1)
            }
            Text(steps[index])
                .font(.pixel(16 * scale))
                .foregroundStyle(countdownGreen)
        }
    }
}

#Preview {
    let vm = RaceViewModel(seed: 1)
    return CountdownView(maze: vm.maze, spawnPosition: vm.spawnPosition, isItemAvailable: vm.isItemAvailable, onComplete: {})
}
