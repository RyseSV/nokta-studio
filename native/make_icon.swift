import AppKit

let srcPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let canvasSize: CGFloat = 1024
// Leave ~9% margin on each side so the mark isn't flush with the edges,
// matching how the brand logo is normally given breathing room.
let contentInset: CGFloat = canvasSize * 0.09

guard let srcImage = NSImage(contentsOfFile: srcPath) else {
    fatalError("Could not load \(srcPath)")
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvasSize), pixelsHigh: Int(canvasSize),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// Nokta cream (#F0ECE4) — same tone as the web panel's light text color,
// used here as the icon's background so the black enso mark + ember dot
// read clearly against it on any home screen.
let cream = NSColor(calibratedRed: 0xF0/255.0, green: 0xEC/255.0, blue: 0xE4/255.0, alpha: 1)
cream.setFill()
NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

let drawSize = canvasSize - contentInset * 2
let drawRect = NSRect(x: contentInset, y: contentInset, width: drawSize, height: drawSize)
srcImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

let pngData = rep.representation(using: .png, properties: [:])!
try! pngData.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
