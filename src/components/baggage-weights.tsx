"use client";
import Link from "next/link";
import { useState,useTransition } from "react";
import { useRouter } from "next/navigation";
import { SectionHeader } from "@/components/section-header";
import { ConfigurationStatusBadge } from "@/components/configuration-status-badge";
import { PageHelp } from "@/components/page-help";
import { saveBaggage,saveBaggageOperationMode,saveBaggageVariationStandard } from "@/app/baggage-actions";
import { categories,defaultPlanningRecord,newBaggageRecord,pieceFields,validateBaggage,type BaggageRecord,type BaggageSection,type BaggageSnapshot } from "@/domain/baggage-weights";
import { b4Statuses } from "@/domain/b4-status";
import {displayUnit} from "@/domain/display-standards";
const pieceLabels={male:"Adult Male",female:"Adult Female",child:"Child",all:"All Passengers (optional)",summer:"Summer (optional)",winter:"Winter (optional)"};
export function BaggageWeights({iata,initial,passengerOperations}:{iata:string;initial:BaggageSnapshot;passengerOperations:boolean}){
 const [saved,setSaved]=useState(initial);
 const weightUnit=displayUnit(saved.unit);
 const volumeUnit=saved.volumeUnit==="m3"?"m³":saved.volumeUnit==="ft3"?"ft³":saved.volumeUnit;
 const router=useRouter();const [editing,setEditing]=useState<{section:BaggageSection;row:BaggageRecord}|null>(null);
 const [openVariation,setOpenVariation]=useState<string|null>(null);
 const [error,setError]=useState("");const [message,setMessage]=useState("");const [pending,startTransition]=useTransition();
 const completion=b4Statuses(saved);const suggestedPlanning=defaultPlanningRecord(saved);
 function begin(section:BaggageSection,row?:BaggageRecord){setEditing({section,row:row?structuredClone(row):newBaggageRecord(section)});setError("");setMessage("");}
 function beginVariation(code:string){const row=newBaggageRecord("weights");row.values.variation=code;setOpenVariation(code);begin("weights",row);}
 function change(key:string,value:string){setEditing(e=>{
 if(!e)return e;const values={...e.row.values,[key]:value};
 if(e.section==="weights"){
  if(key==="passengerMethod"&&value==="UNSET")values.passenger="";
  if(!values.classCode&&!values.variation){values.pieceMethod="INHERIT";values.piece="";}
 }
 return {...e,row:{...e.row,values}};
 });}
 function chooseOperationMode(mode:"STANDARD"|"ACTUAL"){setError("");setMessage("");startTransition(async()=>{const result=await saveBaggageOperationMode(iata,saved.revision,mode);if(!result.ok){setError(result.error);return;}setSaved(result.snapshot);setEditing(null);setOpenVariation(null);setMessage(`${mode==="STANDARD"?"Standard":"Actual"} Baggage Weight Operations selected.`);router.refresh();});}
 function selectStandardForVariation(code:string){setError("");setMessage("");startTransition(async()=>{const result=await saveBaggageVariationStandard(iata,saved.revision,code);if(!result.ok){setError(result.error);return;}setSaved(result.snapshot);setMessage(`${code} will use the Standard Baggage Weights.`);router.refresh();});}
 function save(remove=false){if(!editing)return;const {section,row}=editing;setError("");
  try{if(!remove)validateBaggage(section,row,saved);}catch(e){setError(e instanceof Error?e.message:"Check your entries.");return;}
  startTransition(async()=>{try{const result=await saveBaggage(iata,saved.revision,section,row,remove);if(!result.ok){setError(result.error);return;}setSaved(result.snapshot);setEditing(null);setMessage(remove?"Record removed.":section==="planning"?"Planning assumptions reviewed and saved.":"Changes saved.");router.refresh();}catch{setError("Unable to save. Your entries are still here; please try again.");}});
 }
 function field(row:BaggageRecord,key:string,label:string,active:boolean,options?:{value:string;label:string}[],disabled=false,decimal=false){
  const id=`b4-${editing?.section??"view"}-${row.id??"new"}-${key}`;
  return <div key={key}><label htmlFor={active?id:undefined}>{label}</label>{active?options?<select id={id} value={row.values[key]} disabled={disabled} onChange={e=>change(key,e.target.value)}>{options.map(o=><option key={o.value} value={o.value}>{o.label}</option>)}</select>:<input id={id} type="number" inputMode={decimal?"decimal":"numeric"} min="0" max={decimal?"99999999.9999":"2147483647"} step={decimal?"0.0001":"1"} value={row.values[key]} disabled={disabled} onChange={e=>change(key,e.target.value)}/>:<p className="passenger-value">{options?options.find(o=>o.value===row.values[key])?.label??"Not specified":disabled?"Inactive":row.values[key]||"Not specified"}</p>}</div>;
 }
 const method=[{value:"STANDARD",label:"Standard Weight"},{value:"ACTUAL",label:"Actual Weight"}];
 function card(section:BaggageSection,source:BaggageRecord,title:string){
  const active=editing?.section===section&&editing.row.id===source.id;
  const row=active?editing.row:source;
  const global=row.values.classCode===""&&row.values.variation==="";
  return <article className="baggage-card" key={source.id??"new"}>
   <div className="details-heading"><h4>{title}</h4>{!editing&&saved.canEdit&&saved.unit&&<button type="button" className="secondary" onClick={()=>begin(section,source)}>{section==="planning"&&source.id===null?"REVIEW":"EDIT"}</button>}</div>
   <form noValidate onSubmit={e=>{e.preventDefault();save();}}><fieldset disabled={pending}><legend className="sr-only">{title}</legend>
   {section!=="defaults"&&<div className="passenger-weight-grid">
    {field(row,"variation","Flight Variation",active,[{value:"",label:"Standard Flights"},...saved.variations.map(v=>({value:v.code,label:`${v.code} — ${v.description}`}))],row.baseline)}
    {field(row,"classCode","Class",active,[{value:"",label:"All Classes"},...saved.classes.map(c=>({value:c.code,label:`${c.code} — ${c.description}`}))],row.baseline)}
    {section==="weights"&&field(row,"category","Passenger Category",active,categories.map(c=>({value:c,label:c==="ALL"?"All Passengers":c[0]+c.slice(1).toLowerCase()})),row.baseline)}
   </div>}
   {section==="defaults"?<>
    {field(row,"method","Weight per Piece Method",active,method)}
    <div className="passenger-weight-grid">{pieceFields.map(k=>field(row,k,`${pieceLabels[k]} (${weightUnit})`,active,undefined,row.values.method==="ACTUAL"))}</div>
    <p className="muted">These are Weights per Piece. Standard values are retained when Actual Weight is selected. Seasonal values are optional and are not selected automatically.</p>
   </>:section==="weights"?<>
    <div className="passenger-weight-grid">
     {field(row,"pieceMethod","Weight per Piece Method",active,[{value:"INHERIT",label:"Use Default per Piece"},...method],global)}
     {field(row,"piece",`Weight per Piece (${weightUnit})`,active,undefined,row.values.pieceMethod!=="STANDARD")}
    </div>
    <div className="passenger-weight-grid">
     {field(row,"passengerMethod","Weight per Passenger Method",active,[...(row.baseline?[{value:"UNSET",label:"Not Yet Configured"}]:[]),...method])}
     {field(row,"passenger",`Weight per Passenger (${weightUnit})`,active,undefined,row.values.passengerMethod!=="STANDARD")}
    </div>
    {active&&row.baseline&&<p className="muted">All Flights / All Classes is the fixed default record. Administrators may change its weight values, but cannot rename or remove this record.</p>}
    {active&&row.values.passengerMethod==="UNSET"&&<p className="muted">The default Weight per Passenger has not yet been configured. This does not mean zero.</p>}
    {active&&<p className="muted">Actual Weight requires measured baggage weights. Inactive standard values are retained. Flight Variations are selected explicitly; overlapping labels do not select a weight set automatically.</p>}
   </>:<div className="passenger-weight-grid">
    {field(row,"bags","Average Bags per Passenger",active,undefined,false,true)}
    {field(row,"weight",`Average Bag Weight per Passenger (${weightUnit})`,active,undefined,false,true)}
    {field(row,"volume",`Average Bag Volume (${volumeUnit||"Volume Unit not set"}; optional)`,active,undefined,false,true)}
   </div>}
   {active&&section==="planning"&&<p className="b4-note">If Average Bag Volume is blank, the Bag Density provided in <Link href={`/carrier/${encodeURIComponent(iata)}?sheet=B1`}><strong>1. STANDARD UNITS AND CODES</strong></Link> will be utilised.</p>}
   <label htmlFor={active?`remarks-${section}-${row.id??"new"}`:undefined}>Remarks</label>{active?<textarea id={`remarks-${section}-${row.id??"new"}`} rows={2} maxLength={2000} value={row.values.remarks} onChange={e=>change("remarks",e.target.value)}/>:<p className="passenger-remarks">{row.values.remarks}</p>}
   {active&&<>{error&&<p role="alert" className="field-error">{error}</p>}<div className="logo-actions"><button type="submit">{pending?"Saving…":section==="planning"&&row.id===null?"SAVE REVIEW":"SAVE"}</button><button type="button" className="secondary" onClick={()=>{setEditing(null);setError("");}}>CANCEL</button>{row.id&&!row.baseline&&section!=="defaults"&&<button type="button" className="secondary" onClick={()=>{if(window.confirm("Remove this saved record?"))save(true);}}>REMOVE</button>}</div></>}
   </fieldset></form>
  </article>;
 }
 if(!saved.canView)return <section className="overview"><SectionHeader id="baggage-title" title="4. BAGGAGE WEIGHTS AND PLANNING" reference="(AHM565 Sheet B4)"/><p>These settings are not available for your account.</p></section>;
 if(!passengerOperations)return <section className="overview carrier-details passenger-weights baggage-weights"><SectionHeader id="baggage-title" title="4. BAGGAGE WEIGHTS AND PLANNING" reference="(AHM565 Sheet B4)"><ConfigurationStatusBadge status="not_required" variant="large"/></SectionHeader><p>This carrier currently operates only Freighter aircraft. Passenger baggage weights and planning assumptions are not required; any existing data is retained.</p></section>;
 return <section className="overview carrier-details passenger-weights baggage-weights">
  <SectionHeader id="baggage-title" title="4. BAGGAGE WEIGHTS AND PLANNING" reference="(AHM565 Sheet B4)"><div className="page-heading-actions"><PageHelp title="B4. Baggage Weights and Planning">
   <section><h3>Purpose</h3><p>Use this Page to define the baggage weights and any planning assumptions used by the carrier.</p></section>
   <section><h3>Before you begin</h3><p>Complete the applicable Units, Baggage Density and Class Codes on Page B1. Any Flight Variations created on B3 will also require a decision on this page.</p></section>
   <section><h3>What to complete</h3><ul><li>Choose Standard or Actual Baggage Weight Operations.</li><li>For Standard operations, complete All Other Flights and resolve every Page B3 Flight Variation.</li><li>For both methods, review and save the Baggage Planning Assumptions.</li></ul></section>
   <section><h3>Completion</h3><p>For Standard operations, B4 is Configured when All Other Flights is complete, every Flight Variation is resolved, and Planning Assumptions are Reviewed and Saved. For Actual operations, only Planning Assumptions are required.</p></section>
  </PageHelp><ConfigurationStatusBadge status={completion.page} variant="large"/></div></SectionHeader>
  <p>{saved.unit?`All weights are in ${weightUnit}, as selected on Sheet B1.`:"Save a Weight Unit on Sheet B1 before entering baggage weights."} {saved.volumeUnit?`Planning volumes are in ${volumeUnit}.`:"Save a Volume Unit on Sheet B1 before entering volume."}</p>
  {!saved.canEdit&&<p className="muted">These settings are read-only for your account.</p>}
  <p role="status" aria-live="polite">{message}</p>
  {error&&!editing&&<p className="field-error" role="alert">{error}</p>}
  <section className="commodity-section b4-operation-section"><div className="details-heading"><div><h3>BAGGAGE WEIGHT OPERATIONS</h3><p>Select the method used by this carrier.</p></div></div>
   <fieldset className="b4-operation-options" disabled={pending||!!editing||!saved.canEdit}><legend className="sr-only">Baggage Weight Operations</legend>
    <label className={saved.operationMode==="STANDARD"?"selected":""}><input type="radio" name="baggage-operation-mode" checked={saved.operationMode==="STANDARD"} onChange={()=>chooseOperationMode("STANDARD")}/><span><strong>STANDARD BAGGAGE WEIGHT OPERATIONS</strong><small>Complete All Other Flights, resolve every Flight Variation, and complete Baggage Planning Assumptions.</small></span></label>
    <label className={saved.operationMode==="ACTUAL"?"selected":""}><input type="radio" name="baggage-operation-mode" checked={saved.operationMode==="ACTUAL"} onChange={()=>chooseOperationMode("ACTUAL")}/><span><strong>ACTUAL BAGGAGE WEIGHT OPERATIONS</strong><small>Actual baggage weights are used. Complete Baggage Planning Assumptions only.</small></span></label>
   </fieldset>
  </section>
  {saved.operationMode==="STANDARD"&&<section className="commodity-section"><div className="details-heading"><div><h3>STANDARD BAGGAGE WEIGHT TABLES</h3><p>Complete All Other Flights and resolve each Flight Variation.</p></div><ConfigurationStatusBadge status={completion.defaults==="configured"&&completion.passenger==="configured"?"configured":completion.defaults==="incomplete"&&completion.passenger==="incomplete"?"incomplete":"partial"}/></div>
   <div className="b4-table-accordion" aria-label="Standard Baggage Weight Tables">
    <section className={`b4-table-panel${openVariation==="__STANDARD__"?" open":""}`}>
     <div className="b4-table-panel-heading"><div><strong>ALL OTHER FLIGHTS</strong><span>Standard baggage weights used except where a named Flight Variation has a separate table.</span></div><button type="button" className="passenger-table-selector" disabled={!!editing} aria-expanded={openVariation==="__STANDARD__"} onClick={()=>setOpenVariation(current=>current==="__STANDARD__"?null:"__STANDARD__")}>{openVariation==="__STANDARD__"?"CLOSE TABLE":"OPEN TABLE"}</button></div>
     {openVariation==="__STANDARD__"&&<div className="b4-table-panel-content">
      {card("defaults",saved.defaults??newBaggageRecord("defaults"),"All Other Flights — Weight per Piece")}
      {saved.weights.filter(row=>!row.values.variation).map(row=>card("weights",row,row.baseline?"All Other Flights — All Classes / All Passengers":`${row.values.classCode||"All Classes"} — ${row.values.category}`))}
      {editing?.section==="weights"&&editing.row.id===null&&!editing.row.values.variation&&card("weights",editing.row,"New All Other Flights Baggage Weight Record")}
      {!editing&&saved.canEdit&&saved.unit&&<button className="secondary" onClick={()=>begin("weights")}>ADD BAGGAGE WEIGHT RECORD</button>}
     </div>}
    </section>
    {saved.variations.map(variation=>{
     const specific=saved.weights.filter(row=>!row.baseline&&row.values.variation===variation.code),usesStandard=saved.standardVariations.includes(variation.code),open=openVariation===variation.code;
     return <section className={`b4-table-panel${open?" open":""}`} key={variation.code}><div className="b4-table-panel-heading"><div><strong>{variation.code} — {variation.description}</strong><span>{specific.length?`${specific.length} variation-specific Baggage Weight record${specific.length===1?"":"s"}`:usesStandard?"Uses All Other Flights Standard Baggage Weights":"Review required"}</span></div><button type="button" className="passenger-table-selector" disabled={!!editing} aria-expanded={open} onClick={()=>setOpenVariation(current=>current===variation.code?null:variation.code)}>{open?"CLOSE TABLE":specific.length?"OPEN TABLE":"REVIEW"}</button></div>
      {open&&<div className="b4-table-panel-content">{specific.map(row=>card("weights",row,`${row.values.classCode||"All Classes"} — ${row.values.category}`))}{editing?.section==="weights"&&editing.row.id===null&&editing.row.values.variation===variation.code&&card("weights",editing.row,`New ${variation.code} Baggage Weight Record`)}{!editing&&specific.length===0&&<div className="b4-variation-decision"><p>{usesStandard?`${variation.code} currently uses the All Other Flights Standard Baggage Weights.`:`Choose how Baggage Weights apply to ${variation.code}.`}</p><div className="logo-actions"><button type="button" className="secondary" onClick={()=>beginVariation(variation.code)}>CREATE SEPARATE TABLE</button>{!usesStandard&&<button type="button" onClick={()=>selectStandardForVariation(variation.code)} disabled={pending}>USE ALL OTHER FLIGHTS WEIGHTS</button>}</div></div>}{!editing&&specific.length>0&&saved.canEdit&&<button type="button" className="secondary" onClick={()=>beginVariation(variation.code)}>ADD ANOTHER {variation.code} RECORD</button>}</div>}
     </section>;
    })}
   </div>
  </section>}
  <section className="commodity-section"><div className="details-heading"><h3>BAGGAGE PLANNING ASSUMPTIONS</h3><ConfigurationStatusBadge status={completion.planning}/></div>
   <p>Set planning averages for All Flights or an adopted Flight Variation, for All Classes or a selected Class. You may use up to four decimal places.</p>
   {!saved.planning.length?<p className="b4-review-notice"><strong>REVIEW REQUIRED</strong><span>The values below are suggested defaults and have not been saved. Select REVIEW, check the values, then select SAVE REVIEW.</span></p>:<p className="b4-note">The saved assumptions below determine the planning values used by B4.</p>}
   {saved.planning.map(r=>card("planning",r,`${r.values.variation||"All Flights"} — ${r.values.classCode||"All Classes"}`))}
   {!saved.planning.length&&!editing&&card("planning",suggestedPlanning,"SUGGESTED — All Flights / All Classes")}
   {editing?.section==="planning"&&editing.row.id===null&&card("planning",editing.row,saved.planning.length?"NEW PLANNING ASSUMPTIONS":"REVIEW — All Flights / All Classes")}
   {!editing&&saved.planning.length>0&&saved.canEdit&&saved.unit&&<button className="secondary" onClick={()=>begin("planning")}>ADD PLANNING ASSUMPTIONS</button>}
  </section>
 </section>;
}
