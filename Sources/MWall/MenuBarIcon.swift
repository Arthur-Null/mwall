import AppKit

/// Flat monochrome status-bar glyph: a framed landscape above three palette dots,
/// echoing the app icon. Drawn as a template image so macOS tints it for the menu bar.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let frame = NSBezierPath(
                roundedRect: NSRect(x: 1.75, y: 1.75, width: 14.5, height: 10.5),
                xRadius: 2.5, yRadius: 2.5)
            frame.lineWidth = 1.25
            frame.stroke()

            NSBezierPath(ovalIn: NSRect(x: 10.5, y: 3.9, width: 3, height: 3)).fill()

            NSGraphicsContext.saveGraphicsState()
            frame.addClip()
            let mountains = NSBezierPath()
            mountains.move(to: NSPoint(x: 1.75, y: 10.5))
            mountains.line(to: NSPoint(x: 6.5, y: 5.75))
            mountains.line(to: NSPoint(x: 9.75, y: 9))
            mountains.line(to: NSPoint(x: 11.5, y: 7.5))
            mountains.line(to: NSPoint(x: 16.25, y: 11.25))
            mountains.line(to: NSPoint(x: 16.25, y: 12.25))
            mountains.line(to: NSPoint(x: 1.75, y: 12.25))
            mountains.close()
            mountains.fill()
            NSGraphicsContext.restoreGraphicsState()

            for x in [3.5, 7.75, 12.0] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 13.75, width: 2.5, height: 2.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MWall"
        return image
    }
}
