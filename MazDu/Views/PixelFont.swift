import SwiftUI

/// `PressStart2P-Regular.ttf` (Resources/Fonts, registered in Info.plist's `UIAppFonts`)
/// — the pixel font D-011 planned for all "screen" text but never wired up until now.
/// Single weight only (no bold/heavy variant exists), so callers drop `weight:`.
extension Font {
    static func pixel(_ size: CGFloat) -> Font {
        .custom("PressStart2P-Regular", size: size)
    }
}

/// Shared type scale (D-080) — before this, every screen picked its own raw point size
/// independently, producing near-duplicate values (5.5/6/6.5, 6/7) for the exact same
/// role. Reach for one of these instead of a fresh number; only `RaceView`'s mini-screen
/// and `ContentView`'s `TimerHUD`/`VsArrowHUD` stay on raw `.pixel(_:)` sizes — both
/// render into tiny fixed cutouts already tuned and confirmed on real hardware (D-055
/// through D-060, D-076), where nudging the base size risks the exact clipping
/// regression D-076 already cost a session to fix.
enum PixelTextStyle {
    /// Compact control hints and small status badges: "↕ NAIK/TURUN", "READY"/"...".
    case hint
    /// Box/section labels: "KAMU"/"LAWAN" headers, "LAWAN KAMU:" sublabel.
    case label
    /// Secondary status/description lines: "MENUNGGU PEMAIN LAIN...", tour captions.
    case body
    /// List items and value text: "PLAY"/"QUIT", opponent name, "MENCARI LAWAN...".
    case item
    /// Screen titles: "MULAI?", "WINNER", "LAWAN KELUAR". Use `.pixelTitle(scale:)`
    /// below, not this directly — titles always need the shared shrink-to-fit safety net
    /// so a short title ("SERI") and a long one ("WINNER\nIPHONE#1234") render at
    /// consistent weight instead of one ballooning and the other shrinking arbitrarily.
    case title

    var size: CGFloat {
        switch self {
        case .hint: 5.5
        case .label: 6
        case .body: 7
        case .item: 8
        case .title: 11
        }
    }
}

extension Font {
    static func pixel(_ style: PixelTextStyle, scale: CGFloat = 1) -> Font {
        .pixel(style.size * scale)
    }
}

extension View {
    /// Every screen title goes through this, not a bare `.font(.pixel(.title, ...))` —
    /// the shared `lineLimit`/`minimumScaleFactor` pair is what keeps a short title at
    /// full size while a long one shrinks just enough to fit, instead of each screen
    /// wiring its own (or, before D-080, none at all — see `OpponentQuitAlertView`'s
    /// old two-line wrap and `FinishStatsView`'s old wide shrink range). `lineLimit`
    /// defaults to 2 (titles that are genuinely long, like a name, are expected to wrap)
    /// — pass 1 for a short title that should shrink-to-fit on one line instead of
    /// wrapping (SwiftUI prefers wrapping over shrinking whenever `lineLimit` allows it).
    func pixelTitle(scale: CGFloat, lineLimit: Int = 2) -> some View {
        self
            .font(.pixel(.title, scale: scale))
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.5)
    }
}
