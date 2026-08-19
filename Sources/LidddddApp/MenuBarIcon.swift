import AppKit
import LidddddCore

enum MenuBarIconState {
  case off
  case on
  case attention
}

enum MenuBarIcon {
  static func image(for state: MenuBarIconState) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { _ in
      let centers = pentagonCenters()
      let dotRadius: CGFloat = 1.45

      NSColor.labelColor.setFill()
      NSColor.labelColor.setStroke()

      for (index, center) in centers.enumerated() {
        let dot = NSBezierPath(
          ovalIn: NSRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
          )
        )

        switch state {
        case .off:
          dot.lineWidth = 1
          dot.stroke()
        case .on:
          dot.fill()
        case .attention:
          if index == 0 {
            dot.lineWidth = 1
            dot.stroke()
          } else {
            dot.fill()
          }
        }
      }

      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = LidddddConstants.productName
    return image
  }

  private static func pentagonCenters() -> [NSPoint] {
    let center = NSPoint(x: 9, y: 9.2)
    let circumradius: CGFloat = 5.4

    return (0..<5).map { index in
      let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * CGFloat.pi / 5
      return NSPoint(
        x: center.x + cos(angle) * circumradius,
        y: center.y + sin(angle) * circumradius
      )
    }
  }
}
