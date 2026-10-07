"use client";
import{useMemo,useState,useTransition}from"react";
import{useRouter}from"next/navigation";
import{saveScheduleParameters}from"@/app/flight-schedule-actions";
import{filterPublishedScheduleItineraries,publishedScheduleItineraries,scheduleAircraftCarriesPassengers,scheduleAircraftSubtype,scheduleCodesForSubtype,scheduleOnlyCode}from"@/domain/flight-schedules";
import type{FlightScheduleParameters,FlightScheduleWorkspace,PublishedScheduleLeg}from"@/ports/flight-schedule-repository";

const weekday=["M","T","W","T","F","S","S"];
const days=(bits:string)=>Array.from(bits).flatMap((bit,index)=>bit==="1"?[weekday[index]]:[]).join(" ");
const date=(value:string)=>new Intl.DateTimeFormat("en-GB",{day:"2-digit",month:"short",year:"2-digit"}).format(new Date(`${value}T00:00:00Z`));

function LegEditor({iata,leg,workspace,onClose}:{iata:string;leg:PublishedScheduleLeg;workspace:FlightScheduleWorkspace;onClose:()=>void}){
  const subtypes=workspace.aircraft.filter(item=>item.typeCode===leg.aircraftType),initialSubtype=scheduleAircraftSubtype(leg,subtypes[0]?.subtype??"");
  const[draft,setDraft]=useState<FlightScheduleParameters>(leg.parameters??{aircraftSubtype:initialSubtype,crewCode:scheduleOnlyCode(workspace.crewCodes,leg.aircraftType,initialSubtype)??"",pantryCode:scheduleOnlyCode(workspace.pantryCodes,leg.aircraftType,initialSubtype)??"",passengerWeightBasis:workspace.weightOptions.passenger.defaultBasis,passengerVariation:null,baggageWeightBasis:workspace.weightOptions.baggage.defaultBasis,baggageVariation:null,remarks:""});
  const[state,setState]=useState({ok:false,message:""}),[pending,start]=useTransition(),router=useRouter();
  const crew=scheduleCodesForSubtype(workspace.crewCodes,leg.aircraftType,draft.aircraftSubtype),pantry=scheduleCodesForSubtype(workspace.pantryCodes,leg.aircraftType,draft.aircraftSubtype),passengerChoices=workspace.weightOptions.passenger.variations,baggageChoices=workspace.weightOptions.baggage.variations;
  const carriesPassengers=scheduleAircraftCarriesPassengers(workspace.aircraft,leg.aircraftType,draft.aircraftSubtype);
  const update=<K extends keyof FlightScheduleParameters>(key:K,value:FlightScheduleParameters[K])=>setDraft(current=>key==="aircraftSubtype"?{...current,aircraftSubtype:String(value),crewCode:scheduleOnlyCode(workspace.crewCodes,leg.aircraftType,String(value))??"",pantryCode:scheduleOnlyCode(workspace.pantryCodes,leg.aircraftType,String(value))??""}:{...current,[key]:value});
  const save=()=>start(async()=>{const result=await saveScheduleParameters(iata,leg.scheduleLegId,draft);setState(result);if(result.ok)router.refresh()});
  return <div className="schedule-parameter-editor">
    <div className="schedule-parameter-grid">
      <label>Aircraft subtype<select value={draft.aircraftSubtype} onChange={event=>update("aircraftSubtype",event.target.value)}><option value="">Select subtype</option>{subtypes.map(item=><option key={item.subtype} value={item.subtype}>{item.typeCode}-{item.subtype} · {item.name}</option>)}</select></label>
      <label>Crew code{crew.length===1?<input value={crew[0]} readOnly aria-label="Crew code automatically selected"/>:<select value={draft.crewCode} onChange={event=>update("crewCode",event.target.value)}><option value="">Select crew code</option>{crew.map(code=><option key={code}>{code}</option>)}</select>}</label>
      <label>Pantry code{pantry.length===1?<input value={pantry[0]} readOnly aria-label="Pantry code automatically selected"/>:<select value={draft.pantryCode} onChange={event=>update("pantryCode",event.target.value)}><option value="">Select pantry code</option>{pantry.map(code=><option key={code}>{code}</option>)}</select>}</label>
      {carriesPassengers&&passengerChoices.length>0&&<label>Passenger weights<select value={draft.passengerWeightBasis} onChange={event=>update("passengerWeightBasis",event.target.value as FlightScheduleParameters["passengerWeightBasis"])}><option value="STANDARD">Standard</option><option value="VARIATION">Flight variation</option></select></label>}
      {carriesPassengers&&passengerChoices.length>0&&draft.passengerWeightBasis==="VARIATION"&&<label>Passenger variation<select value={draft.passengerVariation??""} onChange={event=>update("passengerVariation",event.target.value||null)}><option value="">Select variation</option>{passengerChoices.map(item=><option key={item.code} value={item.code}>{item.code} · {item.description}</option>)}</select></label>}
      {carriesPassengers&&baggageChoices.length>0&&<label>Baggage weights<select value={draft.baggageWeightBasis} onChange={event=>update("baggageWeightBasis",event.target.value as FlightScheduleParameters["baggageWeightBasis"])}><option value={workspace.weightOptions.baggage.defaultBasis}>{workspace.weightOptions.baggage.defaultBasis==="ACTUAL"?"Actual":"Standard"}</option><option value="VARIATION">Flight variation</option></select></label>}
      {carriesPassengers&&baggageChoices.length>0&&draft.baggageWeightBasis==="VARIATION"&&<label>Baggage variation<select value={draft.baggageVariation??""} onChange={event=>update("baggageVariation",event.target.value||null)}><option value="">Select variation</option>{baggageChoices.map(item=><option key={item.code} value={item.code}>{item.code} · {item.description}</option>)}</select></label>}
      {!carriesPassengers&&<p className="schedule-freighter-note">Passenger and baggage parameters are not required for this freighter.</p>}
      <label className="schedule-remarks">Remarks<textarea value={draft.remarks} onChange={event=>update("remarks",event.target.value)} maxLength={1000}/></label>
    </div>
    {(!subtypes.length||!crew.length||!pantry.length)&&<p className="save-feedback error">Complete the matching aircraft C1 and E2 crew/pantry configuration before this flight can be made ready.</p>}
    {state.message&&<p className={state.ok?"save-feedback success":"save-feedback error"}>{state.message}</p>}
    <div className="c7-actions"><button type="button" onClick={save} disabled={pending}>{pending?"SAVING…":"SAVE PARAMETERS"}</button><button type="button" className="secondary" onClick={onClose}>CLOSE</button></div>
  </div>;
}

export function PublishedScheduleWorkspace({iata,workspace}:{iata:string;workspace:FlightScheduleWorkspace}){
  const[query,setQuery]=useState(""),[readiness,setReadiness]=useState("ALL"),[open,setOpen]=useState<string|null>(null);
  const itineraries=useMemo(()=>filterPublishedScheduleItineraries(publishedScheduleItineraries(workspace.legs),iata,query,readiness as "ALL"|"READY"|"INCOMPLETE"),[workspace.legs,query,readiness,iata]);
  if(!workspace.publishedImportIds.length)return <details className="configuration-card published-schedule schedule-collapsible" open><summary className="schedule-section-heading"><div><h2>PUBLISHED SCHEDULE</h2><p className="muted">Publish a validated SSIM or manual edition to view its flights and add Load Control parameters.</p></div></summary></details>;
  return <details className="configuration-card published-schedule schedule-collapsible" open><summary className="schedule-section-heading"><div><h2>PUBLISHED SCHEDULE</h2><p className="muted">{workspace.publishedImportIds.length} published {workspace.publishedImportIds.length===1?"schedule":"schedules"} · {workspace.legs.length} recurring flight legs · {workspace.legs.filter(leg=>leg.parameters).length} ready for Load Control</p></div></summary>
    <div className="schedule-collapsible-content">
    <div className="schedule-filters"><label>Search<input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Flight or airport"/></label><label>Readiness<select value={readiness} onChange={event=>setReadiness(event.target.value)}><option value="ALL">All flights</option><option value="READY">Ready</option><option value="INCOMPLETE">Parameters required</option></select></label></div>
    <div className="published-flight-list">{itineraries.map(itinerary=><section className="published-itinerary" key={itinerary.key}>
      <header className="published-itinerary-heading"><div><strong>{iata}{itinerary.flightNumber}{itinerary.operationalSuffix}</strong><span>{itinerary.route}</span><small>{itinerary.scheduleName}</small></div><span>{itinerary.sectorCount} {itinerary.sectorCount===1?"sector":"sectors"}</span></header>
      <div className="published-itinerary-legs">{itinerary.legs.map(leg=><article className="published-flight" key={leg.scheduleLegId}>
        <div className="published-flight-summary"><strong>LEG {leg.legSequence}</strong><span>{leg.departureAirport} <b>→</b> {leg.arrivalAirport}</span><span>{leg.departureTime} – {leg.arrivalTime}{leg.arrivalDayOffset?` +${leg.arrivalDayOffset}`:""}</span><span>{days(leg.operatingDays)}</span><span>{date(leg.periodStart)} – {date(leg.periodEnd)}</span><span>{leg.aircraftType??"—"}{scheduleAircraftSubtype(leg)?`-${scheduleAircraftSubtype(leg)}`:""}</span><span className={leg.parameters?"schedule-readiness ready":"schedule-readiness"}>{leg.parameters?"READY":"PARAMETERS REQUIRED"}</span><button type="button" className="secondary" onClick={()=>setOpen(open===leg.scheduleLegId?null:leg.scheduleLegId)}>{open===leg.scheduleLegId?"CLOSE":"CONFIGURE"}</button></div>
        {leg.parameters&&<div className="published-flight-parameters"><span>Crew {leg.parameters.crewCode}</span><span>Pantry {leg.parameters.pantryCode}</span>{scheduleAircraftCarriesPassengers(workspace.aircraft,leg.aircraftType,leg.parameters.aircraftSubtype)&&<><span>Passenger {leg.parameters.passengerWeightBasis}{leg.parameters.passengerVariation?` ${leg.parameters.passengerVariation}`:""}</span><span>Baggage {leg.parameters.baggageWeightBasis}{leg.parameters.baggageVariation?` ${leg.parameters.baggageVariation}`:""}</span></>}</div>}
        {open===leg.scheduleLegId&&<LegEditor iata={iata} leg={leg} workspace={workspace} onClose={()=>setOpen(null)}/>}
      </article>)}</div>
    </section>)}</div>
    </div>
  </details>;
}
