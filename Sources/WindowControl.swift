import AppKit
import ApplicationServices

private func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
}
private func element(_ object: CFTypeRef?) -> AXUIElement? {
    guard let object, CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
    return (object as! AXUIElement)
}
private func unpack<T>(_ item: CFTypeRef?, _ type: AXValueType, into result: inout T) -> Bool {
    guard let item, CFGetTypeID(item) == AXValueGetTypeID() else { return false }
    return withUnsafeMutablePointer(to: &result) { AXValueGetValue(item as! AXValue, type, $0) }
}
struct MinimizedWindow {
    let ref: AXUIElement
    let pid: pid_t
    func restore() -> RestoreAttempt {
        guard let app = NSRunningApplication(processIdentifier:pid), !app.isTerminated else { return .stale }
        var minimized: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(ref, kAXMinimizedAttribute as CFString, &minimized)
        if status == .invalidUIElement { return .stale }
        guard status == .success, let hidden = minimized as? Bool else { return .failed }
        guard hidden else { return .stale } // The user already restored it elsewhere.
        guard AXUIElementSetAttributeValue(ref, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { return .failed }
        _ = app.activate(options: [])
        _ = AXUIElementPerformAction(ref, kAXRaiseAction as CFString)
        return .restored
    }
}

struct ManagedWindow {
    let ref: AXUIElement
    let resizable: Bool
    init?(_ item: AXUIElement?) {
        guard let item, value(item, kAXRoleAttribute) as? String == kAXWindowRole,
              value(item, "AXFullScreen") as? Bool != true else { return nil }
        var writable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(item, kAXPositionAttribute as CFString, &writable) == .success, writable.boolValue else { return nil }
        resizable = AXUIElementIsAttributeSettable(item, kAXSizeAttribute as CFString, &writable) == .success && writable.boolValue
        self.ref = item
    }
    static func at(_ point: CGPoint) -> ManagedWindow? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        return ManagedWindow(element(value(hit, kAXWindowAttribute)) ?? hit)
    }
    private static func focusedElement(pid: pid_t) -> AXUIElement? {
        element(value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute))
    }
    static func focused(pid: pid_t) -> ManagedWindow? {
        ManagedWindow(focusedElement(pid: pid))
    }
    static func minimizeFocused(pid: pid_t) -> MinimizedWindow? {
        // Minimizing a fixed-size window does not require a writable position or size.
        guard let window = focusedElement(pid: pid), value(window, "AXFullScreen") as? Bool != true,
              AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else { return nil }
        return MinimizedWindow(ref:window, pid:pid)
    }
    var frame: CGRect? {
        var p = CGPoint.zero, s = CGSize.zero
        guard unpack(value(ref, kAXPositionAttribute), .cgPoint, into: &p), unpack(value(ref, kAXSizeAttribute), .cgSize, into: &s) else { return nil }
        return CGRect(origin:p, size:s)
    }
    private func move(to origin: CGPoint) -> Bool {
        var p = origin
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(ref, kAXPositionAttribute as CFString, value) == .success
    }
    private func resize(to requested: CGSize) -> Bool {
        var s = requested
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(ref, kAXSizeAttribute as CFString, value) == .success
    }
    func place(_ frame: CGRect, layout: Layout, display: CGRect, current: CGRect? = nil) -> Bool {
        guard let before = current ?? self.frame else { return false }
        if nearFrame(before,frame) { return true }
        var pid: pid_t = 0
        guard AXUIElementGetPid(ref, &pid) == .success else { return false }
        let app = AXUIElementCreateApplication(pid)
        let attribute = "AXEnhancedUserInterface"
        return instantWrite(enhanced:value(app,attribute) as? Bool, setEnhanced:{ enabled in
            AXUIElementSetAttributeValue(app, attribute as CFString, enabled ? kCFBooleanTrue : kCFBooleanFalse) == .success
        }) {
            placeImmediately(frame, layout:layout, display:display, before:before)
        }
    }
    private func placeImmediately(_ frame: CGRect, layout: Layout, display: CGRect, before: CGRect) -> Bool {
        if layout == .fill {
            return fillOrCenter(in: frame, resizable: resizable, read: { self.frame }, move: move(to:), resize: { _ = self.resize(to: $0) })
        }
        guard resizable else { return false }
        let crossing = !display.contains(CGPoint(x:before.midX, y:before.midY))
        guard placeHalf(from: before, to: frame, crossDisplay: crossing, move: move(to:), resize: resize(to:)) else { return false }
        return correctHalf(frame,layout:layout,read:{ self.frame },move:move(to:),resize:resize(to:))
    }
}
