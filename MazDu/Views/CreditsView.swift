import SwiftUI

private let creditsScreenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let creditsScreenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

/// TestFlight/App Review audit P1: an in-app surface for the CC BY 4.0 attribution
/// "Itty Bitty 8 Bit" (Kevin MacLeod, incompetech.com) requires — see
/// `Resources/Audio/README.md`'s "Music credits" section, the source of truth this
/// screen's text is drawn from.
///
/// Screen content only — no shell, no D-pad/circle controls of its own. `MainMenuView`
/// swaps this in for its own `menuScreen` inside the same `DeviceShellView` instance
/// (not a separate presentation), so only the middle screen changes, the way a real
/// handheld's screen redraws without the whole device flickering.
///
/// `scrollOffset` is owned by `MainMenuView` (the D-pad that drives it lives in the
/// shell's `controls` layer, a sibling of this content, not a child of it); this view
/// only renders at that offset and reports how far there still is to scroll.
struct CreditsView: View {
    let scrollOffset: CGFloat
    let onMaxScrollChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            let scale = max(1, geo.size.width / ShellLayout.mainScreenHole.width)
            let viewportHeight = geo.size.height

            ZStack(alignment: .top) {
                creditsScreenGreen

                VStack(alignment: .leading, spacing: 5 * scale) {
                    Text("CREDITS")
                        .pixelTitle(scale: scale * 0.8, lineLimit: 1)

                    creditEntry(
                        title: "\u{201C}Itty Bitty 8 Bit\u{201D}",
                        body: "By Kevin MacLeod (incompetech.com). CC BY 4.0: creativecommons.org/licenses/by/4.0. Modified: converted from MP3 to WAV (44.1kHz, 16-bit PCM); no other changes.",
                        scale: scale
                    )

                    creditEntry(
                        title: "\u{201C}Game BOI 2\u{201D}",
                        body: "By HoliznaCC0. CC0 1.0.",
                        scale: scale
                    )
                }
                .foregroundStyle(creditsScreenDark)
                .padding(.horizontal, 6 * scale)
                .padding(.top, 6 * scale)
                .padding(.bottom, 16 * scale)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    onMaxScrollChange(max(0, height - viewportHeight))
                }
                .offset(y: -scrollOffset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                controlHint(scale: scale)
                    .padding(.bottom, 2 * scale)
            }
        }
    }

    private func creditEntry(title: String, body: String, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(title)
                .font(.pixel(.hint, scale: scale))
            Text(body)
                .font(.pixel(.hint, scale: scale * 0.85))
        }
        .accessibilityElement(children: .combine)
    }

    /// Same legend idiom as `MainMenuView.controlHint` — "SCROLL" instead of "UP/DOWN"
    /// (the D-pad scrolls this screen instead of moving a list cursor) and "BACK"
    /// instead of "OK", so the affordance is spelled out rather than assumed.
    private func controlHint(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            HStack(spacing: 4 * scale) {
                Image(systemName: "arrow.up.and.down")
                Text("SCROLL")
            }
            HStack(spacing: 4 * scale) {
                Circle()
                    .strokeBorder(creditsScreenDark, lineWidth: 1.2 * scale)
                    .frame(width: 7 * scale, height: 7 * scale)
                Text("BACK")
            }
        }
        .font(.pixel(.hint, scale: scale))
        .foregroundStyle(creditsScreenDark)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 2 * scale)
        .background(creditsScreenGreen.opacity(0.85))
        .clipShape(Capsule())
    }
}

#Preview {
    CreditsView(scrollOffset: 0, onMaxScrollChange: { _ in })
}
