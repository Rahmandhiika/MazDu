import SwiftUI
import UIKit

/// Raw touch tracking — no `UIGestureRecognizer` at all — for the D-pad's whole zone.
/// `DragGesture` compiles to `UIPanGestureRecognizer`, which iOS's system-gesture
/// arbitration treats as a candidate edge-swipe and can delay ~1-2s (logged to Console as
/// "Gesture: System gesture gate timed out.") depending on where in the zone the touch
/// lands — confirmed live on 2 real iPhones (down/left/right affected, up not), and
/// unmoved by 3 different SwiftUI-level fixes first (RunLoop mode, view restructuring,
/// `.simultaneousGesture`). Plain `touchesBegan/Moved/Ended` on a `UIView` never enters
/// that negotiation. `TapButtonControl`'s `.onTapGesture` (a *tap*, not *pan*, recognizer)
/// was never affected either — this sidesteps the same recognizer family entirely rather
/// than trying to convince it to behave.
private final class DPadTouchView: UIView {
    var onDirectionChanged: ((RaceViewModel.Direction) -> Void)?
    var onRelease: (() -> Void)?

    private func direction(for point: CGPoint) -> RaceViewModel.Direction {
        let dx = point.x - bounds.midX
        let dy = point.y - bounds.midY
        return abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        onDirectionChanged?(direction(for: point))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        onDirectionChanged?(direction(for: point))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onRelease?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onRelease?()
    }
}

private struct DPadTouchRepresentable: UIViewRepresentable {
    let onPress: (RaceViewModel.Direction) -> Void
    let onRelease: () -> Void

    func makeUIView(context: Context) -> DPadTouchView {
        let view = DPadTouchView()
        view.backgroundColor = .clear
        view.onDirectionChanged = onPress
        view.onRelease = onRelease
        return view
    }

    func updateUIView(_ uiView: DPadTouchView, context: Context) {
        // Closures are recreated every SwiftUI body pass — keep the live view's copies
        // current so they always call into this render's onPress/onRelease.
        uiView.onDirectionChanged = onPress
        uiView.onRelease = onRelease
    }
}

/// Invisible tap-target over the painted D-pad in the shell art (D-013: controls are
/// baked into the image, taps are handled by overlays matching its coordinates).
struct DPadControl: View {
    let scale: CGFloat
    let activeDirection: RaceViewModel.Direction?
    let onPress: (RaceViewModel.Direction) -> Void
    let onRelease: () -> Void

    private static let dark = Color(red: 0.027, green: 0.094, blue: 0.129)
    private static let light = Color(red: 0.878, green: 0.973, blue: 0.812)

    var body: some View {
        let rect = ShellLayout.dpadHole
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)

        DPadTouchRepresentable(onPress: onPress, onRelease: onRelease)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
            .overlay(
                // Rocker feel: the pressed arm dips (dark tint), the opposite arm lifts
                // (light tint) — mirrors a real D-pad's mechanical seesaw, not just a
                // single side lighting up, per the "kayak gameboy asli" feedback. Purely
                // decorative — hit-testing stays with DPadTouchRepresentable underneath.
                ForEach([RaceViewModel.Direction.up, .down, .left, .right], id: \.self) { direction in
                    armHighlight(direction, in: size)
                }
            )
            .overlay(
                // VoiceOver can't drive the raw-touch zone above (it intercepts direct
                // touches for its own swipe/double-tap navigation, and the whole point of
                // that raw UIView — see the file comment — is to opt out of gesture
                // arbitration, so it can't also expose itself as one draggable element).
                // Four discrete, invisible per-direction elements instead: VoiceOver swipes
                // between them and double-tap fires one press+release, matching the
                // one-move-per-activation model `MainMenuView` already uses for its cursor.
                ForEach([RaceViewModel.Direction.up, .down, .left, .right], id: \.self) { direction in
                    directionAccessibilityElement(direction, in: size)
                }
            )
            .position(x: rect.midX * scale, y: rect.midY * scale)
    }

    private func directionAccessibilityElement(_ direction: RaceViewModel.Direction, in size: CGSize) -> some View {
        let armThickness = size.width / 3
        let armLength = size.height / 3

        let elementSize: CGSize
        let position: CGPoint
        switch direction {
        case .up:
            elementSize = CGSize(width: armThickness, height: armLength)
            position = CGPoint(x: size.width / 2, y: elementSize.height / 2)
        case .down:
            elementSize = CGSize(width: armThickness, height: armLength)
            position = CGPoint(x: size.width / 2, y: size.height - elementSize.height / 2)
        case .left:
            elementSize = CGSize(width: armLength, height: armThickness)
            position = CGPoint(x: elementSize.width / 2, y: size.height / 2)
        case .right:
            elementSize = CGSize(width: armLength, height: armThickness)
            position = CGPoint(x: size.width - elementSize.width / 2, y: size.height / 2)
        }

        return Color.clear
            .frame(width: elementSize.width, height: elementSize.height)
            .position(position)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(directionLabel(direction))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onPress(direction)
                onRelease()
            }
    }

    private func directionLabel(_ direction: RaceViewModel.Direction) -> String {
        switch direction {
        case .up: "D-pad up"
        case .down: "D-pad down"
        case .left: "D-pad left"
        case .right: "D-pad right"
        }
    }

    private func armHighlight(_ direction: RaceViewModel.Direction, in size: CGSize) -> some View {
        let isPressed = activeDirection == direction
        let isOpposite = activeDirection == direction.opposite
        let armThickness = size.width / 3
        let armLength = size.height / 3

        let armSize: CGSize
        let position: CGPoint
        switch direction {
        case .up:
            armSize = CGSize(width: armThickness, height: armLength)
            position = CGPoint(x: size.width / 2, y: armSize.height / 2)
        case .down:
            armSize = CGSize(width: armThickness, height: armLength)
            position = CGPoint(x: size.width / 2, y: size.height - armSize.height / 2)
        case .left:
            armSize = CGSize(width: armLength, height: armThickness)
            position = CGPoint(x: armSize.width / 2, y: size.height / 2)
        case .right:
            armSize = CGSize(width: armLength, height: armThickness)
            position = CGPoint(x: size.width - armSize.width / 2, y: size.height / 2)
        }

        return Rectangle()
            .fill(isPressed ? Self.dark : Self.light)
            .opacity(isPressed || isOpposite ? 0.3 : 0)
            .frame(width: armSize.width, height: armSize.height)
            .position(position)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.08), value: activeDirection)
    }
}
