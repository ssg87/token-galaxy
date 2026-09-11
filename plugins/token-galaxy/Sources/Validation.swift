import Foundation

func validationCheck(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "Validation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func runVisualChecks() throws {
    try runClaudeChecks()
    try runSpiritChecks();try runInputWaitChecks()
    try runIdleFocusChecks()
    try runUnifiedFocusChecks();try runRecentRiverChecks()
    let scales = [100, 100_000, 999_999, 1_000_000, 10_000_000].map { TokenScale.cumulative(Int64($0)) }
    try validationCheck(scales.map { $0.tier } == [0, 2, 2, 3, 4], "Token tiers do not cross the 1M boundary")
    try validationCheck(scales[0].grains < scales[1].grains && scales[2].grains < scales[3].grains && scales[3].grains < scales[4].grains, "Tier density is not distinct")
    try validationCheck(scales[3].radius > scales[2].radius * 1.2, "1M structure is indistinguishable from less than 1M")
    let impulses = [100, 1_000_000, 10_000_000].map { TokenScale.increment(Int64($0)) }
    try validationCheck(impulses[0].streams < impulses[1].streams && impulses[1].streams < impulses[2].streams, "100/1M/10M bursts saturate at the same stream count")
    try validationCheck(impulses[0].strength < impulses[1].strength && impulses[1].strength < impulses[2].strength, "Large increment strengths saturate early")
    let root = TaskUsage(id: "root", title: "root", project: "fixture", total: 1_000_000, input: nil, cached: nil, output: nil, source: "event")
    var a = TaskUsage(id: "a", title: "a", project: "fixture", total: 100_000, input: nil, cached: nil, output: nil, source: "event"); a.parentID = root.id
    var b = TaskUsage(id: "b", title: "b", project: "fixture", total: 10_000, input: nil, cached: nil, output: nil, source: "event"); b.parentID = root.id
    let unrelated = TaskUsage(id: "other", title: "other", project: "fixture", total: 10_000, input: nil, cached: nil, output: nil, source: "event")
    let model = GalaxyModel(); model.selected = root.id
    model.update([root, a, b, unrelated], deltas: [:], events: [:])
    try validationCheck(model.links.count == 2, "Graph invented or lost a parent-child relation")
    let message = WorkEvent(id: "message", at: Date().timeIntervalSince1970, phase: .input)
    model.update([root, a, b, unrelated], deltas: [:], events: [root.id: [message]])
    for _ in 0..<3 { model.step(1 / 30) }
    try validationCheck(model.workDrive > 0.7 && model.tokenDrive == 0 && model.receivedTokens == 0, "Message feedback fabricated token usage or failed to respond")
    try validationCheck(model.nodes[0].motion.z == Float(WorkPhase.input.rawValue), "Input direction is not carried to renderer")
    let tool = WorkEvent(id: "tool", at: Date().timeIntervalSince1970, phase: .tool)
    model.update([root, a, b, unrelated], deltas: [:], events: [a.id: [tool]])
    for _ in 0..<3 { model.step(1 / 30) }
    try validationCheck(model.links.contains { $0.style.x > 0.7 }, "Child activity did not light its real branch")
    let received = model.receivedEvents
    model.update([root, a, b, unrelated], deltas: [:], events: [:])
    try validationCheck(model.receivedEvents == received, "Refresh replayed events")
    for _ in 0..<300 { model.step(1 / 30) }
    try validationCheck(model.workDrive < 0.001 && model.tokenDrive == 0, "Idle failed to settle")
    model.update([root, a, b, unrelated], deltas: [root.id: 100], events: [:])
    for _ in 0..<3 { model.step(1 / 30) }
    try validationCheck(model.tokenDrive > 0.4 && model.receivedTokens == 100, "100 Tokens do not have a visible floor")
    let phase = model.nodes[0].motion.x, position = model.nodes[0].space
    model.step(0.1, reduceMotion: true)
    try validationCheck(model.nodes[0].motion.x == phase && model.nodes[0].space == position, "Reduce Motion moved the galaxy")
    print("PASS: tiers 100/<1M/1M/10M; non-saturating increments; real parent edges; messages vs usage; child feedback; idle and reduced motion")
}
func runIdleFocusChecks() throws {
    let quiet=TaskUsage(id:"quiet-root",title:"Quiet main",project:"fixture",total:100_000_000,input:nil,cached:nil,output:nil,source:"event")
    let active=TaskUsage(id:"active-root",title:"Active main",project:"fixture",total:100,input:nil,cached:nil,output:nil,source:"event")
    var child=TaskUsage(id:"fast-child",title:"Child",project:"fixture",total:1_000_000,input:nil,cached:nil,output:nil,source:"event");child.parentID=quiet.id
    var orphan=child;orphan.parentID=nil;orphan.subagentRecord=true
    let model=GalaxyModel();model.selected=quiet.id
    model.update([quiet,active,child],deltas:[active.id:100,child.id:10_000_000],events:[:]);model.step(0.1)
    try validationCheck(model.rotationRate(for:child.id)>model.rotationRate(for:active.id),"Fixture child is not fastest")
    try validationCheck(model.fastestConversation(keeping:quiet.id)==active.id,"Auto focus chose a child, large total, or parent by child activity")
    var idle=IdleConversationFocus(now:100)
    try validationCheck(!idle.ready(now:159.999) && idle.ready(now:160),"One-minute boundary failed")
    idle.switched(now:160)
    try validationCheck(!idle.ready(now:164.999) && idle.ready(now:165),"Switch cooldown failed")
    idle.interact(now:166)
    try validationCheck(!idle.ready(now:225.999) && idle.ready(now:226),"Manual interaction did not restart the full minute")
    model.selected=active.id
    try validationCheck(model.shown.first?.id==active.id && model.nodes.first?.visual.y==1,"Selected lead did not rebuild immediately")
    model.update([quiet,active,orphan],deltas:[orphan.id:10_000_000],events:[:]);model.step(0.1)
    try validationCheck(model.fastestConversation(keeping:quiet.id)==active.id,"Orphan subagent was treated as a main conversation")
    for _ in 0..<360{model.step(1/30)}
    try validationCheck(model.fastestConversation(keeping:active.id)==nil,"All idle caused unnecessary switching")
    model.update([quiet,active],deltas:[quiet.id:100,active.id:100],events:[:]);model.step(0.1)
    try validationCheck(model.fastestConversation(keeping:active.id)==active.id,"Equal speeds did not preserve selection")
    model.update([],deltas:[:],events:[:])
    try validationCheck(model.fastestConversation(keeping:active.id)==nil && model.nodes.isEmpty,"Empty/removed task handling failed")
    print("PASS: root-only actual rotation ranking; no child aggregation; 60s boundary/reset; 5s cooldown; equal/idle/missing candidates")
}
func runTelemetryChecks() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("token-galaxy-reader-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let log = folder.appendingPathComponent("fixture.jsonl")
    func line(_ kind: String, _ payload: [String: Any], _ time: String) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["timestamp": time, "type": kind, "payload": payload]); data.append(10); return data
    }
    let seed = try line("event_msg", ["type": "token_count", "info": ["total_token_usage": ["total_tokens": 100]]], "2026-09-09T12:00:00.000Z")
    try seed.write(to: log)
    let reader = TelemetryReader(home: folder); _ = reader.latest(log)
    let message = try line("response_item", ["type": "message", "role": "user", "content": []], "2026-09-09T12:00:01.000Z")
    let huge = try line("response_item", ["type": "function_call_output", "output": String(repeating: "x", count: 400_000)], "2026-09-09T12:00:02.000Z")
    let usage = try line("event_msg", ["type": "token_count", "info": ["total_token_usage": ["total_tokens": 200], "last_token_usage": ["input_tokens": 100], "model_context_window": 828400]], "2026-09-09T12:00:03.000Z")
    let file = try FileHandle(forWritingTo: log); try file.seekToEnd(); try file.write(contentsOf: message + huge + usage); try file.close()
    let parsed = reader.latest(log)
    try validationCheck(parsed.lastUserAt != nil && parsed.total == 200 && parsed.contextLimit == 828400 && parsed.contextInput == 100, "Message before >128KB output was lost, or context was conflated with totals")
    let eventCount = parsed.events.count
    try validationCheck(reader.latest(log).events.count == eventCount, "Unchanged log replayed its records")
    let next = try line("response_item", ["type": "message", "role": "user", "content": []], "2026-09-09T12:00:04.000Z")
    let split = next.count / 2
    let handle = try FileHandle(forWritingTo: log); try handle.seekToEnd(); try handle.write(contentsOf: next.prefix(split))
    try validationCheck(reader.latest(log).lastUserAt == parsed.lastUserAt, "Partial line was parsed as complete")
    try handle.write(contentsOf: next.suffix(next.count - split)); try handle.close()
    try validationCheck((reader.latest(log).lastUserAt ?? 0) > (parsed.lastUserAt ?? 0), "Split message was lost after its newline arrived")
    let reset=try line("event_msg",["type":"token_count","info":["total_token_usage":["total_tokens":50]]],"2026-09-09T12:00:05.000Z")
    let after=try line("event_msg",["type":"token_count","info":["total_token_usage":["total_tokens":60]]],"2026-09-09T12:00:06.000Z")
    let more=try FileHandle(forWritingTo:log);try more.seekToEnd();try more.write(contentsOf:reset+huge+after);try more.close()
    let updated=reader.latest(log)
    try validationCheck(updated.segmentFirstAt != nil,"counter reset did not establish a new segment")
    let cold=TelemetryReader(home:folder);let coldValue=cold.latest(log)
    var sample=TaskUsage(id:"origin",title:"origin",project:"fixture",total:60,input:nil,cached:nil,output:nil,source:"event")
    sample.logPath=log.path;sample.logIdentity=coldValue.identity
    let origin=try cold.resolveSegmentStart(sample)
    try validationCheck(origin==updated.segmentFirstAt,"history scan confused task creation with latest counter segment")
    print("PASS: current counter segment found across >512KB history; reset timestamp preserved")
    print("PASS: forward JSONL cursor; message followed by 400KB output; complete-line buffering; no replay; context vs cumulative")
}

func runSpiritChecks()throws{
    var t=TaskUsage(id:"pet-test",title:"fixture",project:"test",total:100,input:nil,cached:nil,output:nil,source:"demo")
    let pet=SpiritModel(),galaxy=GalaxyModel()
    galaxy.update([t],deltas:[:],events:[:]);pet.update([t],events:[:],deltas:[:],at:0)
    try validationCheck(pet.expression(task:t,at:0,stale:false).mood == .resting,"Idle was incorrectly labelled waiting")
    func feed(_ phase:WorkPhase,_ now:Float){let event=WorkEvent(id:"pet-\(phase)-\(now)",at:Date().timeIntervalSince1970,phase:phase);pet.update([t],events:[t.id:[event]],deltas:[:],at:now)}
    feed(.input,1);try validationCheck(pet.expression(task:t,at:1.2,stale:false).mood == .awake,"Message did not wake pet")
    feed(.thinking,2);try validationCheck(pet.expression(task:t,at:3.5,stale:false).mood == .working,"Work did not follow wake")
    pet.touch(at:3.5);try validationCheck(pet.expression(task:t,at:3.6,stale:false).caption=="我在呢" && galaxy.receivedTokens==0,"Tap changed usage or failed to acknowledge")
    feed(.complete,5);try validationCheck(pet.expression(task:t,at:5.2,stale:false).mood == .complete,"Completion did not celebrate")
    try validationCheck(pet.expression(task:t,at:11,stale:false).mood == .resting,"Completion did not settle")
    t.awaitingInput=true;feed(.waiting,12)
    try validationCheck(pet.expression(task:t,at:400,stale:false).mood == .waiting && !t.isWorking,"Explicit unresolved question lost waiting state")
    try validationCheck(pet.expression(task:t,at:400,stale:true).mood == .unavailable,"Stale data still claimed confirmed waiting")
    t.awaitingInput=false;feed(.input,401)
    try validationCheck(pet.expression(task:t,at:401.1,stale:false).mood == .awake,"Answer did not wake pet")
    feed(.interrupted,402);try validationCheck(pet.expression(task:t,at:402.1,stale:false).mood == .resting,"Interrupted task incorrectly celebrated")
    pet.update([],events:[:],deltas:[:],at:403)
    try validationCheck(pet.expression(task:nil,at:405,stale:false).mood == .resting,"Removed task left stale expression")
    print("PASS: spirit wake/work/done/wait; tap without usage; idle vs waiting; stale/interrupted/removed tasks")
}

func runInputWaitChecks()throws{
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("spirit-wait-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
    let log=folder.appendingPathComponent("wait.jsonl");FileManager.default.createFile(atPath:log.path,contents:Data());let reader=TelemetryReader(home:folder)
    func append(_ payload:[String:Any])throws{
        var bytes=try JSONSerialization.data(withJSONObject:["timestamp":"2026-09-10T00:00:00.000Z","type":"response_item","payload":payload]);bytes.append(10)
        let f=try FileHandle(forWritingTo:log);try f.seekToEnd();try f.write(contentsOf:bytes);try f.close()
    }
    try append(["type":"function_call","name":"functions.request_user_input","call_id":"q-sync"])
    try validationCheck(reader.latest(log).pendingInputCallID=="q-sync","Synchronous question not detected")
    try append(["type":"function_call_output","call_id":"other","output":"unrelated"])
    try validationCheck(reader.latest(log).pendingInputCallID=="q-sync","Unrelated tool answer cleared question")
    try append(["type":"function_call_output","call_id":"q-sync","output":"answer"])
    try validationCheck(reader.latest(log).pendingInputCallID==nil,"Synchronous answer did not clear waiting")
    try append(["type":"function_call","name":"functions.request_user_input_async","call_id":"q-async"])
    try append(["type":"function_call_output","call_id":"q-async","output":"question posted"])
    try validationCheck(reader.latest(log).pendingInputCallID=="q-async","Async acknowledgement was mistaken for an answer")
    try append(["type":"message","role":"user","content":[]])
    let parsed=reader.latest(log)
    try validationCheck(parsed.pendingInputCallID==nil && parsed.total==nil,"User answer not cleared or waiting invented tokens")
    print("PASS: real JSONL sync/async question records; acknowledgement vs answer; no token changes")
}

func runClaudeChecks()throws{
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("claude-reader-"+UUID().uuidString)
    let project=folder.appendingPathComponent("projects/test");try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
    let log=project.appendingPathComponent("session.jsonl"),reader=ClaudeTelemetryReader(home:folder)
    func record(_ mid:String,_ output:Int,_ uuid:String,agent:String?=nil)throws->Data{
        var d:[String:Any]=["type":"assistant","sessionId":"session","timestamp":"2026-09-11T01:00:00.000Z","uuid":uuid,"requestId":"req-"+mid,"cwd":project.path,"message":["id":mid,"usage":["input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":output],"content":[["type":"thinking"]]]]
        if let a=agent{d["agentId"]=a;d["isSidechain"]=true}
        var bytes=try JSONSerialization.data(withJSONObject:d);bytes.append(10);return bytes
    }
    let first=try record("main",5,"a");try (first+record("main",15,"b")+first).write(to:log)
    let childFolder=project.appendingPathComponent("session/subagents");try FileManager.default.createDirectory(at:childFolder,withIntermediateDirectories:true)
    try record("child",7,"c",agent:"agent1").write(to:childFolder.appendingPathComponent("agent1.jsonl"))
    try first.write(to:project.appendingPathComponent("copy.jsonl"))
    let items=try reader.snapshot();try validationCheck(reader.allUsage?.total==142,"Claude duplicated block/history usage or cache categories")
    let main=items.first{$0.id=="claude:session:session"}!,child=items.first{$0.parentID==main.id}!
    try validationCheck(main.total==75 && main.input==60 && main.cached==30 && main.cacheWrite==20 && child.total==67,"Claude breakdown or parent mapping failed")
    let next=try record("main",25,"d"),half=next.count/2;let handle=try FileHandle(forWritingTo:log);try handle.seekToEnd();try handle.write(contentsOf:next.prefix(half))
    _ = try reader.snapshot();try validationCheck(reader.allUsage?.total==142,"Partial Claude line was consumed")
    try handle.write(contentsOf:next.suffix(next.count-half));try handle.close();let updated=try reader.snapshot()
    try validationCheck(reader.allUsage?.total==152 && usageDelta(main,updated.first{$0.id==main.id}!)==10,"Partial output update was counted more than once")
    let c=TaskUsage(id:"codex-fixture",title:"Codex",project:"fixture",total:1_000_000,input:nil,cached:nil,output:nil,source:"demo")
    let model=GalaxyModel();model.update([c,main,child],deltas:[:],events:[:]);let event=WorkEvent(id:"live",at:Date().timeIntervalSince1970,phase:.tool)
    model.update([c,main,child],deltas:[:],events:[main.id:[event]]);model.step(0.1)
    try validationCheck(model.dualProvider && model.providerDrive.x==0 && model.providerDrive.z>0.5,"Claude activity drove Codex")
    model.update([c,main,child],deltas:[c.id:100],events:[:]);model.step(0.1)
    try validationCheck(model.providerDrive.y>0.3 && model.providerDrive.z>0.5 && model.nodes.filter{$0.visual.y>0.5}.count==1,"Simultaneous providers lost the shared leader or an independent drive")
    try validationCheck(model.links.count==1 && model.links[0].style.z<0,"Claude graph invented a cross-provider edge")
    print("PASS: Claude request/block/copy dedup, four token categories, parent IDs, split records, +10 only; two independent visual drives")
}

func runUnifiedFocusChecks() throws {
    let c=TaskUsage(id:"unified-c",title:"C",project:"fixture",total:1_000_000,input:nil,cached:nil,output:nil,source:"fixture")
    var a=TaskUsage(id:"unified-a",title:"A",project:"fixture",total:1_000_000,input:nil,cached:nil,output:nil,source:"fixture");a.provider = .claude
    var child=TaskUsage(id:"unified-child",title:"Child",project:"fixture",total:100_000,input:nil,cached:nil,output:nil,source:"fixture");child.provider = .claude;child.parentID=a.id
    let model=GalaxyModel();model.selected=c.id;model.update([c,a,child],deltas:[:],events:[:]);model.step(0.1)
    try validationCheck(model.nodes.filter{$0.visual.y>0.5}.count==1 && model.shown.first?.id==c.id,"Unified field has two leads or lost Codex selection")
    model.update([c,a,child],deltas:[:],events:[child.id:[WorkEvent(id:"child",at:Date().timeIntervalSince1970,phase:.tool)]])
    model.step(0.1)
    try validationCheck(model.fastestConversation(keeping:c.id)==nil,"Child incorrectly ranked as main")
    model.update([c,a,child],deltas:[a.id:1_000],events:[:]);model.step(0.1)
    try validationCheck(model.fastestConversation(keeping:c.id)==a.id,"Claude main cannot win focus")
    model.selected=a.id
    for _ in 0..<30 {model.step(1/30)}
    try validationCheck(model.shown.first?.id==a.id && model.nodes[0].space.x==0 && model.nodes[0].space.y==0,"Claude lead is not centered")
    try validationCheck(model.nodes.filter{$0.visual.y>0.5}.count==1 && model.nodes[0].space.w>model.nodes[1].space.w*2,"New main did not become dominant")
    let clock=model.providerClocks
    model.step(1,reduceMotion:true)
    try validationCheck(model.providerClocks==clock,"Reduced motion advanced provider motion")
    model.selected=c.id;model.step(0.1)
    try validationCheck(model.shown.first?.id==c.id && model.nodes[0].space.x==0 && model.receivedTokens==1000,"Reverse handoff moved center or fabricated usage")
    print("PASS: one shared center; cross-provider fastest-main handoff; child-only exclusion; reduced motion; unchanged usage")
}

func runRecentRiverChecks() throws {
    let c=TaskUsage(id:"river-c",title:"C",project:"fixture",total:100_000_000,input:nil,cached:nil,output:nil,source:"fixture")
    var a=TaskUsage(id:"river-a",title:"A",project:"fixture",total:100,input:nil,cached:nil,output:nil,source:"fixture");a.provider = .claude
    let m=GalaxyModel();m.update([c,a],deltas:[:],events:[:]);m.step(1)
    try validationCheck(m.recentTotals.x==0 && m.recentTotals.y==0 && m.recentVisual.z==0.5,"History dominated current river")
    m.update([c,a],deltas:[c.id:100,a.id:9900],events:[:]);for _ in 0..<45{m.step(1/30)}
    try validationCheck(m.recentTotals.x==100 && m.recentTotals.y==9900 && m.recentVisual.z>0.95,"Recent Claude majority did not dominate river")
    m.update([c,a],deltas:[:],events:[:]);m.step(1)
    try validationCheck(m.receivedTokens==10000 && m.recentTotals.y==9900,"Refresh replayed recent usage")
    m.step(11)
    try validationCheck(m.recentTotals.x==0 && m.recentTotals.y==0 && m.recentVisual.z==0.5 && m.receivedTokens==10000,"10-second window did not expire independently of accounting")
    m.update([c,a],deltas:[c.id:9900,a.id:100],events:[:]);m.step(2)
    try validationCheck(m.recentVisual.z<0.05,"Recent Codex majority did not dominate river")
    print("PASS: exact 10-second sums; no history/replay; Claude/Codex majority and expiration; display-only smoothing")
}
