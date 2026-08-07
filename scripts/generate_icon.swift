import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first ?? "Assets/AppIcon-master.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 212, yRadius: 212)
NSColor(calibratedRed: 0.965, green: 0.945, blue: 0.89, alpha: 1).setFill()
background.fill()

let sheet = NSBezierPath(roundedRect: NSRect(x: 218, y: 180, width: 588, height: 664), xRadius: 54, yRadius: 54)
NSColor(calibratedRed: 0.995, green: 0.987, blue: 0.956, alpha: 1).setFill()
sheet.fill()

let accent = NSColor(calibratedRed: 0.66, green: 0.36, blue: 0.075, alpha: 1)
accent.setStroke()
let fold = NSBezierPath()
fold.lineWidth = 24
fold.lineCapStyle = .round
fold.move(to: NSPoint(x: 278, y: 688))
fold.line(to: NSPoint(x: 512, y: 506))
fold.line(to: NSPoint(x: 746, y: 688))
fold.stroke()

let lineColor = NSColor(calibratedRed: 0.19, green: 0.23, blue: 0.2, alpha: 0.78)
lineColor.setStroke()
for (y, width) in [(426.0, 350.0), (354.0, 420.0), (282.0, 288.0)] {
    let line = NSBezierPath()
    line.lineWidth = 18
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: 302, y: y))
    line.line(to: NSPoint(x: 302 + width, y: y))
    line.stroke()
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render app icon")
}
try FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: URL(fileURLWithPath: output))
