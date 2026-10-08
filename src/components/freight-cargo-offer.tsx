"use client";
import{useState,useTransition}from"react";
import{saveOperationalFreightPlanning}from"@/app/load-control-actions";
import{cargoOfferLimitingLabel}from"@/domain/freight-acceptance";
import type{OperationalFreightPlanning}from"@/ports/operational-flight-repository";

const kg=(value:number|null|undefined)=>value===null||value===undefined?"—":`${Math.round(value).toLocaleString()} KG`;
const number=(value:number|null|undefined,places=1)=>value===null||value===undefined?"—":value.toLocaleString(undefined,{minimumFractionDigits:places,maximumFractionDigits:places});
const volume=(value:number)=>value.toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2});
const bulkDetail=(volumeValue:number,density:number|null,planningWeight:number)=>{const densityWeight=Math.round(volumeValue*Number(density??0)),formula=`${volume(volumeValue)} × B1 cargo density ${number(density,0)} = ${kg(densityWeight)}`;return densityWeight>planningWeight?`${formula} · limited to ${kg(planningWeight)} by the hold maximum`:formula};
type Draft={weightBasis:"FLEET_WEIGHT"|"REGISTRATION";registration:string;crewCode:string;pantryCode:string};
const draftOf=(p:OperationalFreightPlanning):Draft=>({weightBasis:p.weightBasis,registration:p.registration??"",crewCode:p.crewCode??"",pantryCode:p.pantryCode??""});

export function FreightCargoOffer({iata,flightId,initial}:{iata:string;flightId:string;initial:OperationalFreightPlanning}){
 const[saved,setSaved]=useState(initial),[draft,setDraft]=useState(()=>draftOf(initial)),[editing,setEditing]=useState(false),[notice,setNotice]=useState<{ok:boolean;text:string}|null>(null),[pending,start]=useTransition();
 if(!saved.applicable)return null;
 const save=()=>start(async()=>{const result=await saveOperationalFreightPlanning(iata,flightId,saved.version,{...draft,registration:draft.weightBasis==="REGISTRATION"?draft.registration:null});if(!result.ok||!result.planning){setNotice({ok:false,text:result.message});return}setSaved(result.planning);setDraft(draftOf(result.planning));setEditing(false);setNotice({ok:true,text:result.message})});
 return <div className="freight-planning-stack">
  <details className="freight-planning operational-collapsible">
   <summary className="operational-collapsible-summary">
    <div><p className="eyebrow">FREIGHT LOAD PLANNING</p><h2>Aircraft and operating codes</h2><p>Aircraft weight basis and the flight's applicable crew and pantry codes.</p></div>
    <div className="operational-summary-facts">
     <span><small>WEIGHT BASIS</small><strong>{saved.weightBasis==="FLEET_WEIGHT"?"FLEET WEIGHT":saved.registration}</strong></span>
     <span><small>CREW CODE</small><strong>{saved.crewCode??"—"}</strong></span>
     <span><small>PANTRY CODE</small><strong>{saved.pantryCode??"—"}</strong></span>
    </div>
   </summary>
   <div className="operational-collapsible-body">
    <div className="freight-planning-heading"><p>Use Fleet Weight until the operating registration is known. Crew and pantry begin with the schedule values and may be changed for this flight.</p>{saved.canEdit&&!editing&&<button className="secondary" onClick={()=>{setDraft(draftOf(saved));setEditing(true);setNotice(null)}}>EDIT</button>}</div>
    {editing?<div className="freight-planning-form">
     <label>Aircraft weight basis<select value={draft.weightBasis==="FLEET_WEIGHT"?"FLEET_WEIGHT":draft.registration} onChange={event=>{const value=event.target.value;setDraft(current=>value==="FLEET_WEIGHT"?{...current,weightBasis:"FLEET_WEIGHT",registration:""}:{...current,weightBasis:"REGISTRATION",registration:value})}}><option value="FLEET_WEIGHT">FLEET WEIGHT · {kg(saved.fleetWeight)}</option>{saved.registrationOptions.map(row=><option value={row.registration} key={row.registration}>{row.registration} · {kg(row.weight)}</option>)}</select></label>
     <label>Crew code<select value={draft.crewCode} onChange={event=>setDraft(current=>({...current,crewCode:event.target.value}))}><option value="">Select crew code</option>{saved.crewOptions.map(row=><option value={row.code} key={row.code}>{row.code}{row.isBase?" · BASE":""}</option>)}</select></label>
     <label>Pantry code<select value={draft.pantryCode} onChange={event=>setDraft(current=>({...current,pantryCode:event.target.value}))}><option value="">Select pantry code</option>{saved.pantryOptions.map(row=><option value={row.code} key={row.code}>{row.code}{row.isBase?" · BASE":""}</option>)}</select></label>
     <div className="freight-planning-actions"><button className="secondary" disabled={pending} onClick={()=>{setDraft(draftOf(saved));setEditing(false);setNotice(null)}}>CANCEL</button><button disabled={pending||!draft.crewCode||!draft.pantryCode||(draft.weightBasis==="REGISTRATION"&&!draft.registration)} onClick={save}>{pending?"SAVING…":"SAVE"}</button></div>
    </div>:<div className="freight-basis-summary">
     <div><small>WEIGHT BASIS</small><strong>{saved.weightBasis==="FLEET_WEIGHT"?"FLEET WEIGHT":saved.registration}</strong><span>{kg(saved.planningAircraftWeight)}</span></div>
     <div><small>CREW CODE</small><strong>{saved.crewCode??"—"}</strong><span>{saved.crewWeightAdjustment?`${saved.crewWeightAdjustment>0?"+":""}${kg(saved.crewWeightAdjustment)}`:"BASE"}</span></div>
     <div><small>PANTRY CODE</small><strong>{saved.pantryCode??"—"}</strong><span>{saved.pantryWeightAdjustment?`${saved.pantryWeightAdjustment>0?"+":""}${kg(saved.pantryWeightAdjustment)}`:"BASE"}</span></div>
    </div>}
    {notice&&<p className={notice.ok?"load-control-notice success":"load-control-notice error"}>{notice.text}</p>}
   </div>
  </details>
  <details className="cargo-offer-section operational-collapsible">
   <summary className="cargo-offer-heading">
    <div><p className="eyebrow">PLANNING CAPACITY</p><h2>Cargo Offer</h2><p>Gross capacity available for cargo, mail and special loads before fuel restrictions are known.</p></div>
    <div className={saved.ready?"cargo-offer-total ready":"cargo-offer-total incomplete"}><small>CARGO OFFER</small><strong>{saved.ready?kg(saved.cargoOfferWeight):"INCOMPLETE"}</strong><span>{saved.ready?cargoOfferLimitingLabel(saved.limitingFactor):"Complete the missing aircraft data"}</span></div>
   </summary>
   <div className="operational-collapsible-body">
    <div className="cargo-offer-capacity"><div><small>MZFW</small><strong>{kg(saved.mzfw)}</strong></div><div><small>PLANNING AIRCRAFT WEIGHT</small><strong>{kg(saved.planningAircraftWeight)}</strong></div><div><small>STRUCTURAL PAYLOAD CAPACITY</small><strong>{kg(saved.structuralCapacity)}</strong></div><div><small>SPACE WEIGHT CAPACITY</small><strong>{kg(saved.spaceWeightCapacity)}</strong></div></div>
    <div className="cargo-space-list">{saved.uldPositionGroups.map(row=><article key={`${row.deck}-${row.uldType}-${row.uldCode}`}><small>{row.deck==="MDECK"?"MAIN DECK":"LOWER DECK"}</small><strong>{row.positionCount} × {row.uldType}</strong><span>{row.uldCode?`Default ULD ${row.uldCode} · `:""}{kg(row.maximumWeight)} position capacity</span></article>)}{saved.bulkHolds.map(row=><article key={row.holdId}><small>BULK HOLD {row.name}</small><strong>{volume(row.volume)} m³ · {kg(row.planningWeight)}</strong><span>{bulkDetail(row.volume,saved.cargoPlanningDensity,row.planningWeight)}</span></article>)}</div>
    <p className="cargo-offer-note">ULD bays use position count and permitted gross weight only. Volume applies only to Bulk holds. B1 supplies the cargo planning density.</p>
    {saved.missing.length>0&&<p className="field-error">Missing: {saved.missing.map(item=>item.replaceAll("_"," ")).join(", ")}.</p>}
   </div>
  </details>
 </div>
}
