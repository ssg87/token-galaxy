import Foundation
import CSQLite

enum WorkPhase: Int, Codable {
    case quiet = 0, input, thinking, tool, result, spawn, reply, complete, interrupted, plan, waiting
    var label: String {
        switch self {
        case .quiet: return "状态未确认"
        case .input: return "收到消息"
        case .thinking: return "思考中"
        case .tool: return "调用工具"
        case .result: return "工具返回"
        case .spawn: return "调度代理"
        case .reply: return "生成回复"
        case .complete: return "本轮完成"
        case .interrupted: return "已中断"
        case .plan: return "更新计划"
        case .waiting: return "等待回答"
        }
    }
}
struct WorkEvent {
    let id: String
    let at: TimeInterval
    let phase: WorkPhase
    var tool: String? = nil
}
struct TaskUsage {
    let id: String
    let title: String
    let project: String
    var total: Int64
    var input: Int64?
    var cached: Int64?
    var output: Int64?
    let source: String
    var provider:UsageProvider = .codex
    var cacheWrite:Int64? = nil
    var displayTitle:String? = nil
    var label:String {displayTitle ?? nickname ?? title}
    var parentID: String? = nil
    var subagentRecord = false
    var awaitingInput = false
    var isMainConversation: Bool { parentID == nil && !subagentRecord }
    var agentPath: String? = nil
    var nickname: String? = nil
    var role: String? = nil
    var projectPath = ""
    var lastEventAt: TimeInterval? = nil
    var lastUserAt: TimeInterval? = nil
    var lifecycle: String? = nil
    var contextInput: Int64? = nil
    var contextLimit: Int64? = nil
    var lastUsageAt: TimeInterval? = nil
    var events = [WorkEvent]()
    var createdAt: TimeInterval? = nil
    var segmentFirstAt: TimeInterval? = nil
    var logPath = ""
    var logIdentity = ""
    var pendingBytes: Int64 = 0
    var readIssue: String? = nil
    var stateLabel: String {
        if awaitingInput { return "等待回答" }
        if let e = events.last, Date().timeIntervalSince1970 - e.at < 120 { return e.phase.label }
        if lifecycle == "task_complete" { return "本轮完成" }
        if lifecycle == "turn_aborted" { return "已中断" }
        if let at = lastEventAt, Date().timeIntervalSince1970 - at < 120 {
            return lifecycle == "task_started" ? "工作中" : "近期活动"
        }
        return "状态未确认"
    }
    var isWorking: Bool {
        if awaitingInput { return false }
        guard let at = lastEventAt, Date().timeIntervalSince1970 - at < 120 else { return false }
        return lifecycle != "task_complete" && lifecycle != "turn_aborted"
    }
    var activity: Float { isWorking ? 0.8 : 0.025 }
}
struct UsageDetail {
    var pendingInputCallID: String? = nil
    var inputWaitsForMessage = false
    var total: Int64? = nil
    var input: Int64? = nil
    var cached: Int64? = nil
    var output: Int64? = nil
    var lastEventAt: TimeInterval? = nil
    var lastUserAt: TimeInterval? = nil
    var lifecycle: String? = nil
    var contextInput: Int64? = nil
    var contextLimit: Int64? = nil
    var lastUsageAt: TimeInterval? = nil
    var events = [WorkEvent]()
    var segmentFirstAt: TimeInterval? = nil
    var identity = ""
    var pendingBytes: Int64 = 0
    var issue: String? = nil
}

/// A forward-only cursor after the first tail baseline. Complete records are read
/// exactly once even if a large tool result follows a user record in the same write.
struct AllUsage {
    var total: Int64
    var indexedTotal: Int64
    var records: Int
    var logOverrides: Int = 0
}
final class TelemetryReader {
    private(set) var allUsage: AllUsage?
    private final class Cursor {
        var inode: UInt64 = 0
        var offset: UInt64 = 0
        var carry = Data()
        var skippingPartial = false
        var baselineFromStart = false
        var detail = UsageDetail()
    }
    let home: URL
    private var cache = [String: Cursor]()
    private let iso = ISO8601DateFormatter()
    private let isoSeconds = ISO8601DateFormatter()
    init(home: URL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex")) {
        self.home = home.resolvingSymlinksInPath()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    private func timestamp(_ value: Any?) -> TimeInterval? {
        guard let value = value as? String else { return nil }
        return (iso.date(from: value) ?? isoSeconds.date(from: value))?.timeIntervalSince1970
    }
    private func consume(_ bytes: Data, offset: UInt64, cursor: Cursor) {
        // This upper bound prevents malformed logs from retaining unlimited data.
        guard !bytes.isEmpty, bytes.count <= 8 * 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: bytes),
              let e = object as? [String: Any], let type = e["type"] as? String,
              let p = e["payload"] as? [String: Any] else { return }
        let kind = p["type"] as? String ?? ""
        let at = timestamp(e["timestamp"])
        var phase: WorkPhase? = nil
        var tool: String? = nil
        if type == "event_msg" {
            if let at = at { cursor.detail.lastEventAt = max(cursor.detail.lastEventAt ?? 0, at) }
            switch kind {
            case "task_started": cursor.detail.lifecycle = kind; phase = .thinking
            case "task_complete": cursor.detail.lifecycle = kind; cursor.detail.pendingInputCallID = nil; phase = .complete
            case "turn_aborted": cursor.detail.lifecycle = kind; cursor.detail.pendingInputCallID = nil; phase = .interrupted
            case "user_message": phase = .input
            case "agent_reasoning": phase = .thinking
            case "token_count":
                if let info = p["info"] as? [String: Any],
                   let u = info["total_token_usage"] as? [String: Any],
                   let total = (u["total_tokens"] as? NSNumber)?.int64Value, total >= 0 {
                    if let previous = cursor.detail.total, total < previous { cursor.detail.segmentFirstAt = at }
                    else if cursor.detail.total == nil && cursor.baselineFromStart { cursor.detail.segmentFirstAt = at }
                    cursor.detail.total = total
                    cursor.detail.input = (u["input_tokens"] as? NSNumber)?.int64Value
                    cursor.detail.cached = (u["cached_input_tokens"] as? NSNumber)?.int64Value
                    cursor.detail.output = (u["output_tokens"] as? NSNumber)?.int64Value
                    let last = info["last_token_usage"] as? [String: Any]
                    cursor.detail.contextInput = (last?["input_tokens"] as? NSNumber)?.int64Value
                    cursor.detail.contextLimit = (info["model_context_window"] as? NSNumber)?.int64Value
                    cursor.detail.lastUsageAt = at
                }
            default: break
            }
        } else if type == "response_item" {
            switch kind {
            case "message":
                if p["role"] as? String == "user" { phase = .input }
                else if p["role"] as? String == "assistant" { phase = .reply }
            case "reasoning": phase = .thinking
            case "function_call", "custom_tool_call":
                let name = p["name"] as? String ?? "tool"
                tool = String(name.prefix(90))
                phase = name.contains("spawn") || name.contains("send_message") || name.contains("followup_task") ? .spawn : name.contains("update_plan") ? .plan : .tool
                if name.hasSuffix("request_user_input") || name.hasSuffix("request_user_input_async") {
                    cursor.detail.pendingInputCallID = p["call_id"] as? String ?? "input-request"
                    cursor.detail.inputWaitsForMessage = name.hasSuffix("request_user_input_async")
                    phase = .waiting
                }
            case "function_call_output", "custom_tool_call_output":
                phase = .result
                if let call = p["call_id"] as? String, call == cursor.detail.pendingInputCallID {
                    if !cursor.detail.inputWaitsForMessage { cursor.detail.pendingInputCallID = nil }
                    else { phase = nil } // Async acknowledgement is not the user's answer.
                }
            case "agent_message": phase = .result
            default: break
            }
        }
        if let phase = phase, let at = at {
            if phase == .input { cursor.detail.lastUserAt = max(cursor.detail.lastUserAt ?? 0, at); cursor.detail.pendingInputCallID = nil }
            cursor.detail.lastEventAt = max(cursor.detail.lastEventAt ?? 0, at)
            let event = WorkEvent(id: "\(cursor.detail.identity.suffix(36)):\(offset):\(kind)", at: at, phase: phase, tool: tool)
            cursor.detail.events.append(event)
            if cursor.detail.events.count > 64 { cursor.detail.events.removeFirst(cursor.detail.events.count - 64) }
        }
    }
    func latest(_ url: URL) -> UsageDetail {
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(home.path + "/") else { var d = UsageDetail(); d.issue = "记录路径不在本地数据目录"; return d }
        guard let attr = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              let size = (attr[.size] as? NSNumber)?.uint64Value,
              let inode = (attr[.systemFileNumber] as? NSNumber)?.uint64Value else {
            var d = cache[resolved.path]?.detail ?? UsageDetail(); d.issue = "记录文件暂不可读"; return d
        }
        let cursor: Cursor
        if let old = cache[resolved.path], old.inode == inode, size >= old.offset {
            cursor = old
        } else {
            cursor = Cursor(); cursor.inode = inode
            cursor.offset = size > 512 * 1024 ? size - 512 * 1024 : 0
            cursor.skippingPartial = cursor.offset > 0
            cursor.baselineFromStart = cursor.offset == 0
            cursor.detail.identity = resolved.path + ":" + String(inode) + ":" + UUID().uuidString
            cache[resolved.path] = cursor
        }
        if cursor.offset < size {
            guard let handle = try? FileHandle(forReadingFrom: resolved) else { var d = cursor.detail; d.issue = "记录读取暂不可用"; return d }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: cursor.offset)
                let readSize = Int(min(size - cursor.offset, 4 * 1024 * 1024))
                let incoming = try handle.read(upToCount: readSize) ?? Data()
                let baseOffset = cursor.offset - UInt64(cursor.carry.count)
                cursor.offset += UInt64(incoming.count)
                cursor.carry.append(incoming)
                let joined = cursor.carry
                var begin = joined.startIndex
                while let newline = joined[begin...].firstIndex(of: 10) {
                    if cursor.skippingPartial { cursor.skippingPartial = false }
                    else {
                        let line = Data(joined[begin..<newline])
                        autoreleasepool { consume(line, offset: baseOffset + UInt64(begin), cursor: cursor) }
                    }
                    begin = newline + 1
                    if begin == joined.endIndex { break }
                }
                cursor.carry = Data(joined[begin...])
                if cursor.carry.count > 8 * 1024 * 1024 {
                    cursor.carry.removeAll(keepingCapacity: false); cursor.skippingPartial = true
                    cursor.detail.issue = "有超大未完成记录，正在等待下一条完整事件"
                } else { cursor.detail.issue = nil }
            } catch { cursor.detail.issue = "读取中断，自动重试" }
        }
        cursor.detail.pendingBytes = Int64(size - cursor.offset)
        return cursor.detail
    }
    func snapshot() throws -> [TaskUsage] {
        var raw: OpaquePointer?
        let code = sqlite3_open_v2(home.appendingPathComponent("state_5.sqlite").path, &raw, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard code == SQLITE_OK, let db = raw else { if let raw = raw { sqlite3_close(raw) }; throw failure("无法读取 Codex 本地记录") }
        defer { sqlite3_close(db) }; sqlite3_busy_timeout(db, 700)
        guard sqlite3_exec(db,"BEGIN",nil,nil,nil)==SQLITE_OK else { throw failure("无法读取用量汇总") }
        defer { sqlite3_exec(db,"ROLLBACK",nil,nil,nil) }
        var aggregate: OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT COUNT(*),COALESCE(SUM(CASE WHEN tokens_used>0 THEN tokens_used ELSE 0 END),0) FROM threads",-1,&aggregate,nil)==SQLITE_OK else { throw failure("无法汇总本地用量") }
        guard sqlite3_step(aggregate)==SQLITE_ROW else { sqlite3_finalize(aggregate);throw failure("本地用量汇总暂不可用") }
        let indexedTotal=sqlite3_column_int64(aggregate,1)
        var summary=AllUsage(total:indexedTotal,indexedTotal:indexedTotal,records:Int(sqlite3_column_int64(aggregate,0)))
        sqlite3_finalize(aggregate)
        var columns = Set<String>(), meta: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &meta, nil) == SQLITE_OK {
            while sqlite3_step(meta) == SQLITE_ROW { if let value = sqlite3_column_text(meta, 1) { columns.insert(String(cString: value)) } }
        }
        sqlite3_finalize(meta)
        let title = columns.contains("name") ? "COALESCE(NULLIF(name,''),NULLIF(title,''),'未命名任务')" : "COALESCE(NULLIF(title,''),'未命名任务')"
        let optional = ["source", "agent_path", "agent_nickname", "agent_role", "created_at"].map { columns.contains($0) ? $0 : "NULL" }.joined(separator: ",")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id,\(title),cwd,tokens_used,rollout_path,\(optional) FROM threads ORDER BY updated_at DESC,id LIMIT 80", -1, &statement, nil) == SQLITE_OK else { throw failure("本地数据格式暂不兼容") }
        defer { sqlite3_finalize(statement) }
        func string(_ i: Int32) -> String { guard let value = sqlite3_column_text(statement, i) else { return "" }; return String(cString: value) }
        var result = [TaskUsage](), paths = Set<String>(), status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let id = string(0), name = string(1), cwd = string(2), indexed = sqlite3_column_int64(statement, 3), path = string(4), origin = string(5)
            paths.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
            let d = latest(URL(fileURLWithPath: path))
            if let total=d.total {
                summary.total += total-max(0,indexed)
                summary.logOverrides += 1
            }
            var t = TaskUsage(id: id, title: name, project: URL(fileURLWithPath: cwd).lastPathComponent,
                              total: d.total ?? max(0, indexed), input: d.input, cached: d.cached, output: d.output, source: d.total == nil ? "index" : "event")
            t.projectPath = cwd; t.agentPath = string(6).nilIfEmpty; t.nickname = string(7).nilIfEmpty; t.role = string(8).nilIfEmpty
            t.lastEventAt = d.lastEventAt; t.lastUserAt = d.lastUserAt; t.lifecycle = d.lifecycle
            t.awaitingInput = d.pendingInputCallID != nil
            t.contextInput = d.contextInput; t.contextLimit = d.contextLimit; t.lastUsageAt = d.lastUsageAt
            t.createdAt = sqlite3_column_type(statement,9)==SQLITE_NULL ? nil : Double(sqlite3_column_int64(statement,9))
            t.segmentFirstAt = d.segmentFirstAt; t.logPath = path
            t.events = d.events; t.logIdentity = d.identity; t.pendingBytes = d.pendingBytes; t.readIssue = d.issue
            if let bytes = origin.data(using: .utf8), let data = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] {
                t.subagentRecord = data["subagent"] != nil
            }
            if let bytes = origin.data(using: .utf8), let data = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
               let sub = data["subagent"] as? [String: Any], let spawn = sub["thread_spawn"] as? [String: Any] {
                t.parentID = spawn["parent_thread_id"] as? String
                t.agentPath = t.agentPath ?? spawn["agent_path"] as? String
                t.nickname = t.nickname ?? spawn["agent_nickname"] as? String
            }
            result.append(t); status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure("记录暂时忙碌") }
        cache = cache.filter { paths.contains($0.key) }
        allUsage = summary
        return result
    }
    /// Resolve only the opened task, once per cursor identity; never scan all histories at launch.
    func resolveSegmentStart(_ task: TaskUsage) throws -> TimeInterval? {
        let url = URL(fileURLWithPath:task.logPath).resolvingSymlinksInPath()
        guard url.path.hasPrefix(home.path+"/") else{return nil}
        if let known=cache[url.path]?.detail.segmentFirstAt{return known}
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        let limit=try handle.seekToEnd();try handle.seek(toOffset:0)
        var remaining=limit,carry=Data(),last:Int64?,start:TimeInterval?
        let needle=Data("\"token_count\"".utf8)
        while remaining>0 {
            let bytes=try handle.read(upToCount:Int(min(remaining,512*1024))) ?? Data()
            if bytes.isEmpty{break};remaining-=UInt64(bytes.count);carry.append(bytes)
            let joined=carry;var begin=joined.startIndex
            while let end=joined[begin...].firstIndex(of:10){
                let line=joined[begin..<end]
                if line.range(of:needle) != nil,
                   let e=(try? JSONSerialization.jsonObject(with:Data(line))) as? [String:Any],e["type"] as? String=="event_msg",
                   let payload=e["payload"] as? [String:Any],payload["type"] as? String=="token_count",
                   let info=payload["info"] as? [String:Any],let usage=info["total_token_usage"] as? [String:Any],
                   let total=(usage["total_tokens"] as? NSNumber)?.int64Value,total>=0 {
                    if last==nil || total<last!{start=timestamp(e["timestamp"])};last=total
                }
                begin=end+1;if begin==joined.endIndex{break}
            }
            carry=Data(joined[begin...])
        }
        if cache[url.path]?.detail.identity==task.logIdentity{cache[url.path]?.detail.segmentFirstAt=start}
        return start
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "TokenGalaxy", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
func usageDelta(_ old: TaskUsage?, _ new: TaskUsage) -> Int64 {
    guard let old = old, old.source == new.source, old.logIdentity == new.logIdentity, new.total >= old.total else { return 0 }
    return new.total - old.total
}
func compactTokens(_ n: Int64) -> String {
    if n >= 1_000_000_000 { return String(format: "%.2fB", Double(n) / 1_000_000_000) }
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
    return String(n)
}
