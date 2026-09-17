import Foundation
import simd

struct TokenScale {
    let tier: Int
    let radius: Float
    let grains: Int
    let layers: Int
    static func cumulative(_ total: Int64) -> TokenScale {
        let thresholds: [Double] = [0, 1_000, 100_000, 1_000_000, 10_000_000]
        let t = max(0, Double(total))
        let tier = thresholds.lastIndex(where: { t >= $0 }) ?? 0
        let upper = tier == 4 ? 100_000_000 : thresholds[tier + 1]
        let lower = max(1, thresholds[tier])
        let fraction = Float(min(1, max(0, log10(max(1, t) / lower) / log10(upper / lower))))
        let radius: [Float] = [0.30, 0.41, 0.53, 0.74, 0.92]
        let grains = [260, 1200, 3200, 7200, 12800]
        return TokenScale(tier: tier, radius: radius[tier] + fraction * 0.045,
                          grains: grains[tier] + Int(fraction * Float(grains[tier]) * 0.18), layers: tier)
    }
    static func increment(_ count: Int64) -> (strength: Float, streams: Int, duration: Float, tier: Int) {
        let count = max(1, count)
        let tier = count < 1_000 ? 0 : count < 100_000 ? 1 : count < 1_000_000 ? 2 : count < 10_000_000 ? 3 : 4
        let strength = min(1.6, 0.24 + Float(log10(Double(count) + 1)) * 0.17)
        return (strength, [1, 3, 7, 14, 24][tier], [2.2, 2.8, 3.4, 4.2, 5.2][tier], tier)
    }
}
func stableSeed(_ text: String) -> Float {
    var h: UInt64 = 1469598103934665603
    for c in text.utf8 { h = (h ^ UInt64(c)) &* 1099511628211 }
    return Float(h % 1_000_000) / 1_000_000
}
struct GalaxyGPU {
    var brand: SIMD4<Float>      // provider, stale, reserved, reserved
    var space: SIMD4<Float>       // xyz and radius
    var visual: SIMD4<Float>      // tier, lead weight, particle count, seed
    var motion: SIMD4<Float>      // integrated phase, work energy, work phase, token energy
    var flow: SIMD4<Float>        // work age, token age, event seed, context fill (-1 unknown)
    var burst: SIMD4<Float>       // token duration, stream count, increment tier, work envelope
}
struct LinkGPU {
    var source: SIMD4<Float>
    var target: SIMD4<Float>
    var style: SIMD4<Float>       // activity, phase, seed, direction
}
struct SceneGPU {
    var recent: SIMD4<Float>     // recent 10s Codex/Claude strength, smoothed Claude share, reserved
    var channels: SIMD4<Float>   // Codex work/token, Claude work/token
    var clocks: SIMD4<Float>     // Codex/Claude flow clocks, their lead tiers
    var layout: SIMD4<Float>     // dual sources, has Codex, has Claude, lead provider
    var viewport: SIMD4<Float>   // pixels, scene time, surface mode
    var dynamics: SIMD4<Float>   // integrated flow time, work, token, record count
    var settings: SIMD4<Float>   // stale, node count, lead tier, reduced motion
    var focus: SIMD4<Float>      // active branch clearing xyz/radius
    var spirit: SIMD4<Float>     // mood, mood age, touch age, enabled
}
private struct NodeMotion {
    var phase: Float = 0
    var position = SIMD3<Float>(repeating: 0)
    var target = SIMD3<Float>(repeating: 0)
    var workAt: Float = -100
    var workPhase: WorkPhase = .quiet
    var workSeed: Float = 0
    var workLevel: Float = 0
    var tokenAt: Float = -100
    var tokenCount: Int64 = 0
    var usageSeed: Float = 0
    var pending = [WorkEvent]()
    var workEnergy: Float = 0
    var tokenEnergy: Float = 0
    var born: Float = 0
    var radius: Float = 0
}
/// Monotonic idle time belongs to interactions with this app, not other apps.
struct IdleConversationFocus {
    var lastInteraction: TimeInterval
    var lastSwitch: TimeInterval = -.infinity
    init(now: TimeInterval = ProcessInfo.processInfo.systemUptime) { lastInteraction = now }
    mutating func interact(now: TimeInterval) { lastInteraction = now }
    func ready(now: TimeInterval) -> Bool { now - lastInteraction >= 60 && now - lastSwitch >= 5 }
    mutating func switched(now: TimeInterval) { lastSwitch = now }
}
/// One continuous field, with a stable lead family and observed activity as input.
/// All visible graph edges are derived from parentID; light on an edge means that
/// branch is active, not an assertion about a network packet or model FLOPS.
final class GalaxyModel {
    private(set) var tasks = [TaskUsage]()
    private(set) var shown = [TaskUsage]()
    private(set) var nodes = [GalaxyGPU]()
    private(set) var links = [LinkGPU]()
    private(set) var clock: Float = 0
    private(set) var flowClock: Float = 0
    private(set) var providerDrive=SIMD4<Float>(repeating:0)
    private var recentUsage = [(at: Float, amount: SIMD2<Double>)]()
    private(set) var recentTotals = SIMD2<Double>(repeating:0)
    private(set) var recentVisual = SIMD4<Float>(0,0,0.5,0)
    private(set) var providerClocks=SIMD2<Float>(repeating:0)
    var dualProvider:Bool{Set(tasks.map{$0.provider}).count>1}
    private(set) var workDrive: Float = 0
    private(set) var tokenDrive: Float = 0
    private(set) var focusID: String?
    private(set) var receivedEvents = 0
    private(set) var receivedTokens: Int64 = 0
    var selected: String? { didSet { chooseVisible(); rebuild() } }
    var stale = false
    private var state = [String: NodeMotion]()
    private var byID = [String: TaskUsage]()
    private(set) var handoffAge: Float = 100
    private var leadID: String?
    private var lastFocusMessage: TimeInterval = 0
    // A slow idle baseline; observed work and token acceleration retain their original strength.
    private let idleRotationRate: Float = 0.01125
    private func rotationRate(_ n: NodeMotion) -> Float { idleRotationRate + n.workEnergy * 0.75 + n.tokenEnergy * 0.62 }
    func rotationRate(for id: String) -> Float { state[id].map { rotationRate($0) } ?? idleRotationRate }
    func fastestConversation(keeping current: String?) -> String? {
        let candidates = tasks.filter { $0.isMainConversation && $0.readIssue == nil && $0.pendingBytes == 0 }
        let ranked = candidates.sorted {
            let a = rotationRate(for: $0.id), b = rotationRate(for: $1.id)
            return a == b ? $0.id < $1.id : a > b
        }
        guard let best = ranked.first, rotationRate(for: best.id) > idleRotationRate + 0.005 else { return nil }
        if let current = current, candidates.contains(where: { $0.id == current }),
           rotationRate(for: current) >= rotationRate(for: best.id) - 0.001 { return current }
        return best.id
    }
    private func family(_ id: String) -> String {
        var current = id, seen = Set<String>()
        while let parent = byID[current]?.parentID, byID[parent] != nil, !seen.contains(parent) {
            seen.insert(current); current = parent
        }
        return current
    }
    func update(_ items: [TaskUsage], deltas: [String: Int64], events: [String: [WorkEvent]]) {
        tasks = items; byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        if focusID == nil || byID[focusID!] == nil {
            let newest = items.max { ($0.lastUserAt ?? $0.lastEventAt ?? 0) < ($1.lastUserAt ?? $1.lastEventAt ?? 0) }
            focusID = newest.map { family($0.id) }
        }
        var freshUsage=SIMD2<Double>(repeating:0)
        for t in items {
            if state[t.id] == nil { var n = NodeMotion(); n.born = clock; n.phase = stableSeed(t.id) * 9; state[t.id] = n }
            if let fresh = events[t.id], !fresh.isEmpty {
                // Prefer meaningful transitions over a trailing generic reply marker.
                for event in fresh {
                    var n = state[t.id]!
                    if event.phase == .input || (clock - n.workAt >= 0.30 && n.pending.isEmpty) {
                        if event.phase == .input { n.pending.removeAll() }
                        n.workAt = clock; n.workPhase = event.phase; n.workSeed = stableSeed(event.id)
                        n.workLevel = event.phase == .waiting ? 0 : event.phase == .thinking ? 0.72 : event.phase == .complete ? 0.55 : 1
                    } else if n.pending.last?.phase != event.phase {
                        n.pending.append(event); if n.pending.count > 6 { n.pending.removeFirst() }
                    }
                    state[t.id] = n; receivedEvents += 1
                    if event.phase == .input && event.at > lastFocusMessage { lastFocusMessage = event.at; focusID = family(t.id) }
                }
            }
            if let count = deltas[t.id], count > 0 {
                state[t.id]!.tokenAt = clock; state[t.id]!.tokenCount = count
                state[t.id]!.usageSeed = stableSeed("\(t.id):\(count):\(clock):\(receivedTokens)")
                receivedTokens += count
                freshUsage[t.provider == .codex ? 0 : 1] += Double(count)
            }
        }
        if freshUsage.x+freshUsage.y > 0 {recentUsage.append((clock,freshUsage))}
        state = state.filter { byID[$0.key] != nil }
        chooseVisible()
        rebuild()
    }
    private func chooseVisible() {
        guard !tasks.isEmpty else { shown = []; return }
        let root = selected.map { family($0) } ?? focusID ?? family(tasks[0].id)
        func score(_ t: TaskUsage) -> Double {
            let n = state[t.id]
            let fresh = n.map { Double(max($0.workAt, $0.tokenAt)) } ?? -100
            return (family(t.id) == root ? 1_000_000 : 0) + (t.id == selected ? 2_000_000 : 0) + fresh * 100 + (t.lastEventAt ?? 0) / 1_000_000
        }
        let ranked = tasks.sorted { score($0) > score($1) }
        var ids = [String]()
        func include(_ id: String) { if byID[id] != nil && !ids.contains(id) && ids.count < 18 { ids.append(id) } }
        include(root)
        // Preserve both identities in one field; only the selected main is a lead.
        for provider in [UsageProvider.codex, .claude] {
            if let other = ranked.first(where: { $0.provider == provider && $0.isMainConversation && $0.id != root }) { include(other.id) }
        }
        for task in ranked.prefix(14) {if let p=task.parentID{include(p)};include(task.id)}
        shown = ids.compactMap { byID[$0] }
        if leadID != shown.first?.id {
            if leadID != nil { handoffAge = 0 }
            leadID = shown.first?.id
        }
        // Stable orbital anchors, re-evaluated only as the visible set changes.
        for (index, t) in shown.enumerated() {
            guard var n = state[t.id] else { continue }
            let h = stableSeed(t.id)
            if index == 0 { n.target = SIMD3(0, 0, 0.02) }
            else {
                let parentIndex = shown.firstIndex { $0.id == t.parentID }
                let childAngles: [Float] = [0.95, 4.15, 2.2, 5.7, 0.15, 3.2, 1.55, 4.8]
                let sibling = shown.prefix(index).filter { $0.parentID == t.parentID }.count
                let angle = parentIndex == 0 ? childAngles[sibling % childAngles.count] + h * 0.06 : Float(index-1)*2.399963+h*0.32
                let radius: Float = parentIndex == 0 ? 0.65 + Float(index % 3) * 0.02 : 0.66 + h * 0.04
                n.target = SIMD3(cos(angle) * radius, sin(angle) * radius * 0.93, (h - 0.5) * 0.60)
                if let parentIndex = parentIndex, parentIndex > 0, let parent = state[shown[parentIndex].id] {
                    n.target = parent.target + SIMD3(cos(angle) * 0.18, sin(angle) * 0.18, 0.03)
                }
            }
            if index > 0 {
                let distance = simd_length(SIMD2(n.target.x,n.target.y))
                if distance > 0.70 { n.target.x *= 0.70/distance;n.target.y *= 0.70/distance }
            }
            if clock < 0.1 { n.position = n.target } else if n.born == clock { n.position = t.parentID.flatMap { state[$0]?.position } ?? n.target }
            state[t.id] = n
        }
    }
    func step(_ dt: Float, reduceMotion: Bool = false) {
        guard dt > 0 else { return }
        // Event lifetimes progress even when motion is reduced; movement does not.
        clock += dt
        if !reduceMotion { handoffAge += dt }
        var workPeak: Float = 0, tokenPeak: Float = 0
        var drive=SIMD4<Float>(repeating:0)
        for task in tasks {
            guard var n = state[task.id] else { continue }
            if clock - n.workAt >= 0.30, !n.pending.isEmpty {
                let next = n.pending.removeFirst();n.workAt = clock;n.workPhase = next.phase;n.workSeed = stableSeed(next.id)
                n.workLevel = next.phase == .waiting ? 0 : next.phase == .thinking ? 0.72 : next.phase == .complete ? 0.55 : 1
            }
            let workAge = clock - n.workAt
            let workDuration: Float = n.workPhase == .thinking ? 5.5 : n.workPhase == .complete ? 2.2 : 3.2
            var workTarget = n.workLevel * max(0, 1 - max(0, workAge - 0.35) / workDuration)
            if (n.workPhase == .thinking || n.workPhase == .tool), task.isWorking,
               workAge < 60, Date().timeIntervalSince1970 - (task.lastEventAt ?? 0) < 60 {
                workTarget = max(workTarget, 0.26)
            }
            if task.provider == .claude,task.isWorking,workAge<120,![WorkPhase.complete,.interrupted,.waiting,.quiet].contains(n.workPhase){workTarget=max(workTarget,0.26)}
            let scale = TokenScale.increment(n.tokenCount)
            let tokenTarget = n.tokenCount > 0 ? scale.strength * max(0, 1 - max(0, clock - n.tokenAt - 0.2) / scale.duration) : 0
            n.workEnergy += (workTarget - n.workEnergy) * min(1, dt * (workTarget > n.workEnergy ? 26 : 5))
            n.tokenEnergy += (tokenTarget - n.tokenEnergy) * min(1, dt * (tokenTarget > n.tokenEnergy ? 26 : 5))
            if !reduceMotion {
                n.phase += dt * rotationRate(n)
                n.position += (n.target - n.position) * min(1, dt * 4)
            }
            let isLead = task.id == shown.first?.id
            let targetRadius = min(TokenScale.cumulative(task.total).radius * (isLead ? 0.86 : (task.parentID == nil ? 0.23 : 0.19)), isLead ? 0.78 : 0.20)
            if n.radius == 0 || reduceMotion { n.radius = targetRadius }
            else { n.radius += (targetRadius - n.radius) * min(1, dt * (isLead ? 4.5 : 9)) }
            workPeak = max(workPeak, n.workEnergy); tokenPeak = max(tokenPeak, n.tokenEnergy)
            if task.readIssue==nil && task.pendingBytes==0{let i=task.provider == .codex ? 0:2;drive[i]=max(drive[i],n.workEnergy);drive[i+1]=max(drive[i+1],n.tokenEnergy)}
            state[task.id] = n
        }
        recentUsage.removeAll { clock-$0.at >= 10 }
        recentTotals=recentUsage.reduce(SIMD2<Double>(repeating:0)) {$0+$1.amount}
        let recentSum=recentTotals.x+recentTotals.y
        let targetShare:Float=recentSum>0 ? Float(recentTotals.y/recentSum) : 0.5
        recentVisual.z += (targetShare-recentVisual.z)*min(1,dt*2)
        recentVisual.x += (Float(min(1,log10(recentTotals.x+1)/6))-recentVisual.x)*min(1,dt*2)
        recentVisual.y += (Float(min(1,log10(recentTotals.y+1)/6))-recentVisual.y)*min(1,dt*2)
        workDrive = workPeak; tokenDrive = tokenPeak;providerDrive=drive
        if !reduceMotion{providerClocks.x+=dt*(0.035+drive.x*0.34+drive.y*0.28+recentVisual.x*0.3);providerClocks.y+=dt*(0.035+drive.z*0.34+drive.w*0.28+recentVisual.y*0.3)}
        if !reduceMotion { flowClock += dt * (0.035 + workDrive * 0.34 + tokenDrive * 0.28) }
        rebuild()
    }
    private func rebuild() {
        nodes = []
        for (index, t) in shown.enumerated() {
            guard let n = state[t.id] else { continue }
            let mass = TokenScale.cumulative(t.total)
            let scale = TokenScale.increment(n.tokenCount)
            let isLead = index == 0
            let lead: Float = isLead ? 1 : 0
            let targetRadius = min(mass.radius * (isLead ? 0.86 : (t.parentID == nil ? 0.23 : 0.19)), isLead ? 0.78 : 0.20)
            let radius = n.radius > 0 ? n.radius : targetRadius
            let age = clock - n.workAt, tokenAge = clock - n.tokenAt
            let context = t.contextInput.flatMap { input in t.contextLimit.flatMap { $0 > 0 ? min(1, Float(input) / Float($0)) : nil } } ?? -1
            let particles = t.provider == .claude ? (isLead ? 768:384):(isLead ? mass.grains:max(70,Int(Float(mass.grains)*0.13)))
            let p = isLead ? SIMD3<Float>(0, 0, 0.02) : n.position
            nodes.append(GalaxyGPU(brand:SIMD4(t.provider == .claude ? 1:0,t.readIssue != nil || t.pendingBytes>0 ? 1:0,isLead ? handoffAge : 100,0),space: SIMD4(p.x, p.y, p.z, radius),
                visual: SIMD4(Float(mass.tier), lead, Float(particles), stableSeed(t.id)),
                motion: SIMD4(n.phase, n.workEnergy, Float(n.workPhase.rawValue), n.tokenEnergy),
                flow: SIMD4(age, tokenAge, n.workSeed, context),
                burst: SIMD4(scale.duration, Float(scale.streams), Float(scale.tier), n.usageSeed)))
        }
        links = []
        for (index, t) in shown.enumerated() {
            guard let parentID = t.parentID, let parent = shown.firstIndex(where: { $0.id == parentID }), parent != index else { continue }
            let a = nodes[parent], b = nodes[index]
            let useToken = b.motion.w > b.motion.y
            let age = useToken ? b.flow.y : b.flow.x
            let progress = max(0, age / (useToken ? 1.7 : 1.25))
            let active = max(b.motion.y, b.motion.w)
            links.append(LinkGPU(source: a.space, target: b.space,
                                 style: SIMD4(active, progress, t.provider == .claude ? -max(0.0001,b.visual.w):b.visual.w, b.motion.z == Float(WorkPhase.result.rawValue) ? -1 : 1)))
        }
    }
    func evidence() -> [String: Any] {
        ["recentCodexTokens":recentTotals.x,"recentClaudeTokens":recentTotals.y,"claudeRiverShare":recentVisual.z,"composition":"unified", "leadProvider":shown.first?.provider.rawValue ?? "", "leadCount":nodes.filter{$0.visual.y>0.5}.count, "handoffAge":handoffAge, "dualProvider":dualProvider,"codexWork":providerDrive.x,"codexTokens":providerDrive.y,"claudeWork":providerDrive.z,"claudeTokens":providerDrive.w,"codexFlowClock":providerClocks.x,"claudeFlowClock":providerClocks.y,"focusID": shown.first?.id ?? "", "visibleTasks": shown.count, "records": tasks.count,
         "links": links.count, "workDrive": workDrive, "tokenDrive": tokenDrive,
         "flowRate": 0.035 + workDrive * 0.34 + tokenDrive * 0.28,
         "receivedEvents": receivedEvents, "receivedTokens": receivedTokens,
         "leadTier": nodes.first?.visual.x ?? 0, "leadRadius": nodes.first?.space.w ?? 0,
         "leadRotationRate": shown.first.map { rotationRate(for: $0.id) } ?? idleRotationRate,
         "eventPhases": shown.compactMap { state[$0.id]?.workPhase.label }]
    }
}
