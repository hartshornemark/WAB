export type D11FloorLimit = { holdId:string; holdType:string; deckName:string; floorLoadingLimit:number|null };
export type AircraftD11Snapshot = {
  canView:boolean;
  canEdit:boolean;
  revision:string;
  typeCode:string;
  subtype:string;
  applicabilityReviewed:boolean;
  combinedActive:boolean;
  floorActive:boolean;
  asymmetricalActive:boolean;
  floorLimits:D11FloorLimit[];
};
export class AircraftD11Invalid extends Error {}
export class AircraftD11Denied extends Error {}
export class AircraftD11Conflict extends Error {}

export function validateD11FloorLimits(input:unknown, holds:D11FloorLimit[]) {
  if (!Array.isArray(input) || input.length !== holds.length) throw new AircraftD11Invalid("Enter one Floor Loading Limit for every hold defined in D2.");
  const expected = new Set(holds.map(hold=>hold.holdId));
  const seen = new Set<string>();
  return input.map((value,index)=>{
    const row = value as Partial<D11FloorLimit>;
    const holdId = String(row.holdId??"").trim().toUpperCase();
    const limit = typeof row.floorLoadingLimit === "number" ? row.floorLoadingLimit : Number(row.floorLoadingLimit);
    if (!expected.has(holdId)) throw new AircraftD11Invalid(`Unknown hold at row ${index+1}.`);
    if (seen.has(holdId)) throw new AircraftD11Invalid(`Hold ${holdId} is duplicated.`);
    seen.add(holdId);
    if (!Number.isFinite(limit) || limit <= 0 || Math.abs(limit) > 1e9) throw new AircraftD11Invalid(`Enter a valid Floor Loading Limit at row ${index+1}.`);
    return { holdId, floorLoadingLimit:limit };
  });
}
