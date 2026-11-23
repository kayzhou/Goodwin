import AppKit

// Reuse Finder's multi-resolution artwork, without the menu bar's template tint.
func windowGlyph() -> NSImage? {
    guard let url = Bundle.main.url(forResource: "Goodwin", withExtension: "icns"),
          let image = NSImage(contentsOf: url) else {
        return NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Goodwin 窗口布局")
    }
    // Finder artwork includes generous transparent margins. Sample the window
    // silhouette in original 1254-point artwork coordinates for the status item only.
    image.size = NSSize(width: 1254, height: 1254)
    let crop = NSRect(x: 129, y: 180, width: 998, height: 897)
    let height = min(22, NSStatusBar.system.thickness - 2)
    let size = NSSize(width: (height * crop.width / crop.height).rounded(), height: height)
    let glyph = NSImage(size: size, flipped: false) { bounds in
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: bounds, from: crop, operation: .sourceOver, fraction: 1)
        return true
    }
    glyph.isTemplate = false
    glyph.accessibilityDescription = "Goodwin 窗口布局"
    return glyph
}

final class SnapOutline: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        // Paired hairlines stay legible over both light and dark window contents.
        for (inset, color) in [(0.5, NSColor.black.withAlphaComponent(0.65)), (1.5, NSColor.white.withAlphaComponent(0.9))] {
            color.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx:inset, dy:inset)); path.lineWidth = 1; path.stroke()
        }
    }
}
