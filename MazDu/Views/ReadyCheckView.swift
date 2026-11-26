import SwiftUI

private let readyScreenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let readyScreenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

/// D-063 item 3: ready-check gate shown after peers connect, before the race begins.
/// Diamond backs out to the main menu (notifying the opponent via `onBack`); circle
/// toggles local ready state like a switch, each toggle broadcast to the opponent so
/// both KAMU/LAWAN boxes stay in sync. Once both sides are ready, MatchViewModel starts
/// the race on its own — this view has no "start" action of its own.
///
/// D-083: also reused verbatim for `.secondReady` (the post-intro-tour ready gate,
/// D-071) via `showsGuide` — opponent identity is no longer news by then (the intro
/// tour already showed both players in the same maze), so that screen trades the
/// opponent-name block for a compact controls/skills guide instead. `showsGuide`
/// keeps this one view instead of forking into a near-duplicate second file.
struct ReadyCheckView: View {
    let opponentName: String
    let localReady: Bool
    let opponentReady: Bool
    var showsGuide: Bool = false
    let onToggleReady: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DeviceShellView {
                readyScreen
            } controls: { scale in
                TapButtonControl(hole: ShellLayout.diamondHole, scale: scale) {
                    GameFeedback.shared.play(.uiSelect, haptic: .light)
                    onBack()
                }
                TapButtonControl(hole: ShellLayout.circleHole, scale: scale) {
                    GameFeedback.shared.play(.uiSelect, haptic: .selection)
                    onToggleReady()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var readyScreen: some View {
        GeometryReader { geo in
            let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)

            VStack(spacing: 8 * scale) {
                if showsGuide {
                    Text("GOT IT?")
                        .pixelTitle(scale: scale)

                    mechanicsGuide(scale: scale)
                        .padding(.bottom, 3 * scale)
                } else {
                    VStack(spacing: 2 * scale) {
                        Text("ENEMY:")
                            .font(.pixel(.label, scale: scale))
                            .foregroundStyle(readyScreenDark.opacity(0.65))
                        Text(opponentName.uppercased())
                            .font(.pixel(.item, scale: scale))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }

                    Text("START?")
                        .pixelTitle(scale: scale)
                }

                HStack(spacing: 10 * scale) {
                    readyBox(label: "YOU", isReady: localReady, scale: scale)
                    readyBox(label: "ENEMY", isReady: opponentReady, scale: scale)
                }

                Spacer(minLength: 0)

                controlHint(scale: scale)
            }
            .foregroundStyle(readyScreenDark)
            .padding(.top, (showsGuide ? 8 : 14) * scale)
            .padding(.bottom, (showsGuide ? 9 : 4) * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(readyScreenGreen)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityText: String {
        let base = showsGuide
            ? "Second ready screen. Roll picks a random skill from four choices: darken, freeze, switch, shield. Circle button: hold to use a skill, tap to change skill."
            : "Ready screen. Enemy: \(opponentName)."
        return base + " You are \(localReady ? "ready" : "not ready"). Enemy is \(opponentReady ? "ready" : "not ready"). Circle to toggle ready, diamond to go back to the menu."
    }

    /// D-083: compact one-time mechanics primer, shown only on the post-tour ready gate.
    /// "ROLL" stays plain text (the diamond glyph `controlHint` below uses means KELUAR
    /// on this screen, a different meaning). The Activate lines below deliberately DO
    /// reuse the circle glyph — both lines describe the same one physical button (circle
    /// = Activate), so there's no cross-meaning inside the guide itself; `controlHint`'s
    /// own circle (READY) sits far enough below, after the KAMU/LAWAN boxes, that the two
    /// don't read as the same instruction. The 4 skill icons are the exact assets
    /// `RaceView`'s mini-screen renders in-race, so they're already-familiar there.
    private func mechanicsGuide(scale: CGFloat) -> some View {
        VStack(spacing: 3 * scale) {
            Text("ROLL: GET RANDOM SKILL")

            HStack(spacing: 4 * scale) {
                ForEach(SkillType.allCases, id: \.self) { skill in
                    Image(skill.iconName)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 9 * scale, height: 9 * scale)
                        .padding(1.5 * scale)
                        .background(readyScreenDark)
                        .clipShape(RoundedRectangle(cornerRadius: 2 * scale))
                }
            }

            VStack(spacing: 1.5 * scale) {
                activateLine("HOLD", "USE SKILL", scale: scale)
                activateLine("TAP", "CHANGE SKILL", scale: scale)
            }
        }
        .font(.pixel(.hint, scale: scale))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
    }

    private func activateLine(_ action: String, _ meaning: String, scale: CGFloat) -> some View {
        HStack(spacing: 3 * scale) {
            Circle()
                .strokeBorder(readyScreenDark, lineWidth: 1 * scale)
                .frame(width: 6 * scale, height: 6 * scale)
            Text("\(action) = \(meaning)")
        }
    }

    /// The ready indicator is a filled/unfilled circle rather than separate text states —
    /// same "switch" reading the user described for the circle button itself.
    private func readyBox(label: String, isReady: Bool, scale: CGFloat) -> some View {
        VStack(spacing: 3 * scale) {
            Text(label)
                .font(.pixel(.label, scale: scale))
            Circle()
                .strokeBorder(readyScreenDark, lineWidth: 1.2 * scale)
                .background(Circle().fill(isReady ? readyScreenDark : .clear))
                .frame(width: 10 * scale, height: 10 * scale)
            Text(isReady ? "READY" : "...")
                .font(.pixel(.hint, scale: scale))
        }
        .frame(width: 40 * scale)
        .padding(.vertical, 4 * scale)
        .background(readyScreenDark.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
    }

    /// Diamond glyph as a real rotated-square stroke, not a plain "◇" text glyph — same
    /// weight-mismatch fix D-066 already applied to the main menu's circle hint (a plain
    /// glyph in this monospaced font stays hairline-thin regardless of font weight).
    private func controlHint(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            HStack(spacing: 4 * scale) {
                Rectangle()
                    .strokeBorder(readyScreenDark, lineWidth: 1.2 * scale)
                    .frame(width: 5 * scale, height: 5 * scale)
                    .rotationEffect(.degrees(45))
                Text("BACK")
            }
            HStack(spacing: 4 * scale) {
                Circle()
                    .strokeBorder(readyScreenDark, lineWidth: 1.2 * scale)
                    .frame(width: 7 * scale, height: 7 * scale)
                Text("READY")
            }
        }
        .font(.pixel(.hint, scale: scale))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

#Preview {
    ReadyCheckView(opponentName: "iPhone#1234", localReady: true, opponentReady: false, onToggleReady: {}, onBack: {})
}
