import AppKit
// Render an SVG into a transparent 1024px canvas, inset to the macOS icon grid (824px content).
let args = CommandLine.arguments
guard let img = NSImage(contentsOfFile: args[1]) else { fatalError("cannot load svg") }
let size = 1024, content = 824.0, inset = (Double(size) - content) / 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: inset, y: inset, width: content, height: content))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
