import AppKit
final class AgentNode:NSObject{var task:TaskUsage;var children=[AgentNode]();init(_ t:TaskUsage){task=t}}
final class OverviewController:NSObject,NSOutlineViewDataSource,NSOutlineViewDelegate,NSWindowDelegate {
    let window:NSWindow
    let field:StarField
    let outline=NSOutlineView()
    let project=NSPopUpButton()
    let provider=NSPopUpButton()
    private var providerKey="",providerWidth:NSLayoutConstraint?
    let summary=NSTextField(labelWithString:"")
    var onSelect:((String)->Void)?
    var motionPaused=false {didSet{field.paused=motionPaused || !window.isVisible || window.isMiniaturized}}
    private var records=[TaskUsage](),deltas=[String:Int64](),roots=[AgentNode](),nodes=[String:AgentNode]()
    private var filter="",signature="",projectKey="",updating=false
    override init(){
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="Token 星河 · 任务与代理工作总览";window.minSize=NSSize(width:760,height:560);window.isReleasedWhenClosed=false
        let root=NSView();root.wantsLayer=true;root.layer?.backgroundColor=NSColor(calibratedRed:0.035,green:0.045,blue:0.075,alpha:1).cgColor;window.contentView=root;root.appearance=NSAppearance(named:.darkAqua)
        field=StarField(frame:.zero);field.isOverview=true
        super.init();window.delegate=self
        project.addItem(withTitle:"全部项目");project.lastItem?.representedObject=""
        project.target=self;project.action=#selector(changeProject);project.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(project)
        provider.addItem(withTitle:"全部来源");provider.lastItem?.representedObject="";provider.isHidden=true;provider.target=self;provider.action=#selector(changeProvider);provider.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(provider)
        let reset=NSButton(title:"全部项目",target:self,action:#selector(resetFilter));reset.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(reset)
        summary.font=NSFont.systemFont(ofSize:12);summary.textColor = .secondaryLabelColor;summary.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(summary)
        field.translatesAutoresizingMaskIntoConstraints=false;field.onSelect={[weak self] id in guard let self=self,let node=self.nodes[id] else{return};var ancestors=[AgentNode](),p=node.task.parentID,seen=Set<String>();while let key=p,let parent=self.nodes[key],!seen.contains(key){seen.insert(key);ancestors.append(parent);p=parent.task.parentID};for parent in ancestors.reversed(){self.outline.expandItem(parent)};let row=self.outline.row(forItem:node);if row>=0{self.outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);self.outline.scrollRowToVisible(row)}};root.addSubview(field)
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true;scroll.translatesAutoresizingMaskIntoConstraints=false;scroll.drawsBackground=false;root.addSubview(scroll)
        let columns:[(String,String,CGFloat)]=[("name","任务 / 代理 / 子代理",380),("provider","来源",100),("status","活动状态",100),("tokens","本地累计 Tokens",120),("delta","本次观测新增",120)]
        for (id,title,w) in columns{let c=NSTableColumn(identifier:.init(id));c.title=title;c.width=w;c.minWidth=75;outline.addTableColumn(c)}
        outline.outlineTableColumn=outline.tableColumns.first;outline.rowHeight=32;outline.indentationPerLevel=19;outline.delegate=self;outline.dataSource=self;outline.backgroundColor = .clear;outline.usesAlternatingRowBackgroundColors=true;outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle;scroll.documentView=outline
        let note=NSTextField(labelWithString:"每个来源最多显示最近80条本地记录；子代理独立计数，均非账单或订阅额度。");note.font=NSFont.systemFont(ofSize:11);note.textColor = .secondaryLabelColor;note.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(note)
        providerWidth=provider.widthAnchor.constraint(equalToConstant:0)
        NSLayoutConstraint.activate([
            project.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:18),project.topAnchor.constraint(equalTo:root.topAnchor,constant:14),project.widthAnchor.constraint(equalToConstant:210),provider.leadingAnchor.constraint(equalTo:project.trailingAnchor,constant:10),providerWidth!,provider.centerYAnchor.constraint(equalTo:project.centerYAnchor),reset.leadingAnchor.constraint(equalTo:provider.trailingAnchor,constant:10),reset.centerYAnchor.constraint(equalTo:project.centerYAnchor),summary.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-18),summary.centerYAnchor.constraint(equalTo:project.centerYAnchor),
            field.topAnchor.constraint(equalTo:project.bottomAnchor,constant:12),field.leadingAnchor.constraint(equalTo:root.leadingAnchor),field.trailingAnchor.constraint(equalTo:root.trailingAnchor),field.heightAnchor.constraint(equalTo:root.heightAnchor,multiplier:0.50),
            scroll.topAnchor.constraint(equalTo:field.bottomAnchor,constant:8),scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:14),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-14),scroll.bottomAnchor.constraint(equalTo:note.topAnchor,constant:-10),note.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:18),note.trailingAnchor.constraint(lessThanOrEqualTo:root.trailingAnchor,constant:-18),note.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-12)
        ]);window.center()
    }
    func show(){window.makeKeyAndOrderFront(nil);field.paused=motionPaused;NSApp.activate(ignoringOtherApps:true)}
    func windowWillClose(_ notification:Notification){field.paused=true}
    func windowDidMiniaturize(_ notification:Notification){field.paused=true}
    func windowDidDeminiaturize(_ notification:Notification){field.paused=motionPaused}
    @objc func changeProvider(){reload()}
    @objc func changeProject(){filter=project.selectedItem?.representedObject as? String ?? "";reload()}
    @objc func resetFilter(){filter="";project.selectItem(at:0);reload()}
    func update(_ items:[TaskUsage],observed:[String:Int64],increments:[String:Int64],events:[String:[WorkEvent]]=[:]){
        records=items;deltas=observed
        let sources=[UsageProvider.codex,.claude].filter{p in items.contains{$0.provider==p}},sourceKey=sources.map{$0.rawValue}.joined(separator:",")
        if sourceKey != providerKey || provider.numberOfItems==1 {
            let selected=provider.selectedItem?.representedObject as? String ?? "";providerKey=sourceKey;provider.removeAllItems();provider.addItem(withTitle:"全部来源");provider.lastItem?.representedObject=""
            for p in sources {provider.addItem(withTitle:p.label);provider.lastItem?.representedObject=p.rawValue}
            if let i=provider.itemArray.firstIndex(where:{$0.representedObject as? String==selected}){provider.selectItem(at:i)}
            provider.isHidden=sources.count<2;providerWidth?.constant=sources.count<2 ? 0:130
        }
        let paths=Array(Set(items.map{$0.projectPath})).sorted(),key=paths.joined(separator:"|")
        if key != projectKey{projectKey=key;project.removeAllItems();project.addItem(withTitle:"全部项目");project.lastItem?.representedObject="";for path in paths{project.addItem(withTitle:URL(fileURLWithPath:path).lastPathComponent);project.lastItem?.representedObject=path};if let i=project.itemArray.firstIndex(where:{$0.representedObject as? String==filter}){project.selectItem(at:i)}else{filter=""}}
        reload(increments:increments,events:events)
    }
    private func reload(increments:[String:Int64]=[:],events:[String:[WorkEvent]]=[:]){
        let selectedID=field.selected ?? (outline.selectedRow>=0 ? (outline.item(atRow:outline.selectedRow) as? AgentNode)?.task.id:nil)
        let shown=records.filter{(filter.isEmpty || $0.projectPath==filter) && ((provider.selectedItem?.representedObject as? String ?? "").isEmpty || $0.provider.rawValue == (provider.selectedItem?.representedObject as? String ?? ""))};field.update(shown,deltas:increments,events:events);field.paused = motionPaused || !window.isVisible || window.isMiniaturized
        summary.stringValue="\(shown.count) 条记录   ·   \(shown.filter{$0.isWorking}.count) 工作中   ·   \(shown.filter{$0.parentID != nil}.count) 子代理"
        let key=shown.map{$0.id+":"+($0.parentID ?? "")}.sorted().joined(separator:"|");updating=true
        if key != signature {
            signature=key;nodes=Dictionary(uniqueKeysWithValues:shown.map{($0.id,AgentNode($0))});roots=[]
            for t in shown{guard let node=nodes[t.id] else{continue};var p=t.parentID,seen:Set<String>=[t.id],cycle=false;while let id=p,let parent=nodes[id]{if seen.contains(id){cycle=true;break};seen.insert(id);p=parent.task.parentID}
                if !cycle,let id=t.parentID,let parent=nodes[id]{parent.children.append(node)}else{roots.append(node)}
            }
            outline.reloadData();outline.expandItem(nil,expandChildren:true)
        }else{for t in shown{nodes[t.id]?.task=t};outline.reloadData()}
        if let id=selectedID,let node=nodes[id] {
            var p=node.task.parentID,seen=Set<String>()
            while let key=p,let parent=nodes[key],!seen.contains(key){seen.insert(key);outline.expandItem(parent);p=parent.task.parentID}
            let row=outline.row(forItem:node);if row>=0{outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
        }
        updating=false
    }
    func previewImage()->NSImage?{
        guard let root=window.contentView else{return nil};root.layoutSubtreeIfNeeded()
        guard let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) else{return nil};root.cacheDisplay(in:root.bounds,to:bitmap)
        let image=NSImage(size:root.bounds.size);image.lockFocus();bitmap.draw(in:root.bounds)
        if let stars=field.snapshotImage(){stars.draw(in:field.convert(field.bounds,to:root),from:.zero,operation:.sourceOver,fraction:1)}
        image.unlockFocus();return image
    }
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{(item as? AgentNode)?.children.count ?? roots.count}
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{if let n=item as? AgentNode{return n.children[index]};return roots[index]}
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{!((item as? AgentNode)?.children.isEmpty ?? true)}
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{
        guard let t=(item as? AgentNode)?.task else{return nil};let label=NSTextField(labelWithString:"");label.font=NSFont.systemFont(ofSize:12);label.lineBreakMode = .byTruncatingTail
        switch tableColumn?.identifier.rawValue{
        case "name":label.stringValue=t.label
        case "provider":label.stringValue=t.provider.label;label.textColor=t.provider == .claude ? NSColor(calibratedRed:0.94,green:0.59,blue:0.44,alpha:1):.labelColor
        case "status":label.stringValue=t.stateLabel;label.textColor=t.activity>0.5 ? .systemMint:.secondaryLabelColor
        case "tokens":label.stringValue=compactTokens(t.total);label.font=NSFont.monospacedDigitSystemFont(ofSize:12,weight:.regular)
        default:label.stringValue="+"+compactTokens(deltas[t.id] ?? 0);label.textColor = .systemTeal
        };return label
    }
    func outlineViewSelectionDidChange(_ notification:Notification){guard !updating,outline.selectedRow>=0,let node=outline.item(atRow:outline.selectedRow) as? AgentNode else{return};field.selected=node.task.id;onSelect?(node.task.id)}
}
