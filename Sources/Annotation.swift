import AppKit

struct BrushStroke {
    var points: [CGPoint]
    let color: NSColor
    let width: CGFloat
}
struct RectangleAnnotation {
    let rect: CGRect
    let color: NSColor
    let width: CGFloat

    init(start: CGPoint, end: CGPoint, color: NSColor, width: CGFloat) {
        rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: abs(end.x - start.x), height: abs(end.y - start.y))
        self.color = color
        self.width = width
    }

    var isEmpty: Bool { rect.width <= 0 || rect.height <= 0 }
}
struct TextAnnotation {
    let text: String
    let rect: CGRect
    let color: NSColor
    let fontSize: CGFloat
}
enum Annotation {
    case rectangle(RectangleAnnotation)
    case brush(BrushStroke)
    case text(TextAnnotation)
}

/// The preview and PNG share one drawing implementation; export never captures UI chrome.
enum AnnotationRenderer {
    static func draw(image: CGImage, annotations: [Annotation], in context: CGContext) {
        let size = CGSize(width: image.width, height: image.height)
        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for annotation in annotations {
            switch annotation {
            case .rectangle(let rectangle):
                guard !rectangle.isEmpty else { continue }
                context.setStrokeColor(rectangle.color.cgColor)
                context.setLineWidth(rectangle.width)
                context.setLineJoin(.miter)
                context.stroke(rectangle.rect)
            case .brush(let stroke):
                guard let first = stroke.points.first else { continue }
                context.setStrokeColor(stroke.color.cgColor)
                context.setFillColor(stroke.color.cgColor)
                context.setLineWidth(stroke.width)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                if stroke.points.count == 1 {
                    context.fillEllipse(in: CGRect(x: first.x - stroke.width / 2,
                                                  y: first.y - stroke.width / 2,
                                                  width: stroke.width, height: stroke.width))
                } else {
                    context.beginPath()
                    context.move(to: first)
                    stroke.points.dropFirst().forEach { context.addLine(to: $0) }
                    context.strokePath()
                }
            case .text(let text):
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: text.fontSize, weight: .semibold),
                    .foregroundColor: text.color,
                    .paragraphStyle: paragraph
                ]
                NSAttributedString(string: text.text, attributes: attributes).draw(
                    with: text.rect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    static func png(image: CGImage, annotations: [Annotation]) throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RenderError.allocationFailed
        }
        draw(image: image, annotations: annotations, in: context)
        guard let rendered = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
            throw RenderError.encodingFailed
        }
        return data
    }
    enum RenderError: LocalizedError {
        case allocationFailed, encodingFailed
        var errorDescription: String? {
            switch self {
            case .allocationFailed: return "图片太大，无法分配导出内存。请尝试截取较小区域。"
            case .encodingFailed: return "无法编码 PNG 图片，请重试。"
            }
        }
    }
}
