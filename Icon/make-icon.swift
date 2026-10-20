import AppKit

let palette: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemIndigo, .systemPurple
]

let appleIconGrid: CGFloat = 1024
let appleIconTileInset: CGFloat = 100
let wheelCenter = CGPoint(x: 512, y: 494)
let rimRadius: CGFloat = 330
let faceRadius: CGFloat = 307
let sliceAngle = 2 * CGFloat.pi / CGFloat(palette.count)
let firstSliceTurn: CGFloat = 0.21

func gradient(_ colors: [NSColor], at locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: nil, colors: colors.map(\.cgColor) as CFArray, locations: locations)!
}

func square(around center: CGPoint, radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

func render(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / appleIconGrid, y: CGFloat(pixels) / appleIconGrid)

    let tile = CGRect(x: 0, y: 0, width: appleIconGrid, height: appleIconGrid)
        .insetBy(dx: appleIconTileInset, dy: appleIconTileInset)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    drawTileShadow(tilePath, in: ctx)
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    drawTileBackground(in: ctx)
    drawRim(in: ctx)
    drawSlices(in: ctx)
    drawDome(in: ctx)
    drawDividersAndPegs(in: ctx)
    drawFaceOutline(in: ctx)
    drawBall(ctx, at: wheelCenter, radius: 46, shadow: 12)
    drawFlapper(in: ctx)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawTileShadow(_ tilePath: CGPath, in ctx: CGContext) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawTileBackground(in ctx: CGContext) {
    let background = gradient([NSColor(white: 0.26, alpha: 1), NSColor(white: 0.07, alpha: 1)], at: [0, 1])
    ctx.drawRadialGradient(background, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: 600, options: [])
}

func drawRim(in ctx: CGContext) {
    let rim = square(around: wheelCenter, radius: rimRadius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30,
                  color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.addEllipse(in: rim)
    ctx.setFillColor(NSColor(white: 0.5, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: rim)
    ctx.clip()
    let steel = gradient([NSColor(white: 0.9, alpha: 1), NSColor(white: 0.45, alpha: 1),
                          NSColor(white: 0.75, alpha: 1), NSColor(white: 0.3, alpha: 1)],
                         at: [0, 0.4, 0.65, 1])
    ctx.drawLinearGradient(steel, start: CGPoint(x: wheelCenter.x - rimRadius, y: wheelCenter.y + rimRadius),
                           end: CGPoint(x: wheelCenter.x + rimRadius, y: wheelCenter.y - rimRadius), options: [])
    ctx.restoreGState()
}

func drawSlices(in ctx: CGContext) {
    for index in palette.indices {
        ctx.move(to: wheelCenter)
        ctx.addArc(center: wheelCenter, radius: faceRadius,
                   startAngle: firstSliceTurn + CGFloat(index) * sliceAngle,
                   endAngle: firstSliceTurn + CGFloat(index + 1) * sliceAngle, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(palette[index].cgColor)
        ctx.fillPath()
    }
}

func drawDome(in ctx: CGContext) {
    ctx.saveGState()
    ctx.addEllipse(in: square(around: wheelCenter, radius: faceRadius))
    ctx.clip()
    let dome = gradient([NSColor.white.withAlphaComponent(0.22), NSColor.clear, NSColor.black.withAlphaComponent(0.28)],
                        at: [0, 0.55, 1])
    ctx.drawRadialGradient(dome, startCenter: CGPoint(x: wheelCenter.x - 60, y: wheelCenter.y + 90), startRadius: 0,
                           endCenter: wheelCenter, endRadius: faceRadius, options: [])
    ctx.restoreGState()
}

func drawDividersAndPegs(in ctx: CGContext) {
    for index in palette.indices {
        let angle = firstSliceTurn + CGFloat(index) * sliceAngle
        ctx.move(to: wheelCenter)
        ctx.addLine(to: CGPoint(x: wheelCenter.x + cos(angle) * faceRadius, y: wheelCenter.y + sin(angle) * faceRadius))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(5)
        ctx.strokePath()
        let peg = CGPoint(x: wheelCenter.x + cos(angle) * faceRadius * 0.92,
                          y: wheelCenter.y + sin(angle) * faceRadius * 0.92)
        drawBall(ctx, at: peg, radius: 12, shadow: 6)
    }
}

func drawFaceOutline(in ctx: CGContext) {
    ctx.addEllipse(in: square(around: wheelCenter, radius: faceRadius))
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.setLineWidth(5)
    ctx.strokePath()
}

func drawFlapper(in ctx: CGContext) {
    let pivot = CGPoint(x: wheelCenter.x, y: wheelCenter.y + rimRadius - 6)
    ctx.saveGState()
    ctx.translateBy(x: pivot.x, y: pivot.y)
    ctx.setShadow(offset: CGSize(width: 4, height: -8), blur: 12, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    let length: CGFloat = 112, rootHalfWidth: CGFloat = 26, tipRadius: CGFloat = 10
    ctx.move(to: CGPoint(x: -rootHalfWidth, y: 0))
    ctx.addLine(to: CGPoint(x: rootHalfWidth, y: 0))
    ctx.addLine(to: CGPoint(x: tipRadius, y: -length))
    ctx.addArc(center: CGPoint(x: 0, y: -length), radius: tipRadius, startAngle: 0, endAngle: .pi, clockwise: true)
    ctx.closePath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    drawBall(ctx, at: pivot, radius: 34, shadow: 8)
}

func drawBall(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, shadow: CGFloat) {
    let ball = square(around: center, radius: radius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -shadow / 2), blur: shadow,
                  color: NSColor.black.withAlphaComponent(0.5).cgColor)
    ctx.addEllipse(in: ball)
    ctx.setFillColor(NSColor(white: 0.6, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: ball)
    ctx.clip()
    let shine = gradient([NSColor(white: 0.98, alpha: 1), NSColor(white: 0.7, alpha: 1),
                          NSColor(white: 0.38, alpha: 1)],
                         at: [0, 0.5, 1])
    ctx.drawRadialGradient(shine, startCenter: CGPoint(x: center.x - radius * 0.35, y: center.y + radius * 0.4),
                           startRadius: 0, endCenter: center, endRadius: radius * 1.1, options: [])
    ctx.restoreGState()
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let png = render(size * scale).representation(using: .png, properties: [:])!
        do {
            try png.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
        } catch {
            fatalError("could not write \(out)/\(name): \(error)")
        }
    }
}
