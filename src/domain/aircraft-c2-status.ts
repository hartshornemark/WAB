import{aggregateConfigurationStatuses,type ConfigurationStatus,type DisplayConfigurationStatus}from"@/domain/configuration-status";
import type{AircraftC2Snapshot,C2Output}from"@/domain/aircraft-c2";

const documentFields:{code:string;selected:keyof C2Output;valid:keyof C2Output}[]=[
  {code:"LS EDP PRELIM",selected:"selectedEdpPrelim",valid:"validEdpPrelim"},
  {code:"LS ACARS PRELIM",selected:"selectedAcarsPrelim",valid:"validAcarsPrelim"},
  {code:"LS EDP FINAL",selected:"selectedEdpFinal",valid:"validEdpFinal"},
  {code:"LS ACARS FINAL",selected:"selectedAcarsFinal",valid:"validAcarsFinal"}
];

export type AircraftC2Statuses={page:DisplayConfigurationStatus;documents:DisplayConfigurationStatus;balance:DisplayConfigurationStatus;trim:DisplayConfigurationStatus};
export type AircraftC5Applicability={tow:boolean;law:boolean;zfw:boolean};

const envelopeCodes:Record<keyof AircraftC5Applicability,readonly string[]>={
  tow:["LITOW","MACTOW"],
  law:["LILAW","MACLAW"],
  zfw:["LIZFW","MACZFW"]
};

export function aircraftC5ApplicabilityFromC2(snapshot:AircraftC2Snapshot):AircraftC5Applicability{
  const activeDocuments=new Set(snapshot.documents.filter(document=>document.required).map(document=>document.code));
  const selected=(codes:readonly string[])=>snapshot.outputs.some(output=>codes.includes(output.code)&&documentFields.some(field=>activeDocuments.has(field.code)&&Boolean(output[field.valid])&&Boolean(output[field.selected])));
  return{tow:selected(envelopeCodes.tow),law:selected(envelopeCodes.law),zfw:selected(envelopeCodes.zfw)};
}

export function aircraftC2Statuses(snapshot:AircraftC2Snapshot):AircraftC2Statuses{
  const activeDocuments=new Set(snapshot.documents.filter(document=>document.required).map(document=>document.code));
  if(activeDocuments.size===0)return{page:"skipped",documents:"skipped",balance:"skipped",trim:"skipped"};
  const balance:ConfigurationStatus=snapshot.outputs.some(output=>documentFields.some(field=>activeDocuments.has(field.code)&&Boolean(output[field.valid])&&Boolean(output[field.selected])))?"configured":"incomplete";
  const selectedTrim=snapshot.trimOptions.filter(option=>option.selected);
  const priorities=selectedTrim.map(option=>option.priority);
  const trim:ConfigurationStatus=selectedTrim.length>0&&priorities.every(priority=>Number.isInteger(priority)&&priority!>=1&&priority!<=3)&&new Set(priorities).size===priorities.length?"configured":"incomplete";
  return{page:aggregateConfigurationStatuses([balance,trim]),documents:"configured",balance,trim};
}
