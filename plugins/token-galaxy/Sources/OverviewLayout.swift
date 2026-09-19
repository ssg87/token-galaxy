import Foundation
import simd

/// Seeded organic placement; selection and ordinary refresh never change its seed.
struct OverviewConstellationLayout {
    let order:[String]
    let items:[TaskUsage]
    let roots:Set<String>
    let positions:[String:SIMD3<Float>]
    let radii:[String:Float]
    let labelRects:[String:SIMD4<Float>]
    let families:[String:String]
    let worldExtents:SIMD2<Float>
    init(tasks:[TaskUsage],previousOrder:[String],viewport:SIMD2<Float>,seed:UInt64=0){
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
        let base=min(min(width,height)*0.28,sqrt(width*height/(Float(count)*Float.pi))*0.50)
        let footprints=Dictionary(uniqueKeysWithValues:order.enumerated().map{index,id in
            (id,base*(0.75+stableSeed(id+"depth")*0.60)*(index==0 && count>3 ? 1.16:1))
        })
        let largest=footprints.values.max() ?? base
        let extents=SIMD2(max(0.18,1-2*(largest+12)/width),max(0.18,1-2*(largest+25)/height))
        var positions=[String:SIMD3<Float>](),radii=[String:Float](),labels=[String:SIMD4<Float>](),items=[TaskUsage]()
        var centers=[String:SIMD2<Float>]()
        for (index,id) in order.enumerated(){
            guard let main=byID[id] else{continue}
            var random=UInt64(stableSeed(id)*1_000_000) ^ (seed &* 0x9e3779b97f4a7c15)
            func next()->Float {
                random &+= 0x9e3779b97f4a7c15
                var z=random;z=(z^(z>>30)) &* 0xbf58476d1ce4e5b9;z=(z^(z>>27)) &* 0x94d049bb133111eb;z ^= z>>31
                return Float(z>>40)/16_777_216
            }
            let footprint=footprints[id] ?? base
            var chosen=SIMD2<Float>(repeating:0),best:Float = -1
            for _ in 0..<64 {
                let radius=sqrt(next())*(index==0 ? 0.22:1),angle=next()*2*Float.pi
                let candidate=SIMD2(cos(angle)*radius*extents.x,sin(angle)*radius*extents.y)
                var separation:Float=10
                for other in order.prefix(index) {
                    guard let c=centers[other] else{continue}
                    let delta=(candidate-c)*SIMD2(width/2,height/2)
                    separation=min(separation,simd_length(delta)/(footprint+(footprints[other] ?? base)))
                }
                // Prefer separated candidates, with slight variation instead of a lattice.
                let score=separation*(0.93+next()*0.07)
                if score>best{best=score;chosen=candidate}
            }
            if count==1{chosen = .zero}
            centers[id]=chosen;positions[id]=SIMD3(chosen.x,chosen.y,0)
            let rootSize=footprint*0.54,mass=TokenScale.cumulative(main.total)
            radii[id]=rootSize*(0.84+Float(mass.tier)*0.04)*2/height
            let orbit=footprint*0.85,labelWidth=min(150,max(82,footprint*2.5))
            // Rectangles are offsets from the rendered family center, in screen points.
            labels[id]=SIMD4(-labelWidth/2,orbit+6,labelWidth,15)
            items.append(main)
            let children=tasks.filter{$0.id != id && family[$0.id]==id}.sorted{$0.id<$1.id}
            let inner=min(orbit*0.77,rootSize*1.25),density=Float(max(1,children.count))
            let childSize=max(1.2,min(rootSize*0.22,orbit/sqrt(density)*0.48))
            for (i,t) in children.enumerated(){
                let angle=Float(i)*2.399963+stableSeed(id)*6.283185
                let distance=inner+(orbit-inner)*sqrt((Float(i)+0.5)/density)
                positions[t.id]=SIMD3(chosen.x+cos(angle)*distance*2/width,chosen.y-sin(angle)*distance*2/height,0)
                radii[t.id]=childSize*(0.88+Float(TokenScale.cumulative(t.total).tier)*0.03)*2/height
                items.append(t)
            }
        }
        self.order=order;self.items=items;self.roots=allRoots;self.positions=positions;self.radii=radii;self.labelRects=labels;self.families=family;self.worldExtents=extents
    }
}
