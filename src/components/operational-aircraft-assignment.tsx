"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { saveOperationalFreightPlanning } from "@/app/load-control-actions";
import { operationalAircraftAssignmentReady } from "@/domain/operational-flights";
import type { OperationalFreightPlanning } from "@/ports/operational-flight-repository";

type Draft={weightBasis:"FLEET_WEIGHT"|"REGISTRATION";registration:string;crewCode:string;pantryCode:string};
const kg=(value:number|null|undefined)=>value===null||value===undefined?"—":`${Math.round(value).toLocaleString()} KG`;
const draftOf=(planning:OperationalFreightPlanning):Draft=>({weightBasis:planning.weightBasis,registration:planning.registration??"",crewCode:planning.crewCode??"",pantryCode:planning.pantryCode??""});

export function OperationalAircraftAssignment({iata,flightId,aircraftType,aircraftSubtype,initial,embedded=false}:{iata:string;flightId:string;aircraftType:string;aircraftSubtype:string;initial:OperationalFreightPlanning;embedded?:boolean}){
 const router=useRouter(),initialReady=operationalAircraftAssignmentReady(initial),[saved,setSaved]=useState(initial),[draft,setDraft]=useState(()=>draftOf(initial)),[editing,setEditing]=useState(!initialReady),[notice,setNotice]=useState<{ok:boolean;text:string}|null>(null),[pending,start]=useTransition(),assigned=operationalAircraftAssignmentReady(saved),usingFleetWeight=assigned&&saved.weightBasis==="FLEET_WEIGHT";
 if(!saved.applicable)return null;
 const save=()=>start(async()=>{let timer:ReturnType<typeof setTimeout>|undefined;try{const result=await Promise.race([saveOperationalFreightPlanning(iata,flightId,saved.version,{...draft,registration:draft.weightBasis==="REGISTRATION"?draft.registration:null}),new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new Error("SAVE_RESPONSE_TIMEOUT")),15000)})]);if(!result.ok||!result.planning){setNotice({ok:false,text:result.message});return}setSaved(result.planning);setDraft(draftOf(result.planning));setEditing(false);setNotice({ok:true,text:result.message});router.refresh()}catch{setNotice({ok:false,text:"The save response was interrupted. Reloading the current aircraft assignment…"});router.refresh()}finally{if(timer)clearTimeout(timer)}});
 return <details className={`freight-planning aircraft-assignment${embedded?" aircraft-assignment-embedded":" operational-collapsible"}${assigned?" assigned":" unassigned"}`} open={embedded||!assigned||editing}>
  {embedded&&<summary className="aircraft-assignment-embedded-summary">Aircraft assignment details</summary>}
  {!embedded&&<summary className="operational-collapsible-summary">
   <div><p className="eyebrow">OPERATING AIRCRAFT</p><h2>Aircraft Assignment</h2><p>Select the operating registration and confirm the applicable crew and pantry codes.</p></div>
   <div className="operational-summary-facts"><span><small>OPERATING BASIS</small><strong>{saved.registration??(usingFleetWeight?"FLEET WEIGHT":"NOT ASSIGNED")}</strong></span><span><small>PLANNING WEIGHT</small><strong>{kg(saved.planningAircraftWeight)}</strong></span><span><small>RELEASE STATUS</small><strong>{usingFleetWeight?"FLEET WEIGHT CONFIRMED":assigned?"ASSIGNED":"AIRCRAFT REQUIRED"}</strong></span></div>
  </summary>}
  <div className="operational-collapsible-body">
   {!assigned&&<p className="load-control-notice warning"><strong>Preliminary planning only.</strong> Assign the operating aircraft or confirm that this flight will proceed with Fleet Weight before Close Out.</p>}
   <div className="freight-planning-heading"><p>Fleet Weight remains available while the registration is unknown. The selected aircraft supplies its operating weight and index adjustments for final calculations.</p>{saved.canEdit&&!editing&&<button className="secondary" type="button" onClick={()=>{setDraft(draftOf(saved));setEditing(true);setNotice(null)}}>EDIT ASSIGNMENT</button>}</div>
   {editing?<div className="freight-planning-form">
    <label>Operating aircraft<select value={draft.weightBasis==="FLEET_WEIGHT"?"FLEET_WEIGHT":draft.registration} onChange={event=>{const selected=event.target.value;setDraft(current=>selected==="FLEET_WEIGHT"?{...current,weightBasis:"FLEET_WEIGHT",registration:""}:{...current,weightBasis:"REGISTRATION",registration:selected})}}><option value="FLEET_WEIGHT">PROCEED WITH FLEET WEIGHT · {kg(saved.fleetWeight)}</option>{saved.registrationOptions.map(row=><option value={row.registration} key={row.registration}>{row.registration} · {kg(row.weight)}</option>)}</select>{saved.registrationOptions.length===0&&<small>No registrations are configured for {aircraftType}-{aircraftSubtype}. <Link href={`/carrier/${encodeURIComponent(iata)}/aircraft/${encodeURIComponent(aircraftType)}/${encodeURIComponent(aircraftSubtype)}/e1-2`}>Configure fleet registrations</Link>.</small>}</label>
    <label>Crew code<select value={draft.crewCode} onChange={event=>setDraft(current=>({...current,crewCode:event.target.value}))}><option value="">Select crew code</option>{saved.crewOptions.map(row=><option value={row.code} key={row.code}>{row.code}{row.isBase?" · BASE":""}</option>)}</select></label>
    <label>Pantry code<select value={draft.pantryCode} onChange={event=>setDraft(current=>({...current,pantryCode:event.target.value}))}><option value="">Select pantry code</option>{saved.pantryOptions.map(row=><option value={row.code} key={row.code}>{row.code}{row.isBase?" · BASE":""}</option>)}</select></label>
    <div className="freight-planning-actions"><button className="secondary" type="button" disabled={pending||!assigned} onClick={()=>{setDraft(draftOf(saved));setEditing(false);setNotice(null)}}>CANCEL</button><button type="button" disabled={pending||!draft.crewCode||!draft.pantryCode||(draft.weightBasis==="REGISTRATION"&&!draft.registration)} onClick={save}>{pending?"SAVING…":"SAVE"}</button></div>
   </div>:<div className="freight-basis-summary"><div><small>OPERATING BASIS</small><strong>{saved.registration??"FLEET WEIGHT"}</strong><span>{kg(saved.planningAircraftWeight)}</span></div><div><small>CREW CODE</small><strong>{saved.crewCode??"—"}</strong><span>{saved.crewWeightAdjustment?`${saved.crewWeightAdjustment>0?"+":""}${kg(saved.crewWeightAdjustment)}`:"BASE"}</span></div><div><small>PANTRY CODE</small><strong>{saved.pantryCode??"—"}</strong><span>{saved.pantryWeightAdjustment?`${saved.pantryWeightAdjustment>0?"+":""}${kg(saved.pantryWeightAdjustment)}`:"BASE"}</span></div></div>}
   {notice&&<p className={`load-control-notice ${notice.ok?"success":"error"}`} role="status">{notice.text}</p>}
  </div>
 </details>
}
