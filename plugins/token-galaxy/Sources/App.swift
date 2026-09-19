import AppKit
import QuartzCore
final class AppController:NSObject,NSApplicationDelegate,NSTouchBarDelegate,NSMenuDelegate,NSWindowDelegate {
    let reader=TelemetryReader(),queue=DispatchQueue(label:"local.token-galaxy.read",qos:.utility)
    var hasTouchBar=HardwareCapabilities.touchBarAvailable
    var emptyNotice:NSTextField?
    private var previousProviderUI=[UsageProvider]()
    var visibleProviders:[UsageProvider]{[UsageProvider.codex,.claude].filter{p in tasks.contains{$0.provider==p} || ((p == .codex ? codexUsage?.records:claudeUsage?.records) ?? 0) > 0 || sourceErrors[p.rawValue] != nil}}
    var panel:FloatingPanel!,scene:StarField!,touchScene:StarField?,overview:OverviewController?
    var mapping:ScalePreviewController?
    var spiritPreview:SpiritPreviewController?,spiritBadge:SpiritBadge?
    var spiritEnabled:Bool{UserDefaults.standard.object(forKey:"spiritEnabled")==nil || UserDefaults.standard.bool(forKey:"spiritEnabled")}
    var status:NSStatusItem!,timer:Timer?,barCount:NSTextField?
    lazy var combinedReader=CombinedTelemetryReader(codex:reader)
    var codexUsage:AllUsage?,claudeUsage:AllUsage?,sourceErrors=[String:String]()
    var allUsage:AllUsage?
    var tasks=[TaskUsage](),previous=[String:TaskUsage](),observed=[String:Int64](),selected:String?
    var seenEvents=[String:Set<String>](),eventTrace=[[String:Any]](),sampleCount=0
    var lastSampleAt:TimeInterval=0,lastSampleMS:Double=0,lastStatusWrite:TimeInterval=0,readOK=true
    let probeDirectory=ProcessInfo.processInfo.environment["TOKEN_GALAXY_PROBE_DIR"]
    let observationStartedAt=Date().timeIntervalSince1970
    var originTimes=[String:TimeInterval](),originRequested=Set<String>(),originFinished=Set<String>()
    var idleFocus=IdleConversationFocus(),interactionMonitor:Any?,openMenus=0
    var selectionMode="manual"
    var probeFrame=0
    var reading=false,paused=false,visible=true,screenSleeping=false,capturePath:String?
    var appearancePopover:NSPopover?,detailPopover:NSPopover?,detailTitle:NSTextField?,detailText:NSTextField?
    var diameterInput:NSTextField?,logoInput:NSTextField?,logoSlider:NSSlider?,diameterStepper:NSStepper?,logoStepper:NSStepper?
    var diameterSlider:NSSlider?,alphaSlider:NSSlider?,diameterLabel:NSTextField?,alphaLabel:NSTextField?
    func opacityValue()->Double{UserDefaults.standard.object(forKey:"orbOpacity")==nil ? 0.95:UserDefaults.standard.double(forKey:"orbOpacity")}
    func applicationDidFinishLaunching(_ notification:Notification){
        NSApp.setActivationPolicy(.accessory);makeWindow();makeMenu()
        interactionMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.leftMouseDragged,.scrollWheel,.keyDown]){[weak self] event in self?.recordInteraction();return event}
        if let i=CommandLine.arguments.firstIndex(of:"--overview-check"),CommandLine.arguments.count>i+1{do{try overviewMotionCheck(CommandLine.arguments[i+1])}catch{fputs("Overview check failed: \(error)\n",stderr);exit(1)};NSApp.terminate(nil);return}
        if CommandLine.arguments.contains("--ui-smoke"){
            do{apply(combinedReader.snapshot().items);try uiSmoke();print("PASS: circular Metal rendering, size, opacity, details, hierarchy, Touch Bar") }catch{fputs("FAIL: \(error)\n",stderr);exit(1)};NSApp.terminate(nil);return
        }
        if let index=CommandLine.arguments.firstIndex(of:"--review-capture"),CommandLine.arguments.count>index+1{
            do{try reviewCapture(CommandLine.arguments[index+1])}catch{fputs("Review render failed: \(error)\n",stderr);exit(1)};NSApp.terminate(nil);return
        }
        if let i=CommandLine.arguments.firstIndex(of:"--spirit-capture"),CommandLine.arguments.count>i+1{do{try captureSpirit(CommandLine.arguments[i+1])}catch{fputs("Spirit capture failed: \(error)\n",stderr);exit(1)};NSApp.terminate(nil);return}
        if let i=CommandLine.arguments.firstIndex(of:"--claude-motion-capture"),CommandLine.arguments.count>i+1{do{try captureClaudeWeather(CommandLine.arguments[i+1])}catch{fputs("Claude motion capture failed: \(error)\n",stderr);exit(1)};NSApp.terminate(nil);return}
        if let i=CommandLine.arguments.firstIndex(of:"--dual-capture"),CommandLine.arguments.count>i+1{do{try captureDual(CommandLine.arguments[i+1])}catch{fputs("Dual capture failed: \(error)\n",stderr);exit(1)};NSApp.terminate(nil);return}
        if let i=CommandLine.arguments.firstIndex(of:"--capability-check"),CommandLine.arguments.count>i+1{do{try capabilityCheck(CommandLine.arguments[i+1])}catch{fputs("Capability check failed: \(error)\n",stderr);exit(1)};NSApp.terminate(nil);return}
        if let path=capturePath{do{apply(try reader.snapshot());try capture(path)}catch{fputs("Render failed: \(error)\n",stderr);exit(1)};NSApp.terminate(nil);return}
        if probeDirectory==nil{panel.orderFrontRegardless();if CommandLine.arguments.contains("--show-overview"){showOverview()};if CommandLine.arguments.contains("--show-mapping"){showMapping()}}else{scene.paused=true};refresh();timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self] _ in self?.refresh()};timer?.tolerance=0.05;if let timer=timer{RunLoop.main.add(timer,forMode:.common)}
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(sleeping),name:NSWorkspace.screensDidSleepNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(waking),name:NSWorkspace.screensDidWakeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(activeChanged),name:NSApplication.didBecomeActiveNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(activeChanged),name:NSApplication.didResignActiveNotification,object:nil)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{visible=true;panel.orderFrontRegardless();syncMotion();return true}
    func makeWindow(){
        let saved=UserDefaults.standard.double(forKey:"orbDiameter"),d=saved>=96 ? min(640,saved):190
        panel=FloatingPanel(contentRect:NSRect(x:0,y:0,width:d,height:d),styleMask:[.borderless,.nonactivatingPanel,.utilityWindow],backing:.buffered,defer:false);panel.barDelegate=self;panel.supportsTouchBar=hasTouchBar;panel.delegate=self;panel.title="Token 星河球";panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.level = .floating;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.alphaValue=opacityValue()
        let root=OrbRoot(frame:NSRect(x:0,y:0,width:d,height:d));root.wantsLayer=true;root.layer?.masksToBounds=true;root.layer?.cornerRadius=d/2;root.layer?.backgroundColor=NSColor.clear.cgColor
        scene=StarField(frame:root.bounds);scene.autoresizingMask=[.width,.height];scene.onInteraction={[weak self] in self?.recordInteraction()};scene.onSelect={[weak self] id in self?.select(id)};scene.onContext={[weak self] e in guard let self=self else{return};NSMenu.popUpContextMenu(self.makeContextMenu(),with:e,for:self.scene)};scene.onResize={[weak self] delta in self?.resizeOrb((self?.panel.frame.width ?? 320)+delta)};root.addSubview(scene);scene.spiritEnabled=spiritEnabled;let badge=SpiritBadge(frame:root.bounds);badge.autoresizingMask=[.width,.height];badge.isHidden = !spiritEnabled;root.addSubview(badge);spiritBadge=badge;panel.contentView=root
        let empty=NSTextField(wrappingLabelWithString:"正在读取本地会话…");empty.alignment = .center;empty.font=NSFont.systemFont(ofSize:11);empty.textColor = .secondaryLabelColor;empty.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(empty);NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo:root.centerXAnchor),empty.centerYAnchor.constraint(equalTo:root.centerYAnchor),empty.widthAnchor.constraint(equalTo:root.widthAnchor,multiplier:0.82)]);emptyNotice=empty
        if !panel.setFrameUsingName("TokenGalaxyOrb"),let s=NSScreen.main?.visibleFrame{panel.setFrameOrigin(NSPoint(x:s.maxX-d-24,y:s.maxY-d-24))};panel.setContentSize(NSSize(width:d,height:d))
    }
    func makeMenu(){status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);status.button?.image=NSImage(systemSymbolName:"sparkles",accessibilityDescription:"Token 星河球");status.button?.title=" —";status.button?.font=NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular);status.menu=makeContextMenu();let main=NSMenu();let item=NSMenuItem();item.submenu=makeContextMenu();main.addItem(item);NSApp.mainMenu=main;NSApp.touchBar=panel.makeTouchBar()}
    func makeContextMenu()->NSMenu{
        let menu=NSMenu();menu.delegate=self
        for provider in visibleProviders{
            let summary=provider == .codex ? codexUsage:claudeUsage
            let amount=summary.map{compactTokens($0.total)} ?? "读取中…"
            let item=NSMenuItem(title:"\(provider.label)    \(amount)",action:nil,keyEquivalent:"")
            item.attributedTitle=NSAttributedString(string:item.title,attributes:[.foregroundColor:provider == .claude ? NSColor(name:nil,dynamicProvider:{a in a.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(calibratedRed:0.94,green:0.59,blue:0.44,alpha:1):NSColor(calibratedRed:0.60,green:0.25,blue:0.14,alpha:1)}):NSColor.labelColor])
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let petItem=NSMenuItem(title:"星灵陪伴",action:#selector(toggleSpirit),keyEquivalent:"");petItem.target=self;petItem.state=spiritEnabled ? .on:.off;menu.addItem(petItem)
        let demo=NSMenuItem(title:"体验星灵的四种状态…",action:#selector(showSpiritPreview),keyEquivalent:"");demo.target=self;menu.addItem(demo);menu.addItem(.separator())
        let switcher=NSMenuItem(title:"切换主对话",action:nil,keyEquivalent:"");let conversations=NSMenu();conversations.delegate=self
        for task in tasks.filter({$0.isMainConversation}) {
            let title="[\(task.provider.label)] "+(task.label.count>48 ? String(task.label.prefix(48))+"…":task.label)
            let item=NSMenuItem(title:title,action:#selector(pickConversation(_:)),keyEquivalent:"");item.target=self;item.representedObject=task.id;item.toolTip=task.label;item.state=task.id==selected ? .on:.off;conversations.addItem(item)
        }
        switcher.submenu=conversations;menu.addItem(switcher)
        let hint=NSMenuItem(title:"闲置 1 分钟后自动跟随最快主对话",action:nil,keyEquivalent:"");menu.addItem(hint);menu.addItem(.separator())
        let actions:[(String,Selector)]=[("查看用量详情",#selector(showDetails)),("打开任务与代理工作总览",#selector(showOverview)),("用量与动效对照",#selector(showMapping)),("圆球大小与透明度…",#selector(showAppearance)),("返回全部任务",#selector(clearSelection)),(visible ? "隐藏圆球":"显示圆球",#selector(toggleWindow)),(paused ? "继续星河":"暂停星河",#selector(toggleAnimation)),("激活 Touch Bar 流动星河",#selector(activateBar)),("数据说明",#selector(showInfo)),("退出",#selector(quit))]
        for (name,action) in actions{if action == #selector(activateBar) && !hasTouchBar{continue};let i=NSMenuItem(title:name,action:action,keyEquivalent:action == #selector(quit) ? "q":"");i.target=self;menu.addItem(i)};return menu
    }
    func menuWillOpen(_ menu:NSMenu){openMenus+=1;recordInteraction();for i in menu.items{if i.action == #selector(toggleWindow){i.title=visible ? "隐藏圆球":"显示圆球"};if i.action == #selector(toggleAnimation){i.title=paused ? "继续星河":"暂停星河"}}}
    func menuDidClose(_ menu:NSMenu){openMenus=max(0,openMenus-1);recordInteraction()}
    func recordInteraction(now:TimeInterval=ProcessInfo.processInfo.systemUptime){idleFocus.interact(now:now);selectionMode="manual"}
    func setSelection(_ id:String?){selected=id;scene.selected=id;touchScene?.selected=id;overview?.field.selected=id;updateLabels()}
    @objc func pickConversation(_ sender:NSMenuItem){guard let id=sender.representedObject as? String else{return};recordInteraction();setSelection(id);if detailPopover?.isShown==true{requestOrigin()}}
    func select(_ id:String){
        if spiritEnabled{scene.pet.touch(at:scene.model.clock);updateSpirit()}
        recordInteraction()
        if detailPopover?.isShown==true,selected==id{closeDetails();return}
        let alreadyOpen=detailPopover?.isShown==true
        setSelection(id)
        if alreadyOpen{requestOrigin()}else{showDetails()}
    }
    func followFastestConversation(now:TimeInterval=ProcessInfo.processInfo.systemUptime){
        guard idleFocus.ready(now:now),openMenus==0,readOK,!paused,visible,!screenSleeping else{return}
        selectionMode="automatic"
        guard let id=scene.model.fastestConversation(keeping:selected),id != selected else{return}
        // Do not activate the app, open a popover or interrupt typing in Codex.
        detailPopover?.performClose(nil);setSelection(id);idleFocus.switched(now:now)
    }
    @objc func toggleSpirit(){recordInteraction();let enabled = !spiritEnabled;UserDefaults.standard.set(enabled,forKey:"spiritEnabled");scene.spiritEnabled=enabled;spiritBadge?.isHidden = !enabled;updateSpirit()}
    @objc func showSpiritPreview(){if spiritPreview==nil{spiritPreview=SpiritPreviewController()};spiritPreview?.show();syncMotion()}
    func updateSpirit(){
        let expression=scene.spiritExpression;spiritBadge?.expression=expression;spiritBadge?.isHidden = tasks.isEmpty || (!spiritEnabled && !scene.model.dualProvider)
        if scene.model.dualProvider {
            let d=scene.model.providerDrive
            spiritBadge?.providerStates=[max(d.x,d.y)>0.05 ? "工作中":"静息",max(d.z,d.w)>0.05 ? "工作中":"静息"]
        }else{spiritBadge?.providerStates=nil}
        scene.toolTip=spiritEnabled ? "星灵 · \(expression.caption)\n\(scene.model.shown.first?.title ?? "暂无对话")\n点击查看详情，右键切换主对话":nil
        scene.setAccessibilityLabel(spiritEnabled ? "星灵，\(expression.caption)，点击查看详情":"实时星河，点击查看详情")
    }
    func keepInteractionFocus(){
        NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(scene)
        if hasTouchBar {if panel.touchBar==nil{panel.touchBar=NSApp.touchBar ?? panel.makeTouchBar()};NSApp.touchBar=panel.touchBar};syncMotion()
    }
    @objc func closeDetails(){recordInteraction();detailPopover?.performClose(nil);keepInteractionFocus()}
    func requestOrigin(){
        guard let id=selected,let task=tasks.first(where:{$0.id==id}),task.provider == .codex,!task.logPath.isEmpty,task.segmentFirstAt==nil,!originRequested.contains(task.logIdentity) else{return}
        originRequested.insert(task.logIdentity)
        DispatchQueue.global(qos:.utility).async{[weak self] in guard let self=self else{return};let result=try? TelemetryReader(home:self.reader.home).resolveSegmentStart(task)
            DispatchQueue.main.async{self.originFinished.insert(task.logIdentity);if let date=result{self.originTimes[task.logIdentity]=date};self.updateLabels()}
        }
    }
    func segmentTime(_ task:TaskUsage)->String{
        if let value=task.segmentFirstAt ?? originTimes[task.logIdentity]{return displayTime(value)}
        return originFinished.contains(task.logIdentity) ? "未提供":"首次核对中…"
    }
    func displayTime(_ value:TimeInterval?)->String{
        guard let value=value else{return "未提供"};let formatter=DateFormatter();formatter.dateFormat="MM-dd HH:mm:ss";return formatter.string(from:Date(timeIntervalSince1970:value))
    }
    @objc func clearSelection(){recordInteraction();setSelection(nil)}
    @objc func showDetails(){
        recordInteraction()
        if detailPopover?.isShown==true{closeDetails();return}
        appearancePopover?.close();keepInteractionFocus();requestOrigin()
        if !visible{toggleWindow()};let vc=NSViewController();vc.view=NSView(frame:NSRect(x:0,y:0,width:390,height:430))
        let title=NSTextField(wrappingLabelWithString:"");title.font=NSFont.systemFont(ofSize:16,weight:.medium);title.frame=NSRect(x:18,y:362,width:316,height:46);vc.view.addSubview(title);detailTitle=title
        let close=NSButton(image:NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭详情")!,target:self,action:#selector(closeDetails));close.isBordered=false;close.toolTip="关闭详情（也可再次点击圆球）";close.frame=NSRect(x:348,y:384,width:26,height:26);vc.view.addSubview(close)
        let text=NSTextField(wrappingLabelWithString:"");text.font=NSFont.monospacedDigitSystemFont(ofSize:12,weight:.regular);text.frame=NSRect(x:18,y:60,width:354,height:292);vc.view.addSubview(text);detailText=text
        let open=NSButton(title:"打开任务与代理工作总览",target:self,action:#selector(showOverview));open.frame=NSRect(x:18,y:18,width:354,height:30);vc.view.addSubview(open);updateLabels()
        detailPopover?.close();let pop=NSPopover();pop.behavior = .applicationDefined;pop.animates=false;pop.contentViewController=vc;detailPopover=pop;pop.show(relativeTo:NSRect(x:scene.bounds.midX,y:scene.bounds.midY,width:1,height:1),of:scene,preferredEdge:.maxX)
    }
    @objc func showOverview(){
        detailPopover?.close();if overview==nil{overview=OverviewController();overview?.onSelect={[weak self] id in self?.recordInteraction();self?.setSelection(id)}};overview?.update(tasks,observed:observed,increments:[:]);overview?.field.selected=selected;overview?.motionPaused=paused || screenSleeping;overview?.show()
    }
    @objc func showMapping(){if mapping==nil{mapping=ScalePreviewController()};mapping?.show()}
    func resizeOrb(_ desired:CGFloat){
        let d=min(640,max(96,desired.rounded())),f=panel.frame
        panel.setFrame(NSRect(x:f.midX-d/2,y:f.midY-d/2,width:d,height:d),display:true)
        panel.contentView?.needsLayout=true;panel.contentView?.layoutSubtreeIfNeeded()
        UserDefaults.standard.set(Double(d),forKey:"orbDiameter");panel.saveFrame(usingName:"TokenGalaxyOrb")
        diameterSlider?.doubleValue=Double(d);diameterStepper?.doubleValue=Double(d);diameterInput?.stringValue="\(Int(d))"
    }
    func appearanceContent()->NSViewController {
        let hasClaude=visibleProviders.contains(.claude),offset:CGFloat=visibleProviders.contains(.claude) ? 0:-79
        logoSlider=nil;logoInput=nil;logoStepper=nil
        let vc=NSViewController();vc.view=NSView(frame:NSRect(x:0,y:0,width:322,height:266+offset));vc.view.wantsLayer=true;vc.view.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        func label(_ text:String,_ y:CGFloat){let l=NSTextField(labelWithString:text);l.font=NSFont.systemFont(ofSize:12,weight:.medium);l.frame=NSRect(x:18,y:y,width:286,height:20);vc.view.addSubview(l)}
        func input(_ value:Double,_ y:CGFloat,_ selector:Selector)->NSTextField{let t=NSTextField(frame:NSRect(x:212,y:y,width:60,height:24));t.stringValue="\(Int(value.rounded()))";t.alignment = .right;t.font=NSFont.monospacedDigitSystemFont(ofSize:13,weight:.regular);t.target=self;t.action=selector;vc.view.addSubview(t);return t}
        func stepper(_ value:Double,_ min:Double,_ max:Double,_ y:CGFloat,_ selector:Selector)->NSStepper{let v=NSStepper(frame:NSRect(x:280,y:y-1,width:19,height:27));v.minValue=min;v.maxValue=max;v.increment=1;v.valueWraps=false;v.doubleValue=value;v.target=self;v.action=selector;vc.view.addSubview(v);return v}
        label("球体大小",232+offset)
        let ds=FineSizeSlider(value:panel.frame.width,minValue:96,maxValue:640,target:self,action:#selector(diameterChanged));ds.frame=NSRect(x:18,y:199+offset,width:180,height:26);ds.isContinuous=true;vc.view.addSubview(ds);diameterSlider=ds
        diameterInput=input(panel.frame.width,201+offset,#selector(diameterEdited));diameterStepper=stepper(panel.frame.width,96,640,201+offset,#selector(diameterStepped))
        ds.setAccessibilityLabel("球体大小");diameterInput?.setAccessibilityLabel("球体直径");diameterStepper?.setAccessibilityLabel("球体大小，每次增减一")
        if hasClaude {
        label("Claude 图标大小 · %",153)
        let value=Double(scene.claudeLogoScale)*100,ls=FineSizeSlider(value:value,minValue:80,maxValue:160,target:self,action:#selector(logoChanged));ls.frame=NSRect(x:18,y:120,width:180,height:26);ls.isContinuous=true;vc.view.addSubview(ls);logoSlider=ls
        logoInput=input(value,122,#selector(logoEdited));logoStepper=stepper(value,80,160,122,#selector(logoStepped))
        ls.setAccessibilityLabel("Claude图标大小，百分比");logoInput?.setAccessibilityLabel("Claude图标比例，百分比");logoStepper?.setAccessibilityLabel("Claude图标大小，每格百分之一")
        }
        let a=NSTextField(labelWithString:"透明度  \(Int(100*(1-opacityValue())))%");a.frame=NSRect(x:18,y:70,width:286,height:20);vc.view.addSubview(a);alphaLabel=a
        let slider=NSSlider(value:100*(1-opacityValue()),minValue:0,maxValue:85,target:self,action:#selector(alphaChanged));slider.frame=NSRect(x:18,y:36,width:286,height:26);slider.isContinuous=true;vc.view.addSubview(slider);alphaSlider=slider
        let hint=NSTextField(labelWithString:"输入数值或用右侧箭头逐格微调");hint.font=NSFont.systemFont(ofSize:11);hint.textColor = .secondaryLabelColor;hint.frame=NSRect(x:18,y:9,width:286,height:17);vc.view.addSubview(hint)
        return vc
    }
    @objc func showAppearance(){
        if !visible{toggleWindow()};appearancePopover?.close();let pop=NSPopover();pop.behavior = .transient;pop.animates=false;pop.contentViewController=appearanceContent();appearancePopover=pop
        // A non-resizing status-button anchor prevents pointer/slider feedback while the orb changes size.
        if let button=status.button{pop.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)}
    }
    @objc func diameterChanged(){recordInteraction();resizeOrb(CGFloat(diameterSlider?.doubleValue ?? panel.frame.width))}
    @objc func diameterStepped(){recordInteraction();resizeOrb(CGFloat(diameterStepper?.doubleValue ?? panel.frame.width))}
    @objc func diameterEdited(){recordInteraction();let value=Double(diameterInput?.stringValue ?? "");resizeOrb(CGFloat(value?.isFinite==true ? value!:Double(panel.frame.width)))}
    func setLogoPercent(_ percent:Double){
        let value=min(160,max(80,percent.rounded()));UserDefaults.standard.set(value/100,forKey:"claudeLogoScale")
        [scene,touchScene,overview?.field,spiritPreview?.field].compactMap{$0}.forEach{$0.claudeLogoScale=Float(value/100)}
        mapping?.fields.forEach{$0.claudeLogoScale=Float(value/100)}
        logoSlider?.doubleValue=value;logoStepper?.doubleValue=value;logoInput?.stringValue="\(Int(value))"
    }
    @objc func logoChanged(){recordInteraction();setLogoPercent(logoSlider?.doubleValue ?? 140)}
    @objc func logoStepped(){recordInteraction();setLogoPercent(logoStepper?.doubleValue ?? 140)}
    @objc func logoEdited(){recordInteraction();let value=Double(logoInput?.stringValue ?? "");setLogoPercent(value?.isFinite==true ? value!:Double(scene.claudeLogoScale)*100)}
    @objc func alphaChanged(){let a=1-(alphaSlider?.doubleValue ?? 5)/100;UserDefaults.standard.set(a,forKey:"orbOpacity");panel.alphaValue=a;alphaLabel?.stringValue="透明度  \(Int((1-a)*100))%"}
    func syncMotion(){spiritPreview?.field.paused=paused || screenSleeping || !(spiritPreview?.window.isVisible ?? false) || (spiritPreview?.window.isMiniaturized ?? false);mapping?.fields.forEach{$0.paused=paused || screenSleeping || !(mapping?.window.isVisible ?? false) || (mapping?.window.isMiniaturized ?? false)};scene.paused=paused || !visible || screenSleeping;touchScene?.paused=paused || !NSApp.isActive || screenSleeping;overview?.motionPaused=paused || screenSleeping}
    @objc func toggleWindow(){visible.toggle();visible ? panel.orderFrontRegardless():panel.orderOut(nil);syncMotion()}
    @objc func toggleAnimation(){paused.toggle();syncMotion()}
    @objc func activateBar(){guard hasTouchBar else{return};if !visible{toggleWindow()};NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(scene);let bar=panel.makeTouchBar();panel.touchBar=bar;NSApp.touchBar=bar;touchScene?.paused=paused}
    @objc func sleeping(){screenSleeping=true;syncMotion()}
    @objc func waking(){screenSleeping=false;syncMotion();refresh()}
    @objc func activeChanged(){if !NSApp.isActive{detailPopover?.performClose(nil)};syncMotion()}
    @objc func quit(){NSApp.terminate(nil)}
    var dataInformation:String {
        var lines=["顶部显示已发现来源的本地用量合计。每个来源最多展示最近80条活动记录，主对话与子代理分别计数。"]
        if visibleProviders.contains(.codex){lines.append("Codex：近期日志优先，其余取本地索引；输入中已包含缓存，不重复相加。")}
        if visibleProviders.contains(.claude){lines.append("Claude Code：按请求ID和消息ID去重；输入含非缓存输入、缓存读取与写入。连线仅表示记录明确提供的所属主对话。")}
        lines.append("闲置1分钟后跟随活动最快的主对话。动效本身不会产生用量。本地记录不是账号账单或订阅额度。")
        if hasTouchBar{lines.append("Touch Bar通过右键菜单激活，遵循前台应用与系统调暗规则。")}
        return lines.joined(separator:"\n\n")
    }
    @objc func showInfo(){let alert=NSAlert();alert.messageText="Token Galaxy · 本地用量";alert.informativeText=dataInformation;alert.runModal()}
    @objc func nextTask(){recordInteraction();let conversations=tasks.filter{$0.isMainConversation};guard !conversations.isEmpty else{return};let old=conversations.firstIndex{$0.id==selected} ?? -1;setSelection(conversations[(old+1)%conversations.count].id)}
    func updateLabels(){
        updateSpirit()
        if openMenus==0{status.menu=makeContextMenu()}
        let task=tasks.first{$0.id==selected},total=task?.total ?? tasks.reduce(0){$0+$1.total};status.button?.title=allUsage.map{" "+compactTokens($0.total)} ?? " —";status.button?.toolTip=visibleProviders.map{p in "\(p.label)  \((p == .codex ? codexUsage:claudeUsage).map{compactTokens($0.total)} ?? "未知")"}.joined(separator:"\n")+"\n本地记录合计，非账单或订阅额度。"+(readOK ? "":"\n部分来源陈旧或正在读取。");status.button?.image=NSImage(systemSymbolName:readOK ? "sparkles":"exclamationmark.triangle",accessibilityDescription:readOK ? "Token 星河":"数据已陈旧");barCount?.stringValue=compactTokens(total)
        detailTitle?.stringValue=task.map{"[\($0.provider.label)] \($0.label)"} ?? "用量 · 最近 \(tasks.count) 条记录"
        if let t=task{
            let parent=t.parentID.flatMap{id in tasks.first{$0.id==id}?.title} ?? (t.parentID==nil ? "主任务":"父任务不在当前范围")
            if t.provider == .claude {
                detailText?.stringValue="请求去重后累计    \(compactTokens(t.total))\n首条本地用量    \(displayTime(t.segmentFirstAt))\n插件观测起点    \(displayTime(observationStartedAt))\n本次观测新增    +\(compactTokens(observed[t.id] ?? 0))\n\n输入（含缓存）    \(t.input.map(compactTokens) ?? "未知")\n其中缓存读取    \(t.cached.map(compactTokens) ?? "未知")\n其中缓存写入    \(t.cacheWrite.map(compactTokens) ?? "未知")\n输出    \(t.output.map(compactTokens) ?? "未知")\n单次上下文输入    \(t.contextInput.map(compactTokens) ?? "未知")\n\n当前阶段    \(t.stateLabel)\n节点类型    \(t.isMainConversation ? "主对话":"子智能体")\n项目    \(t.project)\n所属主对话    \(parent)\n\n同一请求的多个记录只计一次。\n缓存包含在输入中，不重复相加。"
            }else{detailText?.stringValue="当前计数段累计    \(compactTokens(t.total))\n本段首条记录    \(segmentTime(t))\n任务创建    \(displayTime(t.createdAt))\n插件观测起点    \(displayTime(observationStartedAt))\n单次上下文输入    \(t.contextInput.map(compactTokens) ?? "未知")\n报告上下文容量    \(t.contextLimit.map(compactTokens) ?? "未知")\n本次观测新增    +\(compactTokens(observed[t.id] ?? 0))\n输入    \(t.input.map(compactTokens) ?? "未知")\n缓存    \(t.cached.map(compactTokens) ?? "未知")\n输出    \(t.output.map(compactTokens) ?? "未知")\n\n当前阶段    \(t.stateLabel)\n节点类型    \(t.parentID==nil ? "主任务":"子智能体")\n项目    \(t.project)\n父级    \(parent)\n代理路径    \(t.agentPath ?? "主任务")\n\n累计仅含本任务当前计数段。\n缓存已含在输入中；子智能体分别计数。"}
        }else{detailText?.stringValue="各任务当前段合计    \(compactTokens(total))\n本次观测新增    +\(compactTokens(observed.values.reduce(0,+)))\n\n工作中    \(tasks.filter{$0.isWorking}.count)\n近期活动    \(tasks.filter{$0.stateLabel=="近期活动"}.count)\n子代理记录    \(tasks.filter{$0.parentID != nil}.count)\n\n打开大画面可查看项目、父子代理与用量。\n\n各任务计数段起点不同。\n本地记录不是订阅余额或最终账单。"}
    }
    func refresh(){
        guard !reading else{return};reading=true;let started=CACurrentMediaTime()
        queue.async{[weak self] in
            guard let self=self else{return};let sample=self.combinedReader.snapshot()
            DispatchQueue.main.async{
                self.reading=false;self.lastSampleMS=(CACurrentMediaTime()-started)*1000;self.sampleCount+=1
                self.codexUsage=sample.codex;self.claudeUsage=sample.claude;self.sourceErrors=sample.errors
                if let c=sample.codex,let a=sample.claude{self.allUsage=AllUsage(total:c.total+a.total,indexedTotal:c.indexedTotal,records:c.records+a.records,logOverrides:c.logOverrides+a.logOverrides)}else{self.allUsage=nil}
                self.readOK=sample.errors.isEmpty && sample.items.allSatisfy{$0.readIssue==nil && $0.pendingBytes==0}
                self.lastSampleAt=Date().timeIntervalSince1970;self.apply(sample.items)
                if self.probeDirectory != nil{
                    self.scene.advancePreview(seconds:0.5)
                    if let path=self.probeDirectory{try? self.saveImage(self.scene.snapshotImage(),URL(fileURLWithPath:path).appendingPathComponent(String(format:"frame-%03d.png",self.probeFrame)).path);self.probeFrame+=1}
                }
                self.writeRuntimeStatus()
            }
        }
    }
    func apply(_ items:[TaskUsage]){
        var increments=[String:Int64](),incoming=[String:[WorkEvent]]();let baseline = !previous.isEmpty
        let now=Date().timeIntervalSince1970
        for t in items{
            let known=seenEvents[t.id] ?? []
            if baseline{
                let fresh=t.events.filter{!known.contains($0.id) && now-$0.at<30 && $0.at<=now+2}
                if !fresh.isEmpty{
                    incoming[t.id]=fresh
                    for e in fresh{eventTrace.append(["taskID":t.id,"eventID":e.id,"phase":e.phase.label,"recordedAt":e.at,"detectedAt":now])}
                }
            }
            seenEvents[t.id]=Set(t.events.map{$0.id})
            let count=usageDelta(previous[t.id],t)
            if count>0{increments[t.id]=count;observed[t.id,default:0]+=count;eventTrace.append(["taskID":t.id,"phase":"Token新增","count":count,"recordedAt":t.lastUsageAt ?? now,"detectedAt":now])}
            previous[t.id]=t
        }
        let ids=Set(items.map{$0.id});previous=previous.filter{ids.contains($0.key)};seenEvents=seenEvents.filter{ids.contains($0.key)}
        if eventTrace.count>48{eventTrace.removeFirst(eventTrace.count-48)}
        tasks=items;let allStale=items.isEmpty || items.allSatisfy{$0.readIssue != nil || $0.pendingBytes>0};scene.stale=allStale;touchScene?.stale=allStale
        emptyNotice?.isHidden = !items.isEmpty;emptyNotice?.stringValue=sourceErrors.isEmpty ? "暂无本地会话\n开始任务后自动显示":"本地记录暂不可读\n稍后自动重试"
        if previousProviderUI != visibleProviders {appearancePopover?.performClose(nil);previousProviderUI=visibleProviders}
        scene.update(items,deltas:increments,events:incoming);touchScene?.update(items,deltas:increments,events:incoming)
        overview?.update(items,observed:observed,increments:increments,events:incoming)
        if let id=selected,!ids.contains(id){setSelection(nil)}
        followFastestConversation();updateLabels();if detailPopover?.isShown==true{requestOrigin()}
    }
    func writeRuntimeStatus(){
        let now=Date().timeIntervalSince1970
        guard probeDirectory != nil || now-lastStatusWrite>=1.5 else{return};lastStatusWrite=now
        let folder=probeDirectory.map{URL(fileURLWithPath:$0)} ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TokenGalaxy")
        do{
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let details=tasks.prefix(12).map{t->[String:Any] in ["provider":t.provider.rawValue,"taskID":t.id,"total":t.total,"lastUserAt":t.lastUserAt ?? 0,"lastEventAt":t.lastEventAt ?? 0,"contextInput":t.contextInput ?? -1,"contextLimit":t.contextLimit ?? -1,"state":t.stateLabel,"pendingBytes":t.pendingBytes]}
            let value:[String:Any]=["version":"0.8.1","capabilities":["touchBar":hasTouchBar,"providers":visibleProviders.map{$0.rawValue}],"claudeLogoScale":Double(scene.claudeLogoScale),"codexTokens":codexUsage?.total ?? -1,"claudeTokens":claudeUsage?.total ?? -1,"codexRecords":codexUsage?.records ?? 0,"claudeRecords":claudeUsage?.records ?? 0,"sourceErrors":sourceErrors,"menuTotalTokens":allUsage?.total ?? -1,"menuIndexedTokens":allUsage?.indexedTotal ?? -1,"menuRecordCount":allUsage?.records ?? 0,"menuLogOverrides":allUsage?.logOverrides ?? 0,"menuTitle":status.button?.title ?? "","selectedTaskID":selected ?? "","selectionMode":selectionMode,"idleSeconds":max(0,ProcessInfo.processInfo.systemUptime-idleFocus.lastInteraction),"fastestMainConversationID":scene.model.fastestConversation(keeping:selected) ?? "","observationStartedAt":observationStartedAt,"detailsOpen":detailPopover?.isShown ?? false,"applicationActive":NSApp.isActive,"pid":ProcessInfo.processInfo.processIdentifier,"timestamp":now,"polls":sampleCount,"readOK":readOK,"sampleMS":lastSampleMS,"lastGoodRead":lastSampleAt,"scene":scene.runtimeEvidence(),"touchBar":touchScene?.runtimeEvidence() ?? [:],"overview":overview?.field.runtimeEvidence() ?? [:],"overviewVisible":overview?.window.isVisible ?? false,"overviewMinimized":overview?.window.isMiniaturized ?? false,"recentEvents":eventTrace,"recentRecords":details,"observedTokens":observed.values.reduce(0,+),"opacity":Double(panel.alphaValue),"screenSleeping":screenSleeping,"reduceMotion":NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,"probeFrames":probeFrame]
            let bytes=try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys])
            try bytes.write(to:folder.appendingPathComponent("status.json"),options:.atomic)
        }catch{status.button?.toolTip="运行诊断暂不可写；用量读取继续"}
    }
    func touchBar(_ bar:NSTouchBar,makeItemForIdentifier id:NSTouchBarItem.Identifier)->NSTouchBarItem?{
        guard hasTouchBar else{return nil}
        let item=NSCustomTouchBarItem(identifier:id)
        if id.rawValue=="local.token-galaxy.flow"{item.customizationLabel="流动星河，点按切换任务";let holder=NSView(frame:NSRect(x:0,y:0,width:520,height:30));let field=StarField(frame:holder.bounds);field.isStrip=true;field.selected=selected;field.paused=paused || !NSApp.isActive;field.update(tasks,deltas:[:]);holder.addSubview(field);let tap=NSButton(frame:holder.bounds);tap.title="";tap.isBordered=false;tap.target=self;tap.action=#selector(nextTask);tap.setAccessibilityLabel("流动星河，点按切换任务");holder.addSubview(tap);holder.widthAnchor.constraint(equalToConstant:520).isActive=true;holder.heightAnchor.constraint(equalToConstant:30).isActive=true;touchScene=field;item.view=holder;return item}
        if id.rawValue=="local.token-galaxy.count"{let label=NSTextField(labelWithString:compactTokens(tasks.reduce(0){$0+$1.total}));label.font=NSFont.monospacedDigitSystemFont(ofSize:12,weight:.medium);label.widthAnchor.constraint(equalToConstant:74).isActive=true;barCount=label;item.view=label;return item}
        item.view=NSButton(title:"总览",target:self,action:#selector(showOverview));return item
    }
    func saveImage(_ image:NSImage?,_ path:String)throws{guard let image=image,let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) else{throw NSError(domain:"Render",code:1)};try png.write(to:URL(fileURLWithPath:path))}
    func capture(_ path:String)throws{let compare=ScalePreviewController();try saveImage(compare.previewImage(),path.replacingOccurrences(of:".png",with:"-scales.png"));scene.advancePreview(seconds:0.1);try saveImage(scene.snapshotImage(size:NSSize(width:220,height:220)),path);try saveImage(scene.snapshotImage(size:NSSize(width:96,height:96)),path.replacingOccurrences(of:".png",with:"-96px.png"));scene.advancePreview(seconds:0.35);try saveImage(scene.snapshotImage(size:NSSize(width:220,height:220)),path.replacingOccurrences(of:".png",with:"-motion.png"));let bar=panel.makeTouchBar()!;_ = touchBar(bar,makeItemForIdentifier:.init("local.token-galaxy.flow"));try saveImage(touchScene?.snapshotImage(),path.replacingOccurrences(of:".png",with:"-touchbar.png"));touchScene?.advancePreview(seconds:0.35);try saveImage(touchScene?.snapshotImage(),path.replacingOccurrences(of:".png",with:"-touchbar-motion.png"));let large=OverviewController();large.update(tasks,observed:observed,increments:[:]);try saveImage(large.previewImage(),path.replacingOccurrences(of:".png",with:"-overview.png"));if CommandLine.arguments.contains("--frames"){
            let folder=URL(fileURLWithPath:path).deletingPathExtension();try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            for i in 0..<48{scene.advancePreview(seconds:1/30);touchScene?.advancePreview(seconds:1/30);try saveImage(scene.snapshotImage(size:NSSize(width:140,height:140)),folder.appendingPathComponent(String(format:"orb-%03d.png",i)).path);try saveImage(touchScene?.snapshotImage(),folder.appendingPathComponent(String(format:"bar-%03d.png",i)).path)}
        };if let task=tasks.first{
            let proof=StarField(frame:NSRect(x:0,y:0,width:140,height:140));proof.paused=true;proof.update(tasks,deltas:[:]);proof.advancePreview(seconds:0.1);try saveImage(proof.snapshotImage(),path.replacingOccurrences(of:".png",with:"-idle.png"))
            proof.update(tasks,deltas:[:],messageEvents:[task.id]);proof.advancePreview(seconds:0.1);try saveImage(proof.snapshotImage(),path.replacingOccurrences(of:".png",with:"-message-fixture.png"))
            proof.update(tasks,deltas:[task.id:20000]);proof.advancePreview(seconds:0.1);try saveImage(proof.snapshotImage(),path.replacingOccurrences(of:".png",with:"-usage-fixture.png"))
        };print("Rendered native Metal orb, Touch Bar and agent overview; labelled message/usage fixtures")}
    func capabilityCheck(_ path:String)throws{
        var codex=TaskUsage(id:"cap-c",title:"fixture",project:"fixture",total:100,input:nil,cached:nil,output:nil,source:"fixture")
        codex.provider = .codex
        var claude=TaskUsage(id:"cap-a",title:"fixture",project:"fixture",total:100,input:nil,cached:nil,output:nil,source:"fixture");claude.provider = .claude
        var results=[[String:Any]]()
        for hardware in [false,true] {
            hasTouchBar=hardware;panel.supportsTouchBar=hardware
            for (name,items) in [("none",[TaskUsage]()),("codex",[codex]),("claude",[claude]),("both",[codex,claude])] {
                codexUsage=nil;claudeUsage=nil;sourceErrors=[:];apply(items)
                let titles=makeContextMenu().items.map{$0.title}
                let content=appearanceContent()
                let expectedClaude=items.contains{$0.provider == .claude}
                guard (logoInput != nil)==expectedClaude,
                      titles.contains(where:{$0.contains("Touch Bar")})==hardware,
                      (panel.makeTouchBar() != nil)==hardware,
                      titles.contains(where:{$0.hasPrefix("Claude")})==expectedClaude,
                      titles.contains(where:{$0.hasPrefix("Codex")})==items.contains(where:{$0.provider == .codex})
                else{throw NSError(domain:"CapabilityCheck",code:1,userInfo:[NSLocalizedDescriptionKey:name])}
                results.append(["case":name,"touchBar":hardware,"providers":visibleProviders.map{$0.rawValue},"settingsHeight":content.view.frame.height])
            }
        }
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        print("PASS: eight hardware/provider UI combinations")
    }
    func uiSmoke()throws{
        func check(_ b:Bool,_ text:String)throws{if !b{throw NSError(domain:"UI",code:1,userInfo:[NSLocalizedDescriptionKey:text])}}
        let originalTouchBar=hasTouchBar;hasTouchBar=true;panel.supportsTouchBar=true;defer{hasTouchBar=originalTouchBar;panel.supportsTouchBar=originalTouchBar}
        let f=panel.frame,old=UserDefaults.standard.object(forKey:"orbOpacity"),diameter=UserDefaults.standard.object(forKey:"orbDiameter"),savedLogo=UserDefaults.standard.object(forKey:"claudeLogoScale")
        defer{panel.setFrame(f,display:false);panel.saveFrame(usingName:"TokenGalaxyOrb");if let old=old{UserDefaults.standard.set(old,forKey:"orbOpacity")}else{UserDefaults.standard.removeObject(forKey:"orbOpacity")};if let diameter=diameter{UserDefaults.standard.set(diameter,forKey:"orbDiameter")}else{UserDefaults.standard.removeObject(forKey:"orbDiameter")};if let savedLogo=savedLogo{UserDefaults.standard.set(savedLogo,forKey:"claudeLogoScale")}else{UserDefaults.standard.removeObject(forKey:"claudeLogoScale")}}
        try check(scene.diagnostics()["metalReady"]==1,scene.rendererError ?? "Metal unavailable");resizeOrb(60);try check(panel.frame.width==96 && panel.frame.height==96,"minimum diameter failed");resizeOrb(420);try check(panel.frame.width==420 && panel.frame.height==420,"circle sizing failed");try check(panel.contentView?.layer?.cornerRadius==210,"circle mask failed")
        alphaSlider=NSSlider(value:40,minValue:0,maxValue:85,target:nil,action:nil);alphaChanged();try check(abs(panel.alphaValue-0.6)<0.001,"opacity failed")
        let image=scene.snapshotImage();try check(image != nil,"GPU offscreen render failed");let large=OverviewController();large.update(tasks,observed:observed,increments:[:]);try check(large.outline.numberOfRows==tasks.count,"agent outline lost records");large.motionPaused=true;large.update(tasks,observed:observed,increments:[:]);try check(large.field.paused,"overview pause was lost during refresh")
        let bar=panel.makeTouchBar()!;_ = touchBar(bar,makeItemForIdentifier:.init("local.token-galaxy.flow"));try check(touchScene?.diagnostics()["metalReady"]==1,"Touch Bar Metal failed")
        if let task=tasks.first{
            select(task.id);try check(detailPopover?.isShown==true,"first click did not open details")
            try check(detailPopover?.behavior == .applicationDefined,"popover still auto-dismisses before toggle click")
            let ownedBar=panel.touchBar
            select(task.id);try check(detailPopover?.isShown==false,"second click reopened instead of closing")
            try check(panel.touchBar === ownedBar,"closing details replaced the Touch Bar")
            select(task.id);try check(detailPopover?.isShown==true,"third click did not reopen")
            closeDetails();try check(detailPopover?.isShown==false,"close button did not close")
            print("PASS: open/close/reopen toggle; explicit close; same Touch Bar retained")
        }
        let quiet=TaskUsage(id:"ui-quiet",title:"UI quiet main",project:"fixture",total:100_000_000,input:nil,cached:nil,output:nil,source:"event")
        let fast=TaskUsage(id:"ui-fast",title:"UI fast main",project:"fixture",total:100,input:nil,cached:nil,output:nil,source:"event")
        var child=TaskUsage(id:"ui-child",title:"UI child",project:"fixture",total:1_000_000,input:nil,cached:nil,output:nil,source:"event");child.parentID=quiet.id
        detailPopover?.close();tasks=[quiet,child,fast];scene.update(tasks,deltas:[fast.id:100,child.id:10_000_000]);scene.advancePreview(seconds:0.1)
        select(quiet.id);select(fast.id)
        try check(selected==fast.id && detailPopover?.isShown==true,"Different-node click failed to switch open details")
        select(fast.id);try check(detailPopover?.isShown==false,"Same-node click failed to close details")
        setSelection(quiet.id);nextTask();try check(selected==fast.id,"Next main conversation included child")
        _ = touchBar(panel.makeTouchBar()!,makeItemForIdentifier:.init("local.token-galaxy.count"))
        allUsage=AllUsage(total:123_456_789,indexedTotal:123_456_789,records:178)
        setSelection(quiet.id);let totalTitle=status.button?.title
        setSelection(fast.id);try check(status.button?.title==totalTitle && totalTitle==" 123.46M","Menu total changed with selection")
        try check(barCount?.stringValue==compactTokens(fast.total),"Touch Bar selected-task count changed")
        allUsage=nil;updateLabels();try check(status.button?.title==" —","Missing aggregate displayed an invented zero")
        let menu=makeContextMenu();let choices=menu.items.first(where:{$0.title=="切换主对话"})?.submenu?.items.compactMap{$0.representedObject as? String} ?? []
        try check(choices==[quiet.id,fast.id],"Conversation menu includes child or misses main")
        setSelection(quiet.id);readOK=true;paused=false;visible=true;screenSleeping=false;openMenus=0;idleFocus=IdleConversationFocus(now:100)
        followFastestConversation(now:159.99);try check(selected==quiet.id,"Auto focus stole selection before one minute")
        openMenus=1;followFastestConversation(now:160);try check(selected==quiet.id,"Auto focus changed open menu")
        openMenus=0;let retainedBar=panel.touchBar;followFastestConversation(now:160)
        try check(selected==fast.id && scene.model.shown.first?.id==fast.id && touchScene?.selected==fast.id,"Idle switch failed to synchronize selection")
        try check(detailPopover?.isShown != true && panel.touchBar === retainedBar,"Auto follow opened details or replaced Touch Bar")
        for size:CGFloat in [96,160,420]{
            resizeOrb(size);scene.advancePreview(seconds:1)
            for (i,node) in scene.model.nodes.enumerated(){
                let p=1/(1-node.space.z*0.2)
                let point=NSPoint(x:size/2+CGFloat(node.space.x*p)*size/2,y:size/2-CGFloat(node.space.y*p)*size/2)
                try check(scene.taskID(at:point)==scene.model.shown[i].id,"Rendered node center missed at \(size)px")
            }
        }
        var claudeFixture=fast;claudeFixture.provider = .claude
        let filtered=OverviewController();filtered.update([quiet,claudeFixture],observed:[:],increments:[:]);filtered.provider.selectItem(at:2);filtered.changeProvider()
        try check(filtered.outline.numberOfRows==1 && filtered.field.tasks.first?.provider == .claude,"Source filter mixed providers")
        filtered.provider.selectItem(at:1);filtered.changeProvider();try check(filtered.field.tasks.first?.provider == .codex,"Codex source filter failed")
        print("PASS: different/same click; main-only menu and next; 60s app follow; menu protection; Touch Bar selection; 96/160/420px hit targets")
        var steps=OrbResizeSteps();var total:CGFloat=0
        for _ in 0..<100{total += steps.consume(0.5,precise:true,momentum:false,fine:false)}
        try check(abs(total)<=6 && abs(total)>=5,"Precise scrolling is too coarse or lost small deltas")
        try check(steps.consume(1000,precise:true,momentum:true,fine:false)==0,"Momentum resized orb")
        try check(abs(steps.consume(1000,precise:true,momentum:false,fine:false))<=2,"Large scroll jumped size")
        var sizingClaude=fast;sizingClaude.provider = .claude;tasks.append(sizingClaude)
        resizeOrb(190);showAppearance();RunLoop.current.run(until:Date(timeIntervalSinceNow:0.05))
        let popOrigin=appearancePopover?.contentViewController?.view.window?.frame.origin
        try check(popOrigin != nil,"Appearance popover not shown")
        for value in [191.0,192,200,220,210,195,190]{
            diameterSlider?.doubleValue=value;diameterChanged();RunLoop.current.run(until:Date(timeIntervalSinceNow:0.015))
            try check(panel.frame.width==value,"Slider value jumped to a limit")
            if let before=popOrigin,let after=appearancePopover?.contentViewController?.view.window?.frame.origin{try check(hypot(before.x-after.x,before.y-after.y)<2,"Sizing popover moved under the pointer")}
        }
        diameterStepper?.doubleValue=191;diameterStepped();try check(panel.frame.width==191,"One-pixel step failed")
        diameterInput?.stringValue="207";diameterEdited();try check(panel.frame.width==207,"Exact diameter entry failed")
        diameterInput?.stringValue="bad";diameterEdited();try check(panel.frame.width==207,"Invalid input changed diameter")
        let beforeLogo=panel.frame;logoInput?.stringValue="140";logoEdited();try check(abs(scene.claudeLogoScale-1.4)<0.001 && panel.frame==beforeLogo,"Logo control resized outer orb")
        logoStepper?.doubleValue=141;logoStepped();try check(abs(scene.claudeLogoScale-1.41)<0.001,"One-percent logo step failed")
        appearancePopover?.close();print("PASS: stable sizing-popover anchor; precise scroll accumulation/cap/no momentum; 1px/1percent steps; exact/invalid input; independent logo scale")
        try runVisualChecks()
    }
}
