import "server-only";
import {DataUnavailable} from "@/domain/models";
import {UldConflict,UldDenied,UldInvalid,type OperationalUldAdoption,type ProvisionalUldAdoption,type UldSnapshot} from "@/domain/uld-specifications";
import type {UldRepository} from "@/ports/uld-repository";
import type {RequestClient} from "./server";

function snapshot(data:unknown,pendingAdoptions:ProvisionalUldAdoption[]=[]):UldSnapshot{
 const s=data as UldSnapshot;
 if(!s||typeof s.canView!=="boolean"||typeof s.canEdit!=="boolean"||typeof s.revision!=="string"||typeof s.utilisesUlds!=="boolean"||typeof s.recordsInventory!=="boolean"||typeof s.aircraftType!=="string"||typeof s.aircraftSubtype!=="string"||!["","KG","LB"].includes(s.weightUnit)||!["","m3","ft3"].includes(s.volumeUnit)||!Array.isArray(s.rows)||!Array.isArray(s.master))throw new DataUnavailable();
 for(const r of [...s.rows,...s.master])if(!r||![r.code,r.type,r.tare,r.maximum,r.volume].every(v=>typeof v==="string"))throw new DataUnavailable();
 for(const r of s.rows){if(typeof r.isCustom!=="boolean"||typeof r.isDefault!=="boolean"||typeof r.isBaggageDefault!=="boolean"||typeof r.baggageMaxPieces!=="string"||typeof r.remarks!=="string")throw new DataUnavailable();r.inventory??=[];if(!Array.isArray(r.inventory))throw new DataUnavailable();for(const i of r.inventory)if(!i||!(i.id===null||typeof i.id==="string")||![i.carrierCode,i.serialStart,i.serialEnd].every(v=>typeof v==="string"))throw new DataUnavailable();}
 return{...s,pendingAdoptions};
}
function provisional(data:unknown):ProvisionalUldAdoption[]{if(!Array.isArray(data))throw new DataUnavailable();for(const r of data as ProvisionalUldAdoption[])if(!r||typeof r.code!=="string"||typeof r.type!=="string"||typeof r.tareKg!=="number"||typeof r.maximumGrossWeightKg!=="number"||typeof r.volumeM3!=="number"||typeof r.sourceOperationalFlightId!=="string"||typeof r.proposedAt!=="string")throw new DataUnavailable();return data as ProvisionalUldAdoption[];}
function adoption(data:unknown):OperationalUldAdoption{const r=data as OperationalUldAdoption;if(!r||typeof r.code!=="string"||typeof r.type!=="string"||typeof r.tareWeight!=="number"||typeof r.maximumGrossWeight!=="number"||typeof r.compatibleUldCode!=="string"||!Array.isArray(r.compatiblePositions))throw new DataUnavailable();return r;}
function fail(error:{code?:string}|null){if(!error)return;if(error.code==="42501")throw new UldDenied();if(["40001","PT409","40P01"].includes(error.code??""))throw new UldConflict();if(error.code==="23505")throw new UldInvalid("Each ULD code must be unique, with one Default per ULD Type.");if(error.code==="23503")throw new UldInvalid("A ULD code changed or is still referenced. Reload before saving.");if(["23514","23502","22023","22003","22P02","P0002"].includes(error.code??""))throw new UldInvalid("Check the ULD identity, tare weight and aircraft bay compatibility.");throw new DataUnavailable();}
export function createUldAdapter(client:RequestClient):UldRepository{
 const schema=client.schema("Basic_Carrier_Record");
 const pending=async(iata:string,typeCode:string,subtype:string)=>{const r=await schema.rpc("get_carrier_uld_provisional_adoptions",{p_iata:iata,p_type:typeCode,p_subtype:subtype});fail(r.error);return provisional(r.data)};
 const decorated=async(data:unknown,iata:string,typeCode:string,subtype:string)=>snapshot(data,await pending(iata,typeCode,subtype));
 return{
  async get(iata,typeCode,subtype){const r=await schema.rpc("get_carrier_ulds",{p_iata:iata,p_type:typeCode,p_subtype:subtype});fail(r.error);return decorated(r.data,iata,typeCode,subtype)},
  async save(iata,typeCode,subtype,revision,rows){const r=await schema.rpc("save_carrier_ulds_with_baggage_default",{p_iata:iata,p_type:typeCode,p_subtype:subtype,p_revision:revision,p_rows:rows});fail(r.error);return decorated(r.data,iata,typeCode,subtype)},
  async saveInventoryApplicability(iata,typeCode,subtype,revision,recordsInventory){const r=await schema.rpc("save_carrier_uld_inventory_applicability",{p_iata:iata,p_type:typeCode,p_subtype:subtype,p_revision:revision,p_records:recordsInventory});fail(r.error);return decorated(r.data,iata,typeCode,subtype)},
  async saveApplicability(iata,typeCode,subtype,revision,utilisesUlds){const r=await schema.rpc("save_carrier_uld_applicability",{p_iata:iata,p_type:typeCode,p_subtype:subtype,p_revision:revision,p_utilises:utilisesUlds});fail(r.error);return decorated(r.data,iata,typeCode,subtype)},
  async inspect(iata,operationalFlightId,uldCode){const r=await schema.rpc("inspect_operational_uld_adoption",{p_iata:iata,p_operational_flight_id:operationalFlightId,p_uld_code:uldCode});fail(r.error);return adoption(r.data)},
  async propose(iata,operationalFlightId,uldCode,tareKg){const r=await schema.rpc("propose_operational_uld_adoption",{p_iata:iata,p_operational_flight_id:operationalFlightId,p_uld_code:uldCode,p_tare_kg:tareKg});fail(r.error);return adoption(r.data)},
  async review(iata,typeCode,subtype,uldCode,status){const r=await schema.rpc("review_carrier_uld_provisional_adoption",{p_iata:iata,p_type:typeCode,p_subtype:subtype,p_uld_code:uldCode,p_status:status});fail(r.error)}
 };
}
