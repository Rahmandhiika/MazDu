import SwiftUI
import UIKit

/// Raw touch tracking, same technique as `DPadControl` (see its file comment) — avoids
/// the ~1-2s "system gesture gate" delay a `DragGesture`-based press/release pair can hit
/// near the screen edge. Reports touch-down/touch-up only; tap-vs-hold timing is the
/// caller's job (`RaceView` — see `circlePressStartedAt`).
private final class HoldTouchView: UIView {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onPress?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onRelease?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onRelease?()
    }
}

private struct HoldTouchRepresentable: UIViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeUIView(context: Context) -> HoldTouchView {
        let view = HoldTouchView()
        view.backgroundColor = .clear
        view.onPress = onPress
        view.onRelease = onRelease
        return view
    }

    func updateUIView(_ uiView: HoldTouchView, context: Context) {
        uiView.onPress = onPress
        uiView.onRelease = onRelease
    }
}

/// Invisible tap-target over a painted shell button (Circle/Activate) that distinguishes
/// a quick tap from a sustained hold — see `TapButtonControl` for the plain single-tap
/// version (still used by Diamond/Roll).
///
/// VoiceOver double-tap is one atomic activation, not a press you can hold open, so the
/// default accessibility action fires a full press+release (the "tap" path). Callers whose
/// tap/hold split is meaningful (e.g. RaceView's skill selector) stay reachable through a
/// "Hold"/"Release" action pair on the same element's actions rotor: pick "Hold" to press
/// and hold it open, then "Release" to let go, whenever a VoiceOver user needs the hold path
/// instead of the tap path.
struct HoldButtonControl: View {
    let hole: CGRect
    let scale: CGFloat
    var label: String = "Circle button"
    var hint: String = "Double tap to activate. Use the actions rotor to hold and release."
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        HoldTouchRepresentable(onPress: onPress, onRelease: onRelease)
            .frame(width: hole.width * scale, height: hole.height * scale)
            .position(x: hole.midX * scale, y: hole.midY * scale)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onPress()
                onRelease()
            }
            .accessibilityAction(named: Text("Hold")) {
                onPress()
            }
            .accessibilityAction(named: Text("Release")) {
                onRelease()
            }
    }
}
