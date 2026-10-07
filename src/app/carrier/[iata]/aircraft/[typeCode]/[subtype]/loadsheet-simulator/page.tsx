import Link from"next/link";
import{notFound,redirect}from"next/navigation";
import{AircraftContextHeading}from"@/components/aircraft-context-heading";
import{LoadsheetSimulator,type LoadsheetSimulatorData}from"@/components/loadsheet-simulator";
import{WorkspaceShell}from"@/components/workspace-shell";
import{aircraftC1Services,aircraftC2Services,aircraftC4Services,aircraftC5Services,aircraftC8Services,aircraftC11Services,aircraftD2Services,aircraftD3Services,aircraftD5Services,aircraftD8Services,aircraftE12Services,aircraftE2Services,passengerServices,services}from"@/composition/services";
import{aircraftC5ApplicabilityFromC2}from"@/domain/aircraft-c2-status";
import{effectiveAircraftD2Snapshot}from"@/domain/aircraft-d2";
import{effectiveAircraftD3Snapshot}from"@/domain/aircraft-d3";
import{aircraftLoadsheetLocations}from"@/domain/loadsheet-locations";
import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";

export default async function Page({params}:{params:Promise<{iata:string;typeCode:string;subtype:string}>}){
 const{iata,typeCode,subtype}=await params,result=await(await services()).selectCarrier(iata).catch(error=>{if(error instanceof AuthenticationRequired)redirect("/login");if(error instanceof CarrierUnavailable)notFound();throw error});
 const[c1,c2,c4,c5,c8,c11,d2,d3,d5,d8,e12,e2,passenger]=await Promise.all([(await aircraftC1Services()).get(iata,typeCode,subtype),(await aircraftC2Services()).get(iata,typeCode,subtype),(await aircraftC4Services()).get(iata,typeCode,subtype),(await aircraftC5Services()).get(iata,typeCode,subtype),(await aircraftC8Services()).get(iata,typeCode,subtype),(await aircraftC11Services()).get(iata,typeCode,subtype),(await aircraftD2Services()).get(iata,typeCode,subtype),(await aircraftD3Services()).get(iata,typeCode,subtype),(await aircraftD5Services()).get(iata,typeCode,subtype),(await aircraftD8Services()).get(iata,typeCode,subtype),(await aircraftE12Services()).get(iata,typeCode,subtype),(await aircraftE2Services()).get(iata,typeCode,subtype),(await passengerServices()).get(iata)]);
 if(!c1.typeCode)notFound();
 const registrations=e12.registrations.filter(row=>row.weight!==null&&row.index!==null).map(row=>({registration:row.registration,dow:row.weight!,doi:row.index!,fuelConfigurationCode:row.fuelConfigurationCode,maximumWeights:e12.fuelConfigurations.find(item=>item.code===row.fuelConfigurationCode)?.maximumWeights??null}));
 const deviations=<T extends{isBase:boolean;weightAdjustment:number|null;indexAdjustment:number|null}>(rows:T[],code:(row:T)=>string)=>[...new Map(rows.map(row=>[code(row),{code:code(row),weight:row.weightAdjustment??0,index:row.indexAdjustment??0,base:row.isBase}])).values()];
 const crewCodes=deviations(e2.crewRows,row=>row.crewCode),pantryCodes=deviations(e2.pantryRows,row=>row.pantryCode);
 const locationsByConfiguration:LoadsheetSimulatorData["locationsByConfiguration"]={};
 const configurationKeys=["ALL",...e12.fuelConfigurations.map(item=>item.code)];
 for(const key of configurationKeys){const configuration=key==="ALL"?null:key,effectiveD2=effectiveAircraftD2Snapshot(d2,configuration),effectiveD3=effectiveAircraftD3Snapshot(d3,configuration);
  locationsByConfiguration[key]=aircraftLoadsheetLocations(effectiveD2,effectiveD3);
 }
 const fuelGroups=new Map<string,{configurationCode:string|null;specificGravity:number;points:{weight:number;index:number}[]}>();
 for(const row of c8.values.standard.rows){const key=`${row.configurationCode??"ALL"}|${row.specificGravity}`,group=fuelGroups.get(key)??{configurationCode:row.configurationCode??null,specificGravity:row.specificGravity,points:[]};group.points.push({weight:row.fuelWeight,index:row.indexValue});fuelGroups.set(key,group)}
 const fuelTables=[...fuelGroups.entries()].map(([id,group])=>({id,label:`${group.configurationCode??"ALL"} · SG ${group.specificGravity.toFixed(3)}`,configurationCode:group.configurationCode,specificGravity:group.specificGravity,points:group.points.sort((a,b)=>a.weight-b.weight)}));
 const weights=passenger.defaultWeights,adult=weights?.adult??0;
 const initial:LoadsheetSimulatorData={carrierCode:iata,typeCode:c1.typeCode,subtype:c1.subtype,weightUnit:c5.weightUnit,registrations,crewCodes,pantryCodes,passengerWeights:{male:weights?.male??adult,female:weights?.female??adult,child:weights?.child??0,infant:weights?.infant??0},passengerWeightSource:weights?`Saved B3 standard passenger weights (${passenger.unit??c5.weightUnit}); hand baggage ${weights.includesHandBaggage?"included":"recorded separately"}.`:"No B3 standard passenger weights are saved.",cabinAreas:d5.cabinAreas.filter(area=>area.index!==null).map(area=>({id:area.id,description:`Rows ${area.startRow}–${area.endRow} · Max ${d8.rows.filter(row=>row.areaId===area.id).reduce((total,row)=>total+(row.maximumSeats??0),0)} seats`,indexPerWeightUnit:area.index!,maximumSeats:d8.rows.filter(row=>row.areaId===area.id).reduce((total,row)=>total+(row.maximumSeats??0),0)||null})),locationsByConfiguration,fuelTables,defaultTaxiFuel:c8.values.taxiFuel.rows.find(row=>row.isDefault)?.taxiFuel??0,formula:c4.values,limits:c5.values,envelopeApplicability:aircraftC5ApplicabilityFromC2(c2),stabiliser:c11.exists?c11.values:null,holdSnapshot:d2,seatMapSnapshot:d8};
 return <WorkspaceShell user={result.user}><Link href={`/carrier/${iata}/aircraft/${typeCode}/${subtype}/dashboard`} className="back">← Aircraft dashboard</Link><p className="eyebrow">DATA VERIFICATION / {result.carrier.iata} / {c1.typeCode}-{c1.subtype}</p><AircraftContextHeading iata={iata} logoUrl={result.carrier.logoUrl} carrierName={result.carrier.name} aircraft={c1}/>{registrations.length&&crewCodes.length&&pantryCodes.length&&fuelTables.length&&c4.exists?<LoadsheetSimulator initial={initial}/>:<section className="sim-card"><h2>Simulator prerequisites are incomplete</h2><p>Complete E1.2 registrations, E2 crew and pantry codes, C4 formulae and a C8 standard fuel table before running an EDP loadsheet verification.</p></section>}</WorkspaceShell>;
}
