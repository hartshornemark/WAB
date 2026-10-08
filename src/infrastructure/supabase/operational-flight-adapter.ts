import"server-only";
import{DataUnavailable}from"@/domain/models";
import{OperationalFlightConflict,OperationalFlightDenied,OperationalFlightInvalid}from"@/domain/operational-flights";
import{operationalWeightBasis}from"@/domain/operational-flights";
import type{DailyLoadControlBoard,OperationalFlightDetail,OperationalFlightRepository}from"@/ports/operational-flight-repository";
import type{RequestClient}from"./server";
import type{Json}from"./database.types";
function fail(error:{code?:string;message?:string}|null){if(!error)return;if(error.code==="42501")throw new OperationalFlightDenied("You do not have permission to operate Load Control.");if(error.code==="23505")throw new OperationalFlightConflict(error.message||"This operational flight already exists.");if(["23514","23503","22023","23502","22P02","55000","P0002"].includes(error.code??""))throw new OperationalFlightInvalid(error.message||"The operational flight data is invalid.");throw new DataUnavailable("Operational flight data is temporarily unavailable.")}
function board(value:unknown){const row=value as DailyLoadControlBoard;if(!row||typeof row.serviceDate!=="string"||typeof row.canOperate!=="boolean"||!Array.isArray(row.flights)||!Array.isArray(row.airports)||!Array.isArray(row.aircraft)||!Array.isArray(row.serviceTypes))throw new DataUnavailable("The Daily Load Control board was incomplete.");return row}
function detail(value:unknown){const row=value as OperationalFlightDetail;if(!row||typeof row.operationalFlightId!=="string"||typeof row.status!=="string"||!Array.isArray(row.itinerary?.legs)||!Array.isArray(row.events))throw new DataUnavailable("The operational flight record was incomplete.");return row}
export function createOperationalFlightAdapter(client:RequestClient):OperationalFlightRepository{return{
  async board(iata,date,airport){
    const[result,aircraftResult]=await Promise.all([
      client.schema("Basic_Carrier_Record").rpc("get_daily_load_control_board",{p_iata:iata,p_service_date:date,p_airport_iata:airport}),
      client.schema("Basic_Carrier_Record").from("Basic_Aircraft_Data").select("Aircraft_Type_IATA,Aircraft_Series_Subtype,Aircraft_Operating_Role").eq("Carrier_IATA",iata),
    ]);
    fail(result.error);fail(aircraftResult.error);
    const value=board(result.data),roles=new Map((aircraftResult.data??[]).map(row=>[`${row.Aircraft_Type_IATA}|${row.Aircraft_Series_Subtype}`,row.Aircraft_Operating_Role]));
    return{...value,aircraft:value.aircraft.map(row=>({...row,operatingRole:roles.get(`${row.typeCode}|${row.subtype}`)})),flights:value.flights.map(row=>{const role=roles.get(`${row.aircraftType}|${row.aircraftSubtype??""}`);return{...row,passengerWeightBasis:operationalWeightBasis(role,row.passengerWeightBasis),baggageWeightBasis:operationalWeightBasis(role,row.baggageWeightBasis)}})};
  },
  async start(iata,scheduleLegId,date){const result=await client.schema("Basic_Carrier_Record").rpc("start_operational_flight",{p_iata:iata,p_schedule_leg_id:scheduleLegId,p_service_date:date});fail(result.error);if(typeof result.data!=="string")throw new DataUnavailable("The operational flight was not created.");return result.data},
  async createAdHoc(iata,input){const result=await client.schema("Basic_Carrier_Record").rpc("create_ad_hoc_operational_flight",{p_iata:iata,p_values:input as unknown as Json});fail(result.error);if(typeof result.data!=="string")throw new DataUnavailable("The ad-hoc flight was not created.");return result.data},
  async get(iata,id){const result=await client.schema("Basic_Carrier_Record").rpc("get_operational_flight",{p_iata:iata,p_operational_flight_id:id});fail(result.error);return detail(result.data)},
}}
