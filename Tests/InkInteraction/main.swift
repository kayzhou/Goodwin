// On an idle desktop: compile alongside Sources/Annotation.swift and Sources/FountainPenCursor.swift and run separately
// from the normal build. All test clicks are within a disposable fixture window.
import AppKit
import Carbon
let app = NSApplication.shared, previous = NSWorkspace.shared.frontmostApplication
let controller = AnnotationController()
final class Counter: NSView { var clicks = 0; override func mouseDown(with event: NSEvent) { clicks += 1 }; override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true } }
func pump(_ seconds:Double) {
    let end = Date(timeIntervalSinceNow:seconds)
    while Date() < end { if let e = app.nextEvent(matching:.any,until:end,inMode:.default,dequeue:true) { app.sendEvent(e) }; app.updateWindows() }
}
func run() throws {
    guard CGPreflightPostEventAccess(), let screen = NSScreen.screens.first else { throw NSError(domain:"requires an idle GUI with input permission",code:1) }
    app.setActivationPolicy(.regular); app.finishLaunching()
    let center = CGPoint(x:screen.frame.midX,y:screen.frame.midY)
    let win = NSWindow(contentRect:CGRect(x:center.x-120,y:center.y-100,width:240,height:200),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    win.title = "Goodwin 标注验收"; win.isReleasedWhenClosed = false
    let counter = Counter(); win.contentView = counter
    let saved = CGEvent(source:nil)?.location
    defer { controller.clear(); win.close(); if let saved { CGWarpMouseCursorPosition(saved) }; _ = previous?.activate(options:[]) }
    win.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true); pump(0.3)
    func require(_ yes:Bool, _ name:String) throws { if !yes { throw NSError(domain:name,code:1) }; print(name) }
    func click(_ delta:CGFloat, arrow:Bool=false, pinned:Bool=false) throws {
        let id = NSWindow.windowNumber(at:center,belowWindowWithWindowNumber:0)
        let target = app.windows.first { $0.windowNumber == id }
        try require(app.isActive && (pinned ? target === win : target?.title == "Goodwin 屏幕标注"), "hit test before input: \(pinned ? "underlying window" : "ink panel")")
        for (kind,dx) in [(CGEventType.leftMouseDown,0.0),(.leftMouseDragged,delta),(.leftMouseUp,delta)] {
            let e = CGEvent(mouseEventSource:nil,mouseType:kind,mouseCursorPosition:CGPoint(x:center.x+dx,y:screen.frame.height-center.y),mouseButton:.left)!
            e.flags = arrow ? [.maskShift] : []; e.post(tap:.cghidEventTap); pump(0.07)
        }
    }
    func key(_ code:Int, cmd:Bool=false) throws {
        try require(app.keyWindow?.title == "Goodwin 屏幕标注", "keyboard targets ink")
        for down in [true,false] { let e = CGEvent(keyboardEventSource:nil,virtualKey:CGKeyCode(code),keyDown:down)!; e.flags = cmd ? [.maskCommand] : []; e.post(tap:.cghidEventTap); pump(0.05) }
    }
    controller.edit(on:screen); pump(0.2); try click(35); try click(60,arrow:true)
    try require(controller.ink.strokes.count == 2 && controller.ink.strokes.last?.arrow == true && counter.clicks == 0,"pen and arrow captured")
    try key(kVK_ANSI_Z,cmd:true); try require(controller.ink.strokes.count == 1,"undo")
    try key(kVK_Return); try require(controller.ink.mode == .pinned,"pinned")
    try click(0,pinned:true); try require(counter.clicks == 1 && controller.ink.strokes.count == 1,"click through retained ink")
    controller.edit(on:screen); pump(0.1); try key(kVK_Escape); try require(controller.ink.mode == .off && controller.ink.strokes.isEmpty,"escape clears and exits")
}
do { try run() } catch { print("FAIL",error); exit(1) }
