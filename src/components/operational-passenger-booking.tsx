"use client";
import{useState,useTransition}from"react";
import{useRouter}from"next/navigation";
import{saveOperationalPassengerBooking}from"@/app/load-control-actions";
import type{OperationalPassengerBooking}from"@/domain/operational-passengers";
import{forecastPassengerAreas,type PassengerAreaCapacity}from"@/domain/passenger-area-forecast";

const kg=(value:number|null)=>value===null?"—":`${Math.round(value).toLocaleString()} KG`;
const draftOf=(booking:OperationalPassengerBooking)=>Object.fromEntries(booking.classes.map(row=>[row.code,String(row.booked)]));
export function OperationalPassengerBookingPanel({iata,flightId,initial,configurationCode,cabinAreas}:{iata:string;flightId:string;initial:OperationalPassengerBooking;configurationCode:string|null;cabinAreas:PassengerAreaCapacity[]}){
 const[saved,setSaved]=useState(initial),[draft,setDraft]=useState<Record<string,string>>(()=>draftOf(initial)),[editing,setEditing]=useState(false),[notice,setNotice]=useState<{ok:boolean;text:string}|null>(null),[pending,start]=useTransition(),router=useRouter();
 if(!saved.applicable)return null;
 const editable=saved.canEdit&&editing,dirty=JSON.stringify(draft)!==JSON.stringify(draftOf(saved)),forecastTotal=editable?saved.classes.reduce((sum,row)=>sum+Math.max(0,Number(draft[row.code]||0)||0),0):saved.totalBooked,areaForecast=forecastPassengerAreas(forecastTotal,cabinAreas),bookedByClass=saved.classes.filter(row=>row.booked>0).map(row=>`${row.code}${row.booked.toLocaleString()}`).join(" · ");
 const save=()=>start(async()=>{const result=await saveOperationalPassengerBooking(iata,flightId,saved.version,{classes:saved.classes.map(row=>({code:row.code,booked:Number(draft[row.code]||0)}))});if(!result.ok||!result.booking){setNotice({ok:false,text:result.message});return}setSaved(result.booking);setDraft(draftOf(result.booking));setEditing(false);setNotice({ok:true,text:result.message});router.refresh()});
 return <div className="passenger-booking operational-collapsible">
  <header className="operational-collapsible-summary"><div><p className="eyebrow">PASSENGER PLANNING</p><h2>Booked Passengers</h2><p>Manual booking snapshot by class of service for planning before passenger-system integration.</p></div><div className="operational-summary-facts"><span><small>BOOKED</small><strong>{saved.totalBooked.toLocaleString()}</strong>{bookedByClass&&<small className="operational-summary-breakdown">{bookedByClass}</small>}</span><span><small>PLANNING WEIGHT</small><strong>{kg(saved.totalPassengerWeight)}</strong></span></div>{saved.canEdit&&!editing&&<button type="button" className="secondary traffic-plan-header-action" onClick={()=>{setDraft(draftOf(saved));setNotice(null);setEditing(true)}}>EDIT</button>}</header>
  <div className="operational-collapsible-body">
   <div className="passenger-booking-heading"><p>This is the booked load used for advance planning. Checked-in and boarded passenger figures will remain separate operational stages.</p></div>
   <div className="passenger-booking-grid"><div className="passenger-booking-grid-head"><span>CLASS</span><span>BOOKED</span><span>PLANNING WT / PAX</span><span>PASSENGER WEIGHT</span></div>{saved.classes.map(row=>{const booked=Number(draft[row.code]||0),weight=row.planningWeight===null?null:booked*row.planningWeight;return <div className="passenger-booking-row" key={row.code}><strong><b>{row.code}</b>{row.name}</strong>{editable?<input aria-label={`${row.name} booked passengers`} inputMode="numeric" min="0" max="999" step="1" type="number" value={draft[row.code]??"0"} onChange={event=>{setDraft(current=>({...current,[row.code]:event.target.value}));setNotice(null)}}/>:<span>{row.booked.toLocaleString()}</span>}<span>{kg(row.planningWeight)}</span><span>{kg(editable?weight:row.passengerWeight)}</span></div>})}</div>
   {areaForecast.length>0&&<section className="passenger-booking-forecast" aria-labelledby="passenger-booking-forecast-heading"><header><div><small>CABIN FORECAST</small><h3 id="passenger-booking-forecast-heading">Booked passengers by cabin area</h3></div>{configurationCode&&<strong>{configurationCode}</strong>}</header><p>Distributed evenly in proportion to the installed seats in each cabin area.</p><div className="passenger-cabin-plan">{areaForecast.map(area=><article key={area.areaId}><div><small>CABIN AREA {area.areaId}</small><strong>{area.seats.toLocaleString()} SEATS</strong></div><b>{area.passengers} PAX</b></article>)}</div></section>}
   {saved.missing.length>0&&<p className="field-error">Passenger planning is incomplete: {saved.missing.map(item=>item.replaceAll("_"," ").toLowerCase()).join(", ")}.</p>}
   {editable&&<div className="passenger-booking-actions"><button className="secondary" disabled={pending} onClick={()=>{setDraft(draftOf(saved));setNotice(null);setEditing(false)}}>CANCEL</button><button disabled={pending||saved.classes.length===0||!dirty} onClick={save}>{pending?"SAVING…":"SAVE BOOKED LOAD"}</button></div>}
   {notice&&<p className={notice.ok?"load-control-notice success":"load-control-notice error"}>{notice.text}</p>}
  </div>
 </div>;
}
