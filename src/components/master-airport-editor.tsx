"use client";
import{useMemo,useState,useTransition}from"react";
import{useRouter}from"next/navigation";
import{saveMasterAirportAction,type AirportActionState}from"@/app/admin/airports/actions";
import type{MasterAirport,MasterAirportInput}from"@/domain/master-airports";
const empty:MasterAirportInput={iata:"",icao:null,name:"",city:null,countryCode:null,timeZone:"",active:true};
const clean=(value:string)=>value||null;
export function MasterAirportEditor({initial,timeZones}:{initial:MasterAirport[];timeZones:string[]}){
 const[query,setQuery]=useState(""),[original,setOriginal]=useState<string|null|undefined>(undefined),[draft,setDraft]=useState<MasterAirportInput>(empty),[feedback,setFeedback]=useState<AirportActionState|null>(null),[pending,start]=useTransition(),router=useRouter();
 const visible=useMemo(()=>{const needle=query.trim().toLowerCase();return needle?initial.filter(item=>[item.iata,item.icao,item.name,item.city,item.countryCode,item.timeZone].some(value=>value?.toLowerCase().includes(needle))):initial},[initial,query]);
 const edit=(item?:MasterAirport)=>{setOriginal(item?.iata??null);setDraft(item?{iata:item.iata,icao:item.icao,name:item.name,city:item.city,countryCode:item.countryCode,timeZone:item.timeZone,active:item.active}:empty);setFeedback(null)};
 const cancel=()=>{setOriginal(undefined);setDraft(empty);setFeedback(null)};
 const change=<K extends keyof MasterAirportInput>(key:K,value:MasterAirportInput[K])=>setDraft(current=>({...current,[key]:value}));
 const save=()=>start(async()=>{const result=await saveMasterAirportAction(original??null,draft);setFeedback(result);if(result.ok){cancel();router.refresh()}});
 return <section className="overview airport-admin-card">
  <div className="airport-admin-heading"><div><h2>Master Airports</h2><p className="muted">{initial.length.toLocaleString()} airport{initial.length===1?"":"s"} recorded. Inactive airports remain in the audit record and are excluded from schedule entry.</p></div><button type="button" onClick={()=>edit()}>ADD AIRPORT</button></div>
  <label className="airport-search">Search airports<input type="search" value={query} onChange={event=>setQuery(event.target.value)} placeholder="IATA, ICAO, airport, city, country or time zone"/></label>
  {original!==undefined&&<div className="airport-editor-panel"><div className="airport-editor-title"><h3>{original?`Amend ${original}`:"Add airport"}</h3><span className={`schedule-status ${draft.active?"published":"superseded"}`}>{draft.active?"ACTIVE":"INACTIVE"}</span></div><div className="airport-editor-grid">
   <label><span className="airport-field-title">IATA code</span><span className="airport-field-help" aria-hidden="true">&nbsp;</span><input value={draft.iata} disabled={!!original} maxLength={3} onChange={event=>change("iata",event.target.value.toUpperCase().replace(/[^A-Z]/g,"").slice(0,3))}/></label>
   <label><span className="airport-field-title">ICAO code</span><span className="airport-field-help">Optional</span><input value={draft.icao??""} maxLength={4} onChange={event=>change("icao",clean(event.target.value.toUpperCase().replace(/[^A-Z0-9]/g,"").slice(0,4)))}/></label>
   <label className="airport-name-field"><span className="airport-field-title">Airport name</span><span className="airport-field-help" aria-hidden="true">&nbsp;</span><input value={draft.name} maxLength={160} onChange={event=>change("name",event.target.value)}/></label>
   <label><span className="airport-field-title">City</span><span className="airport-field-help">Optional</span><input value={draft.city??""} maxLength={120} onChange={event=>change("city",clean(event.target.value))}/></label>
   <label><span className="airport-field-title">Country code</span><span className="airport-field-help">Optional</span><input value={draft.countryCode??""} maxLength={2} onChange={event=>change("countryCode",clean(event.target.value.toUpperCase().replace(/[^A-Z]/g,"").slice(0,2)))}/></label>
   <label className="airport-time-zone-field"><span className="airport-field-title">IANA time zone</span><span className="airport-field-help" aria-hidden="true">&nbsp;</span><input list="master-airport-time-zones" value={draft.timeZone} onChange={event=>change("timeZone",event.target.value)} placeholder="Asia/Manila"/><datalist id="master-airport-time-zones">{timeZones.map(zone=><option key={zone} value={zone}/>)}</datalist></label>
   <label className="airport-active"><input type="checkbox" checked={draft.active} onChange={event=>change("active",event.target.checked)}/><span>Available for schedule entry</span></label>
  </div>{feedback&&<p className={feedback.ok?"save-feedback success":"save-feedback error"}>{feedback.message}</p>}<div className="airport-editor-actions"><button type="button" className="secondary" onClick={cancel}>CANCEL</button><button type="button" disabled={pending} onClick={save}>{pending?"SAVING…":"SAVE AIRPORT"}</button></div></div>}
  <div className="airport-table-wrap"><table className="airport-table"><thead><tr><th>IATA</th><th>ICAO</th><th>Airport</th><th>City / Country</th><th>IANA Time Zone</th><th>Status</th><th>Action</th></tr></thead><tbody>{visible.map(item=><tr key={item.iata}><th>{item.iata}</th><td>{item.icao??"—"}</td><td>{item.name}</td><td>{[item.city,item.countryCode].filter(Boolean).join(" · ")||"—"}</td><td>{item.timeZone}</td><td><span className={`schedule-status ${item.active?"published":"superseded"}`}>{item.active?"ACTIVE":"INACTIVE"}</span></td><td><button type="button" className="secondary" onClick={()=>edit(item)}>AMEND</button></td></tr>)}</tbody></table>{!visible.length&&<p className="airport-empty">{initial.length?"No airports match this search.":"No master airports have been added yet."}</p>}</div>
 </section>;
}
