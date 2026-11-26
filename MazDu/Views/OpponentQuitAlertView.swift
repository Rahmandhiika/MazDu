import SwiftUI

private let alertScreenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let alertScreenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

/// D-063's reusable "opponent quit" pattern: shown whenever the other device backs out
/// of a gate that requires both players (ready-check today; the rematch-wait gate later,
/// D-063 item 6) instead of silently reading it as a dropped connection. Checked ahead of
/// `MatchViewModel.phase` in ContentView so it can interrupt any gate it applies to.
/// Circle acknowledges and returns this device to the main menu too.
struct OpponentQuitAlertView: View {
    let onAcknowledge: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DeviceShellView {
                alertScreen
            } controls: { scale in
                TapButtonControl(hole: ShellLayout.circleHole, scale: scale, action: onAcknowledge)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var alertScreen: some View {
        GeometryReader { geo in
            let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)

            VStack(spacing: 6 * scale) {
                Spacer(minLength: 0)

                Text("ENEMY LEFT")
                    .pixelTitle(scale: scale * 0.8, lineLimit: 1)
                Text("PRESS TO\nRETURN TO MENU")
                    .font(.pixel(.body, scale: scale))
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)

                HStack(spacing: 4 * scale) {
                    Circle()
                        .strokeBorder(alertScreenDark, lineWidth: 1.2 * scale)
                        .frame(width: 7 * scale, height: 7 * scale)
                    Text("OK")
                        .font(.pixel(.hint, scale: scale))
                }
                .padding(.bottom, 4 * scale)
            }
            .foregroundStyle(alertScreenDark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(alertScreenGreen)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Enemy left the match. Press the circle to return to the main menu.")
        }
    }
}

#Preview {
    OpponentQuitAlertView(onAcknowledge: {})
}
