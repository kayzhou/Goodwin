import Foundation
import CoreGraphics

enum Layout { case left, right, fill
    func rect(in area: CGRect) -> CGRect {
        let split = floor(area.width / 2)
        switch self {
        case .left: return CGRect(origin: area.origin, size: CGSize(width: split, height: area.height))
        case .right: return CGRect(x: area.minX + split, y: area.minY, width: area.width - split, height: area.height)
        case .fill: return area
        }
    }
}
func edge(at point: CGPoint, in screen: CGRect) -> Layout? {
    guard point.x >= screen.minX, point.x < screen.maxX, point.y >= screen.minY, point.y <= screen.maxY else { return nil }
    if screen.maxY - point.y <= 12 { return .fill }
    if point.x - screen.minX <= 12 { return .left }
    if screen.maxX - point.x <= 12 { return .right }
    return nil
}
// AX uses a top-left origin on the primary display; AppKit uses bottom-left.
func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}
func moved(_ before: CGRect, _ after: CGRect) -> Bool {
    abs(before.width - after.width) < 2 && abs(before.height - after.height) < 2 &&
    max(abs(before.minX - after.minX), abs(before.minY - after.minY)) >= 3
}

func centeredOrigin(for size: CGSize, in area: CGRect) -> CGPoint {
    CGPoint(x: area.minX + floor((area.width - size.width) / 2),
            y: area.minY + floor((area.height - size.height) / 2))
}

// Work in AX coordinates. A successful AX size write can still be clamped by the app.
func fillOrCenter(in area: CGRect, resizable: Bool, read: () -> CGRect?,
                  move: (CGPoint) -> Bool, resize: (CGSize) -> Void) -> Bool {
    if resizable {
        // Place on the destination display before asking for its usable size.
        _ = move(area.origin)
        resize(area.size)
    }
    guard let actual = read(), actual.width > 0, actual.height > 0 else { return false }
    let origin = centeredOrigin(for: actual.size, in: area)
    return actual.origin == origin || move(origin)
}

// Same display: shrink before moving to the right edge. Across displays, request
// the new size on the destination, not on a potentially smaller source display.
func placeHalf(from current: CGRect, to target: CGRect, crossDisplay: Bool,
               move: (CGPoint) -> Bool, resize: (CGSize) -> Bool) -> Bool {
    func position() -> Bool { current.origin == target.origin || move(target.origin) }
    func size() -> Bool { current.size == target.size || resize(target.size) }
    return crossDisplay ? position() && size() : size() && position()
}

// AX may report success while clipping a resize to the space at its *old*
// origin. At the destination re-read the actual geometry, not the requested one.
func correctHalf(_ target: CGRect, layout: Layout, read: () -> CGRect?,
                 move: (CGPoint) -> Bool, resize: (CGSize) -> Bool) -> Bool {
    guard var actual = read() else { return false }
    if abs(actual.width-target.width) > 1 || abs(actual.height-target.height) > 1 {
        guard resize(target.size), let reread = read() else { return false }; actual = reread
    }
    // Honor a target app's own size constraints without pushing its right edge offscreen.
    let x = layout == .right ? target.maxX - actual.width : target.minX
    let p = CGPoint(x:x, y:target.minY)
    return (abs(actual.minX-p.x) <= 1 && abs(actual.minY-p.y) <= 1) || move(p)
}
func nearFrame(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX-b.minX) <= 1 && abs(a.minY-b.minY) <= 1 && abs(a.width-b.width) <= 1 && abs(a.height-b.height) <= 1
}

// Scope the target application's optional enhanced-UI mode to the AX write;
// never alter its original state when it was off, absent, or read-only.
func instantWrite<T>(enhanced: Bool?, setEnhanced: (Bool) -> Bool, perform: () -> T) -> T {
    let changed = enhanced == true && setEnhanced(false)
    defer { if changed { _ = setEnhanced(true) } }
    return perform()
}
