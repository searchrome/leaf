import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
NSColor(calibratedRed: 0.965, green: 0.96, blue: 0.92, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 200, yRadius: 200).fill()
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 281, y: 287))
leaf.curve(to: NSPoint(x: 769, y: 779), controlPoint1: NSPoint(x: 212, y: 589), controlPoint2: NSPoint(x: 466, y: 775))
leaf.curve(to: NSPoint(x: 281, y: 287), controlPoint1: NSPoint(x: 791, y: 465), controlPoint2: NSPoint(x: 585, y: 223))
NSColor(calibratedRed: 0.22, green: 0.37, blue: 0.29, alpha: 1).setFill()
leaf.fill()
let vein = NSBezierPath()
vein.move(to: NSPoint(x: 255, y: 240))
vein.curve(to: NSPoint(x: 676, y: 687), controlPoint1: NSPoint(x: 391, y: 398), controlPoint2: NSPoint(x: 535, y: 554))
vein.lineWidth = 25
vein.lineCapStyle = .round
NSColor(calibratedRed: 0.76, green: 0.81, blue: 0.59, alpha: 1).setStroke()
vein.stroke()
NSGraphicsContext.restoreGraphicsState()
try representation.representation(using: .png, properties: [:])!.write(to: output)
