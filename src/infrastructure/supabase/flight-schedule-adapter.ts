import"server-only";
import{DataUnavailable}from"@/domain/models";
import{FlightScheduleConflict,FlightScheduleDenied,FlightScheduleInvalid}from"@/domain/flight-schedules";
import type{FlightScheduleEdition,FlightScheduleRepository,FlightScheduleStageResult,FlightScheduleWorkspace}from"@/ports/flight-schedule-repository";
import type{RequestClient}from"./server";
import type{Json}from"./database.types";

function fail(error:{code?:string;message?:string}|null){
  if(!error)return;
  if(error.code==="42501")throw new FlightScheduleDenied("You do not have permission to manage flight schedules.");
  if(error.code==="23505")throw new FlightScheduleConflict("This SSIM file has already been uploaded for this carrier.");
  if(["23514","23503","22023","23502","22P02","55000","P0002"].includes(error.code??""))throw new FlightScheduleInvalid(error.message||"The schedule data is invalid.");
  throw new DataUnavailable("Flight schedule data is temporarily unavailable.");
}
function stage(value:unknown):FlightScheduleStageResult{
  const row=value as Partial<FlightScheduleStageResult>;
  if(!row||typeof row.importId!=="string"||typeof row.status!=="string"||typeof row.normalizedLegs!=="number")throw new DataUnavailable("The schedule result was incomplete.");
  return{importId:row.importId,status:row.status,records:Number(row.records??0),accepted:Number(row.accepted??0),rejected:Number(row.rejected??0),normalizedLegs:row.normalizedLegs,coverageStart:row.coverageStart??null,coverageEnd:row.coverageEnd??null};
}
function workspace(value:unknown,segmentDefaults:unknown):FlightScheduleWorkspace{const row=value as FlightScheduleWorkspace;if(!row||typeof row.canView!=="boolean"||typeof row.canConfigure!=="boolean"||!Array.isArray(row.legs)||!Array.isArray(segmentDefaults)||!Array.isArray(row.serviceTypes)||!Array.isArray(row.airports)||!Array.isArray(row.aircraft)||!Array.isArray(row.aircraftConfigurations)||!Array.isArray(row.crewCodes)||!Array.isArray(row.pantryCodes)||!Array.isArray(row.variations))throw new DataUnavailable("The schedule workspace was incomplete.");return{...row,segmentDefaults:segmentDefaults as FlightScheduleWorkspace["segmentDefaults"]}}
function edition(value:unknown):FlightScheduleEdition{const row=value as FlightScheduleEdition;if(!row||typeof row.importId!=="string"||typeof row.name!=="string"||typeof row.sourceFormat!=="string"||typeof row.status!=="string"||typeof row.canEdit!=="boolean"||typeof row.canDelete!=="boolean"||!Array.isArray(row.legs))throw new DataUnavailable("The schedule edition was incomplete.");return row}
export function createFlightScheduleAdapter(client:RequestClient):FlightScheduleRepository{return{
  async list(iata){
    const{data,error}=await client.schema("Basic_Carrier_Record").from("Flight_Schedule_Imports").select("Import_ID,Original_File_Name,Source_Carrier_IATA,Source_Format,Status,Uploaded_At,Coverage_Start_Date,Coverage_End_Date,Total_Record_Count,Normalized_Leg_Count,Rejected_Record_Count").eq("Carrier_IATA",iata).order("Uploaded_At",{ascending:false}).limit(50);
    fail(error);return(data??[]).map(row=>({importId:row.Import_ID,fileName:row.Original_File_Name,sourceCarrierIata:row.Source_Carrier_IATA,sourceFormat:row.Source_Format,status:row.Status,uploadedAt:row.Uploaded_At,coverageStart:row.Coverage_Start_Date,coverageEnd:row.Coverage_End_Date,recordCount:row.Total_Record_Count,legCount:row.Normalized_Leg_Count,rejectedCount:row.Rejected_Record_Count}));
  },
  async workspace(iata){const[result,defaults]=await Promise.all([client.schema("Basic_Carrier_Record").rpc("get_flight_schedule_workspace",{p_iata:iata}),client.schema("Basic_Carrier_Record").rpc("get_flight_schedule_segment_defaults",{p_iata:iata})]);fail(result.error);fail(defaults.error);return workspace(result.data,defaults.data)},
  async createAndStage(iata,metadata,records,legs){
    const created=await client.schema("Basic_Carrier_Record").rpc("create_ssim_schedule_import",{p_iata:iata,p_source_carrier_iata:metadata.sourceCarrierIata,p_file_name:metadata.fileName,p_file_sha256:metadata.sha256,p_file_size_bytes:metadata.sizeBytes,p_source_encoding:"UTF-8",p_ssim_edition:null,p_season_code:metadata.seasonCode,p_creator_reference:metadata.creatorReference});
    fail(created.error);if(typeof created.data!=="string")throw new DataUnavailable("The schedule import was not created.");
    const staged=await client.schema("Basic_Carrier_Record").rpc("stage_ssim_schedule_import",{p_iata:iata,p_import_id:created.data,p_records:records as unknown as Json,p_legs:legs as unknown as Json});
    fail(staged.error);return stage(staged.data);
  },
  async publish(iata,importId){const result=await client.schema("Basic_Carrier_Record").rpc("publish_ssim_schedule_import",{p_iata:iata,p_import_id:importId});fail(result.error);return stage(result.data)},
  async createRevision(iata,importId){const result=await client.schema("Basic_Carrier_Record").rpc("create_manual_schedule_revision",{p_iata:iata,p_source_import_id:importId});fail(result.error);if(typeof result.data!=="string")throw new DataUnavailable("The schedule revision was not created.");return result.data},
  async saveParameters(iata,scheduleLegId,values){const result=await client.schema("Basic_Carrier_Record").rpc("save_flight_schedule_leg_parameters",{p_iata:iata,p_schedule_leg_id:scheduleLegId,p_values:values as unknown as Json});fail(result.error);return this.workspace(iata)},
  async saveSegmentDefault(iata,departureAirport,arrivalAirport,aircraftType,values){const result=await client.schema("Basic_Carrier_Record").rpc("save_flight_schedule_segment_default",{p_iata:iata,p_departure_airport:departureAirport,p_arrival_airport:arrivalAirport,p_aircraft_type:aircraftType,p_values:values as unknown as Json});fail(result.error);return this.workspace(iata)},
  async deleteSegmentDefault(iata,departureAirport,arrivalAirport,aircraftType){const result=await client.schema("Basic_Carrier_Record").rpc("delete_flight_schedule_segment_default",{p_iata:iata,p_departure_airport:departureAirport,p_arrival_airport:arrivalAirport,p_aircraft_type:aircraftType});fail(result.error);return this.workspace(iata)},
  async createManual(iata,name,seasonCode){const result=await client.schema("Basic_Carrier_Record").rpc("create_manual_schedule_import",{p_iata:iata,p_name:name,p_season_code:seasonCode});fail(result.error);if(typeof result.data!=="string")throw new DataUnavailable("The manual schedule was not created.");return result.data},
  async saveManualLeg(iata,importId,scheduleLegId,values){const result=await client.schema("Basic_Carrier_Record").rpc("save_manual_schedule_leg",{p_iata:iata,p_import_id:importId,p_schedule_leg_id:scheduleLegId,p_values:values as unknown as Json});fail(result.error);const data=result.data as {importId?:unknown;scheduleLegId?:unknown;status?:unknown};if(typeof data?.importId!=="string"||typeof data.scheduleLegId!=="string"||typeof data.status!=="string")throw new DataUnavailable("The manual flight result was incomplete.");return{importId:data.importId,scheduleLegId:data.scheduleLegId,status:data.status}},
  async saveManualItinerary(iata,importId,values){const result=await client.schema("Basic_Carrier_Record").rpc("save_manual_schedule_itinerary",{p_iata:iata,p_import_id:importId,p_values:values as unknown as Json});fail(result.error);const data=result.data as {importId?:unknown;scheduleLegIds?:unknown;status?:unknown};if(typeof data?.importId!=="string"||!Array.isArray(data.scheduleLegIds)||!data.scheduleLegIds.every(id=>typeof id==="string")||typeof data.status!=="string")throw new DataUnavailable("The manual itinerary result was incomplete.");return{importId:data.importId,scheduleLegIds:data.scheduleLegIds as string[],status:data.status}},
  async edition(iata,importId){const result=await client.schema("Basic_Carrier_Record").rpc("get_flight_schedule_edition",{p_iata:iata,p_import_id:importId});fail(result.error);return edition(result.data)},
  async deleteManualLeg(iata,importId,scheduleLegId){const result=await client.schema("Basic_Carrier_Record").rpc("delete_manual_schedule_leg",{p_iata:iata,p_import_id:importId,p_schedule_leg_id:scheduleLegId});fail(result.error);return edition(result.data)},
  async deleteEdition(iata,importId){const result=await client.schema("Basic_Carrier_Record").rpc("delete_flight_schedule_edition",{p_iata:iata,p_import_id:importId});fail(result.error)},
}};
