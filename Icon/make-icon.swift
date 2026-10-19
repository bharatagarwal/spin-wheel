// Renders AppIcon.icns: ./Icon/make-icon.sh
import AppKit

let palette: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemIndigo, .systemPurple,
]

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Draw on Apple's 1024 grid: an 824 pt tile inset by 100, y pointing up.
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [NSColor(white: 0.26, alpha: 1).cgColor, NSColor(white: 0.07, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: 512, y: 560), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 600, options: [])

    let c = CGPoint(x: 512, y: 494)
    let outer: CGFloat = 330, face: CGFloat = 307

    // Steel rim with a drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
    ctx.setFillColor(NSColor(white: 0.5, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
    ctx.clip()
    let steel = CGGradient(colorsSpace: nil, colors: [NSColor(white: 0.9, alpha: 1), NSColor(white: 0.45, alpha: 1), NSColor(white: 0.75, alpha: 1), NSColor(white: 0.3, alpha: 1)].map(\.cgColor) as CFArray, locations: [0, 0.4, 0.65, 1])!
    ctx.drawLinearGradient(steel, start: CGPoint(x: c.x - outer, y: c.y + outer), end: CGPoint(x: c.x + outer, y: c.y - outer), options: [])
    ctx.restoreGState()

    // Slices, rotated a little so a boundary isn't dead centre under the flapper.
    let n = palette.count
    let seg = 2 * CGFloat.pi / CGFloat(n)
    let turn: CGFloat = 0.21
    for i in 0..<n {
        ctx.move(to: c)
        ctx.addArc(center: c, radius: face, startAngle: turn + CGFloat(i) * seg, endAngle: turn + CGFloat(i + 1) * seg, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(palette[i].cgColor)
        ctx.fillPath()
    }
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - face, y: c.y - face, width: face * 2, height: face * 2))
    ctx.clip()
    let dome = CGGradient(colorsSpace: nil, colors: [NSColor.white.withAlphaComponent(0.22), NSColor.clear, NSColor.black.withAlphaComponent(0.28)].map(\.cgColor) as CFArray, locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(dome, startCenter: CGPoint(x: c.x - 60, y: c.y + 90), startRadius: 0, endCenter: c, endRadius: face, options: [])
    ctx.restoreGState()

    for i in 0..<n {
        let a = turn + CGFloat(i) * seg
        ctx.move(to: c)
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * face, y: c.y + sin(a) * face))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(5)
        ctx.strokePath()
        let p = CGPoint(x: c.x + cos(a) * face * 0.92, y: c.y + sin(a) * face * 0.92)
        drawBall(ctx, p, 12, shadow: 6)
    }
    ctx.addEllipse(in: CGRect(x: c.x - face, y: c.y - face, width: face * 2, height: face * 2))
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.setLineWidth(5)
    ctx.strokePath()

    drawBall(ctx, c, 46, shadow: 12)

    // Flapper hanging straight down from the rim.
    let pivot = CGPoint(x: c.x, y: c.y + outer - 6)
    ctx.saveGState()
    ctx.translateBy(x: pivot.x, y: pivot.y)
    ctx.setShadow(offset: CGSize(width: 4, height: -8), blur: 12, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    let len: CGFloat = 112, root: CGFloat = 26, tip: CGFloat = 10
    ctx.move(to: CGPoint(x: -root, y: 0))
    ctx.addLine(to: CGPoint(x: root, y: 0))
    ctx.addLine(to: CGPoint(x: tip, y: -len))
    ctx.addArc(center: CGPoint(x: 0, y: -len), radius: tip, startAngle: 0, endAngle: .pi, clockwise: true)
    ctx.closePath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    drawBall(ctx, pivot, 34, shadow: 8)

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// A polished silver sphere: pegs, hub and the flapper pivot.
func drawBall(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, shadow: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -shadow / 2), blur: shadow, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    ctx.setFillColor(NSColor(white: 0.6, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    ctx.clip()
    let g = CGGradient(colorsSpace: nil, colors: [NSColor(white: 0.98, alpha: 1), NSColor(white: 0.7, alpha: 1), NSColor(white: 0.38, alpha: 1)].map(\.cgColor) as CFArray, locations: [0, 0.5, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: p.x - r * 0.35, y: p.y + r * 0.4), startRadius: 0, endCenter: p, endRadius: r * 1.1, options: [])
    ctx.restoreGState()
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! render(size * scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
