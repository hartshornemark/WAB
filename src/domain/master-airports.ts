export type MasterAirport={iata:string;icao:string|null;name:string;city:string|null;countryCode:string|null;timeZone:string;active:boolean;updatedAt:string};
export type MasterAirportInput=Omit<MasterAirport,"updatedAt">;
export type MasterAirportConfiguration={airports:MasterAirport[];timeZones:string[]};
export type MasterAirportField="iata"|"icao"|"name"|"city"|"countryCode"|"timeZone";
export class MasterAirportDenied extends Error{}
export class MasterAirportInvalid extends Error{constructor(public field:MasterAirportField,message:string){super(message)}}
export class MasterAirportExists extends Error{constructor(public field:"iata"|"icao"){super("That airport code already exists.")}}
export function validateMasterAirport(value:unknown):MasterAirportInput{
 const row=value as Partial<MasterAirportInput>,iata=String(row?.iata??"").trim().toUpperCase(),icao=String(row?.icao??"").trim().toUpperCase()||null,name=String(row?.name??"").trim(),city=String(row?.city??"").trim()||null,countryCode=String(row?.countryCode??"").trim().toUpperCase()||null,timeZone=String(row?.timeZone??"").trim();
 if(!/^[A-Z]{3}$/.test(iata))throw new MasterAirportInvalid("iata","Enter the three-letter IATA airport code.");
 if(icao&&!/^[A-Z0-9]{4}$/.test(icao))throw new MasterAirportInvalid("icao","Enter the four-character ICAO airport code.");
 if(!name||name.length>160)throw new MasterAirportInvalid("name","Enter an airport name of up to 160 characters.");
 if(city&&city.length>120)throw new MasterAirportInvalid("city","Keep the city name within 120 characters.");
 if(countryCode&&!/^[A-Z]{2}$/.test(countryCode))throw new MasterAirportInvalid("countryCode","Enter the two-letter country code.");
 if(!timeZone||timeZone.length>100)throw new MasterAirportInvalid("timeZone","Select an IANA time zone.");
 return{iata,icao,name,city,countryCode,timeZone,active:row?.active!==false};
}
