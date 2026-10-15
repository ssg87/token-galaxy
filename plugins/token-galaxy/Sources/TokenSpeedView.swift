import AppKit

private let speedCodexColor = NSColor(calibratedWhite:0.95,alpha:1)
private let speedClaudeColor = NSColor(calibratedRed:0.94,green:0.59,blue:0.44,alpha:1)

extension TokenSpeedRates {
    func value(for metric:TokenSpeedMetric)->Double? {
        switch metric {case .total:return total;case .input:return input;case .output:return output}
    }
}

private func speedLabel(_ text:String,size:CGFloat=12,weight:NSFont.Weight = .regular,color:NSColor = .labelColor)->NSTextField {
    let field=NSTextField(labelWithString:text)
    field.font=NSFont.systemFont(ofSize:size,weight:weight);field.textColor=color
    field.lineBreakMode = .byTruncatingTail
    return field
}

func tokenSpeedStateLabel(_ state:TokenSpeedState)->String {
    switch state {
    case .notFound:return "暂无本地记录"
    case .warming:return "正在建立采样窗口"
    case .live:return "观测到新增 Token"
    case .idle:return "窗口内无新增 Token"
    case .gap:return "采样有断档"
    case .unavailable:return "缺少完整速率数据"
    }
}

private func speedReason(_ reason:String)->String {
    // Codes stay stable in JSON; the interface explains known codes in the user's language.
    let labels:[String:String]=[
        "warming":"等待完整采样窗口", "window_warming":"等待完整采样窗口",
        "not_found":"当前范围没有记录", "source_not_found":"当前来源没有记录",
        "read_error":"来源读取失败，恢复后重新建立窗口", "provider_error":"来源读取失败",
        "record_read_error":"记录暂不可读", "pending_bytes":"日志仍有未读内容",
        "sample_gap":"采样间隔过长", "stale_sample":"采样已陈旧",
        "counter_reset":"累计计数回退，正在重新建立基线", "identity_changed":"记录发生替换，正在重新建立基线",
        "membership_changed":"记录范围变化，正在重新建立基线",
        "unknown_input":"输入分类未知", "unknown_output":"输出分类未知",
        "input_unavailable":"输入分类未知", "output_unavailable":"输出分类未知",
        "initial_baseline":"已建立初始基线，等待完整窗口", "window_incomplete":"等待完整采样窗口",
        "scope_changed":"记录范围变化，正在重新建立窗口", "sampling_gap":"采样间隔超过5秒",
        "sample_stale":"最新采样已超过5秒", "source_read_failed":"来源读取失败，恢复后重新建立窗口",
        "record_read_failed":"记录暂不可读", "record_incomplete":"日志仍有未读内容",
        "source_records_missing":"已发现来源的记录暂时消失", "record_missing":"所选记录暂时消失",
        "record_recovered":"记录恢复，正在重新建立窗口", "source_recovered":"来源恢复，正在重新建立窗口",
        "record_rebased":"记录基线已重建", "source_changed":"记录来源发生变化",
        "counter_regressed":"累计计数回退，正在重新建立窗口", "counter_appeared":"累计计数刚刚可用",
        "invalid_counter":"累计计数无效", "duplicate_conflict":"重复记录的计数有冲突",
        "missing_total":"总量未知", "missing_input":"输入分类未知", "missing_output":"输出分类未知",
        "category_recovered":"用量分类恢复，正在重新建立窗口"
    ]
    return labels[reason] ?? reason
}

final class TokenSpeedRateView:NSView {
    let name=speedLabel("",size:12,color:.secondaryLabelColor)
    let value=NSTextField(labelWithString:"—")
    let unit=speedLabel("tokens/s",size:12,color:.secondaryLabelColor)
    let cumulative=speedLabel("累计 — tokens",size:11,color:.secondaryLabelColor)
    override var isFlipped:Bool {true}
    init(name:String) {
        super.init(frame:.zero);self.name.stringValue=name
        value.font=NSFont.monospacedDigitSystemFont(ofSize:34,weight:.medium)
        value.lineBreakMode = .byTruncatingTail
        [self.name,value,unit,cumulative].forEach{addSubview($0)}
        setAccessibilityElement(true);setAccessibilityRole(.group)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func layout(){
        super.layout();name.frame=NSRect(x:0,y:0,width:bounds.width,height:18)
        value.frame=NSRect(x:0,y:23,width:bounds.width,height:43)
        unit.frame=NSRect(x:1,y:68,width:bounds.width,height:17)
        cumulative.frame=NSRect(x:1,y:93,width:bounds.width,height:17)
    }
    func update(rate:Double?,count:Int64?,state:TokenSpeedState){
        value.stringValue=rate.map{String(format:"%.1f",$0)} ?? "—"
        let formatter=NumberFormatter();formatter.numberStyle = .decimal
        cumulative.stringValue="累计 "+(count.flatMap{formatter.string(from:NSNumber(value:$0))} ?? "—")+" tokens"
        value.textColor=rate==nil ? .secondaryLabelColor:.labelColor
        setAccessibilityLabel("\(name.stringValue)，\(rate.map{String(format:"%.1f tokens 每秒",$0)} ?? "速率未知")，\(cumulative.stringValue)，\(tokenSpeedStateLabel(state))")
    }
}

struct TokenSpeedChartSeries {
    var label:String
    var color:NSColor
    var points:[TokenSpeedTrendPoint]
}

final class TokenSpeedChart:NSView {
    var series=[TokenSpeedChartSeries](){didSet{updateUpperBound()}}
    var metric:TokenSpeedMetric = .total {didSet{updateUpperBound()}}
    var now:TimeInterval=0
    var emptyText="等待本地采样"
    private(set) var drawCount=0
    var plotRect:NSRect {NSRect(x:58,y:31,width:max(1,bounds.width-76),height:max(1,bounds.height-48))}
    private(set) var upperBound:Double=10
    private func updateUpperBound(){
        let maximum=series.flatMap{$0.points.compactMap{$0.rates.value(for:metric)}}.filter{$0.isFinite}.max() ?? 0
        guard maximum>0 else{upperBound=10;return}
        let magnitude=pow(10,floor(log10(maximum)))
        upperBound=max(1,ceil(maximum/magnitude/2)*magnitude*2)
    }
    override init(frame:NSRect){super.init(frame:frame);setAccessibilityElement(true);setAccessibilityRole(.image)}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    func point(at:TimeInterval,rate:Double)->NSPoint {
        let r=plotRect
        return NSPoint(x:r.minX+CGFloat((at-(now-120))/120)*r.width,y:r.minY+CGFloat(rate/upperBound)*r.height)
    }
    func segments(_ points:[TokenSpeedTrendPoint])->[[NSPoint]] {
        var result=[[NSPoint]](),segment=[NSPoint](),lastAt:TimeInterval?
        func finish(){if !segment.isEmpty{result.append(segment);segment=[]}}
        for p in points where p.at>=now-120 && p.at<=now+0.001 {
            guard let value=p.rates.value(for:metric),value.isFinite,value>=0 else{finish();lastAt=nil;continue}
            if let previous=lastAt,p.at-previous>1.5{finish()}
            segment.append(point(at:p.at,rate:value));lastAt=p.at
        }
        finish();return result
    }
    override func draw(_ dirtyRect:NSRect){
        super.draw(dirtyRect);drawCount+=1
        let r=plotRect,attributes:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor.secondaryLabelColor]
        for fraction in [0.0,0.5,1.0] {
            let y=r.minY+CGFloat(fraction)*r.height
            NSColor(calibratedWhite:1,alpha:0.10).setStroke()
            let line=NSBezierPath();line.move(to:NSPoint(x:r.minX,y:y));line.line(to:NSPoint(x:r.maxX,y:y));line.lineWidth=0.5;line.stroke()
            let n=upperBound*fraction,text=n>=1000 ? String(format:"%.1fk",n/1000):String(format:"%.0f",n)
            (text as NSString).draw(at:NSPoint(x:5,y:y-6),withAttributes:attributes)
        }
        for (fraction,text) in [(0.0,"−120 秒"),(0.5,"−60 秒"),(1.0,"现在")] {
            let x=r.minX+CGFloat(fraction)*r.width,size=(text as NSString).size(withAttributes:attributes)
            (text as NSString).draw(at:NSPoint(x:x-(fraction==0 ? 0:fraction==1 ? size.width:size.width/2),y:8),withAttributes:attributes)
        }
        var hasValues=false
        NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:r.insetBy(dx:-2,dy:-2)).addClip()
        for entry in series {
            entry.color.setStroke();entry.color.setFill()
            for segment in segments(entry.points) {
                hasValues=true
                if segment.count==1,let p=segment.first{NSBezierPath(ovalIn:NSRect(x:p.x-2,y:p.y-2,width:4,height:4)).fill();continue}
                let line=NSBezierPath();line.lineWidth=2;line.lineJoinStyle = .round;line.lineCapStyle = .round
                for (i,p) in segment.enumerated(){if i==0{line.move(to:p)}else{line.line(to:p)}};line.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if !hasValues {
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.secondaryLabelColor]
            let size=(emptyText as NSString).size(withAttributes:attrs)
            (emptyText as NSString).draw(at:NSPoint(x:r.midX-size.width/2,y:r.midY-size.height/2),withAttributes:attrs)
        }
    }
}

private final class TokenSpeedContentView:NSView {
    var onLayout:(()->Void)?
    override var isFlipped:Bool {true}
    override func layout(){super.layout();onLayout?()}
}

final class TokenSpeedController:NSObject,NSWindowDelegate {
    let window:NSWindow
    let engine:TokenSpeedEngine
    private let root=TokenSpeedContentView()
    private let heading=speedLabel("Token 速度",size:24,weight:.semibold)
    private let subtitle=speedLabel("本地日志每秒新增 · 最近 10 秒滑动窗口",size:12,color:.secondaryLabelColor)
    let provider=NSPopUpButton(frame:.zero,pullsDown:false)
    let task=NSPopUpButton(frame:.zero,pullsDown:false)
    let windowControl=NSSegmentedControl(labels:["10 秒","30 秒","60 秒"],trackingMode:.selectOne,target:nil,action:nil)
    let metricControl=NSSegmentedControl(labels:["总量","输入","输出"],trackingMode:.selectOne,target:nil,action:nil)
    private let providerLabel=speedLabel("来源",size:11,color:.secondaryLabelColor)
    private let taskLabel=speedLabel("记录",size:11,color:.secondaryLabelColor)
    private let windowLabel=speedLabel("滑动窗口",size:11,color:.secondaryLabelColor)
    let totalRate=TokenSpeedRateView(name:"总观测速率")
    let inputRate=TokenSpeedRateView(name:"输入观测速率")
    let outputRate=TokenSpeedRateView(name:"输出观测速率")
    let stateLabel=speedLabel("正在建立采样窗口",size:13,weight:.medium)
    private let coverageLabel=speedLabel("",size:11,color:.secondaryLabelColor)
    private let reasonLabel=NSTextField(wrappingLabelWithString:"")
    private let progress=NSProgressIndicator()
    private let chartTitle=speedLabel("最近 120 秒",size:13,weight:.medium)
    private let chartUnit=speedLabel("tokens/s",size:11,color:.secondaryLabelColor)
    let chart=TokenSpeedChart(frame:.zero)
    private let legend=speedLabel("",size:11,color:.secondaryLabelColor)
    private let explanation=NSTextField(wrappingLabelWithString:"本地记录观测速率，不是精确模型生成速度；日志批量落盘可能突增；每来源最近最多80记录。\n输入口径：Codex缓存是输入子集；Claude输入含缓存读写，均不重复加。")
    private var records=[TaskUsage](),taskKey=""
    private var chosenTask:(id:String,provider:UsageProvider)?
    private var lastRefresh:TimeInterval = -.infinity
    private var previewAt:TimeInterval?
    private(set) var refreshCount=0
    private(set) var latestSnapshot:TokenSpeedSnapshot?
    var suspended=false
    var selectedWindow:TokenSpeedWindow {[TokenSpeedWindow.seconds10,.seconds30,.seconds60][max(0,windowControl.selectedSegment)]}
    var selectedMetric:TokenSpeedMetric {[TokenSpeedMetric.total,.input,.output][max(0,metricControl.selectedSegment)]}
    var selectedProvider:UsageProvider? {UsageProvider(rawValue:provider.selectedItem?.representedObject as? String ?? "")}
    var scope:TokenSpeedScope {
        if let selected=chosenTask{return .task(id:selected.id,provider:selected.provider)}
        return selectedProvider.map{.provider($0)} ?? .all
    }
    var canDraw:Bool {window.isVisible && !window.isMiniaturized && !suspended}

    init(engine:TokenSpeedEngine){
        self.engine=engine
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:680),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        super.init()
        window.title="Token 星河 · Token 速度";window.minSize=NSSize(width:600,height:690);window.isReleasedWhenClosed=false;window.delegate=self
        root.wantsLayer=true;root.layer?.backgroundColor=NSColor(calibratedRed:0.035,green:0.045,blue:0.075,alpha:1).cgColor
        root.appearance=NSAppearance(named:.darkAqua);window.contentView=root
        let views:[NSView]=[heading,subtitle,providerLabel,taskLabel,windowLabel,provider,task,windowControl,totalRate,inputRate,outputRate,stateLabel,coverageLabel,reasonLabel,progress,chartTitle,chartUnit,metricControl,chart,legend,explanation]
        views.forEach{root.addSubview($0)}
        provider.addItem(withTitle:"全部来源");provider.lastItem?.representedObject=""
        for p in [UsageProvider.codex,.claude]{provider.addItem(withTitle:p.label);provider.lastItem?.representedObject=p.rawValue}
        task.addItem(withTitle:"全部记录");task.lastItem?.representedObject=""
        provider.target=self;provider.action=#selector(changeProvider)
        task.target=self;task.action=#selector(changeTask)
        windowControl.selectedSegment=0;windowControl.target=self;windowControl.action=#selector(changeControls)
        metricControl.selectedSegment=0;metricControl.target=self;metricControl.action=#selector(changeControls)
        provider.setAccessibilityLabel("筛选来源");task.setAccessibilityLabel("筛选记录")
        windowControl.setAccessibilityLabel("速率滑动窗口");metricControl.setAccessibilityLabel("图表指标")
        task.toolTip="每个来源最近最多80条本地记录；可选择主对话或子代理。"
        inputRate.toolTip="Codex缓存已包含在输入中；Claude输入包含缓存读取与写入，不重复相加。"
        reasonLabel.font=NSFont.systemFont(ofSize:11);reasonLabel.textColor = .secondaryLabelColor;reasonLabel.maximumNumberOfLines=2
        explanation.font=NSFont.systemFont(ofSize:11);explanation.textColor = .secondaryLabelColor
        progress.isIndeterminate=false;progress.minValue=0;progress.maxValue=1;progress.controlSize = .small;progress.isHidden=true
        root.onLayout={[weak self] in self?.layout()};layout();window.center()
    }
    private func layout(){
        let width=root.bounds.width,padding:CGFloat=24,usable=width-padding*2
        heading.frame=NSRect(x:padding,y:22,width:usable,height:31)
        subtitle.frame=NSRect(x:padding,y:60,width:usable,height:18)
        let sourceWidth:CGFloat=160,windowWidth:CGFloat=204,gap:CGFloat=16,taskWidth=max(140,usable-sourceWidth-windowWidth-gap*2)
        providerLabel.frame=NSRect(x:padding,y:96,width:sourceWidth,height:15)
        taskLabel.frame=NSRect(x:padding+sourceWidth+gap,y:96,width:taskWidth,height:15)
        windowLabel.frame=NSRect(x:width-padding-windowWidth,y:96,width:windowWidth,height:15)
        provider.frame=NSRect(x:padding-3,y:116,width:sourceWidth+6,height:27)
        task.frame=NSRect(x:padding+sourceWidth+gap-3,y:116,width:taskWidth+6,height:27)
        windowControl.frame=NSRect(x:width-padding-windowWidth,y:116,width:windowWidth,height:27)
        let column=(usable-32)/3
        for (i,view) in [totalRate,inputRate,outputRate].enumerated(){view.frame=NSRect(x:padding+CGFloat(i)*(column+16),y:171,width:column,height:114)}
        stateLabel.frame=NSRect(x:padding,y:304,width:usable,height:19)
        coverageLabel.frame=NSRect(x:padding,y:330,width:usable,height:16)
        progress.frame=NSRect(x:padding,y:352,width:usable,height:5)
        reasonLabel.frame=NSRect(x:padding,y:365,width:usable,height:31)
        chartTitle.frame=NSRect(x:padding,y:414,width:140,height:19)
        chartUnit.frame=NSRect(x:padding+141,y:416,width:75,height:16)
        metricControl.frame=NSRect(x:width-padding-180,y:409,width:180,height:27)
        let footerHeight:CGFloat=80,chartBottom=root.bounds.height-footerHeight
        chart.frame=NSRect(x:padding-4,y:445,width:usable+8,height:max(110,chartBottom-445))
        legend.frame=NSRect(x:padding,y:chartBottom+1,width:usable,height:16)
        explanation.frame=NSRect(x:padding,y:chartBottom+26,width:usable,height:47)
    }
    func show(){window.makeKeyAndOrderFront(nil);refresh(force:true);NSApp.activate(ignoringOtherApps:true)}
    func update(_ items:[TaskUsage],at:TimeInterval?=nil){
        records=items;previewAt=at
        guard canDraw else{return}
        refresh()
    }
    func refresh(force:Bool=false){
        guard canDraw else{return}
        let clock=ProcessInfo.processInfo.systemUptime
        guard force || clock-lastRefresh>=0.49 else{return};lastRefresh=clock
        refreshCount+=1;reloadTasks()
        let snapshot=engine.snapshot(scope:scope,window:selectedWindow,at:previewAt)
        let awaitingFirstRead=snapshot.sampledAt==nil
        latestSnapshot=snapshot
        subtitle.stringValue="本地日志每秒新增 · 最近 \(selectedWindow.rawValue) 秒滑动窗口"
        totalRate.update(rate:snapshot.rates.total,count:snapshot.cumulative.total,state:snapshot.metricStates.total)
        inputRate.update(rate:snapshot.rates.input,count:snapshot.cumulative.input,state:snapshot.metricStates.input)
        outputRate.update(rate:snapshot.rates.output,count:snapshot.cumulative.output,state:snapshot.metricStates.output)
        stateLabel.stringValue=awaitingFirstRead ? "正在读取本地记录…":tokenSpeedStateLabel(snapshot.state)
        stateLabel.textColor=[TokenSpeedState.gap,.unavailable].contains(snapshot.state) ? .systemOrange:.labelColor
        let c=snapshot.coverage
        let age=c.lastSampleAgeSeconds.map{String(format:"%.1f 秒前",$0)} ?? "未知"
        let good=c.lastGoodSampleAgeSeconds.map{String(format:"%.1f 秒前",$0)} ?? "未知"
        coverageLabel.stringValue=awaitingFirstRead ? "等待首次采样 · 完成后开始建立 \(c.windowSeconds) 秒窗口":"采样 \(String(format:"%.1f",min(c.observedSeconds,Double(c.windowSeconds)))) / \(c.windowSeconds) 秒  ·  \(c.recordCount) 条记录  ·  最新 \(age)  ·  最近有效 \(good)"
        coverageLabel.toolTip=coverageLabel.stringValue
        progress.isHidden=snapshot.state != .warming;progress.doubleValue=min(1,c.observedSeconds/Double(max(1,c.windowSeconds)))
        let explained=snapshot.reasons.map(speedReason)
        reasonLabel.stringValue=awaitingFirstRead ? "首次读取历史记录可能较慢，完成后开始建立窗口":explained.isEmpty ? "速率按完整窗口计算；未知或断档区间在曲线中留空。":Array(Set(explained)).sorted().joined(separator:"；")
        reasonLabel.toolTip=reasonLabel.stringValue
        chart.metric=selectedMetric;chart.now=previewAt ?? ProcessInfo.processInfo.systemUptime;chart.emptyText=awaitingFirstRead ? "正在读取本地记录…":tokenSpeedStateLabel(snapshot.state)
        if scope == .all {
            chart.series=snapshot.providers.map{TokenSpeedChartSeries(label:$0.provider=="claude" ? "Claude Code":"Codex",color:$0.provider=="claude" ? speedClaudeColor:speedCodexColor,points:$0.trend)}
            let text=NSMutableAttributedString()
            for (i,p) in snapshot.providers.enumerated(){if i>0{text.append(NSAttributedString(string:"      "))};text.append(NSAttributedString(string:"━━  \(p.provider=="claude" ? "Claude Code":"Codex")  ·  \(awaitingFirstRead ? "等待读取":tokenSpeedStateLabel(p.state))",attributes:[.foregroundColor:p.provider=="claude" ? speedClaudeColor:speedCodexColor,.font:NSFont.systemFont(ofSize:11)]))}
            legend.attributedStringValue=text
        }else{
            let source=chosenTask?.provider ?? selectedProvider ?? .codex
            chart.series=[TokenSpeedChartSeries(label:source.label,color:source == .claude ? speedClaudeColor:speedCodexColor,points:snapshot.trend)]
            legend.stringValue="\(source.label)  ·  \(chosenTask==nil ? "全部记录":"所选记录")  ·  未知区间留空"
            legend.textColor=source == .claude ? speedClaudeColor:speedCodexColor
        }
        chart.setAccessibilityLabel("最近120秒的\(metricControl.label(forSegment:metricControl.selectedSegment) ?? "总量")观测速率，横轴从过去到现在，纵轴 tokens 每秒；未知区间不连线")
        chart.needsDisplay=true
    }
    private func reloadTasks(){
        let filtered=records.filter{selectedProvider==nil || $0.provider==selectedProvider}
        let key=(selectedProvider?.rawValue ?? "all")+"|"+filtered.map{$0.provider.rawValue+":"+$0.id+":"+$0.label}.joined(separator:"|")
        guard key != taskKey else{return};taskKey=key
        task.removeAllItems();task.addItem(withTitle:"全部记录");task.lastItem?.representedObject=""
        for (i,t) in filtered.enumerated(){task.addItem(withTitle:"[\(t.provider.label)] \(String(t.label.prefix(60)))");task.lastItem?.representedObject="\(t.provider.rawValue)|\(t.id)";task.lastItem?.toolTip=t.label;if let chosen=chosenTask,chosen.id==t.id,chosen.provider==t.provider{task.selectItem(at:i+1)}}
        if let chosen=chosenTask,!filtered.contains(where:{$0.id==chosen.id && $0.provider==chosen.provider}){
            task.addItem(withTitle:"所选记录（当前未找到）");task.lastItem?.representedObject="\(chosen.provider.rawValue)|\(chosen.id)";task.selectItem(at:task.numberOfItems-1)
        }
    }
    @objc func changeProvider(){chosenTask=nil;taskKey="";refresh(force:true)}
    @objc func changeTask(){
        let key=task.selectedItem?.representedObject as? String ?? ""
        if let split=key.firstIndex(of:"|"),let p=UsageProvider(rawValue:String(key[..<split])){chosenTask=(String(key[key.index(after:split)...]),p)}else{chosenTask=nil}
        refresh(force:true)
    }
    @objc func changeControls(){refresh(force:true)}
    func windowDidDeminiaturize(_ notification:Notification){refresh(force:true)}
    func windowDidBecomeKey(_ notification:Notification){refresh(force:true)}
    func previewImage()->NSImage?{
        root.layoutSubtreeIfNeeded();root.displayIfNeeded()
        guard let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) else{return nil}
        root.cacheDisplay(in:root.bounds,to:bitmap)
        let image=NSImage(size:root.bounds.size);image.addRepresentation(bitmap);return image
    }
}
