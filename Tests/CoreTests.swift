import AppKit

@main
struct CoreTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.00001 }
    static func pixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> NSColor {
        bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    }
    static func main() throws {
        _ = NSApplication.shared
        historyTests()
        geometryTests()
        try rendererTests()
        print("PASS: \(checks) assertions (history, geometry, PNG rendering)")
    }
    static func historyTests() {
        var history = History<String>()
        let initialID = history.current.id
        check(history.items.isEmpty, "history starts empty")
        check(!history.canUndo && !history.canRedo, "empty history has no actions")
        history.undo(); history.redo()
        check(history.current.id == initialID, "empty undo/redo are no-ops")
        history.append("brush")
        let brushID = history.current.id
        check(history.items == ["brush"] && history.canUndo, "append records one action")
        history.append("text")
        let bothID = history.current.id
        history.undo()
        check(history.items == ["brush"] && history.current.id == brushID, "undo restores state identity")
        check(history.canRedo, "undo enables redo")
        history.redo()
        check(history.items == ["brush", "text"] && history.current.id == bothID, "redo restores exported state")
        history.undo()
        history.append("different text")
        check(!history.canRedo, "new action invalidates redo branch")
        history.undo(); history.undo()
        check(history.items.isEmpty && history.current.id == initialID, "undo reaches untouched capture")
    }
    static func geometryTests() {
        let geometry = CanvasGeometry(imageSize: CGSize(width: 2000, height: 1000),
                                      bounds: CGRect(x: 10, y: 20, width: 1040, height: 740), inset: 20)
        check(near(geometry.scale, 0.5), "aspect fit scale")
        check(near(geometry.imageRect.minX, 30) && near(geometry.imageRect.minY, 140), "centered letterboxing")
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 342.5, y: 213.25), CGPoint(x: 1999, y: 999)] {
            let roundtrip = geometry.imagePoint(from: geometry.viewPoint(from: point))!
            check(near(roundtrip.x, point.x) && near(roundtrip.y, point.y), "pixel coordinates survive preview scaling")
        }
        check(geometry.imagePoint(from: .zero) == nil, "letterbox clicks are ignored")
        check(geometry.imagePoint(from: .zero, clamp: true) == .zero, "dragging outside clamps to edge")
        let outside = geometry.imagePoint(from: CGPoint(x: 99999, y: 99999), clamp: true)!
        check(outside == CGPoint(x: 2000, y: 1000), "far drag clamps to image max")
        let empty = CanvasGeometry(imageSize: .zero, bounds: .zero, inset: 18)
        check(empty.scale == 0 && empty.imagePoint(from: .zero) == nil, "zero geometry is safe")
        let tiny = CanvasGeometry(imageSize: CGSize(width: 200, height: 100),
                                  bounds: CGRect(x: 0, y: 0, width: 1, height: 1), inset: 18)
        check(tiny.imageRect == .zero, "negative available size is safe")
    }
    static func rendererTests() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 40))
        let source = context.makeImage()!
        let originalPNG = try AnnotationRenderer.png(image: source, annotations: [])
        let original = NSBitmapImageRep(data: originalPNG)!
        check(original.pixelsWide == 240 && original.pixelsHigh == 160, "export keeps exact pixel dimensions")
        check(pixel(original, x: 5, y: 5).blueComponent > 0.9 && pixel(original, x: 5, y: 5).redComponent > 0.9,
              "top of export remains white")
        check(pixel(original, x: 5, y: 155).blueComponent > 0.9 && pixel(original, x: 5, y: 155).redComponent < 0.1,
              "bottom marker is not vertically flipped")
        let annotations: [Annotation] = [
            .brush(BrushStroke(points: [CGPoint(x: 20, y: 80), CGPoint(x: 100, y: 80)], color: .red, width: 8)),
            .brush(BrushStroke(points: [CGPoint(x: 180, y: 120)], color: .green, width: 12)),
            .text(TextAnnotation(text: "测试 Hello", rect: CGRect(x: 120, y: 50, width: 115, height: 30),
                                 color: .black, fontSize: 18))
        ]
        let png = try AnnotationRenderer.png(image: source, annotations: annotations)
        let rendered = NSBitmapImageRep(data: png)!
        let red = pixel(rendered, x: 60, y: 80)
        check(red.redComponent > 0.8 && red.greenComponent < 0.2, "brush stroke is rendered")
        let green = pixel(rendered, x: 180, y: 40)
        check(green.greenComponent > 0.8 && green.redComponent < 0.2, "single click paints a dot")
        var darkPixels = 0
        for y in 80..<115 { for x in 120..<235 {
            let color = pixel(rendered, x: x, y: y)
            if color.redComponent < 0.5 && color.greenComponent < 0.5 && color.blueComponent < 0.5 { darkPixels += 1 }
        } }
        check(darkPixels > 10, "Unicode text renders inside intended image coordinates")
        check(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), "export is a PNG")
    }
}
