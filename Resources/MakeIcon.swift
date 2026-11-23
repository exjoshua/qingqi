import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for dimension in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = dimension * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let square = NSBezierPath(roundedRect: NSRect(x: 92, y: 92, width: 840, height: 840),
                                  xRadius: 192, yRadius: 192)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.22, green: 0.45, blue: 0.34, alpha: 1),
                                  ending: NSColor(srgbRed: 0.07, green: 0.21, blue: 0.17, alpha: 1))!
        gradient.draw(in: square, angle: -55)
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 313, y: 665))
        arrow.line(to: NSPoint(x: 475, y: 507))
        arrow.line(to: NSPoint(x: 313, y: 349))
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.lineWidth = 79
        NSColor(srgbRed: 0.83, green: 0.98, blue: 0.80, alpha: 1).setStroke()
        arrow.stroke()
        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: 528, y: 349))
        cursor.line(to: NSPoint(x: 688, y: 349))
        cursor.lineWidth = 76
        cursor.lineCapStyle = .round
        NSColor(srgbRed: 0.62, green: 0.84, blue: 0.65, alpha: 1).setStroke()
        cursor.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(dimension)x\(dimension)\(suffix).png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
