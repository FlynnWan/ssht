import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32), ("icon_32x32@2x",64), ("icon_128x128",128), ("icon_128x128@2x",256), ("icon_256x256",256), ("icon_256x256@2x",512), ("icon_512x512",512), ("icon_512x512@2x",1024)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 206, yRadius: 206)
    NSGradient(starting: NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.70, alpha: 1), ending: NSColor(calibratedRed: 0.02, green: 0.34, blue: 0.45, alpha: 1))!.draw(in: background, angle: -70)
    NSColor.white.setStroke()
    let arrows = NSBezierPath(); arrows.lineWidth = 65; arrows.lineCapStyle = .round; arrows.lineJoinStyle = .round
    arrows.move(to: NSPoint(x: 280,y: 630)); arrows.line(to: NSPoint(x: 744,y: 630))
    arrows.move(to: NSPoint(x: 630,y: 740)); arrows.line(to: NSPoint(x: 744,y: 630)); arrows.line(to: NSPoint(x: 630,y: 520))
    arrows.move(to: NSPoint(x: 744,y: 394)); arrows.line(to: NSPoint(x: 280,y: 394))
    arrows.move(to: NSPoint(x: 394,y: 504)); arrows.line(to: NSPoint(x: 280,y: 394)); arrows.line(to: NSPoint(x: 394,y: 284)); arrows.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}
