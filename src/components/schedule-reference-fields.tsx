"use client";
import{useId,useMemo,useState}from"react";
import{firstAircraftConfiguration}from"@/domain/flight-schedules";
import type{FlightScheduleWorkspace,ManualScheduleLegInput}from"@/ports/flight-schedule-repository";

type Change=<K extends keyof ManualScheduleLegInput>(key:K,value:ManualScheduleLegInput[K])=>void;

export function ServiceTypeField({value,workspace,change}:{value:string;workspace:FlightScheduleWorkspace;change:Change}){
 const currentKnown=workspace.serviceTypes.some(item=>item.code===value);
 return <label>Service type<select value={value} onChange={event=>change("serviceType",event.target.value)}><option value="">Select service type</option>{value&&!currentKnown&&<option value={value}>{value} · Current value</option>}{workspace.serviceTypes.map(item=><option key={item.code} value={item.code}>{item.code} · {item.name} ({item.application} / {item.typeOfOperation})</option>)}</select></label>;
}

export function AirportField({label,value,workspace,onChange}:{label:string;value:string;workspace:FlightScheduleWorkspace;onChange:(value:string)=>void}){
 const id=useId(),currentKnown=workspace.airports.some(item=>item.iata===value);
 return <label>{label}<input list={id} value={value} maxLength={3} onChange={event=>onChange(event.target.value.toUpperCase().replace(/[^A-Z]/g,"").slice(0,3))} placeholder="Start typing an IATA code"/><datalist id={id}>{value&&!currentKnown&&<option value={value}>Current value</option>}{workspace.airports.map(item=><option key={item.iata} value={item.iata}>{item.name}{item.city?` · ${item.city}`:""} · {item.timeZone}</option>)}</datalist></label>;
}

export function AircraftConfigurationFields({draft,workspace,change}:{draft:ManualScheduleLegInput;workspace:FlightScheduleWorkspace;change:Change}){
 const id=useId(),listId=`${id}-aircraft-suggestions`,selected=workspace.aircraft.find(item=>item.typeCode===draft.aircraftType&&item.subtype===draft.aircraftSubtype),selectedLabel=selected?`${selected.typeCode}-${selected.subtype} · ${selected.name}`:draft.aircraftType&&draft.aircraftSubtype?`${draft.aircraftType}-${draft.aircraftSubtype}`:"";
 const[typed,setTyped]=useState<string|null>(null),[open,setOpen]=useState(false),query=typed??selectedLabel;
 const suggestions=useMemo(()=>{const value=query.trim().toLowerCase();if(value.length<2)return[];return workspace.aircraft.filter(item=>`${item.typeCode}-${item.subtype} ${item.name}`.toLowerCase().includes(value)).slice(0,20)},[query,workspace.aircraft]);
 const configurations=workspace.aircraftConfigurations.filter(item=>item.typeCode===draft.aircraftType&&item.subtype===draft.aircraftSubtype);
 const configurationKnown=configurations.some(item=>item.code===draft.aircraftConfiguration);
 const selectAircraft=(item:FlightScheduleWorkspace["aircraft"][number])=>{setTyped(null);setOpen(false);change("aircraftType",item.typeCode);change("aircraftSubtype",item.subtype);change("aircraftConfiguration",firstAircraftConfiguration(workspace.aircraftConfigurations,item.typeCode,item.subtype))};
 const type=selected?`${selected.typeCode}-${selected.subtype}`:"";
 return <><div className="schedule-reference-field schedule-aircraft-autocomplete"><label htmlFor={id}>Aircraft type</label><input id={id} value={query} autoComplete="off" role="combobox" aria-autocomplete="list" aria-controls={listId} aria-expanded={open&&suggestions.length>0} placeholder="Start typing an aircraft type" onFocus={()=>setOpen(query.trim().length>=2)} onChange={event=>{const value=event.target.value;setTyped(value);setOpen(value.trim().length>=2);if(selected){change("aircraftType","");change("aircraftSubtype","");change("aircraftConfiguration",null)}}}/>{open&&suggestions.length>0&&<ul id={listId} className="autocomplete-results schedule-aircraft-suggestions">{suggestions.map(item=><li key={`${item.typeCode}-${item.subtype}`}><button type="button" onClick={()=>selectAircraft(item)}><strong>{item.typeCode}-{item.subtype}</strong><span>{item.name}</span></button></li>)}</ul>}</div><label>Configuration<select value={draft.aircraftConfiguration??""} onChange={event=>change("aircraftConfiguration",event.target.value||null)} disabled={!type}><option value="">{configurations.length?"Select configuration (optional)":"No cabin configuration saved"}</option>{draft.aircraftConfiguration&&!configurationKnown&&<option value={draft.aircraftConfiguration}>{draft.aircraftConfiguration} · Current value</option>}{configurations.map(item=><option key={item.code} value={item.code}>{item.code} · {item.description}</option>)}</select></label></>;
}
