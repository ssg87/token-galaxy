import Foundation

/// Speeds describe newly observed local cumulative counters, not model generation throughput.
enum TokenSpeedWindow: Int, CaseIterable, Codable { case seconds10 = 10, seconds30 = 30, seconds60 = 60 }
enum TokenSpeedMetric: String, CaseIterable, Codable { case total, input, output }
enum TokenSpeedState: String, Codable { case notFound, warming, live, idle, gap, unavailable }

struct TokenSpeedScope: Equatable, Codable {
    enum Kind: String, Codable { case all, provider, task }
    let kind: Kind
    let provider: String?
    let taskID: String?
    static let all = TokenSpeedScope(kind: .all, provider: nil, taskID: nil)
    static func provider(_ provider: UsageProvider) -> Self { Self(kind: .provider, provider: provider.rawValue, taskID: nil) }
    static func task(id: String, provider: UsageProvider) -> Self { Self(kind: .task, provider: provider.rawValue, taskID: id) }
}

struct TokenSpeedRates: Codable {
    var total: Double?, input: Double?, output: Double?
    subscript(_ metric: TokenSpeedMetric) -> Double? {
        switch metric { case .total: return total; case .input: return input; case .output: return output }
    }
    private enum CodingKeys: String, CodingKey { case total, input, output }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(total, forKey: .total); try c.encode(input, forKey: .input); try c.encode(output, forKey: .output)
    }
}
struct TokenSpeedCounts: Codable {
    var total: Int64?, input: Int64?, output: Int64?
    private enum CodingKeys: String, CodingKey { case total, input, output }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(total, forKey: .total); try c.encode(input, forKey: .input); try c.encode(output, forKey: .output)
    }
}
struct TokenSpeedMetricStates: Codable {
    var total: TokenSpeedState, input: TokenSpeedState, output: TokenSpeedState
    subscript(_ metric: TokenSpeedMetric) -> TokenSpeedState {
        switch metric { case .total: return total; case .input: return input; case .output: return output }
    }
}
struct TokenSpeedCoverage: Codable {
    var windowSeconds: Int
    var observedSeconds: Double
    var complete: Bool
    var recordCount: Int
    var providerCount: Int
    var lastSampleAgeSeconds: Double?
    var lastGoodSampleAgeSeconds: Double?
    // Counts describe total-rate coverage. Classifications may still be unknown for included records.
    var includedRecordCount: Int = 0
    var excludedRecordCount: Int = 0
    var missingRecordCount: Int = 0
    var warmingRecordCount: Int = 0
    var partial: Bool = false
}
struct TokenSpeedTrendPoint: Codable {
    var at: TimeInterval
    var rates: TokenSpeedRates
    var state: TokenSpeedState
    var partial: Bool = false
    var includedRecordCount: Int = 0
    var excludedRecordCount: Int = 0
}
struct TokenSpeedProviderSnapshot: Codable {
    var provider: String
    var rates: TokenSpeedRates
    var cumulative: TokenSpeedCounts
    var state: TokenSpeedState
    var reasons: [String]
    var metricStates: TokenSpeedMetricStates
    var coverage: TokenSpeedCoverage
    var trend: [TokenSpeedTrendPoint]
}
struct TokenSpeedSnapshot: Codable {
    let schemaVersion: Int
    let name: String
    let scope: TokenSpeedScope
    let windowSeconds: Int
    /// Monotonic completion time of the most recent accepted sample. Never a log event timestamp.
    let sampledAt: TimeInterval?
    var rates: TokenSpeedRates
    var cumulative: TokenSpeedCounts
    var state: TokenSpeedState
    var reasons: [String]
    var metricStates: TokenSpeedMetricStates
    var coverage: TokenSpeedCoverage
    var trend: [TokenSpeedTrendPoint]
    var providers: [TokenSpeedProviderSnapshot]
    let scopeLimitPerProvider: Int
    let unit: String
    func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

private struct SpeedKey: Hashable { let provider: String, id: String }
private struct SpeedCounters: Equatable {
    var total: Int64, input: Int64?, output: Int64?, cached: Int64?, cacheWrite: Int64?
    var totalComplete: Bool
    init(_ task: TaskUsage) { total = task.total; input = task.input; output = task.output; cached = task.cached; cacheWrite = task.cacheWrite; totalComplete = task.usageTotalComplete }
    var counts: TokenSpeedCounts { TokenSpeedCounts(total: totalComplete ? total : nil, input: input, output: output) }
    var valid: Bool { total >= 0 && [input, output, cached, cacheWrite].allSatisfy { $0 == nil || $0! >= 0 } }
    func discontinuity(from old: Self) -> String? {
        let pairs: [(Int64?, Int64?)] = [(old.total, total), (old.input, input), (old.output, output), (old.cached, cached), (old.cacheWrite, cacheWrite)]
        if pairs.contains(where: { $0.0 != nil && $0.1 != nil && $0.1! < $0.0! }) { return "counter_regressed" }
        if pairs.contains(where: { $0.0 == nil && $0.1 != nil }) { return "counter_appeared" }
        return nil
    }
}
private struct SpeedRun {
    var since: TimeInterval?
    var state: TokenSpeedState
    var reasons: [String]
}
private struct SpeedFrame {
    var at: TimeInterval
    var delta: TokenSpeedRates
    var counts: TokenSpeedCounts
    var total: SpeedRun, input: SpeedRun, output: SpeedRun
    var recordCount: Int
    var discovered: Bool
    var lastGoodAt: TimeInterval?
    func run(_ metric: TokenSpeedMetric) -> SpeedRun {
        switch metric { case .total: return total; case .input: return input; case .output: return output }
    }
}
private struct SpeedHistory {
    // A bounded deque. Compaction is amortized, rather than moving all samples at every poll.
    private(set) var frames = [SpeedFrame]()
    private(set) var start = 0
    var count: Int { frames.count - start }
    var first: SpeedFrame? { start < frames.count ? frames[start] : nil }
    var last: SpeedFrame? { frames.last }
    mutating func append(_ frame: SpeedFrame) {
        frames.append(frame)
        while start < frames.count - 1 && (frames[start].at < frame.at - 300 || frames.count - start > 1201) { start += 1 }
        if start > 256 && start * 2 >= frames.count { frames.removeFirst(start); start = 0 }
    }
    func index(at time: TimeInterval) -> Int? {
        var lo = start, hi = frames.count
        while lo < hi { let m = (lo + hi) / 2; if frames[m].at <= time { lo = m + 1 } else { hi = m } }
        return lo > start ? lo - 1 : nil
    }
}
private struct SpeedTaskTrack {
    var history = SpeedHistory()
    var baseline: SpeedCounters?
    var identity = "", source = ""
    var lastSeen: TimeInterval
    var present = false
}
private struct SpeedProviderTrack {
    var history = SpeedHistory()
    var members = Set<SpeedKey>()
    var discovered = false
}
private struct SpeedReading {
    var rates: TokenSpeedRates
    var counts: TokenSpeedCounts
    var states: TokenSpeedMetricStates
    var reasons: [String]
    var coverage: TokenSpeedCoverage
    var state: TokenSpeedState { states.total }
}
private struct SpeedTrendCacheKey: Hashable { let provider: String, window: Int }

/// Own on the same serial queue as ingest/snapshot (the app uses its main queue).
/// Uses the reader's existing <=80 records/provider. It never scans logs or AllUsage deltas.
final class TokenSpeedEngine {
    static let retentionSeconds: TimeInterval = 300
    static let maximumSamplingGap: TimeInterval = 5
    private var providers = [String: SpeedProviderTrack]()
    private var tasks = [SpeedKey: SpeedTaskTrack]()
    private var latestAt: TimeInterval?
    private var trendReadings = [SpeedTrendCacheKey: [TimeInterval: SpeedReading]]()
    private let providerNames = [UsageProvider.codex.rawValue, UsageProvider.claude.rawValue]

    func ingest(_ sample: CombinedUsageSample, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard time.isFinite, time >= 0, latestAt == nil || time > latestAt! else { return }
        let longGap = latestAt.map { time - $0 > Self.maximumSamplingGap } ?? false
        for name in providerNames {
            var provider = providers[name] ?? SpeedProviderTrack()
            var unique = [SpeedKey: TaskUsage](), conflicts = Set<SpeedKey>()
            for task in sample.items where task.provider.rawValue == name {
                let key = SpeedKey(provider: name, id: task.id)
                if let old = unique[key] {
                    if SpeedCounters(old) != SpeedCounters(task) || old.logIdentity != task.logIdentity || old.source != task.source || old.readIssue != task.readIssue || old.pendingBytes != task.pendingBytes { conflicts.insert(key) }
                } else { unique[key] = task }
            }
            // The input is already limited by CombinedTelemetryReader; this also bounds fixture/custom clients.
            let keys = Set(unique.keys.sorted { $0.id < $1.id }.prefix(80))
            unique = unique.filter { keys.contains($0.key) }
            let summary = name == "codex" ? sample.codex : sample.claude
            let sourceFailure = sample.errors[name] != nil || (summary == nil && !unique.isEmpty)
            let wasDiscovered = provider.discovered
            provider.discovered = provider.discovered || !unique.isEmpty || (summary?.records ?? 0) > 0 || sourceFailure
            var steps = [(SpeedFrame, Bool)]()
            for key in keys.sorted(by: { $0.id < $1.id }) {
                guard let task = unique[key] else { continue }
                var track = tasks[key] ?? SpeedTaskTrack(lastSeen: time)
                let previous = track.history.last, counters = SpeedCounters(task)
                var issue: String?
                if sourceFailure { issue = "source_read_failed" }
                else if conflicts.contains(key) { issue = "duplicate_conflict" }
                else if task.readIssue != nil { issue = "record_read_failed" }
                else if task.pendingBytes > 0 { issue = "record_incomplete" }
                else if !task.usageTotalComplete { issue = "missing_total" }
                else if !counters.valid { issue = "invalid_counter" }
                var reset: String?
                if longGap { reset = "sampling_gap" }
                else if let old = track.baseline {
                    if task.logIdentity != track.identity { reset = "identity_changed" }
                    else if task.source != track.source { reset = "source_changed" }
                    else { reset = counters.discontinuity(from: old) }
                } else { reset = previous == nil ? "initial_baseline" : "record_recovered" }
                let rebased = reset != nil || issue != nil
                let healthy = issue == nil
                let baseState: TokenSpeedState = previous == nil ? .warming : .gap
                func run(_ known: Bool, _ metric: TokenSpeedMetric) -> SpeedRun {
                    if let issue = issue { return SpeedRun(since: nil, state: .unavailable, reasons: [issue]) }
                    if !known { return SpeedRun(since: nil, state: .unavailable, reasons: ["missing_" + metric.rawValue]) }
                    if let reset = reset { return SpeedRun(since: time, state: baseState, reasons: [reset]) }
                    return previous?.run(metric) ?? SpeedRun(since: time, state: .warming, reasons: ["initial_baseline"])
                }
                let old = track.baseline
                func delta(_ current: Int64?, _ before: Int64?) -> Double? {
                    guard healthy, !rebased, let current = current, let before = before, current >= before else { return nil }
                    return Double(current - before)
                }
                let frame = SpeedFrame(at: time,
                    delta: TokenSpeedRates(total: delta(counters.total, old?.total), input: delta(counters.input, old?.input), output: delta(counters.output, old?.output)),
                    counts: counters.counts, total: run(true, .total), input: run(counters.input != nil, .input), output: run(counters.output != nil, .output),
                    recordCount: 1, discovered: true, lastGoodAt: healthy ? time : previous?.lastGoodAt)
                track.history.append(frame); track.lastSeen = time; track.present = true
                track.baseline = healthy ? counters : nil; track.identity = task.logIdentity; track.source = task.source
                tasks[key] = track; steps.append((frame, rebased))
            }
            // A vanished record is not allowed to bridge a future reappearance.
            for key in provider.members.subtracting(keys) {
                guard var track = tasks[key] else { continue }
                let missing = SpeedRun(since: nil, state: .unavailable, reasons: [sourceFailure ? "source_read_failed" : "record_missing"])
                let frame = SpeedFrame(at: time, delta: TokenSpeedRates(total: nil, input: nil, output: nil), counts: track.history.last?.counts ?? Self.emptyCounts,
                    total: missing, input: missing, output: missing, recordCount: 0, discovered: true, lastGoodAt: track.history.last?.lastGoodAt)
                track.history.append(frame); track.baseline = nil; track.present = false; tasks[key] = track
            }
            let previous = provider.history.last
            let missingRecords = provider.discovered && keys.isEmpty && !sourceFailure
            let unhealthy = sourceFailure || missingRecords || steps.contains { $0.0.total.since == nil }
            let membershipChanged = provider.members != keys
            let reset = longGap ? "sampling_gap" : !wasDiscovered && provider.discovered ? "initial_baseline" : membershipChanged ? "scope_changed" : steps.contains(where: { $0.1 }) ? "record_rebased" : previous?.total.since == nil && provider.discovered ? "source_recovered" : nil
            func providerRun(_ metric: TokenSpeedMetric) -> SpeedRun {
                if !provider.discovered { return SpeedRun(since: nil, state: .notFound, reasons: ["source_not_found"]) }
                if unhealthy { return SpeedRun(since: nil, state: .unavailable, reasons: sourceFailure ? ["source_read_failed"] : missingRecords ? ["source_records_missing"] : Array(Set(steps.flatMap { $0.0.total.reasons })).sorted()) }
                if steps.contains(where: { $0.0.run(metric).since == nil }) { return SpeedRun(since: nil, state: .unavailable, reasons: ["missing_" + metric.rawValue]) }
                if let reset = reset { return SpeedRun(since: time, state: !wasDiscovered ? .warming : .gap, reasons: [reset]) }
                if let previous = previous, previous.run(metric).since != nil { return previous.run(metric) }
                return SpeedRun(since: time, state: wasDiscovered ? .gap : .warming, reasons: ["category_recovered"])
            }
            func summedDelta(_ metric: TokenSpeedMetric) -> Double? {
                guard !unhealthy, reset == nil else { return nil }
                let values = steps.map { $0.0.delta[metric] }
                guard values.allSatisfy({ $0 != nil }) else { return nil }
                return values.reduce(0) { $0 + $1! }
            }
            let counts = !provider.discovered ? Self.emptyCounts : sourceFailure || missingRecords ? previous?.counts ?? Self.emptyCounts : Self.sumCounts(steps.map { $0.0.counts })
            provider.history.append(SpeedFrame(at: time, delta: TokenSpeedRates(total: summedDelta(.total), input: summedDelta(.input), output: summedDelta(.output)), counts: counts,
                total: providerRun(.total), input: providerRun(.input), output: providerRun(.output), recordCount: keys.count, discovered: provider.discovered,
                lastGoodAt: !unhealthy && provider.discovered ? time : previous?.lastGoodAt))
            provider.members = keys; providers[name] = provider
        }
        latestAt = time
        pruneTrendReadings(at: time)
        tasks = tasks.filter { $0.value.present || time - $0.value.lastSeen <= Self.retentionSeconds }
        // Churn must not retain unbounded IDs; always preserve the current <=160 records.
        if tasks.count > 320 {
            let obsolete = tasks.filter { !$0.value.present }.sorted { a, b in a.value.lastSeen == b.value.lastSeen ? a.key.id < b.key.id : a.value.lastSeen < b.value.lastSeen }
            for entry in obsolete.prefix(tasks.count - 320) { tasks.removeValue(forKey: entry.key) }
        }
    }

    func snapshot(scope: TokenSpeedScope = .all, window: TokenSpeedWindow = .seconds10, at time: TimeInterval? = nil, trendSeconds: Int = 120) -> TokenSpeedSnapshot {
        let now = time.flatMap { $0.isFinite ? $0 : nil } ?? ProcessInfo.processInfo.systemUptime
        let seconds = min(300, max(0, trendSeconds))
        let selectedNames = scope.kind == .all ? providerNames : providerNames.filter { $0 == scope.provider }
        let providerSnapshots = selectedNames.map { name -> TokenSpeedProviderSnapshot in
            let reading = readScope(provider: name, taskID: scope.kind == .task ? scope.taskID : nil, window: window, at: now)
            let points: [TokenSpeedTrendPoint]
            if seconds > 0, latestAt != nil {
                let end = floor(now)
                points = stride(from: seconds - 1, through: 0, by: -1).map { i in
                    let at = end - Double(i)
                    return trendPoint(readTrendScope(provider: name, taskID: scope.kind == .task ? scope.taskID : nil, window: window, at: at), at: at)
                }
            } else { points = [] }
            return TokenSpeedProviderSnapshot(provider: name, rates: reading.rates, cumulative: reading.counts, state: reading.state, reasons: reading.reasons,
                metricStates: reading.states, coverage: reading.coverage, trend: points)
        }
        let reading: SpeedReading
        if scope.kind == .all { reading = combine(providerSnapshots.map { SpeedReading(rates: $0.rates, counts: $0.cumulative, states: $0.metricStates, reasons: $0.reasons, coverage: $0.coverage) }, window: window) }
        else if let p = providerSnapshots.first { reading = SpeedReading(rates: p.rates, counts: p.cumulative, states: p.metricStates, reasons: p.reasons, coverage: p.coverage) }
        else { reading = read(nil, window: window, at: now) }
        var combinedTrend = [TokenSpeedTrendPoint]()
        if scope.kind == .all, seconds > 0, latestAt != nil {
            // Reuse each provider's already-computed points instead of rereading 160 task histories.
            for i in 0..<seconds {
                let points = providerSnapshots.compactMap { $0.trend.indices.contains(i) ? $0.trend[i] : nil }
                guard let first = points.first else { continue }
                let valid = points.filter { $0.rates.total != nil }
                func sum(_ metric: TokenSpeedMetric) -> Double? {
                    guard !valid.isEmpty, valid.allSatisfy({ $0.rates[metric] != nil }) else { return nil }
                    return valid.reduce(0) { $0 + $1.rates[metric]! }
                }
                let total = sum(.total), states = points.map { $0.state }
                let state = total.map { $0 > 0 ? TokenSpeedState.live : .idle } ?? unavailableState(states)
                let included = points.reduce(0) { $0 + $1.includedRecordCount }, excluded = points.reduce(0) { $0 + $1.excludedRecordCount }
                combinedTrend.append(TokenSpeedTrendPoint(at: first.at, rates: TokenSpeedRates(total: total, input: sum(.input), output: sum(.output)), state: state,
                    partial: total != nil && (excluded > 0 || points.contains { $0.partial || ($0.state != .notFound && $0.rates.total == nil) }), includedRecordCount: included, excludedRecordCount: excluded))
            }
        } else { combinedTrend = providerSnapshots.first?.trend ?? [] }
        return TokenSpeedSnapshot(schemaVersion: 2, name: "Token 观测速度", scope: scope, windowSeconds: window.rawValue, sampledAt: latestAt,
            rates: reading.rates, cumulative: reading.counts, state: reading.state, reasons: reading.reasons, metricStates: reading.states, coverage: reading.coverage,
            trend: combinedTrend, providers: providerSnapshots, scopeLimitPerProvider: 80, unit: "token/s")
    }

    private static let emptyCounts = TokenSpeedCounts(total: nil, input: nil, output: nil)
    private static func sumCounts(_ counts: [TokenSpeedCounts]) -> TokenSpeedCounts {
        func sum(_ values: [Int64?]) -> Int64? {
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            var result: Int64 = 0
            for value in values { let addition = result.addingReportingOverflow(value!); if addition.overflow { return nil }; result = addition.partialValue }
            return result
        }
        return TokenSpeedCounts(total: sum(counts.map { $0.total }), input: sum(counts.map { $0.input }), output: sum(counts.map { $0.output }))
    }
    private func read(_ history: SpeedHistory?, window: TokenSpeedWindow, at time: TimeInterval) -> SpeedReading {
        let w = Double(window.rawValue)
        guard let history = history, let index = history.index(at: time) else {
            return SpeedReading(rates: TokenSpeedRates(total: nil, input: nil, output: nil), counts: Self.emptyCounts,
                states: TokenSpeedMetricStates(total: .notFound, input: .notFound, output: .notFound), reasons: ["source_not_found"],
                coverage: TokenSpeedCoverage(windowSeconds: window.rawValue, observedSeconds: 0, complete: false, recordCount: 0, providerCount: 0, lastSampleAgeSeconds: nil, lastGoodSampleAgeSeconds: nil))
        }
        let frame = history.frames[index], age = max(0, time - frame.at)
        var reasons = Set<String>(), observed: Double = 0
        func metric(_ metric: TokenSpeedMetric) -> (Double?, TokenSpeedState) {
            let run = frame.run(metric)
            guard frame.discovered else { reasons.insert("source_not_found"); return (nil, .notFound) }
            guard age <= Self.maximumSamplingGap else { reasons.insert("sample_stale"); return (nil, .unavailable) }
            guard let since = run.since else { reasons.formUnion(run.reasons); return (nil, run.state) }
            let available = max(0, frame.at - max(since, history.first?.at ?? since))
            if metric == .total { observed = min(w, available) }
            guard available + 0.000_001 >= w else { reasons.formUnion(run.reasons); reasons.insert("window_incomplete"); return (nil, run.state) }
            let cutoff = frame.at - w
            // Difference against the last observed frame <= cutoff is equivalent to summing
            // deltas in (cutoff, completion], and needs only a binary lookup per window.
            guard let anchorIndex = history.index(at: cutoff), history.frames[anchorIndex].run(metric).since == run.since else {
                reasons.insert("window_incomplete"); return (nil, run.state)
            }
            func count(_ counts: TokenSpeedCounts) -> Int64? {
                switch metric { case .total: return counts.total; case .input: return counts.input; case .output: return counts.output }
            }
            guard let current = count(frame.counts), let before = count(history.frames[anchorIndex].counts), current >= before else {
                reasons.insert("missing_" + metric.rawValue); return (nil, .unavailable)
            }
            let delta = current - before
            return (Double(delta) / w, delta > 0 ? .live : .idle)
        }
        let total = metric(.total), input = metric(.input), output = metric(.output)
        let included = total.0 == nil ? 0 : frame.recordCount
        let excluded = max(0, frame.recordCount - included)
        let warming = [.warming, .gap].contains(total.1) ? excluded : 0
        return SpeedReading(rates: TokenSpeedRates(total: total.0, input: input.0, output: output.0), counts: frame.counts,
            states: TokenSpeedMetricStates(total: total.1, input: input.1, output: output.1), reasons: reasons.sorted(),
            coverage: TokenSpeedCoverage(windowSeconds: window.rawValue, observedSeconds: observed, complete: total.0 != nil, recordCount: frame.recordCount,
                providerCount: frame.discovered ? 1 : 0, lastSampleAgeSeconds: age, lastGoodSampleAgeSeconds: frame.lastGoodAt.map { max(0, time - $0) },
                includedRecordCount: included, excludedRecordCount: excluded, missingRecordCount: excluded - warming, warmingRecordCount: warming))
    }
    private func unavailableState(_ states: [TokenSpeedState]) -> TokenSpeedState {
        if states.contains(.unavailable) { return .unavailable }
        if states.contains(.gap) { return .gap }
        if states.contains(.warming) { return .warming }
        return .notFound
    }
    private func readScope(provider: String, taskID: String?, window: TokenSpeedWindow, at time: TimeInterval) -> SpeedReading {
        if let taskID = taskID { return read(tasks[SpeedKey(provider: provider, id: taskID)]?.history, window: window, at: time) }
        // Provider history retains discovery, cumulative counts and source-level failure metadata.
        // Rate eligibility comes exclusively from each task's own continuous window.
        let metadata = read(providers[provider]?.history, window: window, at: time)
        guard metadata.coverage.providerCount > 0 else { return metadata }
        var members = [SpeedReading]()
        for (key, task) in tasks where key.provider == provider {
            guard let index = task.history.index(at: time), task.history.frames[index].recordCount > 0 else { continue }
            members.append(read(task.history, window: window, at: time))
        }
        guard !members.isEmpty else { return metadata }
        var result = combine(members, window: window)
        result.counts = metadata.counts
        result.coverage.providerCount = 1
        return result
    }
    private func combine(_ readings: [SpeedReading], window: TokenSpeedWindow) -> SpeedReading {
        let active = readings.filter { $0.coverage.providerCount > 0 }
        guard !active.isEmpty else { return read(nil, window: window, at: 0) }
        let included = active.filter { $0.rates.total != nil && $0.coverage.includedRecordCount > 0 }
        func metric(_ metric: TokenSpeedMetric) -> (Double?, TokenSpeedState) {
            let values = included.map { $0.rates[metric] }
            if !included.isEmpty, values.allSatisfy({ $0 != nil }) { let sum = values.reduce(0) { $0 + $1! }; return (sum, sum > 0 ? .live : .idle) }
            return (nil, unavailableState((included.isEmpty ? active : included).map { $0.states[metric] }))
        }
        let total = metric(.total), input = metric(.input), output = metric(.output)
        let includedCount = active.reduce(0) { $0 + $1.coverage.includedRecordCount }
        let excludedCount = active.reduce(0) { $0 + $1.coverage.excludedRecordCount }
        let partial = !included.isEmpty && (excludedCount > 0 || included.count < active.count || active.contains { $0.coverage.partial })
        var reasons = Set(active.flatMap { $0.reasons })
        if partial { reasons.insert("partial_coverage") }
        let freshReadings = included.isEmpty ? active : included
        return SpeedReading(rates: TokenSpeedRates(total: total.0, input: input.0, output: output.0), counts: Self.sumCounts(active.map { $0.counts }),
            states: TokenSpeedMetricStates(total: total.1, input: input.1, output: output.1), reasons: reasons.sorted(),
            coverage: TokenSpeedCoverage(windowSeconds: window.rawValue, observedSeconds: freshReadings.map { $0.coverage.observedSeconds }.min() ?? 0, complete: total.0 != nil,
                recordCount: active.reduce(0) { $0 + $1.coverage.recordCount }, providerCount: active.count,
                lastSampleAgeSeconds: freshReadings.compactMap { $0.coverage.lastSampleAgeSeconds }.max(), lastGoodSampleAgeSeconds: freshReadings.compactMap { $0.coverage.lastGoodSampleAgeSeconds }.max(),
                includedRecordCount: includedCount, excludedRecordCount: excludedCount,
                missingRecordCount: active.reduce(0) { $0 + $1.coverage.missingRecordCount }, warmingRecordCount: active.reduce(0) { $0 + $1.coverage.warmingRecordCount }, partial: partial))
    }
    private func trendPoint(_ reading: SpeedReading, at: TimeInterval) -> TokenSpeedTrendPoint {
        TokenSpeedTrendPoint(at: at, rates: reading.rates, state: reading.state, partial: reading.coverage.partial,
            includedRecordCount: reading.coverage.includedRecordCount, excludedRecordCount: reading.coverage.excludedRecordCount)
    }
    private func pruneTrendReadings(at time: TimeInterval) {
        for key in Array(trendReadings.keys) {
            trendReadings[key] = trendReadings[key]?.filter { $0.key > time - Self.retentionSeconds }
        }
    }
    private func readTrendScope(provider: String, taskID: String?, window: TokenSpeedWindow, at time: TimeInterval) -> SpeedReading {
        // Future/partial seconds can change when the next sample arrives. Never cache those,
        // and keep current rate cards outside this path. Each completed historical second is fixed.
        guard taskID == nil, let latest = latestAt, time >= 0, time <= latest,
              time > latest - Self.retentionSeconds, floor(time) == time else {
            return readScope(provider: provider, taskID: taskID, window: window, at: time)
        }
        let key = SpeedTrendCacheKey(provider: provider, window: window.rawValue)
        if let cached = trendReadings[key]?[time] { return cached }
        let reading = readScope(provider: provider, taskID: nil, window: window, at: time)
        var entries = trendReadings[key] ?? [:]
        entries[time] = reading
        entries = entries.filter { $0.key > latest - Self.retentionSeconds }
        if entries.count > 300 {
            for expired in entries.keys.sorted().prefix(entries.count - 300) { entries.removeValue(forKey: expired) }
        }
        trendReadings[key] = entries
        return reading
    }
    /// Fixture diagnostics only; no content or identifiers.
    var retainedSampleCount: Int { providers.values.reduce(0) { $0 + $1.history.count } + tasks.values.reduce(0) { $0 + $1.history.count } }
    var retainedTaskCount: Int { tasks.count }
    var retainedTrendPointCount: Int { trendReadings.values.reduce(0) { $0 + $1.count } }
    var maximumRetainedTrendPointsPerScope: Int { trendReadings.values.map { $0.count }.max() ?? 0 }
}
