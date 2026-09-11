import AppKit
import simd

enum SpiritMood: Int {
    case resting, awake, working, complete, waiting, unavailable
    var caption: String {
        switch self {
        case .resting:return "陪着你"
        case .awake:return "醒啦"
        case .working:return "忙着呢"
        case .complete:return "做好了"
        case .waiting:return "等你回答"
        case .unavailable:return "暂未连上"
        }
    }
}
struct SpiritExpression {
    var mood: SpiritMood = .resting
    var age: Float = 100
    var tapAge: Float = 100
    var caption: String { tapAge < 1.2 && mood != .waiting && mood != .unavailable ? "我在呢":mood.caption }
    var gpu: SIMD4<Float> { SIMD4(Float(mood.rawValue),age,tapAge,1) }
}
/// A display-only companion. It never writes usage, task state, or focus rankings.
final class SpiritModel {
    private var activity = [String:(phase:WorkPhase,at:Float)]()
    private var messages = [String:Float]()
    private var completions = [String:Float]()
    private var tokens = [String:Float]()
    private var touchedAt: Float = -100
    func touch(at now:Float){touchedAt=now}
    func update(_ tasks:[TaskUsage],events:[String:[WorkEvent]],deltas:[String:Int64],at now:Float){
        let ids=Set(tasks.map{$0.id})
        activity=activity.filter{ids.contains($0.key)};messages=messages.filter{ids.contains($0.key)}
        completions=completions.filter{ids.contains($0.key)};tokens=tokens.filter{ids.contains($0.key)}
        for task in tasks {
            for event in events[task.id] ?? [] {
                activity[task.id]=(event.phase,now)
                if event.phase == .input {messages[task.id]=now;completions[task.id]=nil}
                if event.phase == .complete {completions[task.id]=now}
                if event.phase == .interrupted {completions[task.id]=nil;messages[task.id]=nil}
            }
            if (deltas[task.id] ?? 0)>0{tokens[task.id]=now}
        }
    }
    func expression(task:TaskUsage?,at now:Float,stale:Bool)->SpiritExpression{
        let tap=max(0,now-touchedAt)
        guard !stale else{return SpiritExpression(mood:.unavailable,tapAge:tap)}
        guard let t=task else{return SpiritExpression(tapAge:tap)}
        if t.awaitingInput{return SpiritExpression(mood:.waiting,age:max(0,now-(activity[t.id]?.at ?? now)),tapAge:tap)}
        if let done=completions[t.id],now-done<5.5,
           activity[t.id]?.phase == .complete{return SpiritExpression(mood:.complete,age:now-done,tapAge:tap)}
        if let wake=messages[t.id],now-wake<2.2{return SpiritExpression(mood:.awake,age:now-wake,tapAge:tap)}
        if let a=activity[t.id],![WorkPhase.complete,.interrupted,.waiting,.quiet].contains(a.phase),
           now-a.at < ((a.phase == .thinking || a.phase == .tool) && t.isWorking ? 60:8){
            return SpiritExpression(mood:.working,age:now-a.at,tapAge:tap)
        }
        if activity[t.id]?.phase != .complete && activity[t.id]?.phase != .interrupted,
           let token=tokens[t.id],now-token<4{return SpiritExpression(mood:.working,age:now-token,tapAge:tap)}
        return SpiritExpression(tapAge:tap)
    }
}
/// A small caption inside the orb. Pointer events continue to the galaxy below.
final class SpiritBadge:NSView {
    override var isOpaque:Bool{false}
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=NSColor.clear.cgColor;layer?.isOpaque=false}
    required init?(coder:NSCoder){fatalError()}
    var providerStates:[String]?{didSet{needsDisplay=true}}
    var expression=SpiritExpression(){didSet{needsDisplay=true}}
    override var isFlipped:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
    override func draw(_ dirtyRect:NSRect){
        if let states=providerStates {
            let small=bounds.width<120
            let font=NSFont.systemFont(ofSize:small ? 7:9,weight:.medium)
            let gap:CGFloat=small ? 7:10
            let labels=["Codex", "Claude"]
            let widths=labels.map { ($0 as NSString).size(withAttributes:[.font:font]).width + (small ? 7:9) }
            let totalWidth=widths.reduce(0,+)+gap
            let textHeight=labels.map { ($0 as NSString).size(withAttributes:[.font:font]).height }.max() ?? 12
            // Every corner of the whole legend must fit the actual OrbRoot circle.
            let safeRadius=max(0,min(bounds.width,bounds.height)/2-4)
            let halfWidth=totalWidth/2
            let bottom=bounds.height/2+sqrt(max(0,safeRadius*safeRadius-halfWidth*halfWidth))
            let y=min(bounds.height*0.88,bottom-textHeight-2)
            var x=(bounds.width-totalWidth)/2
            NSColor(calibratedWhite:0.003,alpha:0.96).setFill()
            NSBezierPath(roundedRect:NSRect(x:x-2,y:y-1,width:totalWidth+4,height:textHeight+2),xRadius:4,yRadius:4).fill()
            for i in 0..<2 {
                let active=states[i] == "工作中"
                let color=i==0 ? NSColor(calibratedWhite:0.94,alpha:1):NSColor(calibratedRed:0.851,green:0.467,blue:0.341,alpha:1)
                color.withAlphaComponent(active ? 1:0.38).setFill()
                let dot:CGFloat=small ? 3:4
                NSBezierPath(ovalIn:NSRect(x:x,y:y+(small ? 3:4),width:dot,height:dot)).fill()
                (labels[i] as NSString).draw(at:NSPoint(x:x+dot+3,y:y),withAttributes:[.font:font,.foregroundColor:color.withAlphaComponent(active ? 0.95:0.50)])
                x += widths[i]+gap
            };return
        }
        let text=expression.caption
        let font=NSFont.systemFont(ofSize:bounds.width<120 ? 10:11,weight:.medium)
        let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:NSColor(calibratedWhite:0.96,alpha:1)]
        let size=(text as NSString).size(withAttributes:attrs)
        let box=NSRect(x:(bounds.width-size.width-27)/2,y:bounds.height*(bounds.width<120 ? 0.67:0.77),width:size.width+27,height:22)
        NSColor(calibratedWhite:0.025,alpha:0.94).setFill();NSBezierPath(roundedRect:box,xRadius:11,yRadius:11).fill()
        let color=expression.mood == .waiting ? NSColor(calibratedRed:1,green:0.8,blue:0.4,alpha:1):NSColor(calibratedRed:0.77,green:0.87,blue:1,alpha:1)
        color.setFill();NSBezierPath(ovalIn:NSRect(x:box.minX+9,y:box.midY-2,width:4,height:4)).fill()
        (text as NSString).draw(at:NSPoint(x:box.minX+18,y:box.midY-size.height/2),withAttributes:attrs)
    }
}
final class SpiritPreviewController:NSObject,NSWindowDelegate {
    let window:NSWindow
    let field=StarField(frame:NSRect(x:160,y:102,width:240,height:240))
    let badge=SpiritBadge(frame:NSRect(x:160,y:102,width:240,height:240))
    let label=NSTextField(labelWithString:"演示样本 · 不计入真实用量")
    var task=TaskUsage(id:"spirit-demo",title:"星灵演示",project:"演示",total:1_000_000,input:nil,cached:nil,output:nil,source:"demo")
    private var timer:Timer?,sequence=0
    override init(){
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:415),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        super.init();window.title="星灵 · 陪你工作";window.isReleasedWhenClosed=false;window.delegate=self
        let root=NSView(frame:NSRect(x:0,y:0,width:560,height:415));root.wantsLayer=true;root.layer?.backgroundColor=NSColor(calibratedWhite:0.015,alpha:1).cgColor;root.appearance=NSAppearance(named:.darkAqua);window.contentView=root
        label.font = .systemFont(ofSize:12);label.textColor = .secondaryLabelColor;label.alignment = .center;label.frame=NSRect(x:20,y:365,width:520,height:22);root.addSubview(label)
        field.paused=true;field.spiritEnabled=true;field.update([task],deltas:[:]);root.addSubview(field);root.addSubview(badge)
        field.onSelect={[weak self] _ in self?.field.pet.touch(at:self?.field.model.clock ?? 0);self?.updateBadge()}
        for (i,title) in ["唤醒","工作","完成","等你","摸一下"].enumerated(){let b=NSButton(title:title,target:self,action:#selector(trigger(_:)));b.tag=i;b.frame=NSRect(x:CGFloat(30+i*102),y:49,width:92,height:30);root.addSubview(b)}
        window.center();updateBadge()
    }
    func updateBadge(){badge.expression=field.spiritExpression;field.toolTip="演示："+field.spiritExpression.caption}
    @objc func trigger(_ sender:NSButton){
        if sender.tag==4{field.pet.touch(at:field.model.clock);updateBadge();return}
        sequence+=1;task.awaitingInput=sender.tag==3;task.lifecycle=sender.tag==2 ? "task_complete":"task_started";task.lastEventAt=Date().timeIntervalSince1970
        let phase:[WorkPhase]=[.input,.thinking,.complete,.waiting]
        field.update([task],deltas:[:],events:[task.id:[WorkEvent(id:"spirit-demo-\(sequence)",at:Date().timeIntervalSince1970,phase:phase[sender.tag])]])
        label.stringValue="演示：\(sender.title) · 不计入真实用量";updateBadge()
    }
    func show(){window.makeKeyAndOrderFront(nil);field.paused=false;NSApp.activate(ignoringOtherApps:true);timer?.invalidate();timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self] _ in self?.updateBadge()}}
    func windowWillClose(_ notification:Notification){field.paused=true;timer?.invalidate();timer=nil}
    func windowDidMiniaturize(_ notification:Notification){field.paused=true}
    func windowDidDeminiaturize(_ notification:Notification){field.paused=false}
}
