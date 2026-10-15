import AppKit

enum TokenGalaxyRuntime {
    static let previewBundleID="local.token-galaxy.speed-preview"
    static var isPreview:Bool {Bundle.main.bundleIdentifier==previewBundleID}
    static var speedOnly:Bool {CommandLine.arguments.contains("--speed-only")}
    static func opensSpeedURL(_ url:URL)->Bool {
        url.scheme?.lowercased()=="token-galaxy" && url.host?.lowercased()=="speed" &&
        (url.path.isEmpty || url.path=="/") && url.query==nil && url.fragment==nil &&
        url.user==nil && url.password==nil && url.port==nil
    }
    static func explicitStateDirectory(_ arguments:[String]=CommandLine.arguments)throws->URL? {
        guard let i=arguments.firstIndex(of:"--state-dir") else{return nil}
        guard i+1<arguments.count,!arguments[i+1].isEmpty,!arguments[i+1].hasPrefix("--") else{throw TokenSpeedCLIError("--state-dir requires a directory")}
        return URL(fileURLWithPath:arguments[i+1],isDirectory:true).standardizedFileURL
    }
    static var stateDirectory:URL? {
        if let explicit=try? explicitStateDirectory(){return explicit}
        guard isPreview else{return nil}
        return Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("State",isDirectory:true)
    }
}

func runTokenSpeedURLChecks()throws {
    func require(_ condition:Bool,_ message:String)throws{if !condition{throw TokenSpeedCLIError(message)}}
    for value in ["token-galaxy://speed","token-galaxy://speed/"] {
        try require(TokenGalaxyRuntime.opensSpeedURL(URL(string:value)!),"Speed URL was rejected")
    }
    for value in ["https://speed","token-galaxy://other","token-galaxy://speed/other","token-galaxy://speed?task=other","token-galaxy://speed#other","token-galaxy://user@speed","token-galaxy://speed:80"] {
        try require(!TokenGalaxyRuntime.opensSpeedURL(URL(string:value)!),"Unexpected URL was accepted")
    }
    let types=Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String:Any]] ?? []
    let schemes=types.flatMap{$0["CFBundleURLSchemes"] as? [String] ?? []}
    try require(TokenGalaxyRuntime.isPreview ? schemes.isEmpty:schemes.contains("token-galaxy"),"URL scheme must be registered only by the formal app")
    print("PASS: speed URL allowlist, unrelated URL rejection, formal-only scheme registration")
}

private func speedDemoTask(_ id:String,provider:UsageProvider,total:Int64,input:Int64,output:Int64)->TaskUsage {
    var task=TaskUsage(id:id,title:provider == .codex ? "示例主任务":"示例子代理",project:"合成预览",total:total,input:input,cached:0,output:output,source:"synthetic-speed-demo")
    task.provider=provider;task.logIdentity="fixture-\(id)";task.lastUsageAt=1_700_000_000
    return task
}

private func speedDemoSample(_ items:[TaskUsage],errors:[String:String]=[:])->CombinedUsageSample {
    let codex=items.filter{$0.provider == .codex},claude=items.filter{$0.provider == .claude}
    return CombinedUsageSample(items:items,codex:AllUsage(total:codex.reduce(0){$0+$1.total},indexedTotal:0,records:codex.count),claude:AllUsage(total:claude.reduce(0){$0+$1.total},indexedTotal:0,records:claude.count),errors:errors)
}

private func saveSpeedImage(_ image:NSImage?,to url:URL)throws {
    guard let image=image,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) else{throw TokenSpeedCLIError("Native speed preview could not render")}
    try data.write(to:url,options:.atomic)
}

/// Only synthetic in-memory counters are used. No app delegate, readers, updater, or preferences are created.
func runTokenSpeedDemo(_ directory:String)throws {
    let folder=URL(fileURLWithPath:directory,isDirectory:true)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    func require(_ condition:Bool,_ message:String)throws{if !condition{throw TokenSpeedCLIError(message)}}
    let initial=TokenSpeedEngine(),initialController=TokenSpeedController(engine:initial)
    defer{initialController.window.orderOut(nil)}
    initialController.window.setContentSize(NSSize(width:940,height:700));initialController.window.orderFrontRegardless();initialController.update([],at:0);initialController.refresh(force:true)
    try require(initialController.latestSnapshot?.sampledAt==nil && initialController.stateLabel.stringValue=="正在读取本地记录…" && initialController.chart.emptyText=="正在读取本地记录…","Pending first read incorrectly claimed no local records")
    try saveSpeedImage(initialController.previewImage(),to:folder.appendingPathComponent("speed-initial-read.png"))
    initialController.window.orderOut(nil)
    let engine=TokenSpeedEngine(),controller=TokenSpeedController(engine:engine)
    defer{controller.window.orderOut(nil)}
    var items=[speedDemoTask("fixture-codex",provider:.codex,total:10_000,input:8_000,output:2_000),speedDemoTask("fixture-claude",provider:.claude,total:5_000,input:4_000,output:1_000)]
    for tick in 0...240 {
        let at=Double(tick)/2
        if tick>0 {
            let codexDelta:Int64=tick%18<9 ? 90:30,claudeDelta:Int64=tick%24<8 ? 60:15
            items[0].input!+=codexDelta*4/5;items[0].output!+=codexDelta/5;items[0].total+=codexDelta
            items[1].input!+=claudeDelta*4/5;items[1].output!+=claudeDelta/5;items[1].total+=claudeDelta
        }
        engine.ingest(speedDemoSample(items),at:at)
    }
    controller.window.setContentSize(NSSize(width:940,height:700));controller.window.orderFrontRegardless()
    controller.update(items,at:120);controller.refresh(force:true)
    try require(controller.latestSnapshot?.state == .live,"Active preview must be live")
    try require(controller.latestSnapshot?.rates.total != nil,"Active preview lost observed rate")
    try require(controller.chart.series.count==2,"All-provider trend must show two sources")
    let pointLow=controller.chart.point(at:110,rate:0),pointHigh=controller.chart.point(at:120,rate:10)
    try require(pointHigh.x>pointLow.x && pointHigh.y>pointLow.y,"Chart axes must increase toward now and higher rates")
    try saveSpeedImage(controller.previewImage(),to:folder.appendingPathComponent("speed-active-wide.png"))
    try engine.snapshot(at:120).encodedJSON().write(to:folder.appendingPathComponent("speed-active.json"),options:.atomic)
    controller.window.setContentSize(NSSize(width:600,height:740));controller.refresh(force:true)
    try saveSpeedImage(controller.previewImage(),to:folder.appendingPathComponent("speed-active-narrow.png"))
    // Exercise native controls, not a second independently calculated rate.
    controller.provider.selectItem(at:2);controller.changeProvider()
    try require(controller.scope == .provider(.claude) && controller.chart.series.count==1,"Source control failed")
    controller.task.selectItem(at:1);controller.changeTask()
    try require(controller.scope == .task(id:"fixture-claude",provider:.claude),"Task control failed")
    controller.windowControl.selectedSegment=1;controller.metricControl.selectedSegment=2;controller.changeControls()
    try require(controller.latestSnapshot?.windowSeconds==30 && controller.chart.metric == .output,"Window or metric control failed")
    controller.provider.selectItem(at:0);controller.changeProvider();controller.windowControl.selectedSegment=0;controller.metricControl.selectedSegment=0
    controller.changeControls()
    _ = controller.previewImage()
    controller.window.orderOut(nil);let hiddenRefresh=controller.refreshCount,hiddenDraw=controller.chart.drawCount
    controller.update(items,at:120);controller.refresh(force:true)
    try require(controller.refreshCount==hiddenRefresh && controller.chart.drawCount==hiddenDraw,"Hidden speed window performed a redraw")
    controller.window.setContentSize(NSSize(width:940,height:700));controller.window.orderFrontRegardless()
    for tick in 241...264{engine.ingest(speedDemoSample(items),at:Double(tick)/2)}
    controller.update(items,at:132);controller.refresh(force:true)
    try require(controller.latestSnapshot?.state == .idle && controller.latestSnapshot?.rates.total==0,"Healthy idle must be a known zero")
    try saveSpeedImage(controller.previewImage(),to:folder.appendingPathComponent("speed-idle.png"))
    try engine.snapshot(at:132).encodedJSON().write(to:folder.appendingPathComponent("speed-idle.json"),options:.atomic)
    engine.ingest(speedDemoSample(items),at:140)
    controller.update(items,at:140);controller.refresh(force:true)
    try require(controller.latestSnapshot?.state == .gap && controller.latestSnapshot?.rates.total==nil,"Missing sampling must remain a gap")
    try saveSpeedImage(controller.previewImage(),to:folder.appendingPathComponent("speed-gap.png"))
    try engine.snapshot(at:140).encodedJSON().write(to:folder.appendingPathComponent("speed-gap.json"),options:.atomic)
    for tick in 281...304{engine.ingest(speedDemoSample(items),at:Double(tick)/2)}
    controller.update(items,at:152);controller.refresh(force:true)
    try require(controller.latestSnapshot?.state == .idle,"Recovered sampling must regain a complete window")
    try require(controller.chart.series.contains{controller.chart.segments($0.points).count>=2},"Unknown intervals must break the line rather than connect through zero")
    try saveSpeedImage(controller.previewImage(),to:folder.appendingPathComponent("speed-recovered.png"))
    try engine.snapshot(at:152).encodedJSON().write(to:folder.appendingPathComponent("speed-recovered.json"),options:.atomic)
    let empty=TokenSpeedEngine(),emptyController=TokenSpeedController(engine:empty)
    defer{emptyController.window.orderOut(nil)}
    empty.ingest(speedDemoSample([]),at:0)
    emptyController.window.setContentSize(NSSize(width:940,height:700));emptyController.window.orderFrontRegardless();emptyController.update([],at:0);emptyController.refresh(force:true)
    try require(emptyController.latestSnapshot?.state == .notFound && emptyController.latestSnapshot?.rates.total==nil && emptyController.stateLabel.stringValue=="暂无本地记录","Confirmed empty state must not invent a zero or remain pending")
    try saveSpeedImage(emptyController.previewImage(),to:folder.appendingPathComponent("speed-empty.png"))
    try empty.snapshot(at:0).encodedJSON().write(to:folder.appendingPathComponent("speed-empty.json"),options:.atomic)
    let warming=TokenSpeedEngine(),warmingController=TokenSpeedController(engine:warming)
    defer{warmingController.window.orderOut(nil)}
    for tick in 0...8{warming.ingest(speedDemoSample(items),at:Double(tick)/2)}
    warmingController.window.setContentSize(NSSize(width:940,height:700));warmingController.window.orderFrontRegardless();warmingController.update(items,at:4);warmingController.refresh(force:true)
    try require(warmingController.latestSnapshot?.state == .warming && warmingController.totalRate.value.stringValue=="—","Short sampling must be warming, with no false rate")
    try saveSpeedImage(warmingController.previewImage(),to:folder.appendingPathComponent("speed-warming.png"))
    try warming.snapshot(at:4).encodedJSON().write(to:folder.appendingPathComponent("speed-warming.json"),options:.atomic)
    let partial=TokenSpeedEngine(),partialController=TokenSpeedController(engine:partial)
    defer{partialController.window.orderOut(nil)}
    var partialItems=[TaskUsage]()
    for provider in [UsageProvider.codex,.claude]{for id in 0..<80{
        var task=speedDemoTask("partial-\(provider.rawValue)-\(id)",provider:provider,total:10_000,input:8_000,output:2_000)
        if provider == .codex && id>=37{task.readIssue="synthetic missing record"}
        partialItems.append(task)
    }}
    for tick in 0...240{
        if tick>0{for i in partialItems.indices{partialItems[i].total+=5;partialItems[i].input!+=4;partialItems[i].output!+=1}}
        partial.ingest(speedDemoSample(partialItems),at:Double(tick)/2)
    }
    partialController.window.setContentSize(NSSize(width:940,height:700));partialController.window.orderFrontRegardless();partialController.update(partialItems,at:120);partialController.refresh(force:true)
    try require(partialController.latestSnapshot?.rates.total==1170 && partialController.latestSnapshot?.coverage.partial==true && partialController.latestSnapshot?.coverage.includedRecordCount==117 && partialController.latestSnapshot?.coverage.missingRecordCount==43,"Partial preview must continue the 117 healthy records")
    let partialText="部分统计：已统计117/160条，缺失或不可读43条未计入"
    try require(partialController.stateLabel.stringValue==partialText,"Partial coverage must be explained explicitly")
    try saveSpeedImage(partialController.previewImage(),to:folder.appendingPathComponent("speed-partial-wide.png"))
    partialController.window.setContentSize(NSSize(width:600,height:740));partialController.refresh(force:true)
    _ = partialController.previewImage()
    let textWidth=(partialText as NSString).size(withAttributes:[.font:partialController.stateLabel.font!]).width
    try require(textWidth<=partialController.stateLabel.bounds.width,"Narrow partial coverage text must not truncate its counts")
    try saveSpeedImage(partialController.previewImage(),to:folder.appendingPathComponent("speed-partial-narrow.png"))
    try partial.snapshot(at:120).encodedJSON().write(to:folder.appendingPathComponent("speed-partial.json"),options:.atomic)
    let assertions:[String:Any]=["syntheticOnly":true,"initialReadDoesNotClaimEmpty":true,"sourceSwitch":true,"taskSwitch":true,"windowSwitch":true,"metricSwitch":true,"hiddenWindowNoRedraw":true,"axesPastToNowAndLowToHigh":true,"unknownIntervalsBreakLine":true,"idleIsKnownZero":true,"gapIsUnknown":true,"emptyIsUnknown":true,"warmingHasNoRate":true,"snapshotIsSingleEngineSource":true,"partialHealthy117Of160":true,"partialExcluded43Explicit":true,"partialNarrowCountsVisible":true]
    try JSONSerialization.data(withJSONObject:assertions,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("speed-ui-checks.json"),options:.atomic)
    print("PASS: native token speed previews, source/task/window/metric controls, hidden redraw guard, chart direction, warming/idle/gap/empty states")
}
