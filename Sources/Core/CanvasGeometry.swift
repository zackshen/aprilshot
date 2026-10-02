import Foundation

/// All annotation coordinates are original image pixels, with a bottom-left origin.
struct CanvasGeometry {
    let imageSize: CGSize
    let bounds: CGRect
    let inset: CGFloat

    var imageRect: CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let available = bounds.insetBy(dx: inset, dy: inset)
        guard available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        return CGRect(x: bounds.midX - imageSize.width * scale / 2,
                      y: bounds.midY - imageSize.height * scale / 2,
                      width: imageSize.width * scale, height: imageSize.height * scale)
    }
    var scale: CGFloat { imageSize.width > 0 ? imageRect.width / imageSize.width : 0 }
    func imagePoint(from viewPoint: CGPoint, clamp: Bool = false) -> CGPoint? {
        guard scale > 0, clamp || imageRect.contains(viewPoint) else { return nil }
        let point = CGPoint(x: (viewPoint.x - imageRect.minX) / scale,
                            y: (viewPoint.y - imageRect.minY) / scale)
        return CGPoint(x: min(max(point.x, 0), imageSize.width),
                       y: min(max(point.y, 0), imageSize.height))
    }
    func viewPoint(from imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + imagePoint.x * scale,
                y: imageRect.minY + imagePoint.y * scale)
    }
}
