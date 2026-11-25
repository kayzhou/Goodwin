import AppKit
import ApplicationServices

final class Goodwin: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let preview = NSPanel(contentRect: .zero, styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: true)
    private let annotation = AnnotationController()
    private var permission = PermissionChanges()
    private var permissionTimer: Timer?
    private var restoreSlot = RestoreSlot<MinimizedWindow>()
    private var commandGeneration = 0
    var shortcuts: GlobalShortcuts?
    private lazy var dragging = DragController(preview: preview)
    var monitor: Any?, previousPID: pid_t?
    var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
    func applicationDidFinishLaunching(_ note: Notification) {
        if let glyph = windowGlyph() {
            item.length = glyph.size.width + 8
            item.button?.imageScaling = .scaleNone
            item.button?.image = glyph
        }
        item.button?.toolTip = "Goodwin"
        menu.delegate = self; item.menu = menu
        preview.isOpaque = false; preview.backgroundColor = .clear; preview.hasShadow = false
        preview.ignoresMouseEvents = true; preview.level = .floating
        preview.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        preview.animationBehavior = .none
        preview.contentView = SnapOutline()
        NotificationCenter.default.addObserver(self, selector:#selector(cancelDrag), name:NSApplication.didChangeScreenParametersNotification, object:nil)
        shortcuts = GlobalShortcuts(toggleInk:{ [weak self] in self?.toggleInk() }) { [weak self] action in
            self?.perform(action,pid:NSWorkspace.shared.frontmostApplication?.processIdentifier)
        }
        syncPermission()
        let timer = Timer(timeInterval:2, repeats:true) { [weak self] _ in self?.syncPermission() }
        timer.tolerance = 0.5; RunLoop.main.add(timer, forMode:.common); permissionTimer = timer
    }
    private func syncPermission() {
        guard let trusted = permission.update(AXIsProcessTrusted()) else { return }
        shortcuts?.enableLayoutKeys(trusted)
        if trusted {
            monitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] event in
                guard self?.annotation.ink.mode != .editing else { return }
                if event.type == .leftMouseDown { self?.commandGeneration += 1 }
                self?.dragging.handle(event)
            }
        } else {
            commandGeneration += 1
            restoreSlot.saved = nil
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            dragging.cancel()
        }
        let bound = Shortcut.allCases.filter { shortcuts?.registered($0) == true }.count
        NSLog("Goodwin: Accessibility=%@, shortcuts=%d/%d, annotation=%@", trusted ? "authorized" : "not authorized", bound, Shortcut.allCases.count, shortcuts?.inkRegistered == true ? "registered" : "unavailable")
    }
    @discardableResult func add(_ title:String, _ action:Selector, tag:Int = 0) -> NSMenuItem {
        let entry = menu.addItem(withTitle:title, action:action, keyEquivalent:""); entry.target = self; entry.tag = tag
        return entry
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        syncPermission(); menu.removeAllItems()
        if permission.trusted == true {
            previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for key in Shortcut.allCases {
                let available = shortcuts?.registered(key) == true
                let entry = add(key.menuLabel + (available ? "" : "（快捷键未注册）"), #selector(arrange(_:)), tag:Int(key.rawValue))
                if available {
                    switch key {
                    case .left: entry.keyEquivalent = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
                    case .right: entry.keyEquivalent = String(UnicodeScalar(NSRightArrowFunctionKey)!)
                    case .up: entry.keyEquivalent = String(UnicodeScalar(NSUpArrowFunctionKey)!)
                    case .down: entry.keyEquivalent = String(UnicodeScalar(NSDownArrowFunctionKey)!)
                    }
                    entry.keyEquivalentModifierMask = [.control, .option]
                }
            }
        } else { add("开启辅助功能…", #selector(authorize)) }
        menu.addItem(.separator())
        let inkTitle: String
        switch annotation.ink.mode {
        case .off: inkTitle = "屏幕标注"
        case .editing: inkTitle = "保留标注"
        case .pinned: inkTitle = "继续标注"
        }
        let available = shortcuts?.inkRegistered == true
        let entry = add(inkTitle + (available ? "" : "（快捷键未注册）"), #selector(toggleInk))
        if available { entry.keyEquivalent = "\r"; entry.keyEquivalentModifierMask = [.control,.option] }
        entry.toolTip = "拖动画线，Shift 拖动画箭头；回车保留，Esc 清除。"
        if annotation.ink.mode != .off { add("清除标注", #selector(clearInk)) }
        menu.addItem(.separator()); add("退出", #selector(quit))
    }
    @objc private func toggleInk() {
        if annotation.ink.mode == .editing { annotation.pin() } else { editInk() }
    }
    private func editInk() {
        guard let s = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        commandGeneration += 1; dragging.cancel(); annotation.edit(on:s)
    }
    @objc private func clearInk() { annotation.clear() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func authorize() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt":true] as CFDictionary)
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    @objc func arrange(_ sender:NSMenuItem) {
        guard let shortcut = Shortcut(rawValue: UInt32(sender.tag)) else { return }
        perform(shortcut.action, pid: previousPID)
    }
    func perform(_ action: WindowAction, pid: pid_t?) {
        guard annotation.ink.mode != .editing else { return }
        commandGeneration += 1
        dragging.cancel()
        guard AXIsProcessTrusted() else { NSSound.beep(); return }
        switch action {
        case .minimize:
            guard let pid, let window = ManagedWindow.minimizeFocused(pid:pid) else { NSSound.beep(); return }
            restoreSlot.saved = window
        case .arrange(let layout):
            switch restoreSlot.take(restoring: { $0.restore() }) {
            case .window(let restored): place(layout, ref: restored.ref, restored: true)
            case .none: place(layout, ref: pid.flatMap { ManagedWindow.focused(pid:$0)?.ref }, restored: false)
            case .failed: NSSound.beep()
            }
        }
    }
    private func place(_ layout: Layout, ref: AXUIElement?, restored: Bool) {
        guard let ref else { NSSound.beep(); return }
        let generation = commandGeneration
        var destination: (rect: CGRect, display: CGRect)?
        var accepted: CGRect?
        // Dock transitions can temporarily hide geometry or overwrite the first write.
        // Pin the window and screen; never look up a different focused window on retry.
        func apply(_ pass: Int) {
            guard commandGeneration == generation else { return }
            var success = false
            if let w = ManagedWindow(ref), let ax = w.frame, ax.width > 0, ax.height > 0 {
                if destination == nil {
                    let frame = flip(ax, primaryHeight:primaryHeight)
                    func area(_ s:NSScreen) -> CGFloat { let r = frame.intersection(s.frame); return r.isNull ? 0 : r.width*r.height }
                    if let screen = NSScreen.screens.max(by:{area($0)<area($1)}) {
                        destination = (flip(layout.rect(in:screen.visibleFrame), primaryHeight:primaryHeight), flip(screen.frame, primaryHeight:primaryHeight))
                    }
                }
                if let target = destination {
                    if nearFrame(ax,target.rect) { return }
                    // A constrained app may settle short of the requested size. Never
                    // replay its motion unless the Dock actually undid our placement.
                    if let accepted, nearFrame(ax,accepted) { return }
                    // Fixed-size windows are already settled when centered.
                    if !w.resizable && layout == .fill && ax.origin == centeredOrigin(for:ax.size,in:target.rect) { return }
                    success = w.place(target.rect,layout:layout,display:target.display,current:ax)
                    if success, let actual = w.frame, nearFrame(actual,target.rect) || !nearFrame(actual,ax) { accepted = actual }
                }
            }
            // Ordinary snaps finish synchronously. Only Dock recovery or a rejected
            // write gets a later check; never interpolate frames on a timer.
            let delays = restored ? [0.12, 0.32, 0.32] : (success ? [] : [0.10])
            if pass < delays.count {
                DispatchQueue.main.asyncAfter(deadline:.now()+delays[pass]) { apply(pass+1) }
            } else if !success { NSSound.beep() }
        }
        apply(0)
    }
    @objc private func cancelDrag() { annotation.clear(); commandGeneration += 1; dragging.cancel() }
}
let app = NSApplication.shared
let delegate = Goodwin(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
