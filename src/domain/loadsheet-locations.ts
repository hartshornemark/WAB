import type{AircraftD2Snapshot}from"@/domain/aircraft-d2";
import type{AircraftD3Snapshot}from"@/domain/aircraft-d3";

export type LoadsheetLocation={id:string;description:string;indexPerWeightUnit:number;maximumWeight:number|null;occupiedBayIds:string[]};

export function aircraftLoadsheetLocations(d2:AircraftD2Snapshot,d3:AircraftD3Snapshot):LoadsheetLocation[]{
 const locations:LoadsheetLocation[]=[];
 for(const hold of d2.rows.filter(row=>row.holdType==="BLK")){
  const areas=hold.compartments.flatMap(compartment=>compartment.areas.map(area=>({compartment,area})));
  if(areas.length){
   for(const{compartment,area}of areas)if(area.indexPerWeightUnit!==null)locations.push({id:`BLK:${hold.deckCode}:${hold.name}:${compartment.id}:${area.id}`,description:`${hold.name} / ${compartment.id} / ${area.id} (Bulk area)`,indexPerWeightUnit:area.indexPerWeightUnit,maximumWeight:area.maxWeight,occupiedBayIds:[]});
  }else if(hold.indexPerWeightUnit!==null){
   locations.push({id:`BLK:${hold.deckCode}:${hold.name}`,description:`${hold.name} (Complete bulk hold)`,indexPerWeightUnit:hold.indexPerWeightUnit,maximumWeight:hold.maxWeight,occupiedBayIds:[]});
  }
 }
 for(const config of d3.configurations)for(const row of config.rows)if(row.rowType==="POSITION"&&row.indexPerWeightUnit!==null)locations.push({id:`ULD:${config.holdId}:${config.code}:${row.positionId}:${row.uldCode??""}`,description:`${config.holdId} / ${row.positionId}${row.uldCode?` / ${row.uldCode}`:""} (ULD)`,indexPerWeightUnit:row.indexPerWeightUnit,maximumWeight:row.maxWeight,occupiedBayIds:row.occupiedBayIds});
 return locations;
}
