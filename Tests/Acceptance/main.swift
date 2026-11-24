// Black-box test. Do not import or call Goodwin's implementation. An active GUI session is required.
import AppKit
import Carbon

struct Halt: Error { let message: String; init(_ message: String) { self.message = message } }
let app = NSApplication.shared
let pid = ProcessInfo.processInfo.processIdentifier
let oldFront = NSWorkspace.shared.frontmostApplication
let args = CommandLine.arguments
let rounds = Int(args.dropFirst().first ?? "3") ?? 3
let mode = args.count > 2 ? args[2] : "normal"
let prefix = "Goodwin QA"
let clock = { ProcessInfo.processInfo.systemUptime }
func wait(_ seconds: Double) {
    let end = Date(timeIntervalSinceNow:seconds)
    while Date() < end {
        if let e = app.nextEvent(matching:.any,until:end,inMode:.default,dequeue:true) { app.sendEvent(e) }
        app.updateWindows()
    }
}
func near(_ a: CGRect, _ b: CGRect) -> Bool {
    [a.minX-b.minX,a.minY-b.minY,a.width-b.width,a.height-b.height].allSatisfy { abs($0) <= 1.1 }
}
func makeWindow(_ name: String, _ frame: CGRect, fixed: Bool = false) -> NSWindow {
    let style: NSWindow.StyleMask = fixed ? [.titled,.miniaturizable,.closable] : [.titled,.resizable,.miniaturizable,.closable]
    let w = NSWindow(contentRect:frame,styleMask:style,backing:.buffered,defer:false)
    w.title = prefix + name; w.isReleasedWhenClosed = false; w.animationBehavior = .none
    return w
}
let map = ["L": kVK_LeftArrow, "R": kVK_RightArrow, "U": kVK_UpArrow, "D": kVK_DownArrow]
func press(_ key: String) throws {
    guard app.isActive, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          app.keyWindow?.title.hasPrefix(prefix) == true else { throw Halt("focus lost: no key sent") }
    guard let code = map[key], let down = CGEvent(keyboardEventSource:nil,virtualKey:CGKeyCode(code),keyDown:true), let up = CGEvent(keyboardEventSource:nil,virtualKey:CGKeyCode(code),keyDown:false) else { throw Halt("event unavailable") }
    for event in [down,up] { event.flags = [.maskControl,.maskAlternate,.maskSecondaryFn,.maskNumericPad]; event.post(tap:.cghidEventTap) }
}
func test() throws {
    guard rounds > 0, rounds <= 100, ["normal","fixed","limited","rapid","focus","transition","drag"].contains(mode) else { throw Halt("invalid rounds/mode") }
    guard CGPreflightPostEventAccess(), AXIsProcessTrusted(), let installed = NSRunningApplication.runningApplications(withBundleIdentifier:"local.goodwin.WindowManager").first, installed.bundleURL?.path == "/Applications/Goodwin.app" else { throw Halt("need installed running Goodwin and test-runner event permission") }
    guard let screen = NSScreen.screens.first else { throw Halt("no display") }
    let desktop = screen.visibleFrame, half = floor(desktop.width/2)
    let l = CGRect(x:desktop.minX,y:desktop.minY,width:half,height:desktop.height)
    let r = CGRect(x:desktop.minX+half,y:desktop.minY,width:desktop.width-half,height:desktop.height)
    app.setActivationPolicy(.regular); app.finishLaunching()
    let anchor = makeWindow(" witness",CGRect(x:desktop.midX-120,y:desktop.midY-70,width:220,height:130))
    let w = makeWindow(" target",CGRect(x:desktop.midX-160,y:desktop.midY-100,width:360,height:220),fixed:mode == "fixed")
    defer { w.close(); anchor.close(); if app.isActive { _ = oldFront?.activate(options:[]) } }
    if mode == "limited" { w.maxSize = NSSize(width:520,height:360) }
    anchor.makeKeyAndOrderFront(nil); w.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true); wait(0.5)
    if app.keyWindow !== w && app.isActive { w.makeKeyAndOrderFront(nil); wait(0.25) }
    let original = w.frame, witness = anchor.frame
    var serial = 0
    var focusFailures = 0
    func check(_ key:String, burst:Bool = false) throws {
        // Minimize always targets the fixture: never let the witness replace it by accident.
        guard (w.isMiniaturized || app.keyWindow === w), key != "D" || !w.isMiniaturized else { throw Halt("unexpected target focus before \(key): appActive=\(app.isActive), frontIsFixture=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid), keyIsWitness=\(app.keyWindow === anchor), keyIsNil=\(app.keyWindow == nil)") }
        let wasMin = w.isMiniaturized; let start = clock(); serial += 1
        if burst { try press("L"); wait(0.025); try press("U"); wait(0.025) }
        try press(key)
        let expected:CGRect
        if key == "U" && ["fixed","limited"].contains(mode) {
            let size = mode == "fixed" ? original.size : w.maxSize
            expected = CGRect(x:desktop.minX+floor((desktop.width-size.width)/2),y:desktop.minY+floor((desktop.height-size.height)/2),width:size.width,height:size.height)
        } else { expected = key == "L" ? l : (key == "R" ? r : desktop) }
        func matches() -> Bool { key == "D" ? w.isMiniaturized : (!w.isMiniaturized && near(w.frame,expected)) }
        repeat { wait(0.01) } while !matches() && clock()-start < 1.5
        let latency = Int((clock()-start)*1000); let first = matches()
        // Re-check past Goodwin's deferred correction deadlines; wrong-window writes fail too.
        wait(wasMin || burst ? 0.85 : 0.16)
        let ok = first && matches() && near(anchor.frame,witness) && !anchor.isMiniaturized
        let label = (burst ? "burst-" : (wasMin ? "restore-" : "")) + key
        print("ROW,\(mode),\(serial),\(label),\(ok ? "PASS" : "FAIL"),\(latency)"); fflush(stdout)
        if wasMin && app.keyWindow !== w { print("OBS,restore-not-key,\(label)") }
        if wasMin && mode == "focus" {
            // Both foreground windows belong to this fixture. Probe the very next shortcut.
            try press("R"); wait(0.45)
            let correct = near(w.frame,r) && near(anchor.frame,witness)
            print("FOCUS,\(correct ? "PASS" : "FAIL"),targetRight=\(near(w.frame,r)),witnessMoved=\(!near(anchor.frame,witness))")
            if !correct { focusFailures += 1 }; anchor.setFrame(witness,display:true,animate:false)
        }
        if wasMin && app.keyWindow !== w {
            guard app.isActive else { throw Halt("focus left fixture") }
            // Isolate later geometry trials; the focus probe already ran above.
            w.makeKeyAndOrderFront(nil); wait(0.08)
        }
        if !ok { throw Halt("\(label) expected=\(expected) actual=\(w.frame) minimized=\(w.isMiniaturized) witnessChanged=\(!near(anchor.frame,witness) || anchor.isMiniaturized)") }
    }
    print("RUN mode=\(mode) rounds=\(rounds) displayCount=\(NSScreen.screens.count) desktop=\(desktop) goodwinPID=\(installed.processIdentifier)"); fflush(stdout)
    if mode == "drag" {
        let h = screen.frame.height
        let pointer = CGEvent(source:nil)?.location
        defer { if let pointer { CGWarpMouseCursorPosition(pointer) } }
        for _ in 0..<rounds { for side in ["L","R","U","cancel"] {
            guard app.isActive, app.keyWindow === w, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw Halt("focus lost: no mouse down") }
            w.setFrame(original,display:true,animate:false); wait(0.08)
            let start = CGPoint(x:original.midX,y:h-original.maxY+12)
            // Confirm the first (mouse-down) pixel belongs to this fixture, even if a panel is floating.
            var hit: AXUIElement?, owner:pid_t = -1
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(start.x),Float(start.y),&hit) == .success,
                  let hit, AXUIElementGetPid(hit,&owner) == .success, owner == pid else { throw Halt("covered fixture: no mouse down") }
            let edge = CGPoint(x:(side == "U" ? screen.frame.midX : (side == "R" ? screen.frame.maxX-2 : screen.frame.minX+2)), y:(side == "U" ? 4 : start.y))
            let release = side == "cancel" ? CGPoint(x:start.x+35,y:start.y+20) : edge
            // AppKit tracks the drag in a modal event loop. Deliver the remainder on a worker.
            DispatchQueue.global().async {
                func mouse(_ type:CGEventType,_ p:CGPoint) {
                    CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)
                }
                mouse(.leftMouseDown,start); Thread.sleep(forTimeInterval:0.10)
                for i in 1...15 { let f=Double(i)/15; mouse(.leftMouseDragged,CGPoint(x:start.x+(edge.x-start.x)*f,y:start.y+(edge.y-start.y)*f)); Thread.sleep(forTimeInterval:0.015) }
                Thread.sleep(forTimeInterval:0.09)
                if side == "cancel" { mouse(.leftMouseDragged,release); Thread.sleep(forTimeInterval:0.09) }
                mouse(.leftMouseUp,release)
            }
            wait(1.1)
            let correct = side == "cancel" ? w.frame.size == original.size && w.frame.origin != original.origin : near(w.frame,side == "L" ? l : (side == "R" ? r : desktop))
            let ok = correct && near(anchor.frame,witness) && !anchor.isMiniaturized
            print("DRAG,\(side),\(ok ? "PASS" : "FAIL"),actual=\(w.frame)"); fflush(stdout)
            if !ok { throw Halt("drag mismatch") }
        } }; return
    }
    // First own the restore slot by minimizing this fixture, even if the user previously minimized a window.
    try check("D"); try check("U")
    for index in 0..<rounds {
        if mode == "transition" {
            guard app.keyWindow === w else { throw Halt("unexpected target before transition") }
            let key = ["L","R","U"][index%3], expected = [l,r,desktop][index%3]
            w.setFrame(original,display:true,animate:false); try press("D"); wait(0.045); try press(key); wait(1.2)
            let correct = !w.isMiniaturized && near(w.frame,expected) && near(anchor.frame,witness) && !anchor.isMiniaturized
            print("PAIR,\(key),\(correct ? "PASS" : "FAIL"),actual=\(w.frame),minimized=\(w.isMiniaturized)"); fflush(stdout)
            if !correct { throw Halt("rapid minimize-restore did not settle") }
        } else if mode == "focus" { try check("D"); try check("U") }
        else if mode == "rapid" { try check("R",burst:true); try check("L") }
        else if mode == "normal" {
            try check("R"); try check("L"); try check("U"); try check("D"); try check(["L","R","U"][index%3])
        } else { w.setFrame(original,display:true,animate:false); try check("U"); try check("D"); try check("U") }
    }
    if focusFailures != 0 { throw Halt("restore continuity failures: \(focusFailures)") }
}
do { try test() } catch { print("STOP \(error)"); exit(1) }
