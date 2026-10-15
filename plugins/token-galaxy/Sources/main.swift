import AppKit

do{_ = try TokenGalaxyRuntime.explicitStateDirectory()}catch{fputs("Token speed: \(error.localizedDescription)\n",stderr);exit(2)}
if CommandLine.arguments.contains("--speed-json") {
    do{
        let options=try TokenSpeedSampleOptions.parse(CommandLine.arguments)
        let report=try runTokenSpeedSample(options)
        guard let json=String(data:try report.encodedJSON(),encoding:.utf8) else{throw TokenSpeedCLIError("Could not encode speed report")}
        print(json);exit(0)
    }catch{fputs("Token speed: \(error.localizedDescription)\n",stderr);exit(2)}
}
if let index=CommandLine.arguments.firstIndex(of:"--speed-demo") {
    guard index+1<CommandLine.arguments.count,!CommandLine.arguments[index+1].hasPrefix("--") else{fputs("--speed-demo requires an output directory\n",stderr);exit(2)}
    let app=NSApplication.shared;app.setActivationPolicy(.accessory)
    do{try runTokenSpeedDemo(CommandLine.arguments[index+1]);exit(0)}catch{fputs("Speed demo failed: \(error.localizedDescription)\n",stderr);exit(1)}
}

if CommandLine.arguments.contains("--capabilities") {
    let sample=CombinedTelemetryReader(codex:TelemetryReader()).snapshot()
    let providers=[UsageProvider.codex,.claude].filter{p in sample.items.contains{$0.provider==p} || sample.errors[p.rawValue] != nil}
    let value:[String:Any]=["touchBar":HardwareCapabilities.touchBarAvailable,"providers":providers.map{$0.rawValue},"readErrors":Array(sample.errors.keys).sorted()]
    print(String(data:try! JSONSerialization.data(withJSONObject:value,options:.sortedKeys),encoding:.utf8)!);exit(0)
}

if let i=CommandLine.arguments.firstIndex(of:"--inspect-origin"),CommandLine.arguments.count>i+1 {
    do {
        let reader=TelemetryReader();let items=try reader.snapshot()
        guard let task=items.first(where:{$0.id==CommandLine.arguments[i+1]}) else{throw NSError(domain:"Origin",code:1)}
        let started=Date();let origin=try reader.resolveSegmentStart(task)
        let value:[String:Any]=["taskID":task.id,"createdAt":task.createdAt ?? 0,"segmentFirstAt":origin ?? 0,"total":task.total,"scanSeconds":Date().timeIntervalSince(started)]
        print(String(data:try JSONSerialization.data(withJSONObject:value,options:.sortedKeys),encoding:.utf8)!);exit(0)
    }catch{fputs("Origin check failed: \(error)\n",stderr);exit(1)}
}
if CommandLine.arguments.contains("--inspect-claude") {
    do{let reader=ClaudeTelemetryReader();let start=Date();let tasks=try reader.snapshot();let first=Date().timeIntervalSince(start);let second=Date();_ = try reader.snapshot()
        let report:[String:Any]=["total":reader.allUsage?.total ?? -1,"records":tasks.count,"main":tasks.filter{$0.isMainConversation}.count,"agents":tasks.filter{!$0.isMainConversation}.count,"readIssues":tasks.filter{$0.readIssue != nil}.count,"initialSeconds":first,"repeatSeconds":Date().timeIntervalSince(second)]
        print(String(data:try JSONSerialization.data(withJSONObject:report,options:.sortedKeys),encoding:.utf8)!);exit(0)
    }catch{fputs("Claude read failed: \(error)\n",stderr);exit(1)}
}
if CommandLine.arguments.contains("--self-test") {
    let sample=TaskUsage(id:"a",title:"test",project:"test",total:100,input:90,cached:30,output:10,source:"event")
    let next=TaskUsage(id:"a",title:"test",project:"test",total:125,input:115,cached:30,output:10,source:"event")
    guard usageDelta(nil,sample)==0,usageDelta(sample,sample)==0,usageDelta(sample,next)==25,usageDelta(next,sample)==0 else{fatalError("Delta tests failed")}
    do{
        try runTelemetryChecks();try runTokenSpeedChecks();try runTokenSpeedCLIOptionChecks();try runTokenSpeedURLChecks();try runVisualChecks();try runUpdaterConfigurationChecks()
        print("PASS: fixture-only telemetry and visual checks; no personal data required");exit(0)}catch{fputs("FAIL: \(error)\n",stderr);exit(1)}
}
let app=NSApplication.shared
let delegate=AppController()
if let index=CommandLine.arguments.firstIndex(of:"--render"),CommandLine.arguments.count>index+1{delegate.capturePath=CommandLine.arguments[index+1]}
app.delegate=delegate
app.run()
