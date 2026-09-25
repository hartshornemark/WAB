"use client";
import {useSaveFeedback,SaveScope,SaveButton,SaveInput,SaveTextarea,SaveSubmit,SaveCancel} from "@/components/save-feedback";
import{useEffect,useState,useTransition}from"react";
import{SectionHeader}from"@/components/section-header";
import{saveAircraftC1,searchAircraftManufacturers}from"@/app/aircraft-actions";
import{aircraftVariant,type AircraftC1Snapshot,type AircraftC1Values,type AircraftOperatingRole}from"@/domain/aircraft-c1";
import{aircraftC1Statuses}from"@/domain/aircraft-c1-status";
import{ConfigurationStatusBadge}from"@/components/configuration-status-badge";

const groups:{key:keyof Omit<AircraftC1Values,"remarks">;label:string;options:[string,string][]}[]=[
  {key:"length",label:"Length",options:[["CM","Centimetres"],["M","Metres"],["IN","Inches"],["FT","Feet"]]},
  {key:"weight",label:"Weight",options:[["KG","Kilograms"],["LB","US Pounds"]]},
  {key:"volume",label:"Volume",options:[["M3","Cubic Metres (m³)"],["FT3","Cubic Feet (ft³)"]]},
  {key:"liquidVolume",label:"Liquid Volume",options:[["L","Litres"],["US_GAL","US Gallons"]]},
  {key:"moment",label:"Moments",options:[["KG_IN","KG Inches"],["LB_IN","LB Inches"],["KG_CM","KG Centimetres"],["LB_CM","LB Centimetres"],["KG_M","KG Metres"],["LB_M","LB Metres"]]},
  {key:"fuelDensity",label:"Fuel Density",options:[["KG_L","KG/Litre"],["LB_L","LB/Litre"],["KG_US_GAL","KG/US Gallon"],["LB_US_GAL","LB/US Gallon"]]}
];

export function AircraftC1({iata,initial}:{iata:string;initial:AircraftC1Snapshot}){
  const[saved,setSaved]=useState(initial);
  const[draft,setDraft]=useState({aircraftName:initial.aircraftName,variantCodes:initial.variantCodes,operatingRole:initial.operatingRole,values:initial.values,manufacturerId:initial.manufacturerId});
  const[variantInput,setVariantInput]=useState("");
  const[editing,setEditing]=useState(!initial.exists);
  const[manufacturerQuery,setManufacturerQuery]=useState(initial.manufacturerName);
  const[manufacturers,setManufacturers]=useState<{id:string;name:string}[]>([]);
  const[error,setError]=useState("");
  const[message,setMessage]=useState("");
  const[pending,start,saveFeedback]=useSaveFeedback();
  const[,startSearch]=useTransition();
  const completion=aircraftC1Statuses(saved);

  const canChooseManufacturer=editing&&!saved.manufacturerId&&saved.canAssignManufacturer;
  useEffect(()=>{
    if(!canChooseManufacturer||draft.manufacturerId||manufacturerQuery.trim().length<2)return;
    const timer=setTimeout(()=>startSearch(async()=>{const r=await searchAircraftManufacturers(manufacturerQuery);if(r.ok)setManufacturers(r.rows);else setError(r.error)}),220);
    return()=>clearTimeout(timer);
  },[canChooseManufacturer,draft.manufacturerId,manufacturerQuery,startSearch]);

  function choose(key:keyof AircraftC1Values,value:string){setDraft(d=>({...d,values:{...d.values,[key]:value}}));}
  function reset(){setDraft({aircraftName:saved.aircraftName,variantCodes:saved.variantCodes,operatingRole:saved.operatingRole,values:saved.values,manufacturerId:saved.manufacturerId});setVariantInput("");setManufacturerQuery(saved.manufacturerName);setManufacturers([]);setError("");}
  function addVariant(){const code=aircraftVariant(variantInput);if(!code||draft.variantCodes.includes(code))return;setDraft(d=>({...d,variantCodes:[...d.variantCodes,code].sort()}));setVariantInput("");}
  function save(){
    setError("");
    if(canChooseManufacturer&&manufacturerQuery.trim()&&!draft.manufacturerId){setError("Select an Aircraft Manufacturer from the suggested list.");return;}
    start(async()=>{
      const r=await saveAircraftC1(iata,saved.typeCode,saved.subtype,saved.revision,draft);
      if(!r.ok){setError(r.error);return;}
      setError("");setSaved(r.snapshot);saveFeedback.complete(()=>{
      setDraft({aircraftName:r.snapshot.aircraftName,variantCodes:r.snapshot.variantCodes,operatingRole:r.snapshot.operatingRole,values:r.snapshot.values,manufacturerId:r.snapshot.manufacturerId});
      setManufacturerQuery(r.snapshot.manufacturerName);
      setManufacturers([]);
      setEditing(false);
      setMessage("C1 saved.");});
    });
  }

  return <SaveScope feedback={saveFeedback}>{<section className="aircraft-c1">
    <SectionHeader id="aircraft-c1-heading" title="1. AIRCRAFT TYPE OR FLEET" reference="(AHM565 Sheet C1)"><div className="c5-heading-actions">{saved.canEdit&&!editing&&<SaveButton className="secondary" onClick={()=>{setEditing(true);setMessage("")}}>EDIT</SaveButton>}<ConfigurationStatusBadge status={completion.page} variant="large"/></div></SectionHeader>
    <div className="c1-identity-card">
      <div className="details-heading"><h3>Aircraft Identity</h3><ConfigurationStatusBadge status={completion.identity}/></div>
      <dl>
        <div className={canChooseManufacturer?"manufacturer-editor":""}>
          <dt>Manufacturer</dt>
          <dd>{canChooseManufacturer?<>
            <SaveInput value={manufacturerQuery} onChange={e=>{setManufacturerQuery(e.target.value);setDraft(d=>({...d,manufacturerId:null}));if(e.target.value.trim().length<2)setManufacturers([])}} placeholder="Begin typing a Manufacturer" autoComplete="off" role="combobox" aria-autocomplete="list" aria-controls="manufacturer-suggestions" aria-expanded={manufacturers.length>0}/>
            {manufacturers.length>0&&<ul id="manufacturer-suggestions" className="autocomplete-results">{manufacturers.map(m=><li key={m.id}><SaveButton type="button" onClick={()=>{setDraft(d=>({...d,manufacturerId:m.id}));setManufacturerQuery(m.name);setManufacturers([])}}>{m.name}</SaveButton></li>)}</ul>}
          </>:saved.manufacturerName||"Not yet assigned"}</dd>
        </div>
        <div><dt>Aircraft Type</dt><dd>{saved.typeCode}</dd></div>
        <div><dt>Master Series or Sub-Type</dt><dd>{saved.subtype}</dd></div>
        <div><dt>Aircraft Identity Name</dt><dd>{saved.identityName}</dd></div>
      </dl>
      {editing?<><div className="details-field aircraft-name"><label htmlFor="aircraft-name">Aircraft Name</label><SaveInput id="aircraft-name" value={draft.aircraftName} onChange={e=>setDraft(d=>({...d,aircraftName:e.target.value}))} maxLength={64}/><small>Aircraft name as it will appear on the load sheet.</small></div><fieldset className="c1-operating-role"><legend>Aircraft Operating Role</legend><div className="radio-options">{(["PASSENGER","FREIGHTER","COMBI"] as AircraftOperatingRole[]).map(role=><label key={role}><SaveInput type="radio" name="operating-role" checked={draft.operatingRole===role} onChange={()=>setDraft(d=>({...d,operatingRole:role}))}/><span>{role.charAt(0)+role.slice(1).toLowerCase()}</span></label>)}</div><small>Freighter aircraft exclude passenger-only pages. Combi aircraft retain both passenger and freight requirements.</small></fieldset></>:<dl><div><dt>Aircraft Name</dt><dd>{saved.aircraftName}</dd></div><div><dt>Aircraft Operating Role</dt><dd>{saved.operatingRole.charAt(0)+saved.operatingRole.slice(1).toLowerCase()}</dd></div></dl>}
      <div className="c1-variants"><div><strong>Carrier Variants / Models</strong><p>Use the Master Series for shared configuration, then add the variants operated by this carrier.</p></div><div className="c1-variant-list">{(editing?draft.variantCodes:saved.variantCodes).map(code=><span key={code}>{saved.typeCode}-{code}{editing&&code!==saved.subtype&&<SaveButton type="button" aria-label={`Remove ${code}`} onClick={()=>setDraft(d=>({...d,variantCodes:d.variantCodes.filter(x=>x!==code)}))}>×</SaveButton>}</span>)}</div>{editing&&<div className="c1-variant-add"><label htmlFor="carrier-variant">Add Carrier Variant</label><div><SaveInput id="carrier-variant" value={variantInput} onChange={e=>setVariantInput(aircraftVariant(e.target.value))} onKeyDown={e=>{if(e.key==="Enter"){e.preventDefault();addVariant()}}} maxLength={4} placeholder="e.g. 214"/><SaveButton type="button" className="secondary" onClick={addVariant}>ADD VARIANT</SaveButton></div></div>}</div>
    </div>
    <div className="c1-units">
      <div className="details-heading"><h3>Definitions of Units of Measure</h3><ConfigurationStatusBadge status={completion.units}/></div>
      <div className="c1-unit-grid">{groups.map(group=><fieldset key={group.key} disabled={!editing}><legend>{group.label}</legend><div className="radio-options">{group.options.map(([value,label])=><label key={value}><SaveInput type="radio" name={group.key} value={value} checked={draft.values[group.key]===value} onChange={()=>choose(group.key,value)}/><span>{label}</span></label>)}</div></fieldset>)}</div>
    </div>
    {(editing||saved.values.remarks)&&<div className="details-field c1-remarks"><div className="details-heading"><label htmlFor="c1-remarks">Remarks</label><ConfigurationStatusBadge status={completion.remarks}/></div>{editing?<SaveTextarea id="c1-remarks" value={draft.values.remarks} onChange={e=>choose("remarks",e.target.value)} maxLength={2000}/>:<p>{saved.values.remarks}</p>}</div>}
    {error&&<p className="field-error" role="alert">{error}</p>}
    {message&&<p className="form-success" role="status">{message}</p>}
    {editing&&<div className="logo-actions"><SaveSubmit disabled={pending} onClick={save}>SAVE</SaveSubmit>{saved.exists&&<SaveCancel className="secondary" disabled={pending} onClick={()=>{reset();setEditing(false)}}>Cancel</SaveCancel>}</div>}
  </section>}</SaveScope>;
}
