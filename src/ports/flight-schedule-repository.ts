import type{AircraftOperatingRole}from"@/domain/aircraft-c1";
import type{SsimImportRecord,SsimNormalizedLeg}from"@/domain/ssim-chapter7";

export type FlightScheduleImport={
  importId:string;fileName:string;sourceCarrierIata:string;sourceFormat:string;status:string;uploadedAt:string;
  coverageStart:string|null;coverageEnd:string|null;recordCount:number;legCount:number;rejectedCount:number;
};

export type FlightWeightBasis="STANDARD"|"VARIATION"|"ACTUAL";
export type FlightWeightChoice={code:string;description:string};
export type FlightScheduleWeightOptions={passenger:{available:boolean;defaultBasis:"STANDARD";variations:FlightWeightChoice[]};baggage:{available:boolean;defaultBasis:"STANDARD"|"ACTUAL";variations:FlightWeightChoice[]}};
export type FlightScheduleParameters={aircraftSubtype:string;crewCode:string;pantryCode:string;passengerWeightBasis:FlightWeightBasis;passengerVariation:string|null;baggageWeightBasis:FlightWeightBasis;baggageVariation:string|null;remarks:string};
export type FlightScheduleSegmentDefault=FlightScheduleParameters&{departureAirport:string;arrivalAirport:string;aircraftType:string;updatedAt:string};
export type PublishedScheduleLeg={scheduleImportId:string;scheduleFamilyId:string;scheduleName:string;scheduleLegId:string;flightNumber:string;operationalSuffix:string;itineraryVariation:string;legSequence:number;serviceType:string;periodStart:string;periodEnd:string;operatingDays:string;departureAirport:string;arrivalAirport:string;departureTime:string;arrivalTime:string;arrivalDayOffset:number;aircraftType:string|null;aircraftSubtype:string|null;aircraftConfiguration:string|null;parameters:FlightScheduleParameters|null};
export type FlightScheduleWorkspace={canView:boolean;canConfigure:boolean;publishedImportIds:string[];legs:PublishedScheduleLeg[];segmentDefaults:FlightScheduleSegmentDefault[];weightOptions:FlightScheduleWeightOptions;serviceTypes:{code:string;name:string;application:string;typeOfOperation:string;description:string;sourceReference:string}[];airports:{iata:string;icao:string|null;name:string;city:string;countryCode:string|null;timeZone:string}[];aircraft:{typeCode:string;subtype:string;name:string;operatingRole:AircraftOperatingRole}[];aircraftConfigurations:{typeCode:string;subtype:string;code:string;description:string}[];crewCodes:{typeCode:string;subtype:string;code:string}[];pantryCodes:{typeCode:string;subtype:string;code:string}[];variations:{code:string;description:string}[]};
export type ManualScheduleLegInput={airlineDesignator:string;flightNumber:string;operationalSuffix:string;itineraryVariation:string;legSequence:number;serviceType:string;periodStart:string;periodEnd:string;operatingDays:string;departureAirport:string;arrivalAirport:string;departureTime:string;arrivalTime:string;arrivalDayOffset:number;aircraftType:string;aircraftSubtype:string;aircraftConfiguration:string|null};
export type ScheduleEditionLeg={scheduleLegId:string;flightNumber:string;operationalSuffix:string;itineraryVariation:string;legSequence:number;serviceType:string;periodStart:string;periodEnd:string;operatingDays:string;departureAirport:string;arrivalAirport:string;departureTime:string;arrivalTime:string;arrivalDayOffset:number;aircraftType:string|null;aircraftSubtype:string|null;aircraftConfiguration:string|null};
export type FlightScheduleEdition={importId:string;name:string;sourceFormat:string;status:string;seasonCode:string|null;coverageStart:string|null;coverageEnd:string|null;recordCount:number;legCount:number;rejectedCount:number;canEdit:boolean;canDelete:boolean;legs:ScheduleEditionLeg[]};
export type ManualScheduleItineraryResult={importId:string;scheduleLegIds:string[];status:string};

export type FlightScheduleStageResult={
  importId:string;status:string;records:number;accepted:number;rejected:number;normalizedLegs:number;
  coverageStart:string|null;coverageEnd:string|null;
};

export interface FlightScheduleRepository{
  list(iata:string):Promise<FlightScheduleImport[]>;
  workspace(iata:string):Promise<FlightScheduleWorkspace>;
  createAndStage(iata:string,metadata:{sourceCarrierIata:string;fileName:string;sha256:string;sizeBytes:number;seasonCode:string|null;creatorReference:string|null},records:SsimImportRecord[],legs:SsimNormalizedLeg[]):Promise<FlightScheduleStageResult>;
  publish(iata:string,importId:string):Promise<FlightScheduleStageResult>;
  cancel(iata:string,importId:string):Promise<void>;
  createRevision(iata:string,importId:string):Promise<string>;
  saveParameters(iata:string,scheduleLegId:string,values:FlightScheduleParameters):Promise<FlightScheduleWorkspace>;
  saveSegmentDefault(iata:string,departureAirport:string,arrivalAirport:string,aircraftType:string,values:FlightScheduleParameters):Promise<FlightScheduleWorkspace>;
  deleteSegmentDefault(iata:string,departureAirport:string,arrivalAirport:string,aircraftType:string):Promise<FlightScheduleWorkspace>;
  createManual(iata:string,name:string,seasonCode:string|null):Promise<string>;
  saveManualLeg(iata:string,importId:string,scheduleLegId:string|null,values:ManualScheduleLegInput):Promise<{importId:string;scheduleLegId:string;status:string}>;
  saveManualItinerary(iata:string,importId:string,values:ManualScheduleLegInput[]):Promise<ManualScheduleItineraryResult>;
  edition(iata:string,importId:string):Promise<FlightScheduleEdition>;
  deleteManualLeg(iata:string,importId:string,scheduleLegId:string):Promise<FlightScheduleEdition>;
  deleteEdition(iata:string,importId:string):Promise<void>;
}
