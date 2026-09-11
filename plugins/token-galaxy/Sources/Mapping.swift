import AppKit

/// Explicit demonstration data lives only in this window, never in the reader or counters.
final class ScalePreviewController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private(set) var fields = [StarField]()
    private let amounts: [Int64] = [100, 100_000, 1_000_000, 10_000_000]
    private let stateLabel = NSTextField(labelWithString: "演示样本 · 不计入真实用量")
    private var sequence = 0
    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 450), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "用量与动效对照"; window.isReleasedWhenClosed = false
        super.init(); window.delegate = self
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 450)); root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.012, alpha: 1).cgColor
        root.appearance = NSAppearance(named: .darkAqua); window.contentView = root
        let title = NSTextField(labelWithString: "同一套星河，四种用量体量")
        title.font = .systemFont(ofSize: 21, weight: .medium); title.frame = NSRect(x: 25, y: 397, width: 730, height: 28); root.addSubview(title)
        stateLabel.textColor = .secondaryLabelColor; stateLabel.font = .systemFont(ofSize: 12); stateLabel.frame = NSRect(x: 25, y: 371, width: 730, height: 20); root.addSubview(stateLabel)
        let names = ["100", "100K · 不到 1M", "1M", "10M"]
        let descriptions = ["星核 · 精确小束", "双层星盘 · 纤维展开", "三层星盘 · 扩大覆盖", "外层星河 · 高密度洪流"]
        for i in 0..<4 {
            let x = CGFloat(22 + i * 191)
            let field = StarField(frame: NSRect(x: x, y: 184, width: 160, height: 160)); field.paused = true
            field.update([sample(amounts[i])], deltas: [:]); root.addSubview(field); fields.append(field)
            let label = NSTextField(labelWithString: names[i]); label.alignment = .center; label.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
            label.frame = NSRect(x: x-8, y: 155, width: 180, height: 24); root.addSubview(label)
            let caption = NSTextField(labelWithString: descriptions[i]); caption.alignment = .center; caption.textColor = .secondaryLabelColor; caption.font = .systemFont(ofSize: 10)
            caption.frame = NSRect(x: x-8, y: 132, width: 180, height: 20); root.addSubview(caption)
        }
        let labels = ["消息", "思考", "调用", "返回", "+100", "+1M", "+10M", "完成"]
        for (i, label) in labels.enumerated() {
            let button = NSButton(title: label, target: self, action: #selector(trigger(_:))); button.tag = i
            button.frame = NSRect(x: CGFloat(24 + i*92), y: 73, width: 84, height: 30); root.addSubview(button)
        }
        let note = NSTextField(wrappingLabelWithString: "上方数字是累计调用量；按钮模拟一次新活动或新增量。真实窗口另读本地记录。上下文输入 / 容量在用量详情中独立显示。")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; note.frame = NSRect(x: 25, y: 18, width: 728, height: 37); root.addSubview(note)
        window.center()
    }
    private func sample(_ amount: Int64) -> TaskUsage {
        TaskUsage(id: "scale-demo", title: "演示样本", project: "演示", total: amount, input: nil, cached: nil, output: nil, source: "demo")
    }
    @objc private func trigger(_ sender: NSButton) {
        sequence += 1
        let phases: [WorkPhase] = [.input, .thinking, .tool, .result, .quiet, .quiet, .quiet, .complete]
        for (index, field) in fields.enumerated() {
            let task = sample(amounts[index])
            let count: Int64 = sender.tag == 4 ? 100 : sender.tag == 5 ? 1_000_000 : sender.tag == 6 ? 10_000_000 : 0
            let event = WorkEvent(id: "demo-\(sequence)", at: Date().timeIntervalSince1970, phase: phases[sender.tag])
            field.update([task], deltas: count > 0 ? [task.id: count] : [:], events: count == 0 ? [task.id: [event]] : [:])
        }
        stateLabel.stringValue = "演示：\(sender.title) · 不计入真实用量"
    }
    func show() { window.makeKeyAndOrderFront(nil); fields.forEach { $0.paused = false }; NSApp.activate(ignoringOtherApps: true) }
    func windowWillClose(_ notification: Notification) { fields.forEach { $0.paused = true } }
    func windowDidMiniaturize(_ notification: Notification) { fields.forEach { $0.paused = true } }
    func windowDidDeminiaturize(_ notification: Notification) { fields.forEach { $0.paused = false } }
    func previewImage() -> NSImage? {
        guard let root = window.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return nil }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let image = NSImage(size: root.bounds.size); image.lockFocus(); bitmap.draw(in: root.bounds)
        for field in fields { if let stars = field.snapshotImage() { stars.draw(in: field.frame, from: .zero, operation: .sourceOver, fraction: 1) } }
        image.unlockFocus(); return image
    }
}
