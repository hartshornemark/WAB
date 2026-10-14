"use client";

import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {saveOperationalFlightEquipment} from "@/app/load-control-actions";

export type OperationalEquipmentOption={
 typeCode:string;
 subtype:string;
 name:string;
 configurations:Array<{code:string;description:string;isDefault:boolean}>;
};

type Draft={aircraftKey:string;configuration:string};
const keyOf=(type:string,subtype:string)=>`${type}|${subtype}`;

export function OperationalFlightEquipment({iata,flightId,version,initialType,initialSubtype,initialConfiguration,publishedType,publishedSubtype,publishedConfiguration,options,canOperate,archived,hasLoadPlan}:{iata:string;flightId:string;version:number;initialType:string;initialSubtype:string;initialConfiguration:string|null;publishedType:string;publishedSubtype:string|null;publishedConfiguration:string|null;options:OperationalEquipmentOption[];canOperate:boolean;archived:boolean;hasLoadPlan:boolean}){
 const router=useRouter(),initialKey=keyOf(initialType,initialSubtype),[editing,setEditing]=useState(false),[draft,setDraft]=useState<Draft>({aircraftKey:initialKey,configuration:initialConfiguration??""}),[notice,setNotice]=useState<{ok:boolean;text:string}|null>(null),[pending,start]=useTransition(),selected=options.find(option=>keyOf(option.typeCode,option.subtype)===draft.aircraftKey)??options[0]??null,editable=canOperate&&!archived&&!hasLoadPlan;
 const begin=()=>{setDraft({aircraftKey:initialKey,configuration:initialConfiguration??""});setNotice(null);setEditing(true)};
 const changeAircraft=(aircraftKey:string)=>{const option=options.find(row=>keyOf(row.typeCode,row.subtype)===aircraftKey),configuration=option?.configurations.find(row=>row.isDefault)?.code??option?.configurations[0]?.code??"";setDraft({aircraftKey,configuration})};
 const save=()=>{if(!selected)return;start(async()=>{const result=await saveOperationalFlightEquipment(iata,flightId,version,{aircraftType:selected.typeCode,aircraftSubtype:selected.subtype,aircraftConfiguration:draft.configuration||null});if(!result.ok||!result.equipment){setNotice({ok:false,text:result.message});return}setEditing(false);setNotice({ok:true,text:result.message});router.refresh()})};
 return <section className="operational-equipment-control">
  <div className="operational-equipment-heading"><div><p className="eyebrow">OPERATIONAL EQUIPMENT</p><h3>{initialType}-{initialSubtype} · {initialConfiguration?`CONFIG ${initialConfiguration}`:"NO CABIN CONFIGURATION"}</h3><p>Published schedule: {publishedType}{publishedSubtype?`-${publishedSubtype}`:""} · {publishedConfiguration?`CONFIG ${publishedConfiguration}`:"configuration not supplied"}</p></div>{editable&&!editing&&<button className="secondary" type="button" onClick={begin}>CHANGE AIRCRAFT / CONFIG</button>}</div>
  {editing&&selected&&<div className="operational-equipment-form">
   <label>AIRCRAFT TYPE / SUB-SERIES<select value={draft.aircraftKey} onChange={event=>changeAircraft(event.target.value)}>{options.map(option=><option value={keyOf(option.typeCode,option.subtype)} key={keyOf(option.typeCode,option.subtype)}>{option.typeCode}-{option.subtype} · {option.name}</option>)}</select></label>
   <label>CABIN CONFIGURATION<select value={draft.configuration} disabled={selected.configurations.length===0} onChange={event=>setDraft(current=>({...current,configuration:event.target.value}))}>{selected.configurations.length===0?<option value="">NOT CONFIGURED ON D9</option>:selected.configurations.map(configuration=><option value={configuration.code} key={configuration.code}>CONFIG {configuration.code}{configuration.description?` · ${configuration.description}`:""}</option>)}</select></label>
   <button className="secondary" type="button" disabled={pending} onClick={()=>{setEditing(false);setNotice(null)}}>CANCEL</button><button type="button" disabled={pending||selected.configurations.length>0&&!draft.configuration} onClick={save}>{pending?"SAVING…":"SAVE CHANGES"}</button>
  </div>}
  {hasLoadPlan&&<small className="operational-equipment-readonly">The aircraft type and configuration are locked after the first load-plan edition is saved.</small>}
  {archived&&<small className="operational-equipment-readonly">This archived flight is read-only.</small>}
  {notice&&<p className={`load-control-notice ${notice.ok?"success":"error"}`} role="status">{notice.text}</p>}
 </section>;
}
