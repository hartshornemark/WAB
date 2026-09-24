"use client";
import { SectionHeader } from "@/components/section-header";
import { ConfigurationStatusBadge } from "@/components/configuration-status-badge";
import { useState, useTransition } from "react";
import { savePassengerWeights } from "@/app/passenger-actions";
import { passengerDraft, passengerFields, validatePassengerValues, validatePassengerRows, validateVariations, type PassengerDraft, type PassengerRowDraft, type PassengerSection, type PassengerSnapshot } from "@/domain/passenger-weights";
import { b3Statuses } from "@/domain/b3-status";
import {displayUnit} from "@/domain/display-standards";
const labels = { adult:"Adult (optional)", male:"Male", female:"Female", child:"Child", infant:"Infant", handBaggage:"Hand Baggage" };
function WeightFields({value,editing,onChange,prefix,unit,remarks=false}:{value:PassengerDraft;editing:boolean;onChange:(v:PassengerDraft)=>void;prefix:string;unit:string;remarks?:boolean}) {
  return <>
    <div className="passenger-weight-grid">{passengerFields.map(key => <div key={key}>
      <label htmlFor={prefix+"-"+key}>{labels[key]} ({unit})</label>
      {editing ? <input id={prefix+"-"+key} type="number" inputMode="numeric" min={key==="infant"||key==="handBaggage"?0:1} step="1" max="2147483647" disabled={key==="handBaggage"&&value.includesHandBaggage} value={value[key]} onChange={e=>onChange({...value,[key]:e.target.value})}/> : <p className="passenger-value">{key==="handBaggage"&&value.includesHandBaggage?"Included":value[key]||"Not specified"}</p>}
    </div>)}</div>
    <label className="crew-checkbox"><input type="checkbox" checked={value.includesHandBaggage} disabled={!editing} onChange={e=>onChange({...value,includesHandBaggage:e.target.checked})}/>Passenger Weights include Hand Baggage</label>
    <p className="muted">{value.includesHandBaggage?"Hand Baggage is included in Passenger Weights. Separate Hand-Baggage values are inactive.":"Enter a separate standard Hand Baggage weight. Infant and Hand Baggage weights may be zero."}</p>
    {remarks && <div><label htmlFor={prefix+"-remarks"}>Remarks</label>{editing ? <textarea id={prefix+"-remarks"} rows={2} maxLength={2000} value={value.remarks} onChange={e=>onChange({...value,remarks:e.target.value})}/> : <p className="passenger-remarks">{value.remarks||"No remarks."}</p>}</div>}
  </>;
}
export function PassengerWeights({iata,initial}:{iata:string;initial:PassengerSnapshot}) {
  const [saved,setSaved]=useState(initial);
  const [editing,setEditing]=useState<PassengerSection|null>(null);
  const [defaults,setDefaults]=useState(()=>passengerDraft(initial.defaultWeights));
  const [rows,setRows]=useState<PassengerRowDraft[]>([]);
  const [variations,setVariations]=useState(initial.variations);
  const [openVariation,setOpenVariation]=useState<string|null>(null);
  const [error,setError]=useState("");
  const [message,setMessage]=useState("");
  const [pending,startTransition]=useTransition();
  function begin(section:PassengerSection) {
    setDefaults(passengerDraft(saved.defaultWeights));
    setRows(saved.rows.map(r=>({...passengerDraft(r),id:r.id,classCode:r.classCode,variation:r.variation})));
    setVariations(saved.variations.map(v=>({...v})));
    setError("");setMessage("");setOpenVariation(null);setEditing(section);
  }
  function controls(section:PassengerSection) {
    return section!=="classes"&&!editing&&saved.canEdit&&(section==="variations"||saved.unit)&&<button type="button" className="secondary" onClick={()=>begin(section)}>EDIT</button>;
  }
  function savedRowDrafts(){return saved.rows.map(r=>({...passengerDraft(r),id:r.id,classCode:r.classCode,variation:r.variation}));}
  function beginTable(scope:string,create=false) {
    const current=savedRowDrafts();
    const variation=scope==="__STANDARD__"?null:scope;
    setDefaults(passengerDraft(saved.defaultWeights));
    setRows(create&&!current.some(row=>row.variation===variation)?[...current,{...passengerDraft(saved.defaultWeights),id:null,classCode:null,variation}]:current);
    setVariations(saved.variations.map(v=>({...v})));
    setError("");setMessage("");setOpenVariation(scope);setEditing("classes");
  }
  function addVariationTable(code:string) {
    beginTable(code,true);
  }
  function persistRows(input:PassengerRowDraft[],success:string,close=false){
    setError("");
    try{validatePassengerRows(input,saved);}catch(cause){setError(cause instanceof Error?cause.message:"Check your entries.");return;}
    startTransition(async()=>{
      try{
        const result=await savePassengerWeights(iata,saved.revision,"classes",input);
        if(result.ok){setSaved(result.snapshot);setEditing(null);if(close)setOpenVariation(null);setMessage(success);}
        else setError(result.error);
      }catch{setError("Unable to save. Your entries are still here; please try again.");}
    });
  }
  function removeTable(scope:string){
    const name=scope==="__STANDARD__"?"Standard Flights class-override table":`${scope} Passenger Weight Table`;
    if(!window.confirm(`Remove the complete ${name}?`))return;
    const variation=scope==="__STANDARD__"?null:scope;
    persistRows(savedRowDrafts().filter(row=>row.variation!==variation),`${name} removed.`,true);
  }
  function save(section:PassengerSection) {
    setError("");
    if(section==="classes"){persistRows(rows,"Passenger Weight Table saved.");return;}
    const input=section==="default"?defaults:variations;
    try { if(section==="default") validatePassengerValues(input); else validateVariations(input); }
    catch(cause) {setError(cause instanceof Error?cause.message:"Check your entries.");return;}
    startTransition(async()=>{
      try {
        const result=await savePassengerWeights(iata,saved.revision,section,input);
        if(result.ok){setSaved(result.snapshot);setEditing(null);setMessage(section==="variations"?"Flight variations saved.": "Passenger weights saved.");}
        else setError(result.error);
      } catch {setError("Unable to save. Your entries are still here; please try again.");}
    });
  }
  function actions(section:PassengerSection) {
    return editing===section&&<>
      {error&&<p role="alert" className="field-error">{error}</p>}
      <div className="logo-actions"><button type="submit">{pending?"Saving…":"Save"}</button><button type="button" className="secondary" onClick={()=>{setEditing(null);setError("");}}>Cancel</button></div>
    </>;
  }
  if(!saved.canView) return <section className="overview"><h2>3. PASSENGER WEIGHTS</h2><p>These settings are not available for your account.</p></section>;
  const allShownRows=editing==="classes"?rows:savedRowDrafts();
  const shownRows=openVariation===null?[]:allShownRows.filter(row=>openVariation==="__STANDARD__"?row.variation===null:row.variation===openVariation);
  const shownVariations=editing==="variations"?variations:saved.variations;
  const completion=b3Statuses(saved);
  function tablePanel(scope:string){
    const active=editing==="classes"&&openVariation===scope;
    const scopeRows=shownRows;
    const variation=scope==="__STANDARD__"?null:scope;
    return <div className="passenger-table-panel-content">
      {scopeRows.map((row,index)=>{const rowIndex=active?rows.indexOf(row):index;return <fieldset className="passenger-set" key={row.id??`${scope}-${rowIndex}`}><legend className="sr-only">Passenger Weight Table row {index+1}</legend>
        <div className="passenger-set-heading">
          <div><label htmlFor={active?`weight-class-${scope}-${index}`:undefined}>Class Scope</label>{active?<select id={`weight-class-${scope}-${index}`} value={row.classCode??""} onChange={e=>setRows(current=>current.map((r,i)=>i===rowIndex?{...r,classCode:e.target.value||null}:r))}><option value="">All Classes</option>{saved.classes.map(c=><option key={c.code} value={c.code}>{c.code} — {c.description}</option>)}</select>:<p>{row.classCode?`${row.classCode} — ${saved.classes.find(c=>c.code===row.classCode)?.description}`:"All Classes"}</p>}</div>
          <div><label>Flight Variation</label><p>{variation?`${variation} — ${saved.variations.find(v=>v.code===variation)?.description}`:"Standard Flights (class override)"}</p></div>
          {active&&<button type="button" className="secondary" aria-label={`Remove table row ${index+1}`} onClick={()=>setRows(current=>current.filter((_,i)=>i!==rowIndex))}>REMOVE ROW</button>}
        </div>
        <WeightFields value={row} editing={active} onChange={value=>setRows(current=>current.map((r,i)=>i===rowIndex?{...r,...value}:r))} prefix={`table-${scope}-${index}`} unit={displayUnit(saved.unit)||"unit not set"} remarks/>
      </fieldset>})}
      {active?<>
        <button type="button" className="secondary" disabled={rows.length>=200} onClick={()=>setRows(current=>[...current,{...passengerDraft(saved.defaultWeights),id:null,classCode:null,variation}])}>{variation?"ADD CLASS ROW":"ADD CLASS OVERRIDE"}</button>
        <p className="muted">New rows begin with the Standard values. Changes and removals take effect only when you save.</p>
        {actions("classes")}
      </>:scopeRows.length>0&&saved.canEdit&&<div className="logo-actions passenger-table-actions"><button type="button" className="secondary" onClick={()=>beginTable(scope)}>EDIT TABLE</button><button type="button" className="secondary" onClick={()=>removeTable(scope)} disabled={pending}>REMOVE TABLE</button></div>}
    </div>;
  }
  return <section className="overview carrier-details passenger-weights" aria-labelledby="passenger-title">
    <SectionHeader id="passenger-title" title="3. PASSENGER WEIGHTS" reference="(AHM565 Sheet B3)"><ConfigurationStatusBadge status={completion.page} variant="large"/></SectionHeader>
    <p>{saved.unit?`All weights are in ${displayUnit(saved.unit)}, as selected on Sheet B1.`:"Choose and save a weight unit on Sheet B1 before entering passenger weights."}</p>
    {!saved.canEdit&&<p className="muted">These settings are read-only for your account.</p>}
    <section className="commodity-section" aria-labelledby="passenger-default-title">
      <div className="details-heading"><h3 id="passenger-default-title">STANDARD / DEFAULT PASSENGER WEIGHTS</h3><div className="c5-heading-actions"><ConfigurationStatusBadge status={completion.standard}/>{controls("default")}</div></div>
      <p>These weights apply to all flights except where a separate Passenger Weight Table is saved for a named Flight Variation. Adult weight is optional. Male, Female, Child and Infant weights are required.</p>
      {!saved.defaultWeights&&editing!=="default"&&<p>No default passenger weights have been saved.</p>}
      <form noValidate onSubmit={e=>{e.preventDefault();if(editing==="default")save("default");}}><fieldset disabled={pending}><legend className="sr-only">Default passenger weights</legend>
        <WeightFields value={editing==="default"?defaults:passengerDraft(saved.defaultWeights)} editing={editing==="default"} onChange={setDefaults} prefix="default" unit={displayUnit(saved.unit)||"unit not set"}/>
        {actions("default")}
      </fieldset></form>
    </section>
    <section className="commodity-section" aria-labelledby="flight-variations-title">
      <div className="details-heading"><h3 id="flight-variations-title">CARRIER FLIGHT VARIATIONS</h3><div className="c5-heading-actions"><ConfigurationStatusBadge status={completion.variations}/>{controls("variations")}</div></div>
      <p>Adopt suggested Flight Variations or add your own Codes and Descriptions. Save them before adding separate Passenger Weight Tables.</p>
      <p className="muted">A saved variation continues to use the Standard Passenger Weights until a separate table is added and saved below.</p>
      <form noValidate onSubmit={e=>{e.preventDefault();if(editing==="variations")save("variations");}}><fieldset disabled={pending}><legend className="sr-only">Flight variations</legend>
        {editing==="variations"&&<div className="variation-suggestions"><h4>Suggested variations</h4><div className="logo-actions">{saved.masterVariations.map(v=><button key={v.code} type="button" className="secondary" disabled={variations.some(r=>r.code===v.code)||variations.length>=100} onClick={()=>setVariations(current=>[...current,{...v}])}>Add {v.description} ({v.code})</button>)}</div></div>}
        {!shownVariations.length&&<p>No Flight Variations have been adopted. Standard/Default can still be used.</p>}
        {shownVariations.map((v,index)=><div className="variation-row" key={editing==="variations"?index:v.code}>
          <div><label htmlFor={"variation-code-"+index}>Variation Code</label>{editing==="variations"?<input id={"variation-code-"+index} maxLength={3} value={v.code} onChange={e=>setVariations(current=>current.map((r,i)=>i===index?{...r,code:e.target.value.toUpperCase()}:r))}/>:<p className="passenger-value">{v.code}</p>}</div>
          <div><label htmlFor={"variation-description-"+index}>Name / Description</label>{editing==="variations"?<input id={"variation-description-"+index} maxLength={64} value={v.description} onChange={e=>setVariations(current=>current.map((r,i)=>i===index?{...r,description:e.target.value}:r))}/>:<p>{v.description}</p>}</div>
          {editing==="variations"&&<button className="secondary" type="button" aria-label={`Remove variation ${v.code||index+1}`} onClick={()=>setVariations(current=>current.filter((_,i)=>i!==index))}>Remove</button>}
        </div>)}
        {editing==="variations"&&<><button type="button" className="secondary" disabled={variations.length>=100} onClick={()=>setVariations(current=>[...current,{code:"",description:""}])}>Add Custom Variation</button><p className="muted">Use unique three-character codes and descriptions up to 64 characters. Remove linked weight sets before removing or changing a variation code.</p></>}
        {actions("variations")}
      </fieldset></form>
    </section>
    <section className="commodity-section" aria-labelledby="passenger-classes-title">
      <div className="details-heading"><h3 id="passenger-classes-title">PASSENGER WEIGHTS BY FLIGHT VARIATION</h3><ConfigurationStatusBadge status={completion.classWeights}/></div>
      <p>Review each saved Flight Variation. Leave it on Standard when the default weights apply, or add a separate table for All Classes or a selected Class.</p>
      {!saved.variations.length&&<p>No named Flight Variations are saved. The Standard Passenger Weights apply to all flights.</p>}
      <form noValidate onSubmit={e=>{e.preventDefault();if(editing==="classes")save("classes");}}><fieldset disabled={pending}><legend className="sr-only">Passenger weight tables by variation</legend>
        <div className="passenger-variation-coverage" aria-label="Flight Variation passenger-weight coverage">{saved.variations.map(variation=>{
          const count=saved.rows.filter(row=>row.variation===variation.code).length,open=openVariation===variation.code;
          return <section className={`passenger-variation-item${open?" open":""}`} key={variation.code}><div className="passenger-variation-heading"><div className="passenger-variation-copy"><strong>{variation.code} — {variation.description}</strong><span>{count?`${count} saved table row${count===1?"":"s"}`:"Uses Standard Passenger Weights"}</span></div>{count?<button type="button" className={`passenger-table-selector${open?" selected":""}`} disabled={!!editing} aria-expanded={open} onClick={()=>setOpenVariation(current=>current===variation.code?null:variation.code)}>{open?"CLOSE TABLE":"OPEN TABLE"}</button>:<button type="button" className="secondary" disabled={!!editing||!saved.canEdit||!saved.unit} onClick={()=>addVariationTable(variation.code)}>ADD SEPARATE TABLE</button>}</div>{open&&tablePanel(variation.code)}</section>;
        })}
        <section className={`passenger-variation-item${openVariation==="__STANDARD__"?" open":""}`}><div className="passenger-variation-heading"><div className="passenger-variation-copy"><strong>STANDARD FLIGHTS — CLASS OVERRIDES</strong><span>{saved.rows.filter(row=>row.variation===null).length?saved.rows.filter(row=>row.variation===null).length+" saved class override row(s)":"No class overrides"}</span></div>{saved.rows.some(row=>row.variation===null)?<button type="button" className={`passenger-table-selector${openVariation==="__STANDARD__"?" selected":""}`} disabled={!!editing} aria-expanded={openVariation==="__STANDARD__"} onClick={()=>setOpenVariation(current=>current==="__STANDARD__"?null:"__STANDARD__")}>{openVariation==="__STANDARD__"?"CLOSE TABLE":"OPEN TABLE"}</button>:<button type="button" className="secondary" disabled={!!editing||!saved.canEdit||!saved.unit} onClick={()=>beginTable("__STANDARD__",true)}>ADD CLASS OVERRIDE</button>}</div>{openVariation==="__STANDARD__"&&tablePanel("__STANDARD__")}</section>
        </div>
        {!saved.rows.length&&!saved.classWeightsReviewed&&!editing&&<div className="b3-standard-confirmation"><p>No separate Passenger Weight Tables are saved. Confirm that the Standard Passenger Weights apply to every Flight Variation.</p><button type="button" onClick={()=>persistRows([],"Standard Passenger Weights confirmed for all Flight Variations.")} disabled={pending||!saved.canEdit||!saved.unit}>CONFIRM STANDARD FOR ALL VARIATIONS</button></div>}
        {!saved.rows.length&&saved.classWeightsReviewed&&<p className="b3-standard-confirmed">Reviewed: Standard Passenger Weights apply to all Flight Variations.</p>}
      </fieldset></form>
    </section>
    <p role="status" aria-live="polite">{message}</p>
  </section>;
}
