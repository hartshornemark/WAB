"use client";
import {useState} from "react";
import Link from "next/link";
import {saveCrewHoldBaggage} from "@/app/crew-actions";
import {type CrewSnapshot,validateCrewHold} from "@/domain/crew-weights";
import {b2HoldBaggageStatus} from "@/domain/b2-status";
import {ConfigurationStatusBadge} from "./configuration-status-badge";
import {useSaveFeedback,SaveScope,SaveInput,SaveButton,SaveSubmit,SaveCancel} from "./save-feedback";
import {displayUnit} from "@/domain/display-standards";
export function CrewHoldBaggage({iata,snapshot,onSaved}:{iata:string;snapshot:CrewSnapshot;onSaved:(s:CrewSnapshot)=>void}){
 return <section className="commodity-section" aria-labelledby="crew-hold-heading"><div className="details-heading"><h3 id="crew-hold-heading">CREW HOLD BAGGAGE</h3><ConfigurationStatusBadge status={b2HoldBaggageStatus(snapshot)}/></div>
 <p>Standard weights apply to all flights except variations with separate weights. Enter a weight per crew member; zero is permitted.</p>
 <HoldTable iata={iata} snapshot={snapshot} code={null} description="Standard — All Other Flights" onSaved={onSaved}/>
 <div className="details-heading"><h4>FLIGHT VARIATIONS</h4><Link href={`/carrier/${encodeURIComponent(iata)}/passenger-weights`}>Manage Flight Variations on B3</Link></div>
 {!snapshot.variations?.length&&<p className="muted">No Flight Variations are defined. Standard weights apply to all flights.</p>}
 {(snapshot.variations??[]).map(v=><HoldTable key={v.code} iata={iata} snapshot={snapshot} code={v.code} description={`${v.code} — ${v.description}`} onSaved={onSaved}/>)}
 </section>;
}
function HoldTable({iata,snapshot,code,description,onSaved}:{iata:string;snapshot:CrewSnapshot;code:string|null;description:string;onSaved:(s:CrewSnapshot)=>void}){
 const row=snapshot.holdRows?.find(r=>r.code===code),standard=snapshot.holdRows?.find(r=>r.code===null);
 const [open,setOpen]=useState(false),[editing,setEditing]=useState(false),[mode,setMode]=useState<"STANDARD"|"SEPARATE">(row?.mode??(code===null?"SEPARATE":"STANDARD")),[fd,setFd]=useState(""),[cc,setCc]=useState(""),[error,setError]=useState("");
 const [pending,start,feedback]=useSaveFeedback();
 const begin=()=>{setMode(row?.mode??(code===null?"SEPARATE":"STANDARD"));setFd(row?.flightDeck?.toString()??(code===null?"0":""));setCc(row?.cabin?.toString()??(code===null?"0":""));setError("");setOpen(true);setEditing(true)};
 const inherited=(editing?mode:row?.mode)==="STANDARD",shown=inherited?standard:row;
 const configured=!!row&&(!inherited||!!standard);
 return <SaveScope feedback={feedback}><section className="crew-hold-table" aria-label={description}><div className="details-heading"><div><h4>{description}</h4><p className="muted">{row?code===null?"Standard weights":row.mode==="STANDARD"?"Uses Standard weights":"Separate weights":"Review and save this table."}</p></div><div className="c5-heading-actions"><ConfigurationStatusBadge status={configured?"configured":"incomplete"}/>{!editing&&<SaveButton type="button" className="secondary" onClick={()=>setOpen(!open)}>{open?"CLOSE":"OPEN TABLE"}</SaveButton>}</div></div>
 {open&&<><div className="crew-hold-options">{code!==null&&(["STANDARD","SEPARATE"] as const).map(m=><label key={m}><SaveInput type="radio" name={`crew-hold-${code}`} checked={(editing?mode:row?.mode)===m} disabled={!editing} onChange={()=>{setMode(m);setError("")}}/>{m==="STANDARD"?"Use Standard weights":"Separate weights"}</label>)}</div>
 {editing&&code===null&&!row&&<p className="muted">Zero weights are suggested. Review and save to confirm.</p>}
 {inherited&&!standard&&<p className="muted">Complete Standard weights to configure this variation.</p>}
 <div className="commodity-table"><table><thead><tr><th>Weight per crew member ({displayUnit(snapshot.unit)})</th><th>Flight Deck Crew</th><th>Cabin Crew</th></tr></thead><tbody><tr><th>Hold baggage</th><td>{editing&&!inherited?<SaveInput aria-label={`Flight Deck Crew hold baggage — ${description}`} inputMode="numeric" value={fd} onChange={e=>{setFd(e.target.value);setError("")}}/>:shown?.flightDeck??"Not specified"}</td><td>{editing&&!inherited?<SaveInput aria-label={`Cabin Crew hold baggage — ${description}`} inputMode="numeric" value={cc} onChange={e=>{setCc(e.target.value);setError("")}}/>:shown?.cabin??"Not specified"}</td></tr></tbody></table></div>
 {error&&<p className="field-error" role="alert">{error}</p>}
 <div className="logo-actions">{editing?<><SaveSubmit type="button" disabled={pending} onClick={()=>{let values;try{values=validateCrewHold({mode,flightDeck:fd,cabin:cc},code)}catch(e){setError(e instanceof Error?e.message:"Check the weights.");return}start(async()=>{const r=await saveCrewHoldBaggage(iata,snapshot.revision,code,values);if(!r.ok){setError(r.error);return}onSaved(r.snapshot);setError("");feedback.complete(()=>setEditing(false));});}}>SAVE</SaveSubmit><SaveCancel type="button" className="secondary" onClick={()=>{setEditing(false);setError("")}}>CANCEL</SaveCancel></>:snapshot.canEdit&&snapshot.unit&&<SaveButton type="button" className="secondary" onClick={begin}>{row?"EDIT":"REVIEW"}</SaveButton>}</div>
 </>}
 </section></SaveScope>;
}
