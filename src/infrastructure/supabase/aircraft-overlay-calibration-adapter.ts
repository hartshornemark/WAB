import"server-only";
import{DataUnavailable}from"@/domain/models";
import type{AircraftOverlayCalibration,AircraftOverlayCalibrationRepository}from"@/ports/aircraft-overlay-calibration-repository";
import type{RequestClient}from"./server";

function calibration(value:unknown):AircraftOverlayCalibration{if(!value||typeof value!=="object")throw new DataUnavailable("Aircraft overlay calibration was incomplete.");const row=value as Record<string,unknown>,offset=row.offsetX;return{canEdit:row.canEdit===true,offsetX:typeof offset==="number"&&Number.isFinite(offset)?offset:null,locked:row.locked===true}}
function fail(error:{message?:string}|null){if(error)throw new DataUnavailable("Aircraft overlay calibration is temporarily unavailable.")}
export function createAircraftOverlayCalibrationAdapter(client:RequestClient):AircraftOverlayCalibrationRepository{return{
  async get(iata,typeCode,subtype,kind){const result=await client.schema("Basic_Carrier_Record").rpc("get_aircraft_overlay_calibration",{p_iata:iata,p_type_code:typeCode,p_subtype:subtype,p_overlay_kind:kind});fail(result.error);return calibration(result.data)},
  async save(iata,typeCode,subtype,kind,offsetX){const result=await client.schema("Basic_Carrier_Record").rpc("save_aircraft_overlay_calibration",{p_iata:iata,p_type_code:typeCode,p_subtype:subtype,p_overlay_kind:kind,p_offset_x:offsetX});fail(result.error);return calibration(result.data)},
}}
