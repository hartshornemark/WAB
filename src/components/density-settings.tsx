"use client";
import {useState,useTransition} from "react";
import {saveDensities} from "@/app/density-actions";
import {densityFields,validateDensities,type DensitySnapshot} from "@/domain/density-settings";
import {ConfigurationStatusBadge} from "@/components/configuration-status-badge";
import {b1DensityStatus} from "@/domain/b1-status";
import {useRouter} from "next/navigation";
import {displayUnit} from "@/domain/display-standards";
export function DensitySettings({iata,initial,unitsEditing=false}:{iata:string;initial:DensitySnapshot;unitsEditing?:boolean}){
 const router=useRouter();
 const [saved,setSaved]=useState(initial),[draft,setDraft]=useState(initial.values),[editing,setEditing]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");const [pending,startTransition]=useTransition();
 // Preserve an open draft: a changed revision will be rejected by the database.
 const [editSource,setEditSource]=useState(initial);
 const [previousInitial,setPreviousInitial]=useState(initial);
 if(previousInitial!==initial){setPreviousInitial(initial);if(!editing)setSaved(initial);}
 if(!saved.canView)return null;
 const unit=saved.weightUnit&&saved.volumeUnit?`${displayUnit(saved.weightUnit)}/${saved.volumeUnit==="m3"?"m³":"ft³"}`:"Units not set";
 return <section className="commodity-section passenger-weights" aria-labelledby="density-title"><div className="details-heading"><h3 id="density-title">COMMODITY DENSITY SETTINGS</h3><div className="c5-heading-actions"><ConfigurationStatusBadge status={b1DensityStatus(saved)}/>{saved.canEdit&&!editing&&!unitsEditing&&saved.weightUnit&&saved.volumeUnit&&<button className="secondary" onClick={()=>{setEditSource(initial);setDraft({...saved.values});setError("");setMessage("");setEditing(true);}}>EDIT</button>}</div></div>
 <p>Densities use the carrier’s selected Weight and Volume Units ({unit}). Enter a positive value for Checked Baggage, General Cargo and General Mail. Saved densities are converted when these units change.</p>
 <form noValidate onSubmit={e=>{e.preventDefault();setError("");try{validateDensities(draft);}catch(e){setError(e instanceof Error?e.message:"Check the density values.");return;}startTransition(async()=>{try{const r=await saveDensities(iata,saved.revision,draft);if(r.ok){setSaved(r.snapshot);setEditing(false);setMessage("Density settings saved.");router.refresh();}else setError(r.error);}catch{setError("Unable to save. Your entries are still here; please try again.");}});}}><fieldset disabled={pending||unitsEditing}><legend className="sr-only">Commodity Densities</legend><div className="passenger-weight-grid">{densityFields.map(f=><div key={f.key}><label htmlFor={editing?`density-${f.key}`:undefined}>{f.label} ({unit})</label>{editing?<input id={`density-${f.key}`} type="number" step="any" min="0" value={draft[f.key]} onChange={e=>setDraft(v=>({...v,[f.key]:e.target.value}))}/>:<p className="passenger-value">{saved.values[f.key]||"Not specified"}</p>}</div>)}</div>{editing&&<>{error&&<p role="alert" className="field-error">{error}</p>}<div className="logo-actions"><button type="submit">{pending?"Saving…":"Save"}</button><button type="button" className="secondary" onClick={()=>{setEditing(false);if(initial!==editSource)setSaved(initial);setError("");}}>Cancel</button></div></>}</fieldset></form>
 {!saved.canEdit&&<p className="muted">Density settings are read-only for your account.</p>}<p role="status" aria-live="polite">{message}</p></section>;
}
