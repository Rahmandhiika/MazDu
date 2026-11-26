import CoreGraphics

/// Pixel rects measured directly from `shell_body` art (160x350 canvas, D-019; re-measured
/// after the D-051 shell art update — same canvas size, bigger D-pad, 2 new top holes).
/// Shared by `DeviceShellView` (screen holes) and control overlays (D-pad/buttons),
/// so both use the exact same coordinate space and scale.
enum ShellLayout {
    static let canvasSize = CGSize(width: 160, height: 350)
    static let mainScreenHole = CGRect(x: 24, y: 68, width: 112, height: 130)
    static let miniScreenHole = CGRect(x: 84, y: 217, width: 62, height: 24)
    static let dpadHole = CGRect(x: 10, y: 249, width: 68, height: 68)
    static let diamondHole = CGRect(x: 81, y: 253, width: 33, height: 33)
    static let circleHole = CGRect(x: 113, y: 273, width: 34, height: 34)
    /// Reserved slots near the "MAZDU" wordmark — real transparent cutouts in the art as
    /// of D-051, content/purpose not decided yet.
    static let topLeftHole = CGRect(x: 18, y: 37, width: 38, height: 14)
    static let topRightHole = CGRect(x: 104, y: 37, width: 38, height: 14)
}
