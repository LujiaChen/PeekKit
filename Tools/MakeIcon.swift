import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 195, yRadius: 195)
        NSGradient(starting: NSColor(srgbRed: 0.28, green: 0.49, blue: 0.93, alpha: 1), ending: NSColor(srgbRed: 0.36, green: 0.28, blue: 0.73, alpha: 1))!.draw(in: tile, angle: -75)
        NSColor.white.withAlphaComponent(0.97).setFill()
        NSBezierPath(roundedRect: NSRect(x: 210, y: 280, width: 604, height: 430), xRadius: 62, yRadius: 62).fill()
        NSBezierPath(roundedRect: NSRect(x: 210, y: 635, width: 265, height: 112), xRadius: 36, yRadius: 36).fill()
        let eye = NSBezierPath()
        eye.move(to: NSPoint(x: 322, y: 491))
        eye.curve(to: NSPoint(x: 702, y: 491), controlPoint1: NSPoint(x: 438, y: 659), controlPoint2: NSPoint(x: 586, y: 659))
        eye.curve(to: NSPoint(x: 322, y: 491), controlPoint1: NSPoint(x: 586, y: 323), controlPoint2: NSPoint(x: 438, y: 323))
        NSColor(srgbRed: 0.28, green: 0.38, blue: 0.75, alpha: 1).setFill(); eye.fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 456, y: 435, width: 112, height: 112)).fill()
        NSColor(srgbRed: 0.28, green: 0.38, blue: 0.75, alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 485, y: 464, width: 54, height: 54)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
    }
}
