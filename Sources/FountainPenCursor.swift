import AppKit

// Draw in nib-local coordinates: (0,0) is the ink contact; +x runs up the barrel.
// NSImage uses a lower-left origin here; NSCursor measures its hotspot from top left.
enum FountainPenCursor {
    static let pen: NSCursor = make(arrow:false)
    static let arrowPen: NSCursor = make(arrow:true)
    private static func make(arrow:Bool) -> NSCursor {
        let image = NSImage(size:NSSize(width:32,height:32),flipped:false) { _ in
            func p(_ x:CGFloat,_ y:CGFloat) -> CGPoint { CGPoint(x:x,y:y) }
            func color(_ hex:Int) -> NSColor { NSColor(srgbRed:CGFloat(hex>>16)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
            func shade(_ path:NSBezierPath,_ colors:[Int],edge:Int) {
                NSGradient(colors:colors.map(color))?.draw(in:path,angle:90)
                color(edge).setStroke(); path.lineJoinStyle = .round; path.lineWidth = 0.65; path.stroke()
            }
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform(); t.translateX(by:3,yBy:3); t.rotate(byDegrees:53); t.concat()
            let nib = NSBezierPath(); nib.move(to:.zero)
            nib.curve(to:p(10.8,4.9),controlPoint1:p(4,0.9),controlPoint2:p(8.2,3.9))
            nib.curve(to:p(18.7,3.4),controlPoint1:p(13.5,5.2),controlPoint2:p(15.1,3.2))
            nib.line(to:p(18.7,-3.4)); nib.curve(to:p(10.8,-4.9),controlPoint1:p(15,-3.2),controlPoint2:p(13,-5.1))
            nib.curve(to:.zero,controlPoint1:p(8.6,-3.2),controlPoint2:p(4.8,-1.2)); nib.close()
            shade(nib,[0xbb8948,0xf0ca7c,0xffeac0],edge:0x88663a)
            let slit = NSBezierPath(); slit.move(to:p(0.3,0)); slit.line(to:p(11.1,0)); slit.lineWidth=0.68
            color(0x433326).set(); slit.stroke(); NSBezierPath(ovalIn:NSRect(x:10,y:-1.05,width:2.1,height:2.1)).fill()
            let grip = NSBezierPath(roundedRect:NSRect(x:18,y:-3.85,width:12,height:7.7),xRadius:1.1,yRadius:1.1)
            shade(grip,[0x131417,0x252429,0x525155,0x18191c],edge:0x88827a)
            let collar = NSBezierPath(roundedRect:NSRect(x:17.3,y:-3.95,width:2.2,height:7.9),xRadius:0.4,yRadius:0.4)
            shade(collar,[0xa66a52,0xf6ccb2,0xe0a983],edge:0x997660)
            NSGraphicsContext.restoreGraphicsState()
            if arrow {
                let mark = NSBezierPath(); mark.move(to:p(22,12)); mark.line(to:p(28,18)); mark.move(to:p(23.5,18)); mark.line(to:p(28,18)); mark.line(to:p(28,13.5)); mark.lineJoinStyle = .round; mark.lineCapStyle = .round
                NSColor.white.setStroke(); mark.lineWidth=3.2; mark.stroke(); InkStroke.color.setStroke(); mark.lineWidth=1.8; mark.stroke()
            }
            return true
        }
        image.isTemplate = false
        return NSCursor(image:image,hotSpot:NSPoint(x:3,y:29))
    }
}
