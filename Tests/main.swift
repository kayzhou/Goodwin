import Foundation
import CoreGraphics
let visible = CGRect(x: -1300, y: 45, width: 1299, height: 880)
let display = CGRect(x: -1300, y: 0, width: 1300, height: 950)
precondition(Layout.left.rect(in: visible) == CGRect(x: -1300, y: 45, width: 649, height: 880))
precondition(Layout.right.rect(in: visible) == CGRect(x: -651, y: 45, width: 650, height: 880))
precondition(Layout.fill.rect(in: visible) == visible)
precondition(edge(at: CGPoint(x:-1298,y:400), in: display) == .left)
precondition(edge(at: CGPoint(x:-2,y:400), in: display) == .right)
precondition(edge(at: CGPoint(x:-1298,y:948), in: display) == .fill)
precondition(edge(at: CGPoint(x:-1100,y:400), in: display) == nil)
precondition(edge(at: CGPoint(x:11,y:400), in: display) == nil)
precondition(flip(visible, primaryHeight: 1000).origin == CGPoint(x:-1300,y:75))
precondition(flip(flip(visible, primaryHeight: 1000), primaryHeight: 1000) == visible)
precondition(moved(visible, visible.offsetBy(dx: 10, dy: 0)))
precondition(!moved(visible, visible)); precondition(!moved(visible, visible.insetBy(dx:10,dy:10)))
print("布局、边缘判定、坐标转换及拖动识别测试通过")

precondition(edge(at: CGPoint(x:-1000,y:950), in: display) == .fill)

let desk = CGRect(x:-1440, y:30, width:1440, height:900)
func exerciseFill(_ initial: CGSize, accepted: CGSize?, resizable: Bool, expected: CGRect) {
    var live = CGRect(origin: CGPoint(x:60,y:70), size:initial)
    var attempts = 0
    let ok = fillOrCenter(in: desk, resizable: resizable, read: { live }, move: { live.origin = $0; return true }, resize: { _ in
        attempts += 1
        if let accepted { live.size = accepted }
    })
    precondition(ok && live == expected && attempts == (resizable ? 1 : 0))
}
let small = CGSize(width:640,height:400)
exerciseFill(small, accepted:desk.size, resizable:true, expected:desk)
exerciseFill(small, accepted:CGSize(width:1000,height:900), resizable:true, expected:CGRect(x:-1220,y:30,width:1000,height:900))
for writable in [true,false] { exerciseFill(small, accepted:nil, resizable:writable, expected:CGRect(x:-1040,y:280,width:640,height:400)) }
print("填满、限宽、拒绝缩放和固定尺寸窗口的居中测试通过")

import Carbon
let bindings = Shortcut.allCases
precondition(bindings.map(\.keyCode) == [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].map(UInt32.init))
precondition(bindings.map(\.action) == [.arrange(.left), .arrange(.right), .arrange(.fill), .minimize])
precondition(Shortcut.modifiers == UInt32(controlKey | optionKey))
print("四组方向键全局快捷键映射通过")

// Observable AX write counts: same-sized halves only move, repeated snaps do nothing.
let left = Layout.left.rect(in: desk), right = Layout.right.rect(in: desk)
func writes(_ from: CGRect, _ to: CGRect, crossDisplay: Bool = false) -> [String] {
    var log: [String] = []
    let ok = placeHalf(from: from, to: to, crossDisplay: crossDisplay, move: { _ in log.append("move"); return true }, resize: { _ in log.append("size"); return true })
    precondition(ok); return log
}
precondition(writes(left, right) == ["move"])
precondition(writes(right, right) == [])
precondition(writes(desk, right) == ["size", "move"])
precondition(writes(CGRect(x: 30,y: 40,width: 300,height: 200), left, crossDisplay: true) == ["move", "size"])
precondition(!placeHalf(from: desk, to:right, crossDisplay:false, move:{ _ in true }, resize:{ _ in false }))
print("同尺寸切换、重复吸附、跨屏落位及写入失败测试通过")

// Exercise asynchronous drag handling against a private stub, never the user's windows.
import AppKit
final class FixtureWindow: DragWindow {
    let resizable = true
    private var reads = 0 // only accessed by the controller's serial lookup queue
    var frame: CGRect? {
        precondition(!Thread.isMainThread); reads += 1
        return CGRect(x:reads == 1 ? 200 : 260,y:120,width:480,height:340)
    }
    var snaps: [Layout] = []
    func snap(to frame:CGRect, layout:Layout, display:CGRect) -> Bool {
        precondition(Thread.isMainThread); snaps.append(layout); return true
    }
}
func pump(until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(2)
    while !condition() && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.005)) }
    precondition(condition())
}
if let primary = NSScreen.screens.first {
    let mid = CGPoint(x:primary.frame.midX, y:primary.frame.height / 2), side = CGPoint(x:1,y:mid.y)
    let stub = FixtureWindow(); var outlines: [CGRect?] = []
    let flow = DragController(lookup: { _ in precondition(!Thread.isMainThread); return stub },render:{ outlines.append($0) })
    flow.handle(.leftMouseDown,at:mid); flow.handle(.leftMouseDragged,at:side)
    pump { outlines.count == 1 }
    for _ in 0..<100 { flow.handle(.leftMouseDragged,at:side) }; precondition(outlines.count == 1)
    flow.handle(.leftMouseDragged,at:mid); flow.handle(.leftMouseUp,at:mid)
    precondition(outlines.count == 2 && outlines[1] == nil && stub.snaps.isEmpty)
    let quick = FixtureWindow(); let gate = DispatchSemaphore(value:0)
    let fast = DragController(lookup:{ _ in precondition(!Thread.isMainThread); _ = gate.wait(timeout:.now()+1); return quick },render:{ _ in preconditionFailure("released: no late preview expected") })
    fast.handle(.leftMouseDown,at:mid); fast.handle(.leftMouseDragged,at:side); fast.handle(.leftMouseUp,at:side)
    gate.signal(); pump { quick.snaps == [.left] }
    print("异步查询、快速松手、预览去重、拖离取消测试通过")
}

var permission = PermissionChanges()
let events = [false,false,true,true,false,false,true].compactMap { permission.update($0) }
precondition(events == [false,true,false,true])
precondition(Shortcut.allCases.map(\.menuLabel) == ["左半屏", "右半屏", "最大化", "最小化"])
print("授权状态切换、重复检查和极简菜单测试通过")

// Remember the exact window, not the pid or whichever window gained focus.
for key in [Shortcut.up, .left, .right] {
    guard case .arrange = key.action else { fatalError("Not a restore-and-layout key") }
    var slot = RestoreSlot<Int>(); slot.saved = 41
    precondition(slot.take(restoring: { _ in .failed }) == .failed && slot.saved == 41)
    precondition(slot.take(restoring: { $0 == 41 ? .restored : .stale }) == .window(41))
    precondition(slot.take(restoring: { _ in fatalError() }) == .none)
    slot.saved = 42
    precondition(slot.take(restoring: { _ in .stale }) == .none && slot.saved == nil)
}
print("三方向恢复、失效窗口及失败重试测试通过")

// Reproduce an AX resize acknowledged but height-clamped at the old origin.
for side: Layout in [.left,.right] {
    let target = side.rect(in: desk)
    var live = CGRect(x:desk.minX+90,y:desk.minY+300,width:400,height:200)
    func size(_ s:CGSize) -> Bool { live.size = CGSize(width:s.width,height:min(s.height,desk.maxY-live.minY)); return true }
    func move(_ p:CGPoint) -> Bool { live.origin = p; return true }
    precondition(placeHalf(from:live,to:target,crossDisplay:false,move:move,resize:size))
    precondition(!nearFrame(live,target))
    precondition(correctHalf(target,layout:side,read:{ live },move:move,resize:size) && live == target)
    precondition(correctHalf(target,layout:side,read:{ live },move:{ _ in fatalError() },resize:{ _ in fatalError() }))
}
print("首次吸附受屏幕边缘限制的回归测试通过")

// Temporary animation suppression must not leave a target app's AX mode changed.
for original: Bool? in [nil,false,true] {
    var calls:[String] = []
    let result = instantWrite(enhanced: original, setEnhanced: { calls.append($0 ? "on" : "off"); return true }) { calls.append("write"); return false }
    precondition(!result && calls == (original == true ? ["off","write","on"] : ["write"]))
}
var deniedCalls:[Bool] = []
precondition(instantWrite(enhanced:true,setEnhanced:{ deniedCalls.append($0); return false },perform:{ true }) && deniedCalls == [false])

// Ink is transient and cannot change while clicks pass through the overlay.
let ink = InkSession(), a = CGPoint(x:12,y:20), b = CGPoint(x:45,y:60), c = CGPoint(x:60,y:80)
ink.begin(at:a, arrow:false); precondition(ink.draft == nil)
ink.edit(); ink.begin(at:a, arrow:false); ink.extend(to:b); ink.finish(at:c)
ink.begin(at:c, arrow:true); ink.extend(to:a); ink.finish(at:b)
precondition(ink.strokes.count == 2 && ink.strokes[1].arrow && ink.strokes[1].path.elementCount == 2)
ink.undo(); precondition(ink.strokes.count == 1)
ink.pin(); precondition(ink.mode == .pinned); ink.begin(at:c, arrow:false); ink.undo(); precondition(ink.draft == nil && ink.strokes.count == 1)
ink.edit(); ink.begin(at:a, arrow:true); ink.finish(at:a); precondition(ink.strokes.last?.start == ink.strokes.last?.end)
ink.clear(); precondition(ink.mode == .off && ink.strokes.isEmpty && ink.draft == nil)
ink.edit(); ink.pin(); precondition(ink.mode == .off)
print("红笔、直箭头、撤销、穿透、继续标注与退出测试通过")

let smoothed = InkStroke(.zero,arrow:false)
for p in [CGPoint(x:8,y:2),CGPoint(x:16,y:7),CGPoint(x:24,y:14)] { smoothed.append(p) }
precondition((0..<smoothed.path.elementCount).contains { smoothed.path.element(at:$0) == .cubicCurveTo })
precondition(smoothed.paintedBounds.contains(smoothed.end))

let nib = FountainPenCursor.pen
precondition(nib.image.size == NSSize(width:32,height:32) && nib.hotSpot == NSPoint(x:3,y:29))
precondition(!nib.image.isTemplate && nib.image.isValid)
