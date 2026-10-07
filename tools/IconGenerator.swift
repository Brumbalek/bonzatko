// Draws the Bonzátko app icon (wheel of fortune with a pointer) and writes PNGs.
// Usage: swift tools/IconGenerator.swift <output-folder> [preview]
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// All coordinates below are in a 1024 × 1024 canvas with the origin at the top left.
func drawIcon(in context: CGContext) {
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)

    // Background: macOS icon grid (824 pt tile, 100 pt margin), deep blue gradient.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.35))
    context.addPath(tilePath)
    context.setFillColor(color(0x18304F))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(colorsSpace: nil, colors: [color(0x24497A), color(0x0E1C30)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Soft light behind the wheel.
    let glow = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 548), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 548), endRadius: 440, options: [])
    context.restoreGState()

    // Wheel.
    let center = CGPoint(x: 512, y: 548)
    let rimRadius: CGFloat = 318
    let wheelRadius: CGFloat = 286
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x000000, 0.45))
    context.addEllipse(in: CGRect(x: center.x - rimRadius, y: center.y - rimRadius, width: rimRadius * 2, height: rimRadius * 2))
    context.setFillColor(color(0xE9B949))
    context.fillPath()
    context.restoreGState()
    context.addEllipse(in: CGRect(x: center.x - rimRadius + 8, y: center.y - rimRadius + 8, width: (rimRadius - 8) * 2, height: (rimRadius - 8) * 2))
    context.setStrokeColor(color(0xF7D77A))
    context.setLineWidth(6)
    context.strokePath()

    let segmentColors: [UInt32] = [0x2F7FE0, 0xF4F1E8, 0xE5534B, 0xF4F1E8, 0x2FA88A, 0xF4F1E8, 0xF2A93B, 0xF4F1E8]
    let count = segmentColors.count * 2
    for index in 0..<count {
        let start = CGFloat(index) / CGFloat(count) * 2 * .pi - .pi / 2
        let end = CGFloat(index + 1) / CGFloat(count) * 2 * .pi - .pi / 2
        context.move(to: center)
        context.addArc(center: center, radius: wheelRadius, startAngle: start, endAngle: end, clockwise: false)
        context.closePath()
        context.setFillColor(color(segmentColors[index % segmentColors.count]))
        context.fillPath()
    }
    // Thin separators and pegs on the rim.
    for index in 0..<count {
        let angle = CGFloat(index) / CGFloat(count) * 2 * .pi - .pi / 2
        context.move(to: center)
        context.addLine(to: CGPoint(x: center.x + cos(angle) * wheelRadius, y: center.y + sin(angle) * wheelRadius))
        context.setStrokeColor(color(0x0E1C30, 0.25))
        context.setLineWidth(3)
        context.strokePath()
        let peg = CGPoint(x: center.x + cos(angle) * (wheelRadius + 15), y: center.y + sin(angle) * (wheelRadius + 15))
        context.addEllipse(in: CGRect(x: peg.x - 8, y: peg.y - 8, width: 16, height: 16))
        context.setFillColor(color(0xFFF4D0))
        context.fillPath()
    }
    // Hub.
    context.addEllipse(in: CGRect(x: center.x - 58, y: center.y - 58, width: 116, height: 116))
    context.setFillColor(color(0xE9B949))
    context.fillPath()
    context.addEllipse(in: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52))
    context.setFillColor(color(0x18304F))
    context.fillPath()

    drawPointer(in: context, tip: CGPoint(x: 512, y: center.y - wheelRadius + 34))
}

/// The pointer at the top that marks the winning segment.
func drawPointer(in context: CGContext, tip: CGPoint) {
    let pointer = CGMutablePath()
    pointer.move(to: tip)
    pointer.addLine(to: CGPoint(x: tip.x - 58, y: tip.y - 118))
    pointer.addQuadCurve(to: CGPoint(x: tip.x + 58, y: tip.y - 118), control: CGPoint(x: tip.x, y: tip.y - 150))
    pointer.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 8), blur: 14, color: color(0x000000, 0.4))
    context.addPath(pointer)
    context.setFillColor(color(0xE5534B))
    context.fillPath()
    context.restoreGState()
    context.addPath(pointer)
    context.setStrokeColor(color(0xFFF4D0))
    context.setLineWidth(8)
    context.setLineJoin(.round)
    context.strokePath()
    // Pin holding the pointer.
    let pin = CGPoint(x: tip.x, y: tip.y - 98)
    context.addEllipse(in: CGRect(x: pin.x - 16, y: pin.y - 16, width: 32, height: 32))
    context.setFillColor(color(0xE9B949))
    context.fillPath()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "preview" {
    // One image: large icon plus Dock-like and Finder-like small sizes on light and dark backgrounds.
    let width = 1500, height = 1100
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    NSColor(white: 0.94, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSColor(white: 0.13, alpha: 1).setFill()
    NSRect(x: 1050, y: 0, width: 450, height: height).fill()
    func place(_ size: Int, x: Int, y: Int) {
        let image = NSImage(data: render(size: size))!
        image.draw(in: NSRect(x: x, y: y, width: size, height: size))
    }
    place(1024, x: 13, y: 38)
    // Light and dark backgrounds, sizes as in the Dock and Finder.
    for (index, size) in [256, 128, 64, 32].enumerated() {
        let y = [790, 600, 470, 400][index]
        place(size, x: 1275 - size / 2, y: y)
    }
    graphics.flushGraphics()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appending(path: "icon-preview.png"))
} else {
    // Full macOS set for Assets.xcassets/AppIcon.appiconset.
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            try render(size: base * scale).write(to: output.appending(path: name))
        }
    }
}
