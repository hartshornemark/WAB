import {AircraftE2Invalid,type E2PantryRow} from './aircraft-e2';
import type {GalleyLocation} from './aircraft-d6';
export type PantryAllocation={locationId:string;weight:number|null};
export type PantryDraft=E2PantryRow & {allocations:PantryAllocation[]};
export function availableGalleyLocations(galleys:GalleyLocation[],allocations:PantryAllocation[],currentIndex:number){
  const selected=new Set(allocations.filter((_,index)=>index!==currentIndex).map(allocation=>allocation.locationId).filter(Boolean));
  return galleys.filter(galley=>!selected.has(galley.id));
}
export function pantryDraft(row:E2PantryRow):PantryDraft {
  const parts=row.galleyLocations.trim().split(/\s+/).filter(Boolean);
  const allocations=parts.map(part=>{const m=/^([A-Z0-9]{1,3})(?:\/(\d+)(?:KG|LB)?)?$/i.exec(part);return m?{locationId:m[1].toUpperCase(),weight:m[2]?Number(m[2]):parts.length===1?row.totalWeight:null}:{locationId:'',weight:null};});
  return {...row,allocations:allocations.length?allocations:[{locationId:'',weight:null}]};
}
export function calculatePantry(row:PantryDraft,galleys:GalleyLocation[]):E2PantryRow {
  if(!Array.isArray(row.allocations)||!row.allocations.length)throw new AircraftE2Invalid(`Pantry ${row.pantryCode||'code'}: add a D6 galley.`);
  let total=0,moment=0,index=0;const seen=new Set<string>();
  for(const a of row.allocations){
    const g=galleys.find(g=>g.id===a.locationId);
    if(!g)throw new AircraftE2Invalid(`Pantry ${row.pantryCode}: select a saved D6 galley.`);
    if(seen.has(g.id))throw new AircraftE2Invalid(`Pantry ${row.pantryCode}: ${g.id} is selected twice.`);seen.add(g.id);
    if(a.weight===null||!Number.isInteger(a.weight)||a.weight<0)throw new AircraftE2Invalid(`Pantry ${row.pantryCode}, ${g.id}: enter a whole-number weight of zero or more.`);
    if(g.maxWeight!==null&&a.weight>g.maxWeight)throw new AircraftE2Invalid(`Pantry ${row.pantryCode}, ${g.id}: weight exceeds its D6 maximum of ${g.maxWeight}.`);
    if(g.centroid===null||g.index===null||!Number.isFinite(g.centroid)||!Number.isFinite(g.index))throw new AircraftE2Invalid(`Complete the balance data for ${g.id} on D6.`);
    total+=a.weight;moment+=a.weight*g.centroid;index+=a.weight*g.index;
  }
  return {pantryCode:row.pantryCode,galleyLocations:row.allocations.map(a=>`${a.locationId}/${a.weight}`).join(' '),totalWeight:total,balanceArm:total?moment/total:0,index};
}
