import AppKit

/// The menu bar's template images: the sunburst alone, or with Session over
/// Weekly beside it. Template, so the menu bar tints them like system items.
enum MenuBarIcon {
    /// The 12-ray sunburst, as the template mark draws it.
    private static func drawMark(in rect: NSRect, ctx: CGContext) {
        let unit = rect.width / 24
        let center = CGPoint(x: rect.midX, y: rect.midY)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(unit * 2.4)
        ctx.setLineCap(.round)
        for i in 0..<12 {
            let angle = CGFloat(i) * 30 * .pi / 180
            ctx.move(to: CGPoint(x: center.x + cos(angle) * unit * 3.2,
                                 y: center.y + sin(angle) * unit * 3.2))
            ctx.addLine(to: CGPoint(x: center.x + cos(angle) * unit * 9,
                                    y: center.y + sin(angle) * unit * 9))
        }
        ctx.strokePath()
    }

    /// The sunburst brand mark as a template image, so it adapts to menu bar
    /// appearance (dark/light, active/inactive) like system status items.
    static let mark: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawMark(in: rect, ctx: ctx)
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// The mark with up to two small figures stacked to its right, as one
    /// template image (a menu bar label shows a single image).
    static func label(_ figures: [String]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: figures.count > 1 ? 9 : 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let sizes = figures.map { ($0 as NSString).size(withAttributes: attributes) }
        let textWidth = ceil(sizes.map(\.width).max() ?? 0)
        let lineHeight = ceil(sizes.map(\.height).max() ?? 0)
        let mark: CGFloat = 16, gap: CGFloat = 3, height: CGFloat = 22
        let image = NSImage(size: NSSize(width: mark + gap + textWidth, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawMark(in: NSRect(x: 0, y: (height - mark) / 2, width: mark, height: mark), ctx: ctx)
            // Right-aligned lines, centered as a block (top line first).
            let block = lineHeight * CGFloat(figures.count) - (figures.count > 1 ? 2 : 0)
            var y = (height + block) / 2 - lineHeight
            for (figure, size) in zip(figures, sizes) {
                let x = mark + gap + textWidth - size.width
                (figure as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
                y -= lineHeight - 2
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
