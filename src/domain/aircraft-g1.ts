export type G1BayOption={holdId:string;bayId:string};
export type G1CompatibilityRow={bayId:string;uldType:string;compatible:boolean|null};
export type AircraftG1Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;applicable:boolean|null;bays:G1BayOption[];uldTypes:string[];rows:G1CompatibilityRow[];suggestions:G1CompatibilityRow[]};
export class AircraftG1Invalid extends Error{} export class AircraftG1Denied extends Error{} export class AircraftG1Conflict extends Error{}

export function validateG1Rows(value:unknown,snapshot:AircraftG1Snapshot):G1CompatibilityRow[]{
  if(!snapshot.applicable)throw new AircraftG1Invalid("G1 is only required when D2 ULD Holds are active.");
  if(!snapshot.bays.length)throw new AircraftG1Invalid("Configure at least one D3 Bay before completing G1.");
  if(!snapshot.uldTypes.length)throw new AircraftG1Invalid("Configure at least one B5 ULD Type before completing G1.");
  if(!Array.isArray(value))throw new AircraftG1Invalid("Complete the ULD compatibility matrix.");
  const expected=new Set(snapshot.bays.flatMap(bay=>snapshot.uldTypes.map(uldType=>`${bay.bayId}|${uldType}`))),seen=new Set<string>();
  const rows=value.map((item,index)=>{const row=item as Partial<G1CompatibilityRow>,bayId=String(row.bayId??"").trim().toUpperCase(),uldType=String(row.uldType??"").trim().toUpperCase(),key=`${bayId}|${uldType}`;if(!expected.has(key))throw new AircraftG1Invalid(`Select a valid Bay and ULD Type at row ${index+1}.`);if(seen.has(key))throw new AircraftG1Invalid(`The Bay and ULD Type at row ${index+1} are duplicated.`);if(typeof row.compatible!=="boolean")throw new AircraftG1Invalid(`Select Yes or No at row ${index+1}.`);seen.add(key);return{bayId,uldType,compatible:row.compatible}});
  if(rows.length!==expected.size||seen.size!==expected.size)throw new AircraftG1Invalid("Answer Yes or No for every Bay and ULD Type combination.");
  return rows;
}
