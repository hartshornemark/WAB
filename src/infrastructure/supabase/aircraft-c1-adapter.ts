import"server-only";
import{DataUnavailable}from"@/domain/models";
import{AircraftC1Conflict,AircraftC1Denied,AircraftC1Invalid,type AircraftC1Snapshot,type AircraftIdentity,type AircraftListSnapshot}from"@/domain/aircraft-c1";
import type{AircraftC1Repository}from"@/ports/aircraft-c1-repository";
import type{RequestClient}from"./server";

function fail(e:{code?:string}|null){if(!e)return;if(e.code==="42501")throw new AircraftC1Denied();if(["40001","40P01"].includes(e.code??""))throw new AircraftC1Conflict();if(e.code==="23505")throw new AircraftC1Invalid("That Aircraft Identity already exists.");if(["23514","23503","22023","23502"].includes(e.code??""))throw new AircraftC1Invalid("Check the Aircraft Identity and C1 selections.");throw new DataUnavailable();}
function list(data:unknown){const s=data as AircraftListSnapshot;if(!s||typeof s.canView!=="boolean"||typeof s.canCreateAircraft!=="boolean"||typeof s.canCreateIdentity!=="boolean"||!Array.isArray(s.rows)||s.rows.some(x=>!Array.isArray(x.variantCodes)))throw new DataUnavailable();return s;}
function c1(data:unknown){const s=data as AircraftC1Snapshot;if(!s||typeof s.canView!=="boolean"||typeof s.canEdit!=="boolean"||typeof s.canAssignManufacturer!=="boolean"||typeof s.revision!=="string"||!Array.isArray(s.variantCodes)||!s.values)throw new DataUnavailable();return s;}

export function createAircraftC1Adapter(client:RequestClient):AircraftC1Repository{return{
  async list(iata){const r=await client.schema("Basic_Carrier_Record").rpc("get_carrier_aircraft",{p_iata:iata});fail(r.error);return list(r.data);},
  async get(iata,typeCode,subtype){const r=await client.schema("Basic_Carrier_Record").rpc("get_aircraft_c1",{p_iata:iata,p_type_code:typeCode,p_subtype:subtype});fail(r.error);return c1(r.data);},
  async searchIdentities(query){const r=await client.schema("Basic_Carrier_Record").rpc("search_aircraft_identities",{p_query:query});fail(r.error);return r.data as AircraftIdentity[];},
  async searchManufacturers(query){const r=await client.schema("Basic_Carrier_Record").rpc("search_aircraft_manufacturers",{p_query:query});fail(r.error);return r.data as{id:string;name:string}[];},
  async createIdentity(input){const r=await client.schema("Basic_Carrier_Record").rpc("create_aircraft_identity",{p_manufacturer_uuid:input.manufacturerId,p_manufacturer_name:input.manufacturerName,p_type_code:input.typeCode,p_subtype:input.subtype,p_identity_name:input.identityName});fail(r.error);return r.data as AircraftIdentity;},
  async assignManufacturer(typeCode,subtype,manufacturerId){const r=await client.schema("Basic_Carrier_Record").rpc("assign_aircraft_manufacturer",{p_type_code:typeCode,p_subtype:subtype,p_manufacturer_uuid:manufacturerId});fail(r.error);},
  async save(iata,typeCode,subtype,revision,aircraftName,variantCodes,values){const r=await client.schema("Basic_Carrier_Record").rpc("save_aircraft_c1",{p_iata:iata,p_type_code:typeCode,p_subtype:subtype,p_revision:revision,p_aircraft_name:aircraftName,p_values:{...values,variantCodes}});fail(r.error);return c1(r.data);}
};}
