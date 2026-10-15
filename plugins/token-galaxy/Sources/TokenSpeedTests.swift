import Foundation

private func speedCheck(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "TokenSpeedChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
private func speedTask(_ id: String = "fixture", provider: UsageProvider = .codex, total: Int64 = 1_000_000, input: Int64? = 800_000, output: Int64? = 200_000, cached: Int64? = 100_000) -> TaskUsage {
    var task = TaskUsage(id: id, title: "PRIVATE_FIXTURE_TITLE", project: "PRIVATE_FIXTURE_PROJECT", total: total, input: input, cached: cached, output: output, source: provider == .codex ? "event" : "claude-jsonl")
    task.provider = provider; task.logIdentity = "PRIVATE_FIXTURE_IDENTITY"; task.logPath = "/PRIVATE_FIXTURE_PATH"; task.projectPath = "/PRIVATE_FIXTURE_PROJECT_PATH"
    if provider == .claude { task.cacheWrite = 50_000 }
    return task
}
private func speedSample(_ items: [TaskUsage], errors: [String: String] = [:]) -> CombinedUsageSample {
    func summary(_ provider: UsageProvider) -> AllUsage {
        let values = items.filter { $0.provider == provider }
        return AllUsage(total: values.reduce(0) { $0 + $1.total }, indexedTotal: 0, records: values.count)
    }
    return CombinedUsageSample(items: items, codex: summary(.codex), claude: summary(.claude), errors: errors)
}

/// Synthetic counters and temporary files only; does not read personal sessions or preferences.
func runTokenSpeedChecks() throws {
    let empty = TokenSpeedEngine()
    empty.ingest(speedSample([]), at: 0)
    let initial = empty.snapshot(at: 0, trendSeconds: 0)
    try speedCheck(initial.state == .notFound && initial.rates.total == nil && initial.cumulative.total == nil, "Never-discovered counters must remain unknown")

    let engine = TokenSpeedEngine()
    var task = speedTask()
    engine.ingest(speedSample([task]), at: 0)
    try speedCheck(engine.snapshot(at: 0).state == .warming && engine.snapshot(at: 0).rates.total == nil, "First read replayed historical usage")
    for i in 1...10 { engine.ingest(speedSample([task]), at: Double(i)) }
    var result = engine.snapshot(at: 10)
    try speedCheck(result.rates.total == 0 && result.state == .idle && result.cumulative.total == 1_000_000, "Healthy zero is distinct from unavailable")
    try speedCheck(result.providers.first { $0.provider == "claude" }?.state == .notFound, "Unused provider polluted a valid all-provider window")
    for i in 11...20 { task.total += 10; task.input! += 8; task.output! += 2; task.cached! += 4; engine.ingest(speedSample([task]), at: Double(i)) }
    result = engine.snapshot(at: 20)
    try speedCheck(result.rates.total == 10 && result.rates.input == 8 && result.rates.output == 2, "Cached input was double counted or fixed-window denominator changed")
    for i in 21...30 { engine.ingest(speedSample([task]), at: Double(i)) }
    try speedCheck(engine.snapshot(at: 30).rates.total == 0, "Rolled-out deltas stayed in the window")
    try speedCheck(engine.snapshot(at: 30, trendSeconds: 120).trend.count == 120, "Trend must have bounded one-second points")
    try speedCheck(engine.snapshot(at: 36).rates.total == nil && engine.snapshot(at: 36).reasons.contains("sample_stale"), "Stale samples appeared healthy")
    try speedCheck(engine.snapshot(at: 38).trend.last?.rates.total == nil && engine.snapshot(at: 38).providers.first?.trend.last?.rates.total == nil, "Trend concealed missing samples at its current tail")

    let recovered = TokenSpeedEngine()
    task = speedTask()
    for i in 0...10 { recovered.ingest(speedSample([task]), at: Double(i)) }
    recovered.ingest(speedSample([task], errors: ["codex": "PRIVATE_ERROR_TEXT"]), at: 11)
    try speedCheck(recovered.snapshot(at: 11).state == .unavailable && recovered.snapshot(at: 11).rates.total == nil, "Read failure became zero")
    task.total += 20_000; task.input! += 20_000
    recovered.ingest(speedSample([task]), at: 12)
    try speedCheck(recovered.snapshot(at: 12).state == .gap, "Recovery did not invalidate the missing interval")
    for i in 13...22 { recovered.ingest(speedSample([task]), at: Double(i)) }
    try speedCheck(recovered.snapshot(at: 22).rates.total == 0, "Missing-period increment appeared as a recovery burst")
    task.pendingBytes = 1; recovered.ingest(speedSample([task]), at: 23)
    try speedCheck(recovered.snapshot(at: 23).reasons.contains("record_incomplete"), "Truncated records appeared complete")
    task.pendingBytes = 0; recovered.ingest(speedSample([task]), at: 24)
    recovered.ingest(speedSample([]), at: 25)
    for i in 26...40 { recovered.ingest(speedSample([]), at: Double(i)) }
    try speedCheck(recovered.snapshot(at: 40).state == .unavailable && recovered.snapshot(at: 40).rates.total == nil && recovered.snapshot(at: 40).reasons.contains("source_records_missing"), "Disappeared discovered source silently became healthy zero")
    try speedCheck(recovered.snapshot(at: 40).cumulative.total == task.total, "Lost source discarded the last known cumulative count")
    recovered.ingest(speedSample([task]), at: 41)
    try speedCheck(recovered.snapshot(at: 41).rates.total == nil, "Disappeared/reappeared record bridged its counters")

    let category = TokenSpeedEngine()
    var missing = speedTask(input: nil, output: nil, cached: nil)
    for i in 0...10 { category.ingest(speedSample([missing]), at: Double(i)) }
    result = category.snapshot(at: 10)
    try speedCheck(result.rates.total == 0 && result.rates.input == nil && result.metricStates.input == .unavailable, "Missing classifications were fabricated or poisoned known total")
    missing.input = 800_000; category.ingest(speedSample([missing]), at: 11)
    try speedCheck(category.snapshot(at: 11).state == .gap && category.snapshot(scope: .task(id: missing.id, provider: .codex), at: 11).reasons.contains("counter_appeared"), "New classification field did not rebaseline conservatively")

    for mutation in ["identity", "source", "total", "input", "cached", "cacheWrite"] {
        let reset = TokenSpeedEngine()
        var before = speedTask(provider: .claude)
        for i in 0...10 { reset.ingest(speedSample([before]), at: Double(i)) }
        switch mutation {
        case "identity": before.logIdentity = "different"
        case "source": before = speedTask(provider: .claude); before = TaskUsage(id: before.id, title: "fixture", project: "fixture", total: before.total, input: before.input, cached: before.cached, output: before.output, source: "new-source", provider: .claude, cacheWrite: before.cacheWrite, logIdentity: before.logIdentity)
        case "total": before.total -= 1
        case "input": before.input! -= 1; before.total += 1
        case "cached": before.cached! -= 1
        default: before.cacheWrite! -= 1
        }
        reset.ingest(speedSample([before]), at: 11)
        try speedCheck(reset.snapshot(at: 11).rates.total == nil && reset.snapshot(at: 11).state == .gap, "Counter/source/identity discontinuity was accepted: " + mutation)
    }

    let members = TokenSpeedEngine()
    var root = speedTask("parent"), child = speedTask("child", total: 5_000_000)
    child.parentID = root.id
    for i in 0...10 { root.total += 10; members.ingest(speedSample([root]), at: Double(i)) }
    members.ingest(speedSample([root, child]), at: 11)
    try speedCheck(members.snapshot(at: 11).rates.total == nil && members.snapshot(at: 11).reasons.contains("scope_changed"), "New member replayed its history")
    try speedCheck(members.snapshot(scope: .task(id: root.id, provider: .codex), at: 11).rates.total == 9, "Membership change damaged an existing task's continuous window")
    for i in 12...21 { root.total += 10; child.total += 30; members.ingest(speedSample([root, child, root]), at: Double(i)) }
    try speedCheck(members.snapshot(at: 21).rates.total == 40, "Parent and child own counters were aggregated more than once")
    try speedCheck(members.snapshot(at: 21).coverage.recordCount == 2, "Duplicate task ID was counted twice")
    var conflicting = root; conflicting.total += 1
    members.ingest(speedSample([root, child, conflicting]), at: 22)
    try speedCheck(members.snapshot(at: 22).rates.total == nil && members.snapshot(at: 22).reasons.contains("duplicate_conflict"), "Conflicting duplicate counters were silently chosen")

    let clock = TokenSpeedEngine()
    task = speedTask()
    clock.ingest(speedSample([task]), at: 0)
    for i in 1...10 { task.total += 10; clock.ingest(speedSample([task]), at: Double(i)) }
    let savedTotal = task.total
    task.total += 10_000; clock.ingest(speedSample([task]), at: 10); clock.ingest(speedSample([task]), at: 9)
    try speedCheck(clock.snapshot(at: 10).cumulative.total == savedTotal && clock.snapshot(at: 10).rates.total == 10, "Duplicate/backward sampling time changed counts")
    clock.ingest(speedSample([task]), at: 15)
    try speedCheck(clock.snapshot(at: 15).rates.total != nil, "Exactly five-second interval should be accepted")
    task.total += 10_000; clock.ingest(speedSample([task]), at: 20.01)
    try speedCheck(clock.snapshot(at: 20.01).rates.total == nil && clock.snapshot(at: 20.01).reasons.contains("sampling_gap"), "Long sample gap bridged unobserved usage")

    let mixed = TokenSpeedEngine()
    var codex = speedTask("same-id"), claude = speedTask("same-id", provider: .claude)
    for i in 0...60 {
        if i > 0 { codex.total += 10; codex.input! += 8; codex.output! += 2; claude.total += 20; claude.input! += 18; claude.output! += 2; claude.cached! += 5; claude.cacheWrite! += 7 }
        mixed.ingest(speedSample([codex, claude]), at: Double(i))
    }
    result = mixed.snapshot(window: .seconds60, at: 60)
    try speedCheck(result.rates.total == 30 && result.rates.input == 26 && result.rates.output == 4 && result.coverage.recordCount == 2, "Provider ID collision or Claude cache double counting")
    mixed.ingest(speedSample([codex, claude], errors: ["claude": "unavailable"]), at: 61)
    try speedCheck(mixed.snapshot(at: 61).rates.total == nil && mixed.snapshot(scope: .provider(.codex), at: 61).rates.total != nil, "All scope hid an established provider failure")
    let json = try result.encodedJSON()
    let text = String(decoding: json, as: UTF8.self)
    try speedCheck(!text.contains("PRIVATE_FIXTURE") && !text.contains("logPath") && !text.contains("title"), "Default speed JSON exposed content or paths")
    let unknownJSON = String(decoding: try initial.encodedJSON(), as: UTF8.self)
    try speedCheck(unknownJSON.contains("\"total\" : null"), "Unknown JSON numbers were serialized as zero or omitted")
    _ = try JSONDecoder().decode(TokenSpeedSnapshot.self, from: json)

    try runTokenSpeedReaderCompletenessChecks()
    try runTokenSpeedBufferChecks()
    print("PASS: Token observation speed fixtures; baseline/cache semantics/zero-vs-missing/windows/recovery/classification/reset/membership/dedup/clocks/parallel providers/privacy/reader completeness/bounded history")
}

private func runTokenSpeedReaderCompletenessChecks() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("token-speed-reader-" + UUID().uuidString)
    let project = folder.appendingPathComponent("projects/fixture")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func line(_ usage: [String: Int], id: String, timestamp: String = "2026-10-15T01:00:00Z") throws -> Data {
        var bytes = try JSONSerialization.data(withJSONObject: ["type": "assistant", "sessionId": "fixture", "timestamp": timestamp, "message": ["id": id, "usage": usage]], options: [.sortedKeys])
        bytes.append(10); return bytes
    }
    let file = project.appendingPathComponent("fixture.jsonl")
    try line(["input_tokens": 10], id: "a").write(to: file)
    let reader = ClaudeTelemetryReader(home: folder)
    var values = try reader.snapshot()
    try speedCheck(values.count == 1 && values[0].input == 10 && values[0].output == nil && !values[0].usageTotalComplete, "Claude missing required output was converted into known zero")
    let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
    try handle.write(contentsOf: line(["input_tokens": 10, "output_tokens": 4], id: "a")); try handle.close()
    values = try reader.snapshot()
    try speedCheck(values[0].usageTotalComplete && values[0].total == 14 && values[0].input == 10 && values[0].output == 4, "Complete Claude request update failed to recover or omitted optional caches were treated as missing")
    let append = try FileHandle(forWritingTo: file); try append.seekToEnd(); try append.write(contentsOf: Data("{\"type\":".utf8)); try append.close()
    values = try reader.snapshot()
    try speedCheck(values[0].pendingBytes > 0, "Claude partial JSON line was reported complete")
    let second = project.appendingPathComponent("newer.jsonl")
    try line(["input_tokens": 10, "output_tokens": 4], id: "a", timestamp: "2026-10-15T01:00:01Z").write(to: second)
    let merged = ClaudeTelemetryReader(home: folder)
    values = try merged.snapshot()
    try speedCheck(values[0].pendingBytes > 0 && values[0].total == 14, "Newer Claude duplicate washed away another file's partial record or counted request twice")
    let bad = try FileHandle(forWritingTo: file); try bad.seekToEnd(); try bad.write(contentsOf: Data("BAD\n".utf8)); try bad.close()
    values = try merged.snapshot()
    try speedCheck(values[0].readIssue != nil, "Newer Claude duplicate washed away a file's malformed record")
    let userFolder = folder.appendingPathComponent("user-only/projects/fixture")
    try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
    var user = try JSONSerialization.data(withJSONObject: ["type": "user", "sessionId": "only-user", "message": ["content": "fixture"]]); user.append(10)
    try user.write(to: userFolder.appendingPathComponent("user.jsonl"))
    let noUsage = try ClaudeTelemetryReader(home: folder.appendingPathComponent("user-only")).snapshot()
    try speedCheck(noUsage.count == 1 && noUsage[0].input == nil && noUsage[0].output == nil && !noUsage[0].usageTotalComplete, "Claude user-only record invented complete usage")
    let codexFolder = folder.appendingPathComponent("codex")
    try FileManager.default.createDirectory(at: codexFolder, withIntermediateDirectories: true)
    let codexLog = codexFolder.appendingPathComponent("fixture.jsonl")
    try Data("{\"type\":\"event_msg\"".utf8).write(to: codexLog)
    try speedCheck(TelemetryReader(home: codexFolder).latest(codexLog).pendingBytes > 0, "Codex partial JSON line was reported complete")
}

private func runTokenSpeedBufferChecks() throws {
    let engine = TokenSpeedEngine()
    var items = [TaskUsage]()
    for provider in [UsageProvider.codex, .claude] { for id in 0..<80 { items.append(speedTask("record-\(id)", provider: provider)) } }
    let begin = ProcessInfo.processInfo.systemUptime
    for sample in 0...600 {
        if sample > 0 { for i in items.indices { items[i].total += 5; items[i].input! += 4; items[i].output! += 1 } }
        engine.ingest(speedSample(items), at: Double(sample) * 0.5)
    }
    let ingestSeconds = ProcessInfo.processInfo.systemUptime - begin
    let snapshotBegin = ProcessInfo.processInfo.systemUptime
    var result = engine.snapshot(at: 300)
    for _ in 0..<9 { result = engine.snapshot(at: 300) }
    let snapshotSeconds = (ProcessInfo.processInfo.systemUptime - snapshotBegin) / 10
    try speedCheck(result.rates.total == 1600 && result.trend.count == 120 && result.providers.allSatisfy { $0.trend.count == 120 }, "160-record five-minute snapshot was incorrect")
    try speedCheck(engine.retainedTaskCount == 160 && engine.retainedSampleCount <= 162 * 1201, "Sampling history is unbounded")
    for sample in 601...900 { engine.ingest(speedSample(items), at: Double(sample) * 0.5) }
    try speedCheck(engine.retainedSampleCount <= 162 * 601, "History retained observations older than five minutes")
    let churn = TokenSpeedEngine()
    for sample in 0..<400 { churn.ingest(speedSample([speedTask("churn-\(sample)")]), at: Double(sample) * 0.5) }
    try speedCheck(churn.retainedTaskCount <= 320, "Record churn retained unbounded task IDs")
    print(String(format: "PASS: speed performance fixture 160 records / 601 polls / 300s; ingest %.3fs total, snapshot + 120s/provider trends %.6fs average; retained samples %d", ingestSeconds, snapshotSeconds, engine.retainedSampleCount))
}
