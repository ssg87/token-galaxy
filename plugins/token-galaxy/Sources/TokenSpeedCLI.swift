import Foundation

struct TokenSpeedSampleOptions {
    let seconds:Int
    let window:TokenSpeedWindow
    let provider:UsageProvider?
    let taskID:String?
    var scope:TokenSpeedScope {
        if let taskID=taskID,let provider=provider{return .task(id:taskID,provider:provider)}
        return provider.map{.provider($0)} ?? .all
    }
    static func parse(_ arguments:[String])throws->TokenSpeedSampleOptions {
        let known:Set<String>=["--speed-json","--seconds","--window","--provider","--task-id","--state-dir"]
        var index=arguments.first.map{!$0.hasPrefix("--")} == true ? 1:0,seen=Set<String>()
        while index<arguments.count {
            let key=arguments[index]
            guard known.contains(key) else{throw TokenSpeedCLIError("Unknown argument: \(key)")}
            guard seen.insert(key).inserted else{throw TokenSpeedCLIError("Duplicate argument: \(key)")}
            if key=="--speed-json"{index+=1;continue}
            guard index+1<arguments.count,!arguments[index+1].isEmpty,!arguments[index+1].hasPrefix("--") else{throw TokenSpeedCLIError("\(key) requires a value")}
            index+=2
        }
        func argument(_ name:String,default fallback:String?=nil)throws->String?{
            guard let i=arguments.firstIndex(of:name) else{return fallback}
            guard i+1<arguments.count,!arguments[i+1].hasPrefix("--") else{throw TokenSpeedCLIError("\(name) requires a value")}
            return arguments[i+1]
        }
        guard let seconds=Int(try argument("--seconds",default:"15") ?? ""),(1...300).contains(seconds) else{throw TokenSpeedCLIError("--seconds must be an integer from 1 to 300")}
        guard let raw=Int(try argument("--window",default:"10") ?? ""),let window=TokenSpeedWindow(rawValue:raw) else{throw TokenSpeedCLIError("--window must be 10, 30, or 60")}
        let name=try argument("--provider",default:"all") ?? "all"
        guard ["all","codex","claude"].contains(name) else{throw TokenSpeedCLIError("--provider must be all, codex, or claude")}
        let taskID=try argument("--task-id")
        if let taskID=taskID,taskID.isEmpty{throw TokenSpeedCLIError("--task-id must not be empty")}
        if taskID != nil && name=="all"{throw TokenSpeedCLIError("--task-id requires --provider codex or claude")}
        return TokenSpeedSampleOptions(seconds:seconds,window:window,provider:UsageProvider(rawValue:name),taskID:taskID)
    }
}

struct TokenSpeedCLIError:LocalizedError {
    var message:String
    init(_ message:String){self.message=message}
    var errorDescription:String?{message}
}

struct TokenSpeedSamplingMetadata:Codable {
    /// Requested observation time after the first read has established a baseline.
    let durationSeconds:Int
    /// Total sampling wall time, including the first read and baseline setup.
    let elapsedSeconds:Double
    let initialReadSeconds:Double
    let observationSeconds:Double
    let intervalSeconds:Double
    let sampleCount:Int
    let clock:String
}

struct TokenSpeedSampleReport:Encodable {
    let snapshot:TokenSpeedSnapshot
    let sampling:TokenSpeedSamplingMetadata
    func encodedJSON()throws->Data {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Runs before NSApplication is created. It shares the reader and the speed engine used by the UI.
func runTokenSpeedSample(_ options:TokenSpeedSampleOptions)throws->TokenSpeedSampleReport {
    let reader=CombinedTelemetryReader(codex:TelemetryReader())
    return sampleTokenSpeed(options,read:{reader.snapshot()},clock:{ProcessInfo.processInfo.systemUptime},pause:{Thread.sleep(forTimeInterval:$0)})
}

/// The three closures keep the cold-start timing check fixture-only and instant.
private func sampleTokenSpeed(_ options:TokenSpeedSampleOptions,read:()->CombinedUsageSample,clock:()->TimeInterval,pause:(TimeInterval)->Void)->TokenSpeedSampleReport {
    let engine=TokenSpeedEngine(),start=clock(),interval=0.5
    let baseline=read(),baselineAt=clock()
    engine.ingest(baseline,at:baselineAt)
    // A large cold log read is initialization, not part of the requested observation window.
    let observationStart=clock(),deadline=observationStart+Double(options.seconds)
    var count=1,next=observationStart+interval
    while true {
        let before=clock()
        if before<next{pause(next-before)}
        let sample=read(),completed=clock()
        engine.ingest(sample,at:completed);count+=1
        if completed>=deadline{break}
        // Slow reads skip deadlines; they are never caught up in a burst.
        next=min(deadline,max(next+interval,completed+interval))
    }
    let completed=clock()
    return TokenSpeedSampleReport(snapshot:engine.snapshot(scope:options.scope,window:options.window,at:completed),sampling:TokenSpeedSamplingMetadata(durationSeconds:options.seconds,elapsedSeconds:completed-start,initialReadSeconds:observationStart-start,observationSeconds:completed-observationStart,intervalSeconds:interval,sampleCount:count,clock:"monotonic-system-uptime"))
}

func runTokenSpeedCLIOptionChecks()throws {
    func require(_ condition:Bool,_ message:String)throws{if !condition{throw TokenSpeedCLIError(message)}}
    let normal=try TokenSpeedSampleOptions.parse(["--speed-json"])
    try require(normal.seconds==15 && normal.window == .seconds10 && normal.scope == .all,"Speed CLI defaults changed")
    let task=try TokenSpeedSampleOptions.parse(["--seconds","1","--window","60","--provider","claude","--task-id","fixture-task"])
    try require(task.scope == .task(id:"fixture-task",provider:.claude),"Speed CLI task scope lost its provider")
    for invalid in [["--seconds","0"],["--seconds","301"],["--seconds","1.5"],["--window","11"],["--provider","other"],["--task-id","fixture"],["--seconds"],["--provider","--seconds","5"],["--second","5"],["--seconds","5","--seconds","6"],["--speed-json","--speed-json"],["--speed-json","unexpected-value"]] {
        do{_ = try TokenSpeedSampleOptions.parse(invalid);throw TokenSpeedCLIError("Invalid CLI arguments accepted: \(invalid)")}
        catch let error as TokenSpeedCLIError {if error.message.hasPrefix("Invalid CLI"){throw error}}
    }
    func simulated(seconds:Int,coldRead:Double,secondRead:Double=0)->(TokenSpeedSampleReport,[TimeInterval]) {
        var time:TimeInterval=100,reads=0,starts=[TimeInterval]()
        let baselineAt=time+coldRead
        let options=TokenSpeedSampleOptions(seconds:seconds,window:.seconds10,provider:.codex,taskID:nil)
        let report=sampleTokenSpeed(options,read:{
            starts.append(time);reads+=1
            if reads==1{time+=coldRead}else if reads==2{time+=secondRead}
            let increment=Int64((max(0,time-baselineAt)*100).rounded())
            var item=TaskUsage(id:"speed-cold-read-fixture",title:"Fixture",project:"Fixture",total:1_000+increment,input:800+increment*4/5,cached:0,output:200+increment/5,source:"synthetic-cli")
            item.logIdentity="speed-cold-read-fixture"
            return CombinedUsageSample(items:[item],codex:AllUsage(total:item.total,indexedTotal:0,records:1),claude:AllUsage(total:0,indexedTotal:0,records:0),errors:[:])
        },clock:{time},pause:{time+=$0})
        return (report,starts)
    }
    let (cold,_)=simulated(seconds:15,coldRead:17.475)
    try require(abs(cold.sampling.initialReadSeconds-17.475)<0.000_001 && abs(cold.sampling.observationSeconds-15)<0.000_001 && abs(cold.sampling.elapsedSeconds-32.475)<0.000_001,"Cold first read consumed requested observation time")
    try require(cold.sampling.sampleCount==31 && cold.snapshot.state == .live && abs((cold.snapshot.rates.total ?? -1)-100)<0.000_001,"Cold-start sampling failed to establish a full, measured window")
    let (short,_)=simulated(seconds:1,coldRead:20)
    try require(short.sampling.sampleCount==3 && short.sampling.observationSeconds==1 && short.snapshot.state == .warming && short.snapshot.rates.total==nil,"Short observation fabricated a rate after cold startup")
    let (slow,starts)=simulated(seconds:15,coldRead:17.475,secondRead:6)
    try require(zip(starts,starts.dropFirst()).allSatisfy{pair in pair.1-pair.0>=0.5-0.000_001},"Slow reads were caught up in a burst")
    try require(slow.snapshot.state == .gap && slow.snapshot.rates.total==nil,"Slow-read sampling gap was hidden")
    print("PASS: token speed CLI defaults, bounds, windows, provider-specific task scope, unknown/duplicate argument rejection")
    print("PASS: cold first read precedes requested observation; metadata, baseline count, short-window warming, and slow-read gaps")
}
