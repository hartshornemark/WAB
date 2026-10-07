import"server-only";
import{DataUnavailable}from"@/domain/models";
import{MasterAirportDenied,MasterAirportExists,MasterAirportInvalid,type MasterAirport,type MasterAirportConfiguration}from"@/domain/master-airports";
import type{MasterAirportRepository}from"@/ports/master-airport-repository";
import type{RequestClient}from"./server";
type DbError={code?:string;details?:string};
const field=(value?:string)=>value==="iata"||value==="icao"||value==="name"||value==="city"||value==="countryCode"||value==="timeZone"?value:"name";
const airport=(value:unknown):MasterAirport=>{const row=value as Partial<MasterAirport>;if(typeof row?.iata!=="string"||typeof row.name!=="string"||typeof row.timeZone!=="string"||typeof row.active!=="boolean"||typeof row.updatedAt!=="string")throw new DataUnavailable("The airport record was incomplete.");return{iata:row.iata,icao:typeof row.icao==="string"?row.icao:null,name:row.name,city:typeof row.city==="string"?row.city:null,countryCode:typeof row.countryCode==="string"?row.countryCode:null,timeZone:row.timeZone,active:row.active,updatedAt:row.updatedAt}};
function fail(error:unknown):never{const item=error as DbError;if(item?.code==="42501")throw new MasterAirportDenied("Solution Administrator access is required.");if(item?.code==="23505")throw new MasterAirportExists(item.details==="iata"?"iata":"icao");if(item?.code==="22023")throw new MasterAirportInvalid(field(item.details),"Check this airport value and try again.");throw new DataUnavailable("Airport configuration is unavailable.")}
export function createMasterAirportAdapter(client:RequestClient):MasterAirportRepository{return{
 async get(){const{data,error}=await client.schema("Basic_Carrier_Record").rpc("get_master_airport_configuration",{});if(error)fail(error);const row=data as Partial<MasterAirportConfiguration>;if(!Array.isArray(row?.airports)||!Array.isArray(row.timeZones)||!row.timeZones.every(zone=>typeof zone==="string"))throw new DataUnavailable("Airport configuration is unavailable.");return{airports:row.airports.map(airport),timeZones:row.timeZones}},
 async save(originalIata,value){const{data,error}=await client.schema("Basic_Carrier_Record").rpc("save_master_airport",{p_original_iata:originalIata,p_values:value});if(error)fail(error);return airport(data)}
}}
