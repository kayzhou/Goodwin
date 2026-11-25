import Carbon

enum WindowAction: Equatable { case arrange(Layout), minimize }

enum Shortcut: UInt32, CaseIterable {
    case left = 1, right, up, down
    static let modifiers = UInt32(controlKey | optionKey)
    var keyCode: UInt32 {
        switch self {
        case .left: return UInt32(kVK_LeftArrow)
        case .right: return UInt32(kVK_RightArrow)
        case .up: return UInt32(kVK_UpArrow)
        case .down: return UInt32(kVK_DownArrow)
        }
    }
    var action: WindowAction {
        switch self {
        case .left: return .arrange(.left)
        case .right: return .arrange(.right)
        case .up: return .arrange(.fill)
        case .down: return .minimize
        }
    }
    var menuLabel: String {
        switch self {
        case .left: return "左半屏"
        case .right: return "右半屏"
        case .up: return "最大化"
        case .down: return "最小化"
        }
    }
}

struct PermissionChanges {
    private(set) var trusted: Bool?
    mutating func update(_ current: Bool) -> Bool? {
        guard current != trusted else { return nil }
        trusted = current
        return current
    }
}

struct KeyLatch {
    private var held = false
    mutating func handle(pressed: Bool) -> Bool {
        defer { held = pressed }; return pressed && !held
    }
}

final class GlobalShortcuts {
    static let inkCode = UInt32(kVK_Return)
    private static let inkID: UInt32 = 5
    private var inkRef: EventHotKeyRef?, inkKey = KeyLatch()
    private let toggleInk: () -> Void
    var inkRegistered: Bool { inkRef != nil }
    private static let signature: OSType = 0x4757494E // GWIN
    private var handler: EventHandlerRef?
    private var registrations: [Shortcut: EventHotKeyRef] = [:]
    private let perform: (WindowAction) -> Void
    func registered(_ key: Shortcut) -> Bool { registrations[key] != nil }

    init(toggleInk: @escaping () -> Void, perform: @escaping (WindowAction) -> Void) {
        self.toggleInk = toggleInk
        self.perform = perform
        let target = GetApplicationEventTarget()
        var events = [kEventHotKeyPressed,kEventHotKeyReleased].map { EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32($0)) }
        let status = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == GlobalShortcuts.signature else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            if id.id == GlobalShortcuts.inkID {
                if owner.inkKey.handle(pressed:pressed) { owner.toggleInk() }
            } else if pressed, let key = Shortcut(rawValue:id.id) { owner.perform(key.action) }
            return noErr
        }, 2, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return }
        _ = RegisterEventHotKey(Self.inkCode, Shortcut.modifiers, EventHotKeyID(signature:Self.signature,id:Self.inkID),target,UInt32(kEventHotKeyExclusive),&inkRef)
    }
    func enableLayoutKeys(_ enabled:Bool) {
        guard handler != nil else { return }
        guard enabled else {
            for ref in registrations.values { UnregisterEventHotKey(ref) }; registrations.removeAll(); return
        }
        let target = GetApplicationEventTarget()
        for key in Shortcut.allCases where registrations[key] == nil {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: key.rawValue)
            if RegisterEventHotKey(key.keyCode, Shortcut.modifiers, id, target, UInt32(kEventHotKeyExclusive), &ref) == noErr {
                registrations[key] = ref
            }
        }
    }
    deinit {
        if let inkRef { UnregisterEventHotKey(inkRef) }
        for ref in registrations.values { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
