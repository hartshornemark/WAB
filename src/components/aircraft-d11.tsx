"use client";
import{holdDisplayName}from"@/domain/aircraft-d2";import {useSaveFeedback,SaveScope,SaveInput,SaveButton,SaveCancel,SaveSubmit} from "@/components/save-feedback";
import { useState } from "react";
import { saveAircraftD11, setAircraftD11FloorActive } from "@/app/aircraft-d11-actions";
import { ConfigurationStatusBadge } from "@/components/configuration-status-badge";
import { SectionHeader } from "@/components/section-header";
import { aircraftD11Status, d11FloorStatus } from "@/domain/aircraft-d11-status";
import type { AircraftD11Snapshot, D11FloorLimit } from "@/domain/aircraft-d11";

const shown=(value:number|null)=>value===null?"—":value.toFixed(2);
const numeric=(value:string)=>value.trim()===""?null:Number(value);

export function AircraftD11({iata,initial}:{iata:string;initial:AircraftD11Snapshot}) {
  const [saved,setSaved]=useState(initial);
  return <section className="aircraft-d11">
    <SectionHeader id="aircraft-d11-heading" title="D11. STRUCTURAL LIMITATIONS II" reference="(AHM565 Sheet D11)">
      <ConfigurationStatusBadge status={aircraftD11Status(saved)} variant="large"/>
    </SectionHeader>
    <p className="c5-intro">Each section is independently applicable. Only selected sections contribute to completion.</p>
    {!saved.applicabilityReviewed&&!saved.floorActive&&<D11ReviewPrompt iata={iata} saved={saved} setSaved={setSaved}/>}
    <UnsupportedSection title="1. COMBINED LOAD LIMITS" description="Provisioned for future support." columns={["Hold / Compartment","Combined Load Group","Maximum Combined Load"]}/>
    <FloorSection iata={iata} saved={saved} setSaved={setSaved}/>
    <UnsupportedSection title="3. ASYMMETRICAL LOAD LIMITS" description="Provisioned for future support." columns={["Hold / Compartment","Asymmetrical Condition","Maximum Permitted Load"]}/>
  </section>;
}

function D11ReviewPrompt({iata,saved,setSaved}:{iata:string;saved:AircraftD11Snapshot;setSaved:(value:AircraftD11Snapshot)=>void}) {
  const [error,setError]=useState("");
  const [pending,start,saveFeedback]=useSaveFeedback();
  const confirm=()=>start(async()=>{
    const result=await setAircraftD11FloorActive(iata,saved.typeCode,saved.subtype,saved.revision,false);
    if(!result.ok){setError(result.error);return}
    setError("");
    saveFeedback.complete(()=>setSaved(result.snapshot));
  });
  return <SaveScope feedback={saveFeedback}>{<section className="d11-review-prompt">
    <div><strong>No D11 section is selected.</strong><p>Save this review if D11 is not required for this aircraft, or select Floor Loading Limits below.</p></div>
    <SaveSubmit disabled={!saved.canEdit||pending} onClick={confirm}/>
    {error&&<p className="field-error" role="alert">{error}</p>}
  </section>}</SaveScope>;
}

function FloorSection({iata,saved,setSaved}:{iata:string;saved:AircraftD11Snapshot;setSaved:(value:AircraftD11Snapshot)=>void}) {
  const [open,setOpen]=useState(false);
  const [draft,setDraft]=useState(saved.floorLimits);
  const [editing,setEditing]=useState(false);
  const [error,setError]=useState("");
  const [message,setMessage]=useState("");
  const [pending,start,saveFeedback]=useSaveFeedback();
  const status=d11FloorStatus(saved);
  const begin=()=>{setDraft(saved.floorLimits.map(row=>({...row})));setEditing(true);setOpen(true);setError("");setMessage("")};
  const save=()=>start(async()=>{
    const result=await saveAircraftD11(iata,saved.typeCode,saved.subtype,saved.revision,draft);
    if(!result.ok){setError(result.error);return}
    setError("");setSaved(result.snapshot);saveFeedback.complete(()=>{setEditing(false);setMessage("SAVED");});
  });
  const toggle=(applicable:boolean)=>start(async()=>{
    setError("");setMessage("");
    const result=await setAircraftD11FloorActive(iata,saved.typeCode,saved.subtype,saved.revision,applicable);
    if(!result.ok){setError(result.error);return}
    setSaved(result.snapshot);setOpen(applicable);
  });
  return <SaveScope feedback={saveFeedback}>{<section className={`d11-card ${saved.floorActive?"":"d11-inactive"}`}>
    <div className="d4-heading">
      <label className="d6-applicability">
        <SaveInput type="checkbox" checked={saved.floorActive} disabled={!saved.canEdit||pending||editing} onChange={event=>toggle(event.target.checked)}/>
        <span><h3>2. FLOOR LOADING LIMITS</h3><p>{saved.floorActive?"One completed row is required for every hold identified in D2.":"Check this section to activate and configure it."}</p></span>
      </label>
      <div className="c5-heading-actions">
        {saved.floorActive&&<SaveButton type="button" className="secondary" aria-expanded={open} onClick={()=>setOpen(!open)}>{open?"CLOSE":"OPEN"}</SaveButton>}
        {message&&<span className="form-success c5-inline-success">{message}</span>}
        {saved.canEdit&&saved.floorActive&&!editing&&<SaveButton className="secondary" onClick={begin}>EDIT</SaveButton>}
        <ConfigurationStatusBadge status={status}/>
      </div>
    </div>
    {saved.floorActive&&open&&<>
      <FloorRows rows={editing?draft:saved.floorLimits} editing={editing} change={(index,value)=>setDraft(rows=>rows.map((row,rowIndex)=>rowIndex===index?{...row,floorLoadingLimit:value}:row))}/>
      {!saved.floorLimits.length&&!editing&&<p className="d2-empty">No D2 holds are available.</p>}
      {error&&<p className="field-error" role="alert">{error}</p>}
      {editing&&<div className="d8-actions"><SaveCancel className="secondary" disabled={pending} onClick={()=>{setEditing(false);setError("")}}>CANCEL</SaveCancel><SaveSubmit disabled={pending} onClick={save}>{pending?"Saving…":"SAVE"}</SaveSubmit></div>}
    </>}
    {!open&&error&&<p className="field-error" role="alert">{error}</p>}
  </section>}</SaveScope>;
}

function UnsupportedSection({title,description,columns}:{title:string;description:string;columns:string[]}) {
  const [open,setOpen]=useState(false);
  return <section className="d11-card d11-unsupported">
    <div className="d4-heading">
      <label className="d6-applicability">
        <SaveInput type="checkbox" checked={false} disabled aria-label={`${title} unsupported`}/>
        <span><h3>{title}</h3><p>{description} Selection is disabled until the section is supported.</p></span>
      </label>
      <div className="c5-heading-actions"><SaveButton type="button" className="secondary" aria-expanded={open} onClick={()=>setOpen(!open)}>{open?"CLOSE":"OPEN"}</SaveButton><ConfigurationStatusBadge status="unsupported"/></div>
    </div>
    {open&&<div className="d11-disabled-table"><div>{columns.map(column=><strong key={column}>{column}</strong>)}</div><p>This section is disabled until support is introduced.</p></div>}
  </section>;
}

function FloorRows({rows,editing,change}:{rows:D11FloorLimit[];editing:boolean;change:(index:number,value:number|null)=>void}) {
  return <div className="d11-table"><div className="d11-row d11-head"><span>Hold / Compartment</span><span>Hold Type</span><span>Deck</span><span>Floor Loading Limit (Kg/m²)</span></div>{rows.map((row,index)=><div className="d11-row" key={row.holdId}><strong>{holdDisplayName(row.holdId)}</strong><span>{row.holdType}</span><span>{row.deckName}</span>{editing?<SaveInput aria-label={`Floor Loading Limit in Kg per square metre for hold ${row.holdId}`} inputMode="decimal" value={row.floorLoadingLimit??""} onChange={event=>change(index,numeric(event.target.value))}/>:<span>{shown(row.floorLoadingLimit)}</span>}</div>)}</div>;
}
