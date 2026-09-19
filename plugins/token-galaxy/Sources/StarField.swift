import AppKit
import MetalKit
import QuartzCore
import simd

final class ClearMetalView: MTKView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class OverviewTaskLabel:NSTextField {override func hitTest(_ point:NSPoint)->NSView?{nil}}
final class StarField: NSView, MTKViewDelegate {
    let model = GalaxyModel()
    let pet = SpiritModel()
    var spiritEnabled = false
    var spiritExpression:SpiritExpression { pet.expression(task:model.shown.first,at:model.clock,stale:stale) }
    var tasks = [TaskUsage]()
    var onSelect: ((String) -> Void)?
    var onContext: ((NSEvent) -> Void)?
    var onResize: ((CGFloat) -> Void)?
    var onInteraction: (() -> Void)?
    var isStrip = false
    var isOverview = false {didSet{model.overviewLayout=isOverview;configureFrameDriver();updateOverviewLabels()}}
    var paused = false { didSet { guard paused != oldValue else{return}; lastFrame=0; metal?.isPaused=isOverview || paused; metal?.draw() } }
    var selected: String? { didSet { model.selected = selected;updateOverviewLabels() } }
    var claudeLogoScale:Float = { let v=UserDefaults.standard.double(forKey:"claudeLogoScale");return v>0 ? Float(min(1.6,max(0.8,v))):1.4 }()
    private var resizeSteps=OrbResizeSteps()
    var animateAmbient = true
    var stale = false { didSet { model.stale = stale } }
    private var overviewLabels=[String:OverviewTaskLabel]()
    private var overviewTimer:Timer?
    private var overviewTracking:NSTrackingArea?
    private var hoveredFamily:String?
    private var workingFamilies=Set<String>()
    private var metal: ClearMetalView?
    private var queue: MTLCommandQueue?
    private var background: MTLRenderPipelineState?
    private var body: MTLRenderPipelineState?
    private var mark: MTLRenderPipelineState?
    private var stars: MTLRenderPipelineState?
    private var chains: MTLRenderPipelineState?
    private var pulses: MTLRenderPipelineState?
    private var river: MTLRenderPipelineState?
    private var lastFrame: Double = 0
    private var visualTime: Float = 0
    private var frameCount = 0
    private var updates = 0
    private var lastUpdateWall = CACurrentMediaTime()
    private var syntheticClock = false
    private(set) var rendererError: String?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = true
        setup()
        setAccessibilityRole(.button)
        setAccessibilityLabel("实时星河，点击查看任务，右键查看用量映射和代理总览")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout(){
        super.layout()
        if isOverview {model.setOverviewViewport(SIMD2(Float(bounds.width),Float(bounds.height)));updateOverviewLabels()}
    }
    private func updateOverviewLabels(){
        guard isOverview else{return}
        let roots=model.overviewRoots
        workingFamilies=Set(model.shown.filter{$0.isWorking}.compactMap{model.overviewFamilies[$0.id]})
        for id in Array(overviewLabels.keys) where !roots.contains(id){overviewLabels.removeValue(forKey:id)?.removeFromSuperview()}
        for id in roots {
            guard let rect=model.overviewLabelRects[id],let task=model.shown.first(where:{$0.id==id}) else{continue}
            let label=overviewLabels[id] ?? OverviewTaskLabel(labelWithString:"")
            if overviewLabels[id]==nil{label.alignment = .center;label.lineBreakMode = .byTruncatingTail;addSubview(label);overviewLabels[id]=label}
            label.font=NSFont.systemFont(ofSize:min(11,max(9,CGFloat(rect.z)/11)),weight:.medium)
            label.stringValue=task.label
            label.textColor=model.overviewFamilies[selected ?? ""]==id ? .systemMint:.secondaryLabelColor
            let children=model.overviewFamilies.values.filter{$0==id}.count-1
            label.toolTip="\(task.label)\n\(task.provider.label) · \(children) 个子任务"
        }
        updateOverviewLabelFrames()
    }
    func reshuffleOverview(){model.reshuffleOverview();updateOverviewLabels()}
    private func updateOverviewLabelFrames(){
        guard isOverview else{return}
        let selectedFamily=model.overviewFamilies[selected ?? ""]
        for (index,task) in model.shown.enumerated(){
            guard index<model.nodes.count,let label=overviewLabels[task.id],let rect=model.overviewLabelRects[task.id] else{continue}
            let p=model.nodes[index].space
            let x=(1+CGFloat(p.x))*bounds.width/2+CGFloat(rect.x)
            let y=(1-CGFloat(p.y))*bounds.height/2+CGFloat(rect.y)
            label.frame=NSRect(x:max(2,min(bounds.width-CGFloat(rect.z)-2,x)),y:max(2,min(bounds.height-CGFloat(rect.w)-2,y)),width:CGFloat(rect.z),height:CGFloat(rect.w))
            label.isHidden=task.id != selectedFamily && task.id != hoveredFamily && !workingFamilies.contains(task.id)
        }
    }
    override func updateTrackingAreas(){
        super.updateTrackingAreas()
        if let old=overviewTracking{removeTrackingArea(old);overviewTracking=nil}
        guard isOverview else{return}
        let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);overviewTracking=area
    }
    override func mouseMoved(with event:NSEvent){
        guard isOverview else{return}
        hoveredFamily=taskID(at:convert(event.locationInWindow,from:nil)).flatMap{model.overviewFamilies[$0]};updateOverviewLabelFrames()
    }
    override func mouseExited(with event:NSEvent){hoveredFamily=nil;updateOverviewLabelFrames()}
    deinit {overviewTimer?.invalidate()}
    private func configureFrameDriver(){
        overviewTimer?.invalidate();overviewTimer=nil
        metal?.isPaused=isOverview || paused
        guard isOverview else{return}
        // MTKView's automatic display link can stop after a secondary window closes.
        // Keep this window's frames on a common-mode timer, drawing only while visible.
        let timer=Timer(timeInterval:1.0/30,repeats:true){[weak self] _ in
            guard let self=self,!self.paused,self.window?.isVisible==true,self.window?.isMiniaturized==false else{return}
            self.metal?.draw()
        }
        timer.tolerance=0.003;overviewTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    private func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else { rendererError = "此 Mac 的 Metal 不可用"; return }
        let view = ClearMetalView(frame: bounds, device: device)
        view.autoresizingMask = [.width, .height]; view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0); view.framebufferOnly = false
        view.preferredFramesPerSecond = 30; view.enableSetNeedsDisplay = false
        view.delegate = self; view.layer?.isOpaque = false
        addSubview(view); metal = view; queue = device.makeCommandQueue()
        do {
            guard let url = Bundle.main.url(forResource: "Cosmos", withExtension: "metal") else {
                throw NSError(domain: "Metal", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少星河着色器"])
            }
            let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
            func pipeline(_ vertex: String, _ fragment: String, blend: Bool = true, additive: Bool = true) throws -> MTLRenderPipelineState {
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = library.makeFunction(name: vertex); desc.fragmentFunction = library.makeFunction(name: fragment)
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                if blend {
                    let a = desc.colorAttachments[0]!
                    a.isBlendingEnabled = true; a.sourceRGBBlendFactor = .one; a.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
                    a.sourceAlphaBlendFactor = .one; a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
                return try device.makeRenderPipelineState(descriptor: desc)
            }
            background = try pipeline("backgroundVertex", "backgroundFragment", blend: false)
            body = try pipeline("bodyVertex", "bodyFragment")
            mark = try pipeline("markVertex", "markFragment", additive: false)
            stars = try pipeline("starVertex", "starFragment")
            chains = try pipeline("chainVertex", "starFragment")
            pulses = try pipeline("pulseVertex", "starFragment")
            river = try pipeline("riverVertex", "starFragment")
        } catch { rendererError = error.localizedDescription; view.isPaused = true }
    }
    func update(_ items: [TaskUsage], deltas: [String: Int64], events: [String: [WorkEvent]] = [:], messageEvents: Set<String> = []) {
        let now = CACurrentMediaTime()
        if paused && !syntheticClock { model.step(Float(now-lastUpdateWall), reduceMotion: true) }
        lastUpdateWall = now
        tasks = items; var incoming = events
        for id in messageEvents { incoming[id, default: []].append(WorkEvent(id: "message-\(updates)-\(id)", at: Date().timeIntervalSince1970, phase: .input)) }
        model.update(items, deltas: deltas, events: incoming);updateOverviewLabels(); pet.update(items,events:incoming,deltas:deltas,at:model.clock); updates += 1
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    private func encode(_ pass: MTLRenderPassDescriptor, _ command: MTLCommandBuffer, _ size: CGSize) {
        guard let background = background, let body = body, let stars = stars, let chains = chains,
              let pulses = pulses, let river = river, let mark = mark, let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let activeNode = model.nodes.filter{$0.visual.y<0.5}.max { max($0.motion.y,$0.motion.w) < max($1.motion.y,$1.motion.w) }
        let clearing = activeNode.map { n -> SIMD4<Float> in let strength = min(1,max(n.motion.y,n.motion.w));return SIMD4(n.space.x,n.space.y,n.space.z,(0.065+n.space.w*0.7)*strength) } ?? SIMD4<Float>(repeating:0)
        let codexTier=model.nodes.first(where:{$0.brand.x<0.5})?.visual.x ?? 0,claudeTier=model.nodes.first(where:{$0.brand.x>0.5})?.visual.x ?? 0
        var recent=model.recentVisual;recent.w=claudeLogoScale
        var scene = SceneGPU(recent:recent,channels:model.providerDrive,clocks:SIMD4(model.providerClocks.x,model.providerClocks.y,codexTier,claudeTier),layout:SIMD4(model.dualProvider ? 1:0,tasks.contains(where:{$0.provider == .codex}) ? 1:0,tasks.contains(where:{$0.provider == .claude}) ? 1:0,model.nodes.first?.brand.x ?? 0),viewport: SIMD4(Float(size.width), Float(size.height), visualTime, isStrip ? 1 : isOverview ? 2 : 0),
                             dynamics: SIMD4(model.flowClock, model.workDrive, model.tokenDrive, Float(tasks.count)),
                             settings: SIMD4(stale ? 1 : 0, Float(model.nodes.count), model.nodes.first?.visual.x ?? 0, reduced ? 1 : 0), focus: clearing, spirit: spiritEnabled && !isStrip && !isOverview ? spiritExpression.gpu : SIMD4<Float>(repeating:0))
        encoder.setVertexBytes(&scene, length: MemoryLayout<SceneGPU>.stride, index: 1)
        encoder.setFragmentBytes(&scene, length: MemoryLayout<SceneGPU>.stride, index: 1)
        encoder.setRenderPipelineState(background); encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if !model.nodes.isEmpty {
            var nodes = model.nodes
            let resolution = isStrip ? Float(0.22) : min(1.35, max(0.38, Float(min(size.width, size.height)) / 440))
            for i in nodes.indices { if nodes[i].brand.x<0.5{nodes[i].visual.z = max(32, (nodes[i].visual.z * resolution).rounded())} }
            nodes.withUnsafeBytes { if let base = $0.baseAddress { if $0.count<=4096{encoder.setVertexBytes(base,length:$0.count,index:0)}else if let buffer=metal?.device?.makeBuffer(bytes:base,length:$0.count,options:.storageModeShared){encoder.setVertexBuffer(buffer,offset:0,index:0)} } }
            if !isStrip {
                encoder.setRenderPipelineState(body); encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nodes.count)
                encoder.setRenderPipelineState(stars)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Int(nodes.map { $0.visual.z }.max() ?? 32), instanceCount: nodes.count)
            } else {
                encoder.setRenderPipelineState(stars)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 768, instanceCount: nodes.count)
            }
            encoder.setRenderPipelineState(mark)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 768 /* Claude Building contour */, instanceCount: nodes.count)
            if !model.links.isEmpty {
                model.links.withUnsafeBytes { if let base = $0.baseAddress { if $0.count<=4096{encoder.setVertexBytes(base,length:$0.count,index:2)}else if let buffer=metal?.device?.makeBuffer(bytes:base,length:$0.count,options:.storageModeShared){encoder.setVertexBuffer(buffer,offset:0,index:2)} } }
                encoder.setRenderPipelineState(chains)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: model.links.count * 72)
            }
            if !reduced {
                encoder.setRenderPipelineState(pulses)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 1800, instanceCount: nodes.count)
            }
        }
        if isStrip {
            encoder.setRenderPipelineState(river)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 17000)
        }
        encoder.endEncoding()
    }
    func draw(in view: MTKView) {
        guard view.drawableSize.width > 2, view.drawableSize.height > 2, rendererError == nil,
              let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue?.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime(), dt = Float(lastFrame == 0 ? 0 : min(0.06, now - lastFrame)); lastFrame = now
        if !paused {
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            model.step(dt, reduceMotion: reduced)
            if !reduced { visualTime += dt }
        }
        updateOverviewLabelFrames()
        encode(pass, command, view.drawableSize); command.present(drawable); command.commit(); frameCount += 1
    }
    func advancePreview(seconds: Float) {
        syntheticClock = true
        let steps = max(1, Int((seconds * 30).rounded())), dt = seconds / Float(steps)
        for _ in 0..<steps { model.step(dt); visualTime += dt }
    }
    func runtimeEvidence() -> [String: Any] {
        var result = model.evidence(); result["frames"] = frameCount; result["updates"] = updates
        result["spiritMood"] = spiritExpression.mood.rawValue; result["spiritCaption"] = spiritExpression.caption; result["spiritEnabled"] = spiritEnabled; result["paused"] = paused; result["rendererError"] = rendererError ?? ""
        result["width"] = bounds.width; result["height"] = bounds.height; result["stale"] = stale
        return result
    }
    func diagnostics() -> [String: Int] {
        ["metalReady": rendererError == nil ? 1 : 0, "tasks": tasks.count, "galaxies": model.nodes.count, "links": model.links.count, "frames": frameCount]
    }
    func snapshotImage(size: NSSize? = nil) -> NSImage? {
        guard let device = metal?.device, let command = queue?.makeCommandBuffer() else { return nil }
        let s = size ?? bounds.size, w = max(1, Int(s.width * 2)), h = max(1, Int(s.height * 2))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        encode(pass, command, CGSize(width: w, height: h)); command.commit(); command.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        texture.getBytes(&pixels, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let c = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
              let cg = c.makeImage() else { return nil }
        updateOverviewLabelFrames()
        let image=NSImage(cgImage:cg,size:s)
        guard isOverview,!overviewLabels.isEmpty else{return image}
        let composed=NSImage(size:s);composed.lockFocusFlipped(true)
        image.draw(in:NSRect(origin:.zero,size:s))
        let sx=s.width/max(1,bounds.width),sy=s.height/max(1,bounds.height)
        for label in overviewLabels.values where !label.isHidden {
            let style=NSMutableParagraphStyle();style.alignment = .center;style.lineBreakMode = .byTruncatingTail
            let frame=label.frame,rect=NSRect(x:frame.minX*sx,y:frame.minY*sy,width:frame.width*sx,height:frame.height*sy)
            let font=NSFont.systemFont(ofSize:(label.font?.pointSize ?? 10)*sy,weight:.medium)
            label.stringValue.draw(in:rect,withAttributes:[.font:font,.foregroundColor:label.textColor ?? NSColor.secondaryLabelColor,.paragraphStyle:style])
        }
        composed.unlockFocus();return composed
    }
    func taskID(at point: NSPoint) -> String? {
        guard !model.nodes.isEmpty else { return nil }
        if isOverview,let label=overviewLabels.first(where:{!$0.value.isHidden && $0.value.frame.contains(point)}){return label.key}
        let m = min(bounds.width, bounds.height)
        let candidates = model.nodes.enumerated().map { i, node -> (Int, CGFloat) in
            let perspective = 1 / (1 - node.space.z * 0.20)
            let x = CGFloat(node.space.x * perspective), y = CGFloat(node.space.y * perspective)
            return (i, hypot(point.x - bounds.width / 2 - x * (isOverview ? bounds.width : m) / 2,
                             point.y - bounds.height / 2 + y * (isOverview ? bounds.height : m) / 2))
        }
        return candidates.min(by: { $0.1 < $1.1 }).map { model.shown[$0.0].id }
    }
    override func rightMouseDown(with event:NSEvent){onInteraction?();onContext?(event)}
    override func mouseDown(with event:NSEvent){
        onInteraction?()
        // Capture the identity before refreshes can reorder or move the nodes.
        let clickedID=taskID(at:convert(event.locationInWindow,from:nil))
        if isOverview{if let id=clickedID{onSelect?(id)};return}
        guard let window=window else{return};let initial=window.frame,startPoint=NSEvent.mouseLocation;var moved=false
        while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp],until:.distantFuture,inMode:.eventTracking,dequeue:true){
            let now=NSEvent.mouseLocation,dx=now.x-startPoint.x,dy=now.y-startPoint.y
            onInteraction?()
            if next.type == .leftMouseUp{if !moved,let id=clickedID{onSelect?(id)};window.saveFrame(usingName:"TokenGalaxyOrb");break}
            if hypot(dx,dy)>6{moved=true;window.setFrameOrigin(NSPoint(x:initial.minX+dx,y:initial.minY+dy))}
        }
    }
    override func scrollWheel(with event:NSEvent){onInteraction?();if !isOverview{let change=resizeSteps.consume(event.scrollingDeltaY,precise:event.hasPreciseScrollingDeltas,momentum:!event.momentumPhase.isEmpty,fine:event.modifierFlags.contains(.shift));if change != 0{onResize?(change)}}}
}
