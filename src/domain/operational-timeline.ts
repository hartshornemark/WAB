export const operationalTimelineMilestoneKeys=["BOOKED_PASSENGERS","CARGO_OFFER","CARGO_RELEASE","AIRCRAFT_ASSIGNMENT","LOAD_PLAN","FLIGHT_PLAN","CLOSE_OUT","DOCUMENTS"]as const;
export type OperationalTimelineMilestoneKey=typeof operationalTimelineMilestoneKeys[number];

export const operationalTimelineMilestoneLabels:Record<OperationalTimelineMilestoneKey,string>={
  BOOKED_PASSENGERS:"Booked Passengers",
  CARGO_OFFER:"Cargo Offer",
  CARGO_RELEASE:"Cargo Uplift Release",
  AIRCRAFT_ASSIGNMENT:"Aircraft Assignment",
  LOAD_PLAN:"Load Plan Edition 1",
  FLIGHT_PLAN:"Flight Plan",
  CLOSE_OUT:"Close Out",
  DOCUMENTS:"Documents Produced",
};

export type OperationalTimelineValues={
  deadlines:Record<OperationalTimelineMilestoneKey,number>;
  amberLeadMinutes:number;
  archiveAfterStdMinutes:number;
};
export type OperationalTimelineConfiguration=OperationalTimelineValues&{
  aircraftType:string|null;
  revision:number;
  source:"SYSTEM_DEFAULT"|"CARRIER_DEFAULT"|"AIRCRAFT_TYPE";
};
export type OperationalTimelineSnapshot={
  canEdit:boolean;
  aircraftTypes:string[];
  defaultConfiguration:OperationalTimelineConfiguration;
  overrides:OperationalTimelineConfiguration[];
};
export type OperationalTimelineCompletion=Record<OperationalTimelineMilestoneKey,boolean>;
export type OperationalTimelineTone="on-track"|"attention"|"late"|"complete"|"archived"|"cancelled"|"unknown";
export type OperationalTimelineHealth={
  tone:OperationalTimelineTone;
  milestone:OperationalTimelineMilestoneKey|null;
  label:string;
  target:string;
  description:string;
};

export const defaultOperationalTimeline:OperationalTimelineValues={
  deadlines:{
    BOOKED_PASSENGERS:360,
    CARGO_OFFER:360,
    CARGO_RELEASE:120,
    AIRCRAFT_ASSIGNMENT:90,
    LOAD_PLAN:90,
    FLIGHT_PLAN:45,
    CLOSE_OUT:30,
    DOCUMENTS:15,
  },
  amberLeadMinutes:10,
  archiveAfterStdMinutes:1_440,
};

export const systemOperationalTimelineConfiguration:OperationalTimelineConfiguration={
  ...defaultOperationalTimeline,
  deadlines:{...defaultOperationalTimeline.deadlines},
  aircraftType:null,
  revision:0,
  source:"SYSTEM_DEFAULT",
};

export class OperationalTimelineInvalid extends Error{}
export class OperationalTimelineDenied extends Error{}
export class OperationalTimelineConflict extends Error{}

const whole=(value:unknown,label:string,min:number,max:number)=>{const number=Number(value);if(!Number.isSafeInteger(number)||number<min||number>max)throw new OperationalTimelineInvalid(`${label} must be a whole number between ${min} and ${max} minutes.`);return number};
export function validateOperationalTimeline(value:unknown):OperationalTimelineValues{
  if(!value||typeof value!=="object")throw new OperationalTimelineInvalid("Enter the Load Control timeline deadlines.");
  const row=value as{deadlines?:Record<string,unknown>;amberLeadMinutes?:unknown;archiveAfterStdMinutes?:unknown};
  if(!row.deadlines||typeof row.deadlines!=="object")throw new OperationalTimelineInvalid("Enter every Load Control timeline deadline.");
  const deadlines=Object.fromEntries(operationalTimelineMilestoneKeys.map(key=>[key,whole(row.deadlines![key],operationalTimelineMilestoneLabels[key],0,1_440)]))as Record<OperationalTimelineMilestoneKey,number>;
  const amberLeadMinutes=whole(row.amberLeadMinutes,"Amber warning",1,120);
  const archiveAfterStdMinutes=whole(row.archiveAfterStdMinutes,"Archive after STD",60,10_080);
  for(let index=1;index<operationalTimelineMilestoneKeys.length;index++){
    const previous=operationalTimelineMilestoneKeys[index-1],current=operationalTimelineMilestoneKeys[index];
    if(deadlines[previous]<deadlines[current])throw new OperationalTimelineInvalid(`${operationalTimelineMilestoneLabels[current]} cannot be due before ${operationalTimelineMilestoneLabels[previous]}.`);
  }
  return{deadlines,amberLeadMinutes,archiveAfterStdMinutes};
}

export function formatTimelineOffset(minutes:number){
  if(minutes===0)return"STD";
  const hours=Math.floor(minutes/60),remainder=minutes%60;
  return`STD − ${hours?`${hours}H`:""}${hours&&remainder?" ":""}${remainder?`${remainder}M`:""}`;
}

export function operationalScheduledInstant(value:string,utcOffsetMinutes:number|null){
  const local=/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/.exec(value);
  if(local){const[,year,month,day,hour,minute,second="0"]=local;return Date.UTC(Number(year),Number(month)-1,Number(day),Number(hour),Number(minute),Number(second))-(utcOffsetMinutes??0)*60_000}
  return Date.parse(value);
}

export function formatOperationalLocalDateTime(value:string,delayMinutes=0){
  const local=/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(value);
  if(!local)return"—";
  const[,year,month,day,hour,minute]=local,date=new Date(Date.UTC(Number(year),Number(month)-1,Number(day),Number(hour),Number(minute))+delayMinutes*60_000);
  return new Intl.DateTimeFormat("en-GB",{day:"2-digit",month:"short",year:"numeric",hour:"2-digit",minute:"2-digit",hour12:false,timeZone:"UTC"}).format(date);
}

export function operationalTimelineHealth(input:{departureLocal:string;departureUtcOffsetMinutes:number|null;delayMinutes?:number;configuration:OperationalTimelineConfiguration;completion:OperationalTimelineCompletion;cancelled?:boolean;now?:Date}):OperationalTimelineHealth{
  if(input.cancelled)return{tone:"cancelled",milestone:null,label:"Cancelled",target:"NOT OPERATING",description:"This flight is cancelled."};
  if(operationalFlightArchived(input.departureLocal,input.departureUtcOffsetMinutes,input.configuration,input.delayMinutes??0,input.now))return{tone:"archived",milestone:null,label:"Archived",target:`REVISED STD + ${formatDuration(input.configuration.archiveAfterStdMinutes)}`,description:"This operational flight is archived and read-only."};
  const milestone=operationalTimelineMilestoneKeys.find(key=>!input.completion[key])??null;
  if(!milestone)return{tone:"complete",milestone:null,label:"Complete",target:"ALL MILESTONES",description:"Every configured Load Control milestone is complete."};
  const departure=operationalScheduledInstant(input.departureLocal,input.departureUtcOffsetMinutes)+(input.delayMinutes??0)*60_000,deadlineMinutes=input.configuration.deadlines[milestone],target=formatTimelineOffset(deadlineMinutes),label=operationalTimelineMilestoneLabels[milestone];
  if(!Number.isFinite(departure))return{tone:"unknown",milestone,label,target:"TIME UNKNOWN",description:"A valid scheduled departure time is required."};
  const deadline=departure-deadlineMinutes*60_000,warning=deadline-input.configuration.amberLeadMinutes*60_000,now=(input.now??new Date()).getTime();
  const description=`${label} is due by ${target}. Amber begins ${input.configuration.amberLeadMinutes} minutes before that deadline; red applies at the deadline.`;
  if(now>=deadline)return{tone:"late",milestone,label,target,description};
  if(now>=warning)return{tone:"attention",milestone,label,target,description};
  return{tone:"on-track",milestone,label,target,description};
}

export function formatDuration(minutes:number){const hours=Math.floor(minutes/60),remainder=minutes%60;return`${hours?`${hours}H`:""}${hours&&remainder?" ":""}${remainder?`${remainder}M`:""}`}
export function operationalFlightArchived(departureLocal:string,utcOffsetMinutes:number|null,configuration:OperationalTimelineConfiguration,delayMinutes=0,now:Date=new Date()){
  const departure=operationalScheduledInstant(departureLocal,utcOffsetMinutes)+delayMinutes*60_000;
  return Number.isFinite(departure)&&now.getTime()>=departure+configuration.archiveAfterStdMinutes*60_000;
}

export function effectiveOperationalTimeline(snapshot:OperationalTimelineSnapshot,aircraftType:string){
  return snapshot.overrides.find(row=>row.aircraftType===aircraftType.trim().toUpperCase())??snapshot.defaultConfiguration;
}
