import AppKit
import Foundation

let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterURL = projectURL.appendingPathComponent("Artwork/liddddd-appicon.png")
let outputURL = projectURL.appendingPathComponent("Resources/Liddddd.icns")

let masterPixels = 1024
let backgroundColor = NSColor(
  srgbRed: 23.0 / 255.0,
  green: 11.0 / 255.0,
  blue: 46.0 / 255.0,
  alpha: 1
)
let dotColor = NSColor(
  srgbRed: 250.0 / 255.0,
  green: 248.0 / 255.0,
  blue: 255.0 / 255.0,
  alpha: 1
)

let representations: [(type: String, pixels: Int)] = [
  ("icp4", 16),
  ("icp5", 32),
  ("icp6", 64),
  ("ic07", 128),
  ("ic08", 256),
  ("ic09", 512),
  ("ic10", 1024),
]

func makeBitmap(pixels: Int, hasAlpha: Bool) throws -> NSBitmapImageRep {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels,
      pixelsHigh: pixels,
      bitsPerSample: 8,
      samplesPerPixel: hasAlpha ? 4 : 3,
      hasAlpha: hasAlpha,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  else {
    throw CocoaError(.fileWriteUnknown)
  }
  return bitmap
}

func pentagonVertices(in rect: NSRect) -> [NSPoint] {
  let center = NSPoint(
    x: rect.midX,
    y: rect.minY + rect.height * (510.0 / 1024.0)
  )
  let circumradius = rect.width * (292.0 / 1024.0)

  return (0..<5).map { index in
    let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * CGFloat.pi / 5
    return NSPoint(
      x: center.x + cos(angle) * circumradius,
      y: center.y + sin(angle) * circumradius
    )
  }
}

func drawLogo(in rect: NSRect) {
  backgroundColor.setFill()
  rect.fill()

  let dotRadius = rect.width * (76.0 / 1024.0)
  dotColor.setFill()
  for center in pentagonVertices(in: rect) {
    NSBezierPath(
      ovalIn: NSRect(
        x: center.x - dotRadius,
        y: center.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
      )
    ).fill()
  }
}

func masterPNGData() throws -> Data {
  let bitmap = try makeBitmap(pixels: masterPixels, hasAlpha: true)
  guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw CocoaError(.fileWriteUnknown)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  drawLogo(in: NSRect(x: 0, y: 0, width: masterPixels, height: masterPixels))
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  return png
}

func iconPNGData(pixels: Int) throws -> Data {
  let bitmap = try makeBitmap(pixels: pixels, hasAlpha: true)
  guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw CocoaError(.fileWriteUnknown)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context

  let side = CGFloat(pixels)
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: side, height: side).fill()

  let inset = side * 0.04
  let iconRect = NSRect(
    x: inset,
    y: inset,
    width: side - 2 * inset,
    height: side - 2 * inset
  )
  NSBezierPath(
    roundedRect: iconRect,
    xRadius: side * 0.21,
    yRadius: side * 0.21
  ).addClip()
  drawLogo(in: iconRect)

  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  return png
}

func bigEndianData(_ value: Int) -> Data {
  var integer = UInt32(value).bigEndian
  return withUnsafeBytes(of: &integer) { Data($0) }
}

try masterPNGData().write(to: masterURL)

var entries = Data()
for representation in representations {
  let png = try iconPNGData(pixels: representation.pixels)
  entries.append(representation.type.data(using: .ascii)!)
  entries.append(bigEndianData(png.count + 8))
  entries.append(png)
}

var icon = Data("icns".utf8)
icon.append(bigEndianData(entries.count + 8))
icon.append(entries)
try icon.write(to: outputURL)
