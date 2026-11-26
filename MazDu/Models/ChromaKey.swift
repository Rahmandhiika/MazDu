import UIKit

extension UIImage {
    /// The source sheet has no alpha channel — it uses a flat green (101,255,0) as a
    /// chroma-key background instead of real transparency. Strip it once at load time.
    func chromaKeyed(removing color: (r: UInt8, g: UInt8, b: UInt8), tolerance: Int = 20) -> UIImage {
        guard let cgImage = cgImage else { return self }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let dr = abs(Int(pixels[i]) - Int(color.r))
            let dg = abs(Int(pixels[i + 1]) - Int(color.g))
            let db = abs(Int(pixels[i + 2]) - Int(color.b))
            if dr < tolerance, dg < tolerance, db < tolerance {
                // Context is premultiplied-alpha: RGB must be 0 when alpha is 0, or the
                // "invisible" pixel's leftover green channel gets composited as an additive
                // fringe instead of actually disappearing.
                pixels[i] = 0
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
            }
        }

        guard let outContext = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let outImage = outContext.makeImage() else { return self }
        return UIImage(cgImage: outImage, scale: scale, orientation: imageOrientation)
    }

    /// Exact-pixel crop of one `cellSize`x`cellSize` cell from a sprite sheet. Cropping the
    /// source bitmap once (vs. offsetting+clipping a scaled-up view in SwiftUI) avoids
    /// fractional-pixel drift at render time bleeding in a sliver of the neighboring cell —
    /// worse the further the cell is from the origin, since the offset accumulates.
    func croppedCell(col: Int, row: Int, cellSize: Int) -> UIImage {
        croppedCell(col: col, row: row, width: cellSize, height: cellSize)
    }

    /// Non-square variant (e.g. `plane_icon`'s 16x12 frames) — same exact-pixel-crop
    /// reasoning as the square version above.
    func croppedCell(col: Int, row: Int, width: Int, height: Int) -> UIImage {
        guard let cgImage = cgImage else { return self }
        let rect = CGRect(x: col * width, y: row * height, width: width, height: height)
        guard let cropped = cgImage.cropping(to: rect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}
