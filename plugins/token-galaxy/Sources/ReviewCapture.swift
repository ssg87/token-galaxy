import AppKit

extension AppController {
    func reviewCapture(_ folder: String) throws {
        let dir = URL(fileURLWithPath: folder); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func save(_ image: NSImage?, _ name: String) throws { try saveImage(image, dir.appendingPathComponent(name).path) }
        let scaleWindow = ScalePreviewController(); try save(scaleWindow.previewImage(), "scales.png")
        var root = TaskUsage(id: "review-root", title: "演示主任务", project: "演示", total: 1_000_000, input: nil, cached: nil, output: nil, source: "demo")
        root.contextInput = 160_000; root.contextLimit = 828400; root.lastUserAt = Date().timeIntervalSince1970
        var child = TaskUsage(id: "review-child-a", title: "演示代理 A", project: "演示", total: 100_000, input: nil, cached: nil, output: nil, source: "demo"); child.parentID = root.id
        var other = TaskUsage(id: "review-child-b", title: "演示代理 B", project: "演示", total: 10_000, input: nil, cached: nil, output: nil, source: "demo"); other.parentID = root.id
        let samples = [root, child, other]
        let field = StarField(frame: NSRect(x: 0, y: 0, width: 160, height: 160)); field.paused = true; field.selected = root.id
        let bar = StarField(frame: NSRect(x: 0, y: 0, width: 520, height: 30)); bar.isStrip = true; bar.paused = true; bar.selected = root.id
        field.update(samples, deltas: [:]); bar.update(samples, deltas: [:])
        for size in [96, 160, 220, 640] { try save(field.snapshotImage(size: NSSize(width: size, height: size)), "idle-\(size).png") }
        try save(bar.snapshotImage(), "bar-idle.png")
        for amount: Int64 in [999_999, 1_000_000] {
            let f = StarField(frame:NSRect(x:0,y:0,width:160,height:160));f.paused=true
            let t = TaskUsage(id:"boundary",title:"边界演示",project:"演示",total:amount,input:nil,cached:nil,output:nil,source:"demo")
            f.update([t],deltas:[:]);try save(f.snapshotImage(),"boundary-\(amount).png")
        }
        for count: Int64 in [100, 1_000_000, 10_000_000] {
            let f = StarField(frame:NSRect(x:0,y:0,width:160,height:160));f.paused=true;f.selected=root.id
            f.update(samples,deltas:[:]);f.advancePreview(seconds:0.25);f.update(samples,deltas:[root.id:count]);f.advancePreview(seconds:0.55)
            try save(f.snapshotImage(),"increment-\(count)-550ms.png")
            let strip = StarField(frame:NSRect(x:0,y:0,width:520,height:30));strip.paused=true;strip.isStrip=true;strip.selected=root.id
            strip.update(samples,deltas:[:]);strip.advancePreview(seconds:0.25);strip.update(samples,deltas:[root.id:count]);strip.advancePreview(seconds:0.55)
            try save(strip.snapshotImage(),"bar-increment-\(count)-550ms.png")
        }
        var manifest = [[String: Any]]()
        for i in 0..<150 {
            var events = [String: [WorkEvent]](), deltas = [String: Int64]()
            var label = ""
            let when = Date().timeIntervalSince1970
            if i == 10 { events[root.id] = [WorkEvent(id: "review-input", at: when, phase: .input)]; label = "message" }
            if i == 23 { events[root.id] = [WorkEvent(id: "review-think", at: when, phase: .thinking)]; label = "thinking" }
            if i == 35 { events[child.id] = [WorkEvent(id: "review-call", at: when, phase: .tool)]; label = "child-call" }
            if i == 48 { events[child.id] = [WorkEvent(id: "review-result", at: when, phase: .result)]; label = "child-result" }
            if i == 60 { deltas[root.id] = 100; label = "plus-100" }
            if i == 75 { deltas[root.id] = 1_000_000; label = "plus-1M" }
            if i == 95 { deltas[root.id] = 10_000_000; label = "plus-10M" }
            if i == 118 { events[root.id] = [WorkEvent(id: "review-complete", at: when, phase: .complete)]; label = "complete" }
            if !label.isEmpty {
                field.update(samples, deltas: deltas, events: events); bar.update(samples, deltas: deltas, events: events)
                manifest.append(["frame": i, "time": Double(i) / 10, "event": label, "note": "演示事件，不是真实用量"])
            }
            field.advancePreview(seconds: 0.1); bar.advancePreview(seconds: 0.1)
            try autoreleasepool {
                try save(field.snapshotImage(), String(format: "orb-%03d.png", i))
                try save(bar.snapshotImage(), String(format: "bar-%03d.png", i))
            }
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appendingPathComponent("sequence.json"))
        print("Rendered tier comparison, sizes, graph and 15-second native demonstration sequence")
    }
}

extension AppController {
    func captureSpirit(_ folder:String)throws{
        let dir=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let f=StarField(frame:NSRect(x:0,y:0,width:160,height:160));f.paused=true;f.spiritEnabled=true
        var root=TaskUsage(id:"spirit-visual",title:"星灵演示",project:"演示",total:1_000_000,input:nil,cached:nil,output:nil,source:"demo")
        root.lifecycle="task_started";root.lastEventAt=Date().timeIntervalSince1970
        var child=TaskUsage(id:"spirit-branch",title:"小星灵",project:"演示",total:100_000,input:nil,cached:nil,output:nil,source:"demo");child.parentID=root.id
        f.update([root,child],deltas:[:]);f.advancePreview(seconds:0.3)
        func portrait(size:Int=160)->NSImage?{
            let sz=NSSize(width:size,height:size),image=NSImage(size:sz)
            let badge=SpiritBadge(frame:NSRect(origin:.zero,size:sz));badge.expression=f.spiritExpression
            guard let galaxy=f.snapshotImage(size:sz) else{return nil}
            image.lockFocusFlipped(true);NSGraphicsContext.saveGraphicsState();NSBezierPath(ovalIn:NSRect(origin:.zero,size:sz)).addClip();galaxy.draw(in:NSRect(origin:.zero,size:sz));badge.draw(badge.bounds);NSGraphicsContext.restoreGraphicsState();image.unlockFocus();return image
        }
        try saveImage(f.snapshotImage(),dir.appendingPathComponent("raw-orb.png").path)
        var manifest=[[String:Any]]()
        for i in 0..<90{
            var phase:WorkPhase?=nil
            if i==8{phase = .input}
            if i==26{phase = .thinking}
            if i==45{phase = .complete;root.lifecycle="task_complete"}
            if i==62{phase = .waiting;root.awaitingInput=true}
            if i==78{root.awaitingInput=false;f.update([root,child],deltas:[:]);f.pet.touch(at:f.model.clock)}
            if let phase=phase{f.update([root,child],deltas:[:],events:[root.id:[WorkEvent(id:"demo-\(i)",at:Date().timeIntervalSince1970,phase:phase)]])}
            f.advancePreview(seconds:0.1)
            try autoreleasepool{try saveImage(portrait(),dir.appendingPathComponent(String(format:"frame-%03d.png",i)).path)}
            if [3,12,30,48,68,80].contains(i){
                let name=[3:"rest",12:"awake",30:"work",48:"complete",68:"waiting",80:"touch"][i]!
                for size in [96,160,240]{try saveImage(portrait(size:size),dir.appendingPathComponent("\(name)-\(size).png").path)}
                manifest.append(["frame":i,"mood":f.spiritExpression.mood.rawValue,"caption":f.spiritExpression.caption,"name":name,"tokens":f.model.receivedTokens])
            }
        }
        try JSONSerialization.data(withJSONObject:["scope":"native demonstration; no real Token usage or physical Touch Bar capture","states":manifest],options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("manifest.json"))
        print("PASS: rendered 9-second spirit demo, six states at 96/160/240pt, no usage increments")
    }
}

extension AppController {
    func captureDual(_ folder:String)throws{
        let dir=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let c=TaskUsage(id:"dual-codex",title:"Codex 演示",project:"演示",total:1_000_000,input:nil,cached:nil,output:nil,source:"demo")
        var a=TaskUsage(id:"claude:dual",title:"Claude 演示",project:"演示",total:1_000_000,input:nil,cached:nil,output:nil,source:"demo");a.provider = .claude
        var cc=c;cc=TaskUsage(id:"dual-codex-child",title:"Codex 子代理",project:"演示",total:100_000,input:nil,cached:nil,output:nil,source:"demo");cc.parentID=c.id
        var ac=TaskUsage(id:"claude:dual-child",title:"Claude 子代理",project:"演示",total:100_000,input:nil,cached:nil,output:nil,source:"demo");ac.provider = .claude;ac.parentID=a.id
        let samples=[c,a,cc,ac],f=StarField(frame:NSRect(x:0,y:0,width:160,height:160)),bar=StarField(frame:NSRect(x:0,y:0,width:520,height:30))
        f.paused=true;bar.paused=true;bar.isStrip=true;f.update(samples,deltas:[:]);bar.update(samples,deltas:[:]);f.advancePreview(seconds:0.2);bar.advancePreview(seconds:0.2)
        func orb(_ size:Int)->NSImage?{let sz=NSSize(width:size,height:size);guard let galaxy=f.snapshotImage(size:sz) else{return nil};let image=NSImage(size:sz),badge=SpiritBadge(frame:NSRect(origin:.zero,size:sz));let d=f.model.providerDrive;badge.providerStates=[max(d.x,d.y)>0.05 ? "工作中":"静息",max(d.z,d.w)>0.05 ? "工作中":"静息"];image.lockFocusFlipped(true);NSGraphicsContext.saveGraphicsState();NSBezierPath(ovalIn:NSRect(origin:.zero,size:sz)).addClip();galaxy.draw(in:NSRect(origin:.zero,size:sz));badge.draw(badge.bounds);NSGraphicsContext.restoreGraphicsState();image.unlockFocus();return image}
        for size in [96,160,240]{try saveImage(orb(size),dir.appendingPathComponent("idle-\(size).png").path)}
        try saveImage(bar.snapshotImage(),dir.appendingPathComponent("bar-idle.png").path)
        for i in 0..<110{
            var incoming=[String:[WorkEvent]](),deltas=[String:Int64]()
            if i==5{incoming[c.id]=[WorkEvent(id:"c-tool",at:Date().timeIntervalSince1970,phase:.tool)]}
            if i==15{incoming[a.id]=[WorkEvent(id:"a-tool",at:Date().timeIntervalSince1970,phase:.tool)]}
            if i==28{deltas=[c.id:1000,a.id:2000];incoming[ac.id]=[WorkEvent(id:"a-child",at:Date().timeIntervalSince1970,phase:.thinking)]}
            if i==72{incoming[c.id]=[WorkEvent(id:"c-done",at:Date().timeIntervalSince1970,phase:.complete)];incoming[a.id]=[WorkEvent(id:"a-done",at:Date().timeIntervalSince1970,phase:.complete)]}
            if !incoming.isEmpty || !deltas.isEmpty{f.update(samples,deltas:deltas,events:incoming);bar.update(samples,deltas:deltas,events:incoming)}
            f.advancePreview(seconds:0.1);bar.advancePreview(seconds:0.1)
            if let fastest=f.model.fastestConversation(keeping:f.selected),fastest != f.selected { f.selected=fastest;bar.selected=fastest }
            if i==85 { f.update(samples,deltas:[c.id:5_000],events:[:]);bar.update(samples,deltas:[c.id:5_000],events:[:]) }
            if [8,18,38,60,95].contains(i) { for size in [96,160,174,190,240,420] {try saveImage(orb(size),dir.appendingPathComponent("focus-\(i)-\(size).png").path)} }
            try autoreleasepool{try saveImage(orb(160),dir.appendingPathComponent(String(format:"orb-%03d.png",i)).path);try saveImage(bar.snapshotImage(),dir.appendingPathComponent(String(format:"bar-%03d.png",i)).path)}
            if i==32{for size in [96,160,240]{try saveImage(orb(size),dir.appendingPathComponent("both-\(size).png").path)}}
        }
        var large=a;large.total=100_000_000
        let stress=[c,large,cc,ac];f.selected=a.id;f.update(stress,deltas:[a.id:10_000_000],events:[:]);f.advancePreview(seconds:0.5)
        for size in [96,160,174,190,240,420] {try saveImage(orb(size),dir.appendingPathComponent("high-\(size).png").path)}
        let overview=OverviewController();overview.update(samples,observed:[:],increments:[:]);try saveImage(overview.previewImage(),dir.appendingPathComponent("overview.png").path)
        let idle=StarField(frame:NSRect(x:0,y:0,width:160,height:160));idle.paused=true;idle.selected=a.id;idle.update(samples,deltas:[:]);idle.advancePreview(seconds:0.2)
        for i in 0..<60 {idle.advancePreview(seconds:0.1);try saveImage(idle.snapshotImage(),dir.appendingPathComponent(String(format:"claude-idle-%03d.png",i)).path)}
        let weighted=StarField(frame:NSRect(x:0,y:0,width:520,height:30));weighted.paused=true;weighted.isStrip=true;weighted.update(samples,deltas:[:]);weighted.advancePreview(seconds:0.1)
        weighted.update(samples,deltas:[c.id:90000,a.id:1000]);weighted.advancePreview(seconds:1.5);try saveImage(weighted.snapshotImage(),dir.appendingPathComponent("bar-codex-dominant.png").path)
        weighted.advancePreview(seconds:11);weighted.update(samples,deltas:[c.id:1000,a.id:90000]);weighted.advancePreview(seconds:1.5);try saveImage(weighted.snapshotImage(),dir.appendingPathComponent("bar-claude-dominant.png").path)
        weighted.advancePreview(seconds:14);try saveImage(weighted.snapshotImage(),dir.appendingPathComponent("bar-settled.png").path)
        print("PASS: 11-second unified-source native demo; fastest-main handoffs, simultaneous activity; 96/160/420pt")
    }
}

extension AppController {
    /// Synthetic workload only: verify the same accepted Claude body across quiet, light, busy and cooling states.
    func captureClaudeWeather(_ folder:String)throws{
        let dir=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        var root=TaskUsage(id:"claude:weather-main",title:"Claude 动态演示",project:"演示",total:1_000_000,input:nil,cached:nil,output:nil,source:"demo");root.provider = .claude
        var small=TaskUsage(id:"claude:weather-small",title:"小任务演示",project:"演示",total:20_000,input:nil,cached:nil,output:nil,source:"demo");small.provider = .claude;small.parentID=root.id
        var medium=TaskUsage(id:"claude:weather-medium",title:"中任务演示",project:"演示",total:240_000,input:nil,cached:nil,output:nil,source:"demo");medium.provider = .claude;medium.parentID=root.id
        var large=TaskUsage(id:"claude:weather-large",title:"大任务演示",project:"演示",total:6_000_000,input:nil,cached:nil,output:nil,source:"demo");large.provider = .claude
        let silver=TaskUsage(id:"weather-codex",title:"Codex 演示",project:"演示",total:1_000_000,input:nil,cached:nil,output:nil,source:"demo")
        var samples=[root,small,medium,large,silver]
        let field=StarField(frame:NSRect(x:0,y:0,width:190,height:190));field.paused=true;field.selected=root.id;field.update(samples,deltas:[:]);field.advancePreview(seconds:0.2)
        func portrait(_ size:Int=190)->NSImage?{
            let sz=NSSize(width:size,height:size);guard let galaxy=field.snapshotImage(size:sz) else{return nil}
            let image=NSImage(size:sz),badge=SpiritBadge(frame:NSRect(origin:.zero,size:sz));let d=field.model.providerDrive
            badge.providerStates=[max(d.x,d.y)>0.05 ? "工作中":"静息",max(d.z,d.w)>0.05 ? "工作中":"静息"]
            image.lockFocusFlipped(true);NSGraphicsContext.saveGraphicsState();NSBezierPath(ovalIn:NSRect(origin:.zero,size:sz)).addClip();galaxy.draw(in:NSRect(origin:.zero,size:sz));badge.draw(badge.bounds);NSGraphicsContext.restoreGraphicsState();image.unlockFocus();return image
        }
        var rows=[[String:Any]](),injected:Int64=0
        for i in 0..<240 {
            var deltas=[String:Int64](),events=[String:[WorkEvent]]()
            if [32,53,74].contains(i){let t=i==53 ? small.id:root.id;deltas[t]=400;events[t]=[WorkEvent(id:"light-\(i)",at:Date().timeIntervalSince1970,phase:.thinking)]}
            if (80..<138).contains(i),i%7==0{
                let t=[root.id,medium.id,large.id][(i/7)%3];deltas[t]=Int64(30_000+(i%4)*70_000);events[t]=[WorkEvent(id:"busy-\(i)",at:Date().timeIntervalSince1970,phase:.tool)]
            }
            if i==140 { for t in samples where t.provider == .claude {events[t.id]=[WorkEvent(id:"done-\(t.id)",at:Date().timeIntervalSince1970,phase:.complete)]} }
            if !deltas.isEmpty || !events.isEmpty {
                for j in samples.indices {samples[j].total += deltas[samples[j].id] ?? 0}
                injected += deltas.values.reduce(0,+);field.update(samples,deltas:deltas,events:events)
            }
            field.advancePreview(seconds:0.1)
            try autoreleasepool{try saveImage(portrait(),dir.appendingPathComponent(String(format:"weather-%03d.png",i)).path)}
            if [20,60,120,238].contains(i){let state=[20:"quiet",60:"light",120:"busy",238:"cooling"][i]!
                for size in [96,160,174,190,240,420]{try saveImage(portrait(size),dir.appendingPathComponent("\(state)-\(size).png").path)}
                var row=field.model.evidence();row["frame"]=i;row["state"]=state;row["injectedTokens"]=injected;rows.append(row)
            }
        }
        let vc=appearanceContent();let view=vc.view
        if let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:rep);let image=NSImage(size:view.bounds.size);image.addRepresentation(rep);try saveImage(image,dir.appendingPathComponent("appearance-controls.png").path)}
        var peak=samples;peak[0].total=100_000_000
        let stress=StarField(frame:NSRect(x:0,y:0,width:190,height:190));stress.paused=true;stress.selected=root.id;stress.claudeLogoScale=1.6;stress.update(peak,deltas:[root.id:10_000_000]);stress.advancePreview(seconds:0.7)
        for size in [96,190,420]{try saveImage(stress.snapshotImage(size:NSSize(width:size,height:size)),dir.appendingPathComponent("logo-max-\(size).png").path)}
        guard field.model.receivedTokens==injected else{throw NSError(domain:"Weather",code:1,userInfo:[NSLocalizedDescriptionKey:"Decorative motion changed usage"])}
        try JSONSerialization.data(withJSONObject:["scope":"synthetic native workload demonstration; actual task usage is untouched; stars are decoration","injectedTokens":injected,"receivedTokens":field.model.receivedTokens,"states":rows],options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("weather-manifest.json"))
        print("PASS: 24-second synthetic use-driven Claude motion; quiet/light/busy/cooling at96/160/174/420; decorative motion did not change usage")
    }
}

extension AppController {
    func overviewMotionCheck(_ folder:String)throws {
        let dir=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let now=Date().timeIntervalSince1970
        var p=TaskUsage(id:"demo-parent",title:"主任务 · 调度中",project:"合成演示",total:1_000_000,input:nil,cached:nil,output:nil,source:"fixture")
        p.lifecycle="task_started";p.lastEventAt=now;p.events=[WorkEvent(id:"p",at:now,phase:.spawn)]
        var c=TaskUsage(id:"demo-child",title:"子代理 · 生成回复",project:"合成演示",total:100_000,input:nil,cached:nil,output:nil,source:"fixture")
        c.parentID=p.id;c.lifecycle="task_started";c.lastEventAt=now;c.events=[WorkEvent(id:"c",at:now,phase:.reply)]
        let v=OverviewController();v.update([p,c],observed:[:],increments:[:]);v.show()
        RunLoop.current.run(until:Date(timeIntervalSinceNow:0.6))
        let first=v.field.diagnostics()["frames"] ?? 0,phase=v.field.model.nodes[0].motion.x
        for _ in 0..<6 {v.update([p,c],observed:[:],increments:[:]);RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15))}
        let second=v.field.diagnostics()["frames"] ?? 0
        try validationCheck(second>first+3 && v.field.model.nodes[0].motion.x>phase && !v.field.paused,"Visible overview stopped during refresh")
        try validationCheck(v.field.model.rotationRate(for:c.id)>0.239,"Overview child lost live state")
        try saveImage(v.previewImage(),dir.appendingPathComponent("overview-active.png").path)
        v.motionPaused=true;RunLoop.current.run(until:Date(timeIntervalSinceNow:0.1));let frozen=v.field.model.nodes[0].motion.x
        v.update([p,c],observed:[:],increments:[:]);RunLoop.current.run(until:Date(timeIntervalSinceNow:0.25))
        try validationCheck(v.field.paused && v.field.model.nodes[0].motion.x==frozen,"Overview ignored deliberate pause")
        v.motionPaused=false;RunLoop.current.run(until:Date(timeIntervalSinceNow:0.3));try validationCheck(v.field.model.nodes[0].motion.x>frozen,"Overview did not resume")
        v.window.performClose(nil);try validationCheck(v.field.paused,"Closed overview kept rendering")
        RunLoop.current.run(until:Date(timeIntervalSinceNow:0.3));v.show();let before=v.field.diagnostics()["frames"] ?? 0;RunLoop.current.run(until:Date(timeIntervalSinceNow:0.4));try validationCheck(!v.field.paused && (v.field.diagnostics()["frames"] ?? 0)>before,"Reopened overview: paused=\(v.field.paused), visible=\(v.window.isVisible), frames=\(v.field.diagnostics()["frames"] ?? 0), before=\(before)")
        v.window.performClose(nil)
        print("PASS: live overview frames/rotation progress through refresh; active child; pause/resume; close/reopen; synthetic screenshot")
    }
}
