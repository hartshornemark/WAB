export type SsimParseStatus="PARSED"|"WARNING"|"ERROR"|"SKIPPED";

export type SsimImportRecord={
  lineNumber:number;
  recordType:string;
  rawRecord:string;
  parseStatus:SsimParseStatus;
  validationMessages:string[];
  parsedData:Record<string,unknown>;
};

export type SsimNormalizedLeg={
  sourceLineNumber:number;
  airlineDesignator:string;
  flightNumber:string;
  operationalSuffix:string;
  itineraryVariationIdentifier:string;
  legSequenceNumber:number;
  serviceType:string;
  periodStart:string;
  periodEnd:string;
  operatingDays:string;
  departureAirport:string;
  arrivalAirport:string;
  departureTimeLocal:string;
  arrivalTimeLocal:string;
  arrivalDayOffset:number;
  departureUtcOffsetMinutes:number|null;
  arrivalUtcOffsetMinutes:number|null;
  departureTerminal:string|null;
  arrivalTerminal:string|null;
  aircraftTypeIata:string|null;
  aircraftConfiguration:string|null;
  trafficRestrictionCodes:string|null;
  additionalData:Record<string,unknown>;
};

export type SsimParseResult={
  sourceCarrierIata:string;
  title:string|null;
  creatorReference:string|null;
  sourceCreationDate:string|null;
  periodStart:string|null;
  periodEnd:string|null;
  seasonCode:string|null;
  records:SsimImportRecord[];
  legs:SsimNormalizedLeg[];
  counts:Record<string,number>;
  warnings:string[];
};

export class SsimChapter7Invalid extends Error{}

const months:Record<string,number>={JAN:1,FEB:2,MAR:3,APR:4,MAY:5,JUN:6,JUL:7,AUG:8,SEP:9,OCT:10,NOV:11,DEC:12};
const text=(line:string,start:number,end:number)=>line.slice(start-1,end);
const value=(line:string,start:number,end:number)=>text(line,start,end).trim();
const upper=(input:string)=>input.trim().toUpperCase();

function parseDate(input:string,label:string){
  const match=/^(\d{2})([A-Z]{3})(\d{2})$/.exec(upper(input));
  if(!match||!months[match[2]])throw new Error(`${label} must use DDMMMYY.`);
  const year=2000+Number(match[3]),month=months[match[2]],day=Number(match[1]);
  const date=new Date(Date.UTC(year,month-1,day));
  if(date.getUTCFullYear()!==year||date.getUTCMonth()!==month-1||date.getUTCDate()!==day)throw new Error(`${label} is not a valid date.`);
  return `${year}-${String(month).padStart(2,"0")}-${String(day).padStart(2,"0")}`;
}

function parseTime(input:string,label:string){
  if(!/^\d{4}$/.test(input))throw new Error(`${label} must use HHMM.`);
  const hours=Number(input.slice(0,2)),minutes=Number(input.slice(2));
  if(hours>23||minutes>59)throw new Error(`${label} is not a valid time.`);
  return{sql:`${input.slice(0,2)}:${input.slice(2)}:00`,minutes:hours*60+minutes};
}

function parseOffset(input:string,label:string){
  const trimmed=input.trim();
  if(!trimmed)return null;
  const match=/^([+-])(\d{2})(\d{2})$/.exec(trimmed);
  if(!match)throw new Error(`${label} must use +HHMM or -HHMM.`);
  const hours=Number(match[2]),minutes=Number(match[3]);
  if(hours>14||minutes>59||(hours===14&&minutes!==0))throw new Error(`${label} is outside the supported UTC offset range.`);
  return(match[1]==="-"?-1:1)*(hours*60+minutes);
}

function operatingDays(input:string){
  if(input.trim()==="")return"1111111";
  return Array.from(input).map((day,index)=>{
    if(day===" ")return"0";
    if(day===String(index+1))return"1";
    throw new Error(`Days of operation contains ${JSON.stringify(day)} in the ${index+1} position.`);
  }).join("");
}

function dayOffset(departureMinutes:number,arrivalMinutes:number,departureOffset:number|null,arrivalOffset:number|null){
  if(departureOffset!==null&&arrivalOffset!==null){
    const departureUtc=departureMinutes-departureOffset;
    for(let day=0;day<=2;day+=1){
      const elapsed=day*1440+arrivalMinutes-arrivalOffset-departureUtc;
      if(elapsed>=0&&elapsed<=26*60)return{day,elapsed};
    }
  }
  const day=arrivalMinutes<departureMinutes?1:0;
  return{day,elapsed:day*1440+arrivalMinutes-departureMinutes};
}

type Supplementary={lineNumber:number;carrier:string;flightNumber:string;itineraryVariationIdentifier:string;legSequenceNumber:number;serviceType:string;boardOffIndicator:string;dataElementCode:string;boardPoint:string;offPoint:string;data:string;serialControl:string};
const supplementaryKey=(carrier:string,flight:string,variation:string,leg:number,service:string)=>[carrier,flight,variation,leg,service].join("|");

function parseSupplementary(line:string,lineNumber:number):Supplementary{
  const carrier=upper(value(line,3,5)),flightNumber=value(line,6,9),variation=value(line,10,11)||"1",leg=Number(value(line,12,13)||"1"),service=upper(value(line,14,14));
  if(!/^[A-Z0-9]{2,3}$/.test(carrier)||!/^(?:\d{1,4}|\d{1,3}[A-Z])$/.test(flightNumber)||!Number.isInteger(leg)||leg<1||!service)throw new Error("Supplementary record does not contain a valid flight key.");
  return{lineNumber,carrier,flightNumber,itineraryVariationIdentifier:variation,legSequenceNumber:leg,serviceType:service,boardOffIndicator:upper(value(line,29,30)),dataElementCode:upper(value(line,31,33)),boardPoint:upper(value(line,34,36)),offPoint:upper(value(line,37,39)),data:value(line,40,194),serialControl:value(line,195,200)};
}

function seasonFrom(start:string,end:string){
  const startDate=new Date(`${start}T00:00:00Z`),endDate=new Date(`${end}T00:00:00Z`);
  const startYear=String(startDate.getUTCFullYear()).slice(-2),endYear=String(endDate.getUTCFullYear()).slice(-2);
  const season=startDate.getUTCMonth()>=9?"W":"S";
  return startYear===endYear?`${season}${startYear}`:`${season}${startYear}/${endYear}`;
}

export function parseSsimChapter7(source:string,expectedCarrierIata:string):SsimParseResult{
  const expected=upper(expectedCarrierIata);
  if(!/^[A-Z0-9]{2}$/.test(expected))throw new SsimChapter7Invalid("Select a valid two-character carrier before importing a schedule.");
  if(source.includes("\0"))throw new SsimChapter7Invalid("The schedule file contains binary data and cannot be read as SSIM text.");
  const lines=source.split(/\r?\n/);if(lines.at(-1)==="")lines.pop();
  if(lines.length===0)throw new SsimChapter7Invalid("The schedule file is empty.");
  if(lines.length>1_000_000)throw new SsimChapter7Invalid("The schedule file contains too many records.");

  const records:SsimImportRecord[]=[],legs:SsimNormalizedLeg[]=[],warnings:string[]=[],counts:Record<string,number>={};
  const supplements=new Map<string,Supplementary[]>();
  let sourceCarrier="",title:string|null=null,creatorReference:string|null=null,sourceCreationDate:string|null=null,periodStart:string|null=null,periodEnd:string|null=null;
  let headerCount=0,carrierCount=0,trailerCount=0;

  lines.forEach((line,index)=>{
    const lineNumber=index+1;
    const zero=/^0+$/.test(line),recordType=zero?"0":line.slice(0,1);
    counts[recordType]=(counts[recordType]??0)+1;
    const base={lineNumber,recordType,rawRecord:line};
    if(line.length!==200){records.push({...base,parseStatus:"ERROR",validationMessages:[`Record must be exactly 200 characters; found ${line.length}.`],parsedData:{}});return}
    if(zero){records.push({...base,parseStatus:"SKIPPED",validationMessages:[],parsedData:{reason:"ZERO_FILLER"}});return}
    try{
      if(recordType==="1"){
        headerCount+=1;title=value(line,2,80)||null;
        records.push({...base,parseStatus:"PARSED",validationMessages:[],parsedData:{title,serialControl:value(line,195,200)}});return;
      }
      if(recordType==="2"){
        carrierCount+=1;
        const carrier=upper(value(line,3,5));
        if(!/^[A-Z0-9]{2,3}$/.test(carrier))throw new Error("Carrier record has no valid source carrier.");
        if(carrier!==expected)throw new Error(`This file is for carrier ${carrier}, while the open workspace is ${expected}.`);
        sourceCarrier=carrier;
        periodStart=parseDate(value(line,15,21),"Schedule start date");
        periodEnd=parseDate(value(line,22,28),"Schedule end date");
        sourceCreationDate=parseDate(value(line,29,35),"File creation date");
        if(periodEnd<periodStart)throw new Error("Schedule end date is before its start date.");
        creatorReference=value(line,36,194)||null;
        records.push({...base,parseStatus:"PARSED",validationMessages:[],parsedData:{transactionIndicator:value(line,2,2),sourceCarrierIata:carrier,periodStart,periodEnd,sourceCreationDate,creatorReference,serialControl:value(line,195,200)}});return;
      }
      if(recordType==="4"){
        const item=parseSupplementary(line,lineNumber),key=supplementaryKey(item.carrier,item.flightNumber,item.itineraryVariationIdentifier,item.legSequenceNumber,item.serviceType);
        supplements.set(key,[...(supplements.get(key)??[]),item]);
        records.push({...base,parseStatus:"PARSED",validationMessages:[],parsedData:item});return;
      }
      if(recordType==="5"){
        trailerCount+=1;
        const carrier=upper(value(line,3,5));
        if(carrier&&carrier!==expected)throw new Error(`Trailer carrier ${carrier} does not match workspace carrier ${expected}.`);
        records.push({...base,parseStatus:"PARSED",validationMessages:[],parsedData:{carrierIata:carrier,creationDate:parseDate(value(line,6,12),"Trailer creation date"),controlData:value(line,13,200)}});return;
      }
      if(recordType!=="3")throw new Error(`Record type ${JSON.stringify(recordType)} is not supported.`);
      // Type 3 records are parsed after supplementary records have been indexed.
    }catch(error){records.push({...base,parseStatus:"ERROR",validationMessages:[error instanceof Error?error.message:"Record could not be parsed."],parsedData:{}})}
  });

  lines.forEach((line,index)=>{
    if(line.length!==200||line.slice(0,1)!=="3")return;
    const lineNumber=index+1,recordIndex=records.findIndex(record=>record.lineNumber===lineNumber);
    try{
      const airlineDesignator=upper(value(line,3,5)),flightNumber=value(line,6,9),operationalSuffix=upper(value(line,2,2)),itineraryVariationIdentifier=value(line,10,11)||"1",legSequenceNumber=Number(value(line,12,13)||"1"),serviceType=upper(value(line,14,14));
      if(airlineDesignator!==expected)throw new Error(`Flight record carrier ${airlineDesignator||"(blank)"} does not match workspace carrier ${expected}.`);
      if(!/^(?:\d{1,4}|\d{1,3}[A-Z])$/.test(flightNumber))throw new Error("Flight number must contain up to four characters, beginning with digits and optionally ending with a letter.");
      if(!Number.isInteger(legSequenceNumber)||legSequenceNumber<1)throw new Error("Leg sequence number is invalid.");
      if(!/^[A-Z0-9]$/.test(serviceType))throw new Error("Service type is invalid.");
      const start=parseDate(value(line,15,21),"Flight period start"),end=parseDate(value(line,22,28),"Flight period end");
      if(end<start)throw new Error("Flight period end is before its start date.");
      const days=operatingDays(text(line,29,35));
      const departureAirport=upper(value(line,37,39)),arrivalAirport=upper(value(line,55,57));
      if(!/^[A-Z0-9]{3}$/.test(departureAirport)||!(/^[A-Z0-9]{3}$/.test(arrivalAirport))||departureAirport===arrivalAirport)throw new Error("Flight route must contain different three-character departure and arrival airports.");
      const passengerDeparture=parseTime(value(line,40,43),"Departure time"),aircraftDeparture=parseTime(value(line,44,47),"Aircraft departure time");
      const passengerArrival=parseTime(value(line,58,61),"Arrival time"),aircraftArrival=parseTime(value(line,62,65),"Aircraft arrival time");
      const departureOffset=parseOffset(value(line,48,52),"Departure UTC offset"),arrivalOffset=parseOffset(value(line,66,70),"Arrival UTC offset");
      const arrival=dayOffset(passengerDeparture.minutes,passengerArrival.minutes,departureOffset,arrivalOffset);
      const key=supplementaryKey(airlineDesignator,flightNumber,itineraryVariationIdentifier,legSequenceNumber,serviceType);
      const attached=(supplements.get(key)??[]).map(item=>({lineNumber:item.lineNumber,flightNumber:item.flightNumber,itineraryVariationIdentifier:item.itineraryVariationIdentifier,legSequenceNumber:item.legSequenceNumber,serviceType:item.serviceType,boardOffIndicator:item.boardOffIndicator,dataElementCode:item.dataElementCode,boardPoint:item.boardPoint,offPoint:item.offPoint,data:item.data,serialControl:item.serialControl}));
      const aircraftTypeIata=upper(value(line,73,75))||null,aircraftConfiguration=upper(value(line,76,78))||null;
      const leg:SsimNormalizedLeg={sourceLineNumber:lineNumber,airlineDesignator,flightNumber,operationalSuffix,itineraryVariationIdentifier,legSequenceNumber,serviceType,periodStart:start,periodEnd:end,operatingDays:days,departureAirport,arrivalAirport,departureTimeLocal:passengerDeparture.sql,arrivalTimeLocal:passengerArrival.sql,arrivalDayOffset:arrival.day,departureUtcOffsetMinutes:departureOffset,arrivalUtcOffsetMinutes:arrivalOffset,departureTerminal:upper(value(line,53,54))||null,arrivalTerminal:upper(value(line,71,72))||null,aircraftTypeIata,aircraftConfiguration,trafficRestrictionCodes:null,additionalData:{scheduledAircraftDeparture:aircraftDeparture.sql,scheduledAircraftArrival:aircraftArrival.sql,scheduledElapsedMinutes:arrival.elapsed,type3UnmappedTail:text(line,79,192),serialControl:value(line,193,200),supplementaryRecords:attached}};
      legs.push(leg);
      const parsedData={...leg,additionalData:leg.additionalData};
      const parsed:SsimImportRecord={lineNumber,recordType:"3",rawRecord:line,parseStatus:"PARSED",validationMessages:[],parsedData};
      if(recordIndex>=0)records[recordIndex]=parsed;else records.push(parsed);
    }catch(error){
      const parsed:SsimImportRecord={lineNumber,recordType:"3",rawRecord:line,parseStatus:"ERROR",validationMessages:[error instanceof Error?error.message:"Flight record could not be parsed."],parsedData:{}};
      if(recordIndex>=0)records[recordIndex]=parsed;else records.push(parsed);
    }
  });

  records.sort((a,b)=>a.lineNumber-b.lineNumber);
  if(headerCount!==1)warnings.push(`Expected one Type 1 header; found ${headerCount}.`);
  if(carrierCount!==1)warnings.push(`Expected one Type 2 carrier record; found ${carrierCount}.`);
  if(trailerCount!==1)warnings.push(`Expected one Type 5 trailer; found ${trailerCount}.`);
  if(!sourceCarrier)warnings.push("No valid Type 2 carrier record was found.");
  if(legs.length===0)warnings.push("No valid Type 3 flight legs were found.");
  const structuralErrors=warnings.map((message,index)=>({lineNumber:records.length+index+1,recordType:"V",rawRecord:"VALIDATION",parseStatus:"ERROR" as const,validationMessages:[message],parsedData:{}}));
  if(structuralErrors.length)records.push(...structuralErrors);
  return{sourceCarrierIata:sourceCarrier,title,creatorReference,sourceCreationDate,periodStart,periodEnd,seasonCode:periodStart&&periodEnd?seasonFrom(periodStart,periodEnd):null,records,legs,counts,warnings};
}
