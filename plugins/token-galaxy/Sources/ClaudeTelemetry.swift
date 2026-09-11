import Foundation

enum UsageProvider:String { case codex,claude
    var label:String {self == .codex ? "Codex":"Claude Code"}
}
private struct ClaudeCount {
    var input:Int64=0,write:Int64=0,read:Int64=0,output:Int64=0
    var total:Int64{input+write+read+output}
    mutating func merge(_ other:ClaudeCount){input=max(input,other.input);write=max(write,other.write);read=max(read,other.read);output=max(output,other.output)}
}
private struct ClaudeRequest { var owner:String;var count:ClaudeCount;var at:TimeInterval }
final class ClaudeTelemetryReader {
    private final class FileState {
        var generation=UUID().uuidString,malformed=false
        var modified:TimeInterval = -1
        var inode:UInt64=0,offset:UInt64=0,carry=Data(),skipping=false
        var requests=[String:ClaudeRequest](),tasks=[String:TaskUsage](),issue:String?
    }
    let home:URL
    private var files=[String:FileState](),known=[URL](),lastDiscovery:TimeInterval = -.infinity
    private let iso=ISO8601DateFormatter(),plainISO=ISO8601DateFormatter()
    private(set) var allUsage:AllUsage?
    init(home:URL?=nil){
        let env=ProcessInfo.processInfo.environment
        let fallback=env["TOKEN_GALAXY_PROBE_DIR"] != nil ? (env["CODEX_HOME"] ?? NSTemporaryDirectory())+"/claude":env["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory()+"/.claude"
        self.home=(home ?? URL(fileURLWithPath:env["TOKEN_GALAXY_CLAUDE_HOME"] ?? fallback)).resolvingSymlinksInPath()
        iso.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    }
    private func time(_ value:Any?)->TimeInterval?{guard let s=value as? String else{return nil};return (iso.date(from:s) ?? plainISO.date(from:s))?.timeIntervalSince1970}
    private func consume(_ data:Data,file:FileState,url:URL){
        if data.isEmpty{return}
        guard let d=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{file.malformed=true;file.issue="Claude记录格式异常";return}
        guard let sid=d["sessionId"] as? String,let kind=d["type"] as? String,
              ["assistant","user","system","custom-title"].contains(kind) else{return}
        let agent=d["agentId"] as? String
        let isChild=(d["isSidechain"] as? Bool ?? false) || agent != nil
        // Unknown sidechains remain isolated rather than being merged into the main conversation.
        let suffix=agent ?? (isChild ? url.deletingPathExtension().lastPathComponent:"")
        let owner=isChild ? "claude:agent:\(sid):\(suffix)":"claude:session:\(sid)"
        let cwd=d["cwd"] as? String ?? ""
        var task=file.tasks[owner] ?? TaskUsage(id:owner,title:isChild ? "Claude 子智能体 \(suffix.prefix(8))":"Claude 会话 \(sid.prefix(8))",project:URL(fileURLWithPath:cwd).lastPathComponent,total:0,input:nil,cached:nil,output:nil,source:"claude-jsonl")
        task.provider = .claude;task.projectPath=cwd.isEmpty ? task.projectPath:cwd;task.subagentRecord=isChild
        task.parentID=isChild ? "claude:session:\(sid)":nil;task.agentPath=agent;task.logPath=url.path;task.logIdentity=owner+":"+file.generation
        let at=time(d["timestamp"])
        if let at=at{task.createdAt=min(task.createdAt ?? at,at)}
        if let title=d["customTitle"] as? String,!title.isEmpty{task.displayTitle=String(title.prefix(100))}
        let message=d["message"] as? [String:Any] ?? [:]
        let blocks=message["content"] as? [[String:Any]] ?? []
        var phases=[WorkPhase]()
        if kind=="assistant" {
            if let usage=message["usage"] as? [String:Any],let mid=message["id"] as? String {
                let req=d["requestId"] as? String ?? mid,key="\(req):\(mid)"
                func n(_ name:String)->Int64{max(0,(usage[name] as? NSNumber)?.int64Value ?? 0)}
                let count=ClaudeCount(input:n("input_tokens"),write:n("cache_creation_input_tokens"),read:n("cache_read_input_tokens"),output:n("output_tokens"))
                var entry=file.requests[key] ?? ClaudeRequest(owner:owner,count:count,at:at ?? 0);entry.count.merge(count);entry.at=max(entry.at,at ?? 0);file.requests[key]=entry
                task.contextInput=count.input+count.write+count.read;task.lastUsageAt=at;task.segmentFirstAt=min(task.segmentFirstAt ?? at ?? 0,at ?? 0)
            }
            for b in blocks {
                switch b["type"] as? String {
                case "thinking":phases.append(.thinking)
                case "tool_use":
                    let name=b["name"] as? String ?? ""
                    if name=="AskUserQuestion"{task.awaitingInput=true;phases.append(.waiting)}
                    else{phases.append(["Agent","Task"].contains(name) ? .spawn:.tool)}
                case "text":phases.append(.reply)
                default:break
                }
            }
            if message["stop_reason"] as? String=="end_turn"{phases.append(.complete);task.lifecycle="task_complete";task.awaitingInput=false}
            else if !phases.isEmpty{task.lifecycle="task_started"}
        } else if kind=="user" {
            if blocks.contains(where:{$0["type"] as? String=="tool_result"}){phases.append(.result);task.awaitingInput=false}
            else{phases.append(.input);task.lastUserAt=at;task.awaitingInput=false
                if task.displayTitle==nil,!isChild {
                    let text=(message["content"] as? String) ?? blocks.first(where:{$0["type"] as? String=="text"})?["text"] as? String
                    if let text=text,!text.hasPrefix("<"),!text.isEmpty{task.displayTitle=String(text.replacingOccurrences(of:"\n",with:" ").prefix(80))}
                }
            }
            task.lifecycle=(d["toolEndsTurn"] as? Bool)==true ? "task_complete":"task_started"
            if (d["toolEndsTurn"] as? Bool)==true{phases.append(.complete)}
        }
        if let at=at,!phases.isEmpty {
            task.lastEventAt=max(task.lastEventAt ?? 0,at)
            let uuid=d["uuid"] as? String ?? "\(file.offset):\(at)"
            for (i,p) in phases.enumerated(){let e=WorkEvent(id:"claude:\(uuid):\(i):\(p.rawValue)",at:at,phase:p);if !task.events.contains(where:{$0.id==e.id}){task.events.append(e)}}
            if task.events.count>64{task.events.removeFirst(task.events.count-64)}
        }
        file.tasks[owner]=task
    }
    func snapshot()throws->[TaskUsage]{
        let folder=home.appendingPathComponent("projects"),now=ProcessInfo.processInfo.systemUptime
        if now-lastDiscovery>=2 {
            var directory:ObjCBool=false
            if !FileManager.default.fileExists(atPath:folder.path,isDirectory:&directory){if !files.isEmpty{throw NSError(domain:"Claude",code:1,userInfo:[NSLocalizedDescriptionKey:"Claude记录目录暂不可用"])};allUsage=AllUsage(total:0,indexedTotal:0,records:0);return []}
            var scanFailed=false
            guard let e=FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles],errorHandler:{_,_ in scanFailed=true;return false}) else{throw NSError(domain:"Claude",code:2)}
            known=e.compactMap{$0 as? URL}.filter{$0.pathExtension=="jsonl" && ($0.deletingPathExtension().lastPathComponent=="journal" ? false:true) && $0.resolvingSymlinksInPath().path.hasPrefix(folder.path+"/")}
            if scanFailed{throw NSError(domain:"Claude",code:3)}
            let paths=Set(known.map{$0.path});files=files.filter{paths.contains($0.key)};lastDiscovery=now
        }
        for url in known {
            do {
                let attrs=try FileManager.default.attributesOfItem(atPath:url.path),size=(attrs[.size] as? NSNumber)?.uint64Value ?? 0,inode=(attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                let modified=(attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let previous=files[url.path]
                let state:FileState
                if let old=previous,old.inode==inode,size>=old.offset,!(size==old.offset && modified != old.modified){state=old}else{state=FileState();state.inode=inode;files[url.path]=state}
                if state.offset==size{state.modified=modified;continue}
                let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()};try handle.seek(toOffset:state.offset)
                while state.offset<size {
                    let bytes=try handle.read(upToCount:Int(min(2*1024*1024,size-state.offset))) ?? Data();if bytes.isEmpty{break}
                    state.offset+=UInt64(bytes.count);state.carry.append(bytes)
                    let joined=state.carry;var start=joined.startIndex
                    while let end=joined[start...].firstIndex(of:10){if !state.skipping{autoreleasepool{consume(Data(joined[start..<end]),file:state,url:url)}};state.skipping=false;start=end+1;if start==joined.endIndex{break}}
                    state.carry=Data(joined[start...]);if state.carry.count>8*1024*1024{state.carry.removeAll();state.skipping=true;state.malformed=true;state.issue="Claude记录行过大，已跳过"}
                }
                state.modified=modified
                if !state.skipping && !state.malformed{state.issue=nil}
            }catch{if let f=files[url.path]{f.issue="Claude记录暂不可读"}else{throw error}}
        }
        var requests=[String:ClaudeRequest](),tasks=[String:TaskUsage]()
        for (_,f) in files.sorted(by:{$0.key<$1.key}) {
            for (id,t) in f.tasks {
                if var old=tasks[id]{
                    let events=Dictionary((old.events+t.events).map{($0.id,$0)},uniquingKeysWith:{a,b in a.at>b.at ? a:b}).values.sorted{$0.at<$1.at}
                    if (t.lastEventAt ?? 0)>(old.lastEventAt ?? 0){old=t};old.events=Array(events.suffix(64));if let issue=f.issue{old.readIssue=issue};tasks[id]=old
                }else{var copy=t;copy.readIssue=f.issue;tasks[id]=copy}
            }
            for (key,value) in f.requests{if var old=requests[key]{old.count.merge(value.count);old.at=max(old.at,value.at);requests[key]=old}else{requests[key]=value}}
        }
        var sums=[String:ClaudeCount]()
        for r in requests.values{var n=sums[r.owner] ?? ClaudeCount();n.input+=r.count.input;n.write+=r.count.write;n.read+=r.count.read;n.output+=r.count.output;sums[r.owner]=n}
        var result=[TaskUsage]()
        for (id,var task) in tasks {
            let n=sums[id] ?? ClaudeCount();task.total=n.total;task.input=n.input+n.write+n.read;task.cached=n.read;task.cacheWrite=n.write;task.output=n.output;result.append(task)
        }
        allUsage=AllUsage(total:requests.values.reduce(0){$0+$1.count.total},indexedTotal:0,records:result.count,logOverrides:result.count)
        return result.sorted{($0.lastEventAt ?? 0)>($1.lastEventAt ?? 0)}
    }
}

struct CombinedUsageSample {
    var items:[TaskUsage]
    var codex:AllUsage?
    var claude:AllUsage?
    var errors:[String:String]
}
final class CombinedTelemetryReader {
    let codex:TelemetryReader,claude:ClaudeTelemetryReader
    private var codexItems=[TaskUsage](),claudeItems=[TaskUsage]()
    init(codex:TelemetryReader,claude:ClaudeTelemetryReader=ClaudeTelemetryReader()){self.codex=codex;self.claude=claude}
    func snapshot()->CombinedUsageSample{
        var errors=[String:String]()
        var codexSummary=codex.allUsage
        do {
            if FileManager.default.fileExists(atPath:codex.home.appendingPathComponent("state_5.sqlite").path) || codex.allUsage != nil {
                codexItems=try codex.snapshot();codexSummary=codex.allUsage
            } else {codexItems=[];codexSummary=AllUsage(total:0,indexedTotal:0,records:0)}
        } catch {errors["codex"]="Codex读取暂不可用"}
        do{claudeItems=try claude.snapshot()}catch{errors["claude"]="Claude读取暂不可用"}
        func marked(_ items:[TaskUsage],_ key:String)->[TaskUsage]{items.map{var t=$0;if let e=errors[key]{t.readIssue=e};return t}}
        let recentClaude=Array(claudeItems.prefix(80))
        return CombinedUsageSample(items:(marked(codexItems,"codex")+marked(recentClaude,"claude")).sorted{($0.lastEventAt ?? 0)>($1.lastEventAt ?? 0)},codex:codexSummary,claude:claude.allUsage,errors:errors)
    }
}
