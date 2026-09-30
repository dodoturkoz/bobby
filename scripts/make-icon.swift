import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
        let side = CGFloat(size)
        let square = NSRect(x: side * 0.06, y: side * 0.06, width: side * 0.88, height: side * 0.88)
        let shape = NSBezierPath(roundedRect: square, xRadius: side * 0.21, yRadius: side * 0.21)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.49, blue: 0.47, alpha: 1),
                                  ending: NSColor(calibratedRed: 0.06, green: 0.26, blue: 0.25, alpha: 1))!
        gradient.draw(in: shape, angle: -90)
        let descriptor = NSFont.systemFont(ofSize: side * 0.76, weight: .medium).fontDescriptor.withDesign(.rounded)!
        let font = NSFont(descriptor: descriptor, size: side * 0.76)!
        let attributes: [NSAttributedString.Key: Any] = [.font: font,
                                                       .foregroundColor: NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.87, alpha: 1)]
        let letter = "b" as NSString
        let measured = letter.size(withAttributes: attributes)
        letter.draw(at: NSPoint(x: (side - measured.width) / 2, y: side * 0.1), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
    }
}
