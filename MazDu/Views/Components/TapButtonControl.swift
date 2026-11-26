import SwiftUI

/// Invisible tap-target over a painted shell button (Diamond/Circle) — same pattern as
/// `DPadControl` but a plain single tap instead of a held direction.
struct TapButtonControl: View {
    let hole: CGRect
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: hole.width * scale, height: hole.height * scale)
            .onTapGesture(perform: action)
            .position(x: hole.midX * scale, y: hole.midY * scale)
    }
}
