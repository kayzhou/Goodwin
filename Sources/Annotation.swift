import AppKit

final class InkStroke {
    let arrow: Bool, start: CGPoint
    private(set) var end: CGPoint
    static let color = NSColor(srgbRed: 235/255, green: 67/255, blue: 106/255, alpha: 1) // #EB436A
    let path = NSBezierPath()
    init(_ p: CGPoint, arrow: Bool) {
        self.arrow = arrow; start = p; end = p
        path.lineWidth = 3; path.lineJoinStyle = .round; path.lineCapStyle = .round; path.move(to:p)
    }
    func append(_ p: CGPoint) {
        guard end != p else { return }
        let prev = end; end = p
        if arrow {
            path.removeAllPoints(); path.move(to:start); path.line(to:p); return
        }
        // Commit a curve to the midpoint; the short live tail below always reaches the cursor.
        let anchor = path.currentPoint
        let mid = CGPoint(x:(prev.x+p.x)/2, y:(prev.y+p.y)/2)
        let u = CGPoint(x:prev.x-anchor.x,y:prev.y-anchor.y), v = CGPoint(x:p.x-prev.x,y:p.y-prev.y)
        if u.x*v.x + u.y*v.y <= 0.12*hypot(u.x,u.y)*hypot(v.x,v.y) {
            path.line(to:prev); path.line(to:mid) // Preserve deliberate corners.
        } else {
            path.curve(to:mid,controlPoint1:CGPoint(x:anchor.x+u.x*2/3,y:anchor.y+u.y*2/3),
                       controlPoint2:CGPoint(x:mid.x-v.x/3,y:mid.y-v.y/3))
        }
    }
    var paintedBounds: CGRect {
        path.bounds.union(CGRect(origin:end,size:.zero)).insetBy(dx:-16,dy:-16)
    }
    func draw() {
        Self.color.set()
        let dx = end.x-start.x, dy = end.y-start.y, length = hypot(dx,dy)
        if path.elementCount == 1 || (arrow && length < 1) {
            NSBezierPath(ovalIn:NSRect(x:start.x-1.5,y:start.y-1.5,width:3,height:3)).fill(); return
        }
        if !arrow {
            path.stroke()
            let tip = NSBezierPath(); tip.move(to:path.currentPoint); tip.line(to:end)
            tip.lineWidth = path.lineWidth; tip.lineCapStyle = .round; tip.stroke(); return
        }
        let x = dx/length, y = dy/length, h = min(16,length*0.47), wing = h*0.39
        let radius = min(1.55, wing*0.50)
        func pt(_ along:CGFloat, _ across:CGFloat) -> CGPoint {
            CGPoint(x:start.x+along*x-across*y,y:start.y+along*y+across*x)
        }
        let shape = NSBezierPath(), neck = length-h*0.78
        shape.move(to:end); shape.line(to:pt(length-h,wing)); shape.line(to:pt(neck,radius)); shape.line(to:pt(radius,radius))
        shape.curve(to:pt(radius,-radius),controlPoint1:pt(-radius/3,radius),controlPoint2:pt(-radius/3,-radius))
        shape.line(to:pt(neck,-radius)); shape.line(to:pt(length-h,-wing)); shape.close(); shape.fill()
    }
}

final class InkSession {
    enum Mode { case off, editing, pinned }
    private(set) var mode = Mode.off, strokes = [InkStroke](), draft: InkStroke?
    func edit() { mode = .editing }
    func begin(at p: CGPoint, arrow: Bool) { if mode == .editing { draft = InkStroke(p,arrow:arrow) } }
    func extend(to p: CGPoint) { draft?.append(p) }
    func finish(at p: CGPoint) { if let draft { draft.append(p); strokes.append(draft); self.draft = nil } }
    func undo() { guard mode == .editing else { return }; if draft != nil { draft = nil } else { _ = strokes.popLast() } }
    func pin() { if let p = draft?.end { finish(at:p) }; mode = strokes.isEmpty ? .off : .pinned }
    func clear() { mode = .off; strokes.removeAll(); draft = nil }
}

private final class InkPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}
private final class InkView: NSView {
    let ink: InkSession
    var onPin: (() -> Void)?, onClear: (() -> Void)?
    init(_ ink: InkSession) { self.ink = ink; super.init(frame:.zero) }
    required init?(coder:NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    private var shift = false
    private var toolCursor: NSCursor { (ink.draft?.arrow ?? shift) ? FountainPenCursor.arrowPen : FountainPenCursor.pen }
    override func resetCursorRects() { super.resetCursorRects(); if ink.mode == .editing { addCursorRect(bounds,cursor:toolCursor) } }
    func refreshCursor(shift:Bool) {
        self.shift = shift; window?.invalidateCursorRects(for:self)
        guard ink.mode == .editing, let window, NSWindow.windowNumber(at:NSEvent.mouseLocation,belowWindowWithWindowNumber:0) == window.windowNumber else { return }
        toolCursor.set()
    }
    override func flagsChanged(with event:NSEvent) { refreshCursor(shift:event.modifierFlags.contains(.shift)) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using:.copy)
        // Non-zero alpha lets transparent areas receive the first stroke; pinned mode
        // explicitly passes *all* input through, including clicks on the red ink.
        if ink.mode == .editing { NSColor.black.withAlphaComponent(0.01).setFill(); dirtyRect.fill() }
        for stroke in ink.strokes where stroke.paintedBounds.intersects(dirtyRect) { stroke.draw() }
        ink.draft?.draw()
    }
    private func p(_ e:NSEvent) -> CGPoint { convert(e.locationInWindow,from:nil) }
    override func mouseDown(with e:NSEvent) { ink.begin(at:p(e),arrow:e.modifierFlags.contains(.shift)); needsDisplay = true }
    override func mouseDragged(with e:NSEvent) {
        guard let stroke = ink.draft else { return }; let old = stroke.end, next = p(e)
        func box(_ a:CGPoint, _ b:CGPoint) -> CGRect { CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)).insetBy(dx:-16,dy:-16) }
        let dirty = stroke.arrow ? box(stroke.start,old).union(box(stroke.start,next)) : box(old,next).union(box(stroke.path.currentPoint,old))
        ink.extend(to:next); setNeedsDisplay(dirty)
    }
    override func mouseUp(with e:NSEvent) { ink.finish(at:p(e)); refreshCursor(shift:e.modifierFlags.contains(.shift)); needsDisplay = true }
    private func undoKey(_ e:NSEvent) -> Bool {
        guard ink.mode == .editing, e.modifierFlags.intersection([.command,.shift,.option,.control]) == [.command], e.charactersIgnoringModifiers?.lowercased() == "z" else { return false }
        ink.undo(); needsDisplay = true; return true
    }
    override func performKeyEquivalent(with e:NSEvent) -> Bool { undoKey(e) || super.performKeyEquivalent(with:e) }
    override func keyDown(with e:NSEvent) {
        guard !undoKey(e) else { return }
        switch e.keyCode { case 53: onClear?(); case 36,76: onPin?(); default: break }
    }
}

final class AnnotationController {
    let ink = InkSession()
    private var panel: InkPanel?, view: InkView?
    func edit(on screen:NSScreen) {
        if panel == nil {
            let w = InkPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            w.title = "Goodwin 屏幕标注"; w.isReleasedWhenClosed = false; w.hidesOnDeactivate = false
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.animationBehavior = .none
            w.level = NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1)
            w.collectionBehavior = [.fullScreenAuxiliary,.moveToActiveSpace,.ignoresCycle]
            let v = InkView(ink); v.onPin = { [weak self] in self?.pin() }; v.onClear = { [weak self] in self?.clear() }
            w.contentView = v; panel = w; view = v
        }
        guard let panel, let view else { return }
        ink.edit(); panel.ignoresMouseEvents = false; panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view)
        view.refreshCursor(shift:NSEvent.modifierFlags.contains(.shift)); view.needsDisplay = true
    }
    func pin() {
        ink.pin(); guard ink.mode == .pinned, let panel, let view else { clear(); return }
        panel.orderOut(nil); panel.ignoresMouseEvents = true; panel.orderFrontRegardless()
        panel.invalidateCursorRects(for:view); view.needsDisplay = true
    }
    func clear() { ink.clear(); panel?.orderOut(nil); panel?.close(); panel = nil; view = nil }
}
