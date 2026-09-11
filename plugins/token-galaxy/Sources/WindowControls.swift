import AppKit
final class OrbRoot:NSView {
    override func resizeSubviews(withOldSize oldSize:NSSize){super.resizeSubviews(withOldSize:oldSize);needsLayout=true}
    override func layout(){super.layout();layer?.cornerRadius=min(bounds.width,bounds.height)/2}
    override func hitTest(_ point:NSPoint)->NSView?{let p=convert(point,from:superview);guard hypot(p.x-bounds.midX,p.y-bounds.midY)<=min(bounds.width,bounds.height)/2 else{return nil};return super.hitTest(point)}
}
final class FloatingPanel:NSPanel {
    weak var barDelegate:NSTouchBarDelegate?
    var supportsTouchBar=HardwareCapabilities.touchBarAvailable
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
    override func makeTouchBar()->NSTouchBar?{
        guard supportsTouchBar else{return nil}
        let bar=NSTouchBar();bar.delegate=barDelegate;bar.defaultItemIdentifiers=[.init("local.token-galaxy.flow"),.init("local.token-galaxy.count"),.init("local.token-galaxy.overview")];return bar
    }
}

/// AppKit-point accumulated steps: ignore trackpad momentum and cap each event.
struct OrbResizeSteps {
    var remainder:CGFloat=0
    mutating func consume(_ delta:CGFloat,precise:Bool,momentum:Bool,fine:Bool)->CGFloat {
        guard !momentum else{return 0}
        let scaled=delta*(precise ? 0.12:0.75)*(fine ? 0.2:1)
        remainder += min(2,max(-2,scaled))
        let steps=remainder.rounded(.towardZero);remainder -= steps
        return -steps
    }
}
final class FineSizeSlider:NSSlider {
    private var steps=OrbResizeSteps()
    override func scrollWheel(with event:NSEvent){
        let change=Double(steps.consume(event.scrollingDeltaY,precise:event.hasPreciseScrollingDeltas,momentum:!event.momentumPhase.isEmpty,fine:event.modifierFlags.contains(.shift)))
        guard change != 0 else{return};doubleValue=min(maxValue,max(minValue,doubleValue+change));sendAction(action,to:target)
    }
    override func keyDown(with event:NSEvent){
        let directions:[UInt16:Double]=[123:-1,124:1,125:-1,126:1]
        if let change=directions[event.keyCode]{doubleValue=min(maxValue,max(minValue,doubleValue+change));sendAction(action,to:target)}else{super.keyDown(with:event)}
    }
}
