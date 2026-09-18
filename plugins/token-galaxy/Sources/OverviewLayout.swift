import Foundation
import simd

/// A stable family map for the large overview. Selection never changes its topology.
struct OverviewConstellationLayout {
    let order:[String]
    let items:[TaskUsage]
    let roots:Set<String>
    let positions:[String:SIMD3<Float>]
    let radii:[String:Float]
    let labelRects:[String:SIMD4<Float>]
    let families:[String:String]
    init(tasks:[TaskUsage],previousOrder:[String],viewport:SIMD2<Float>){
        let byID=Dictionary(uniqueKeysWithValues:tasks.map{($0.id,$0)})
        func root(_ id:String)->String {
            var current=id,path=[String]()
            while true {
                if let index=path.firstIndex(of:current){return path[index...].min() ?? id}
                path.append(current)
                guard let parent=byID[current]?.parentID,byID[parent] != nil else{return current}
                current=parent
            }
        }
        let family=Dictionary(uniqueKeysWithValues:tasks.map{($0.id,root($0.id))})
        let allRoots=Set(family.values)
        let retained=previousOrder.filter{allRoots.contains($0)}
        let newRoots=allRoots.subtracting(retained).sorted{a,b in
            let ta=byID[a]?.lastEventAt ?? 0,tb=byID[b]?.lastEventAt ?? 0
            return ta==tb ? a<b:ta>tb
        }
        let order=retained+newRoots
        let width=max(1,viewport.x),height=max(1,viewport.y),count=max(1,order.count)
        var columns=1,best:Float=0
        for c in 1...count {
            let rows=(count+c-1)/c,fit=min(width/Float(c),height/Float(rows))
            if fit>best {best=fit;columns=c}
        }
        let rows=(count+columns-1)/columns,cw=width/Float(columns),ch=height/Float(rows)
        var positions=[String:SIMD3<Float>](),radii=[String:Float](),labels=[String:SIMD4<Float>](),items=[TaskUsage]()
        func point(_ x:Float,_ y:Float)->SIMD3<Float>{SIMD3(x/width*2-1,1-y/height*2,0)}
        for (index,id) in order.enumerated(){
            guard let main=byID[id] else{continue}
            let x=(Float(index%columns)+0.5)*cw,y=(Float(index/columns)+0.5)*ch-7
            let rootSize=min(cw*0.22,ch*(count==1 ? 0.30:0.25))
            let mass=TokenScale.cumulative(main.total)
            positions[id]=point(x,y);radii[id]=rootSize*(0.84+Float(mass.tier)*0.04)*2/height
            labels[id]=SIMD4(Float(index%columns)*cw+4,Float(index/columns+1)*ch-17,cw-8,15)
            items.append(main)
            let children=tasks.filter{$0.id != id && family[$0.id]==id}.sorted{$0.id<$1.id}
            let orbit=min(cw*0.44,max(8,ch*0.43-10))
            let inner=min(orbit*0.77,rootSize*1.25)
            let density=Float(max(1,children.count))
            let childSize=max(1.2,min(rootSize*0.22,orbit/sqrt(density)*0.48))
            for (i,t) in children.enumerated(){
                // A golden-angle distribution fills the family's annulus without stacking siblings.
                let angle=Float(i)*2.399963+stableSeed(id)*6.283185
                let fraction=sqrt((Float(i)+0.5)/density)
                let distance=inner+(orbit-inner)*fraction
                positions[t.id]=point(x+cos(angle)*distance,y+sin(angle)*distance)
                radii[t.id]=childSize*(0.88+Float(TokenScale.cumulative(t.total).tier)*0.03)*2/height
                items.append(t)
            }
        }
        self.order=order;self.items=items;self.roots=allRoots;self.positions=positions;self.radii=radii;self.labelRects=labels;self.families=family
    }
}
