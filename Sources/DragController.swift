import AppKit

protocol DragWindow {
    var resizable: Bool { get }
    var frame: CGRect? { get }
    func snap(to frame: CGRect, layout: Layout, display: CGRect) -> Bool
}
extension ManagedWindow: DragWindow {
    func snap(to frame: CGRect, layout: Layout, display: CGRect) -> Bool {
        place(frame, layout:layout, display:display)
    }
}

// Event handling and the preview stay on the main thread. The serial worker only
// reads accessibility attributes; it never moves a window on its own.
final class DragController {
    private struct Target: Equatable {
        let side: Layout, rect: CGRect, axDisplay: CGRect
    }
    private final class Gesture {
        let height: CGFloat, screens: [(bounds: CGRect, visible: CGRect)]
        var window: DragWindow?, initial = CGRect.zero, target: Target?
        var confirmed = false, reading = false, released = false, dragged = false
        var nextRead = 0.0
        var pending: DispatchWorkItem?
        init(_ displays: [NSScreen]) {
            height = displays.first?.frame.height ?? 0
            screens = displays.map { ($0.frame, $0.visibleFrame) }
        }
    }
    private var gesture: Gesture?, outline: CGRect?
    private let worker = DispatchQueue(label:"local.goodwin.drag-lookup", qos:.userInteractive)
    private let lookup: (CGPoint) -> DragWindow?
    private let render: (CGRect?) -> Void
    init(lookup: @escaping (CGPoint) -> DragWindow?, render: @escaping (CGRect?) -> Void) {
        self.lookup = lookup; self.render = render
    }
    convenience init(preview: NSPanel) {
        self.init(lookup: { AXIsProcessTrusted() ? ManagedWindow.at($0) : nil }) { rect in
            guard let rect else { preview.orderOut(nil); return }
            preview.setFrame(rect,display:true)
            if !preview.isVisible { preview.orderFrontRegardless() }
        }
    }
    private func hide() {
        if outline != nil { render(nil); outline = nil }
    }
    func cancel() {
        gesture?.pending?.cancel(); gesture = nil; hide()
    }
    private func begin(_ point: CGPoint) {
        cancel()
        let g = Gesture(NSScreen.screens); gesture = g
        let lookup = self.lookup
        let work = DispatchWorkItem { [weak self, weak g] in
            guard g != nil else { return }
            let w = lookup(point)
            let frame = w?.frame
            DispatchQueue.main.async { [weak self, weak g] in
                guard let self, let g, self.gesture === g else { return }
                g.pending = nil
                guard let w, let frame else { self.cancel(); return }
                g.window = w; g.initial = frame; self.evaluate(g)
            }
        }
        g.pending = work; worker.async(execute:work)
    }
    func handle(_ event: NSEvent) {
        guard let p = event.cgEvent?.location else { return }
        handle(event.type, at:p)
    }
    func handle(_ type: NSEvent.EventType, at p: CGPoint) {
        if type == .leftMouseDown { begin(p); return }
        guard let g = gesture else { return }
        if type == .leftMouseDragged { g.dragged = true }
        g.released = type == .leftMouseUp
        guard g.dragged else { if g.released { cancel() }; return }
        let pt = CGPoint(x:p.x, y:g.height-p.y)
        if let s = g.screens.first(where:{ flip($0.bounds, primaryHeight:g.height).contains(p) }),
           let side = edge(at:pt, in:s.bounds) {
            g.target = Target(side:side, rect:side.rect(in:s.visible), axDisplay:flip(s.bounds, primaryHeight:g.height))
        } else { g.target = nil }
        evaluate(g)
    }
    private func evaluate(_ g: Gesture) {
        guard let target = g.target else { hide(); if g.released { cancel() }; return }
        guard let w = g.window else { return } // The initial hit-test is still in flight.
        guard target.side == .fill || w.resizable else { hide(); if g.released { cancel() }; return }
        if !g.confirmed {
            let now = ProcessInfo.processInfo.systemUptime
            guard !g.reading, g.released || now >= g.nextRead else { return }
            g.nextRead = now + 0.03; g.reading = true
            let initial = g.initial, finalCheck = g.released
            worker.async { [weak self, weak g] in
                guard g != nil else { return }
                let confirmed = w.frame.map { moved(initial,$0) } ?? false
                DispatchQueue.main.async { [weak self, weak g] in
                    guard let self, let g, self.gesture === g else { return }
                    g.reading = false; g.confirmed = confirmed
                    if confirmed || (g.released && !finalCheck) { self.evaluate(g) }
                    else if g.released { self.cancel() }
                }
            }
            return
        }
        if g.released {
            cancel()
            if !w.snap(to:flip(target.rect,primaryHeight:g.height), layout:target.side, display:target.axDisplay) { NSSound.beep() }
            return
        }
        let shown = w.resizable ? target.rect : CGRect(origin:centeredOrigin(for:g.initial.size,in:target.rect), size:g.initial.size)
        let rect = shown.insetBy(dx:3,dy:3)
        guard rect != outline else { return }
        render(rect); outline = rect
    }
}
