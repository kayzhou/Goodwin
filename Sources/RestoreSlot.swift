// Only windows successfully minimized by Goodwin are candidates. Never search
// the Dock or guess from the frontmost app, which may have changed on minimize.
enum RestoreAttempt { case restored, stale, failed }
enum RestoreTarget<Window> { case window(Window), none, failed }
extension RestoreTarget: Equatable where Window: Equatable {}

struct RestoreSlot<Window> {
    var saved: Window?
    mutating func take(restoring: (Window) -> RestoreAttempt) -> RestoreTarget<Window> {
        guard let saved else { return .none }
        switch restoring(saved) {
        case .restored: self.saved = nil; return .window(saved)
        case .stale: self.saved = nil; return .none
        case .failed: return .failed
        }
    }
}
